extends SceneTree

var failures: Array[String] = []

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var weapons = scene.get_node("Weapons")
	var sound = weapons.audio
	var recorder := AudioEffectRecord.new()
	recorder.format = AudioStreamWAV.FORMAT_16_BITS
	AudioServer.add_bus_effect(0, recorder)
	recorder.set_recording_active(true)
	Input.action_press("fire")
	await create_timer(0.2).timeout
	check(sound.salvos_played == 0, "Takeoff blocks gun sounds")
	scene.get_node("Departure").finish_immediately()
	var last: int = sound.last_variant
	var count: int = sound.salvos_played
	var variants: Dictionary = {}
	for tick in range(120):
		await physics_frame
		if sound.salvos_played != count:
			check(sound.last_variant != last, "Consecutive salvos use different takes")
			last = sound.last_variant
			count = sound.salvos_played
			variants[last] = true
	Input.action_release("fire")
	var at_release: int = sound.salvos_played
	await create_timer(0.85).timeout
	check(sound.salvos_played == at_release, "No extra sound after releasing Space")
	check(sound.salvos_played * 2 == weapons.shots_fired, "Audio synchronized one to one with salvos")
	check(variants.size() > 1, "Variation is active")
	for voice in sound.voices:
		check(not voice.playing, "All audio tails finish naturally")
	check(sound.get_child_count() == 8, "Voice pool stays fixed")
	recorder.set_recording_active(false)
	var recording := recorder.get_recording()
	var path := ProjectSettings.globalize_path("res://../audio/weapon-ingame.wav")
	check(recording.save_to_wav(path) == OK, "Actual Godot mix exported")
	var bytes := recording.data
	var peak := 0
	for offset in range(0, bytes.size(), 2):
		peak = maxi(peak, absi(bytes.decode_s16(offset)))
	check(peak > 100, "Godot mixer produces audible signal")
	check(peak < 30000, "Godot mix has headroom without clipping")
	AudioServer.remove_bus_effect(0, AudioServer.get_bus_effect_count(0) - 1)
	print("WEAPON AUDIO: ", "PASS" if failures.is_empty() else failures, "; peak PCM=", peak, "; salvos=", count)
	quit(0 if failures.is_empty() else 1)
