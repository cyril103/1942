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
	scene.get_node("Departure").finish_immediately()
	for name in ["Combat", "Weapons", "Seascape", "Player"]:
		scene.get_node(name).set_physics_process(false)
	var combat = scene.get_node("Combat")
	var count: int = scene.get_child_count()
	for i in range(100): combat._explode(Vector3.ZERO)
	check(combat.effects.size() == combat.EFFECT_CAPACITY and combat.effects.size() <= 24, "Bounded effect pool supports dense formations")
	check(scene.get_child_count() == count, "No scene growth on repeated explosions")
	for effect in combat.effects:
		check(effect.get_child_count() == 28, "Fixed internal meshes")
	combat._update_effects(0.8)
	check(combat.effects[0].visible, "Smoke survives fireball")
	combat._update_effects(0.7)
	for effect in combat.effects: check(not effect.visible, "Finished smoke hidden")
	combat.explosion_audio.stop()
	await create_timer(0.1).timeout
	var recorder := AudioEffectRecord.new()
	recorder.format = AudioStreamWAV.FORMAT_16_BITS
	AudioServer.add_bus_effect(0, recorder)
	recorder.set_recording_active(true)
	combat._explode(Vector3(-2,0,0))
	combat._explode(Vector3(2,0,0))
	await create_timer(combat.explosion_audio.stream.get_length()+0.4).timeout
	recorder.set_recording_active(false)
	var recording := recorder.get_recording()
	recording.save_to_wav(ProjectSettings.globalize_path("res://../audio/explosion-ingame-pair.wav"))
	var peak := 0
	var bytes := recording.data
	for offset in range(0, bytes.size(), 2):
		peak = maxi(peak, absi(bytes.decode_s16(offset)))
	check(peak > 100 and peak < 30000, "Pair produces audible unclipped mixer output")
	check(not combat.explosion_audio.playing, "Audio voices finish")
	AudioServer.remove_bus_effect(0, AudioServer.get_bus_effect_count(0)-1)
	scene.queue_free()
	await create_timer(0.4).timeout
	print("EXPLOSION: ", "PASS" if failures.is_empty() else failures, "; pair peak PCM=", peak)
	quit(0 if failures.is_empty() else 1)
