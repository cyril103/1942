extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	scene.get_node("Departure").finish_immediately()
	for name_text in ["Weapons", "Player", "Seascape"]:
		scene.get_node(name_text).set_physics_process(false)
	Input.action_press("fire")
	for tick in range(46):
		scene.get_node("Weapons")._physics_process(1.0 / 60.0)
	Input.action_release("fire")
	for frame in range(8):
		await process_frame
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../renders/projectiles.png"))
	quit(result)
