extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var sea = scene.get_node("Seascape")
	var departure = scene.get_node("Departure")
	sea.set_physics_process(false)
	departure.set_physics_process(false)
	scene.get_node("Player").set_physics_process(false)
	var previous_tick: int = 0
	var times := [0.0, 2.3, 4.2, 5.55, 6.15, 6.75, 7.3, 9.2]
	for index in range(times.size()):
		var target_tick: int = roundi(times[index] * 60.0)
		for tick in range(target_tick - previous_tick):
			sea._physics_process(1.0 / 60.0)
			departure._physics_process(1.0 / 60.0)
		previous_tick = target_tick
		for frame in range(8):
			await process_frame
		await RenderingServer.frame_post_draw
		var path := ProjectSettings.globalize_path("res://../renders/departure-%02d.png" % index)
		var result := root.get_texture().get_image().save_png(path)
		if result != OK:
			quit(result)
			return
		print("DEPARTURE CAPTURE ", times[index], "s / phase ", departure.phase, " / ", path)
	quit()
