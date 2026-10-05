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
	var weapons = cockpit.flight.get_node("Weapons")
	combat.next_wave = 1000
	combat.next_bomber = 1000
	combat.next_special = 1000
	combat.spawn_special()
	for frame in range(220):
		combat._physics_process(1.0/60)
		cockpit.flight.get_node("Seascape")._physics_process(1.0/60)
	await capture("special-red-formation.png")
	for red in combat.red_enemies: red.take_damage(2)
	for frame in range(100): combat._physics_process(1.0/60)
	await capture("special-pow.png")
	cockpit.player.position = combat.pickup.position
	combat._physics_process(1.0/60)
	weapons._fire_salvo()
	weapons._physics_process(0.12)
	await capture("special-pow-collection.png")
	cockpit.player.position = Vector3(0,0,7)
	weapons._physics_process(4)
	for salvo in range(4):
		weapons._fire_salvo()
		weapons._physics_process(0.12)
	combat.pickup.advance(1,combat)
	await capture("special-spread-shot.png")
	print("SPECIAL CAPTURES COMPLETE")
	cockpit._stop_audio(cockpit.flight)
	await create_timer(0.12).timeout
	quit()
