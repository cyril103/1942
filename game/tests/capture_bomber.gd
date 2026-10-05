extends SceneTree
func _initialize() -> void: _run.call_deferred()
func capture(path: String) -> void:
	for frame in range(5): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../renders/"+path))
func _run() -> void:
	var cockpit = load("res://scenes/cockpit.tscn").instantiate()
	cockpit.persistence_enabled = false
	root.add_child(cockpit)
	current_scene = cockpit
	for frame in range(12): await process_frame
	cockpit.flight.get_node("Departure").finish_immediately()
	cockpit.player.get_node("Hurtbox").collision_layer = 0
	for node_name in ["Combat","Weapons","Seascape","Player"]:
		cockpit.flight.get_node(node_name).set_physics_process(false)
	var combat = cockpit.combat
	combat.next_wave = 1000
	combat.next_bomber = 1000
	combat.spawn_bomber()
	var bomber = combat.bombers[0]
	for frame in range(180):
		combat._physics_process(1.0/60)
		cockpit.flight.get_node("Seascape")._physics_process(1.0/60)
	await capture("bomber-entry.png")
	for frame in range(360):
		combat._physics_process(1.0/60)
		cockpit.flight.get_node("Seascape")._physics_process(1.0/60)
	combat.fire_bomber(bomber)
	combat._update_bullets(0.10)
	await capture("bomber-ingame.png")
	bomber.take_damage(1)
	await capture("bomber-impact.png")
	bomber.take_damage(9)
	for frame in range(60): combat._physics_process(1.0/60)
	await capture("bomber-destruction.png")
	print("BOMBER CAPTURES COMPLETE")
	cockpit._stop_audio(cockpit.flight)
	await create_timer(0.12).timeout
	quit()
