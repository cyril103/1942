extends SceneTree
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	scene.get_node("Departure").finish_immediately()
	for name in ["Combat", "Weapons", "Seascape", "Player"]:
		scene.get_node(name).set_physics_process(false)
	var combat = scene.get_node("Combat")
	combat._explode(Vector3(0, 0, -1))
	var previous := 0.0
	for age in [0.08, 0.30, 0.75, 1.6, 2.8]:
		combat._update_effects(age - previous)
		previous = age
		for frame in range(8): await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../renders/explosion-%03d.png" % roundi(age * 100)))
	scene.queue_free()
	await create_timer(0.5).timeout
	quit()
