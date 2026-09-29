extends SceneTree
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var cockpit = load("res://scenes/cockpit.tscn").instantiate()
	cockpit.persistence_enabled = false
	root.add_child(cockpit)
	current_scene = cockpit
	for frame in range(12): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../renders/cockpit-takeoff.png"))
	cockpit.flight.get_node("Departure").finish_immediately()
	cockpit.player.get_node("Hurtbox").collision_layer = 0
	for node_name in ["Combat","Weapons","Seascape","Player"]:
		cockpit.flight.get_node(node_name).set_physics_process(false)
	for frame in range(230):
		cockpit.combat._physics_process(1.0/60.0)
		cockpit.flight.get_node("Seascape")._physics_process(1.0/60.0)
	for frame in range(12): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../renders/cockpit-ingame.png"))
	print("COCKPIT CAPTURE ",cockpit.viewport.size," / ",cockpit.play_rect)
	cockpit.player.take_damage(1)
	cockpit.combat._physics_process(2.3)
	cockpit.player.invulnerable_time = 0
	cockpit.player.take_damage(1)
	cockpit.combat._physics_process(2.3)
	cockpit.player.invulnerable_time = 0
	cockpit.player.take_damage(1)
	for frame in range(8): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../renders/cockpit-defeat.png"))
	cockpit._stop_audio(cockpit.flight)
	await create_timer(0.12).timeout
	quit()
