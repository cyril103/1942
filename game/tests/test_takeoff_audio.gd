extends SceneTree
var failures: Array[String] = []
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	scene.get_node("Combat").set_physics_process(false)
	var departure = scene.get_node("Departure")
	var sound = departure.engine_audio
	var recorder := AudioEffectRecord.new()
	recorder.format = AudioStreamWAV.FORMAT_16_BITS
	AudioServer.add_bus_effect(0, recorder)
	recorder.set_recording_active(true)
	var minimum := 1.0
	var maximum := 1.0
	for tick in range(690):
		await physics_frame
		minimum = minf(minimum, sound.doppler)
		maximum = maxf(maximum, sound.doppler)
	check(minimum < 0.90 and maximum > 1.15, "Approach raises pitch, departure lowers it")
	check(sound.finished, "Engine fades out after opening")
	check(sound.voices.size() == 2 and sound.get_child_count() == 2, "Only two fixed engine voices")
	for voice in sound.voices: check(not voice.playing, "Engine loop stopped")
	recorder.set_recording_active(false)
	var recording := recorder.get_recording()
	recording.save_to_wav(ProjectSettings.globalize_path("res://../audio/takeoff-ingame.wav"))
	var bytes := recording.data
	var peak := 0
	for offset in range(0, bytes.size(), 2):
		peak = maxi(peak, absi(bytes.decode_s16(offset)))
	check(peak > 1000 and peak < 28000, "Audible mix with unclipped headroom")
	AudioServer.remove_bus_effect(0, AudioServer.get_bus_effect_count(0)-1)
	departure.finish_immediately()
	check(sound.finished, "Skipping opening stops loops")
	scene.queue_free()
	await create_timer(0.4).timeout
	print("TAKEOFF AUDIO: ", "PASS" if failures.is_empty() else failures, "; Doppler=", minimum, "..", maximum, "; peak=", peak)
	quit(0 if failures.is_empty() else 1)
