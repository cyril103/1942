extends SceneTree
## Native GL captures: real top-down gameplay and a close relief inspection.
func _initialize() -> void: _run.call_deferred()
func freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children(): freeze(child)
func capture(name_text: String) -> void:
	for frame in range(5): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("C:/ChatGPT/1942/renders/sublime-ocean/"+name_text+".png")
func _run() -> void:
	root.size = Vector2i(1920,1080)
	DirAccess.make_dir_recursive_absolute("C:/ChatGPT/1942/renders/sublime-ocean")
	var app = load("res://scenes/campaign.tscn").instantiate()
	app.testing = true
	app.profile.path = "user://ocean-relief-capture.json"
	root.add_child(app)
	current_scene = app
	app.profile.reset()
	app.profile.data.unlocked = 32
	for mission in [1,17,25]:
		app._launch(mission)
		var d = app.director
		var flight = app.cockpit.flight
		flight.get_node("Departure").finish_immediately()
		freeze(flight)
		d.set_physics_process(false)
		var sea = flight.get_node("Seascape")
		for frame in range(60*48): sea._physics_process(1.0/60.0)
		await capture("mission-%02d" % mission)
		if mission==1:
			for island in sea.islands: island.hide()
			var island: MeshInstance3D = sea.islands[0]
			island.show()
			island.position = Vector3(0,-3,-1)
			island.rotation.y = -.15
			island.mesh.size = Vector2(16,16)
			island.material_override.set_shader_parameter("island_size",Vector2(16,16))
			var atlas = preload("res://assets/environment/archipelago-atlas.png")
			island.material_override.set_shader_parameter("island_atlas",atlas)
			island.material_override.set_shader_parameter("relief_atlas",preload("res://scripts/island_relief.gd").texture_for(atlas))
			island.material_override.set_shader_parameter("atlas_cell",Vector2(1,0))
			flight.get_node("Clouds").hide()
			await capture("island-top-down")
			flight.get_node("Camera").rotation.x = deg_to_rad(-67)
			flight.get_node("Camera").position = Vector3(0,29,12)
			await capture("island-relief-oblique")
		app._dispose_run()
		await process_frame
	app.music.stop()
	app.queue_free()
	await process_frame
	print("OCEAN RELIEF CAPTURES COMPLETE")
	quit()
