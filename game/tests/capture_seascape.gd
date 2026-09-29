extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	scene.get_node("Departure").finish_immediately()
	await process_frame
	var sea = scene.get_node("Seascape")
	sea.set_physics_process(false)
	scene.get_node("Player").set_physics_process(false)
	var last_time: int = 0
	for seconds in [0, 8, 18, 35]:
		for tick in range((seconds - last_time) * 60):
			sea._physics_process(1.0 / 60.0)
		last_time = seconds
		for frame in range(8):
			await process_frame
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		var path := ProjectSettings.globalize_path("res://../renders/ocean-%02ds.png" % seconds)
		var result := image.save_png(path)
		if result != OK:
			push_error("Capture failed: %s" % result)
			quit(1)
			return
		print("CAPTURE ", seconds, "s: ", path)
	# Verify visually that transparent shore planes do not cover the player.
	var player = scene.get_node("Player")
	var island: MeshInstance3D = sea.islands[0]
	island.position = Vector3(-2.0, -3.0, 2.0)
	player.position = Vector3(-2.0, 0.0, 2.0)
	player.bank.rotation.z = deg_to_rad(-28.0)
	for frame in range(8):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../renders/ocean-survol.png"))
	print("GPU CAPTURES COMPLETE")
	quit()
