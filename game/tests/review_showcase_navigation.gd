extends SceneTree
## Read-only review probes: focus route, framing, resize, lifetime and save state.
func _initialize() -> void: _run.call_deferred()
func projected_bounds(studio: Control) -> Rect2:
	var initialized := false
	var rect := Rect2()
	for node in studio.model.find_children("*","MeshInstance3D",true,false):
		if node.mesh==null: continue
		for surface in range(node.mesh.get_surface_count()):
			var arrays: Array = node.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for vertex in vertices:
				var point: Vector2 = studio.camera.unproject_position(node.global_transform*vertex)
				if initialized: rect = rect.expand(point)
				else: rect = Rect2(point,Vector2.ZERO); initialized = true
	return rect
func _run() -> void:
	var app: Control = load("res://scenes/campaign.tscn").instantiate()
	app.testing = true
	app.profile.path = "user://showcase-review-isolated.json"
	root.size = Vector2i(1280,720)
	root.add_child(app)
	app.profile.reset()
	app.profile.data.settings.shake = false
	var saved: Dictionary = app.profile.data.duplicate(true)
	for plane in range(3):
		app._show_aircraft_gallery(plane)
		await process_frame
		var studio: Control = app.design.get_node("AircraftGallery")
		studio.set_process(false)
		for view in range(3):
			studio.set_view(view)
			studio._process(0)
			print("FRAME ",plane,"/",view," viewport=",studio.viewport.size," mesh=",projected_bounds(studio)," fits=",Rect2(Vector2.ZERO,Vector2(studio.viewport.size)).encloses(projected_bounds(studio)))
			studio.reduced_motion = false
			for wave in [-1.0,1.0]:
				studio.elapsed = (PI*.5 if wave>0 else PI*1.5)/.24
				studio._process(0)
				print("DRIFT ",plane,"/",view," wave=",wave," mesh=",projected_bounds(studio)," fits=",Rect2(Vector2.ZERO,Vector2(studio.viewport.size)).encloses(projected_bounds(studio)))
			studio.reduced_motion = true
		print("FOCUS plane=",plane," first=",root.gui_get_focus_owner().name)
		for name_text in ["GalleryThreeQuarter","GalleryProfile","GalleryTop","GalleryNext","GalleryBack","GalleryAssign"]:
			var button: Control = app.design.get_node(name_text)
			var right: Control = button.find_valid_focus_neighbor(SIDE_RIGHT)
			var up: Control = button.find_valid_focus_neighbor(SIDE_TOP)
			print("NAV ",name_text," right=",right.name if right else "null"," up=",up.name if up else "null")
		studio.hide()
		print("HIDDEN disabled=",studio.viewport.render_target_update_mode==SubViewport.UPDATE_DISABLED)
		studio.show()
		print("VISIBLE updates=",studio.viewport.render_target_update_mode==SubViewport.UPDATE_ALWAYS)
		var studio_ref: WeakRef = weakref(studio)
		var viewport_ref: WeakRef = weakref(studio.viewport)
		app._show_hangar()
		await process_frame
		await process_frame
		print("FREED ",studio_ref.get_ref()==null," viewport=",viewport_ref.get_ref()==null)
	print("UNCHANGED PROFILE ",app.profile.data==saved)
	root.size = Vector2i(720,1280)
	await process_frame
	app._show_aircraft_gallery(0)
	await process_frame
	var studio: Control = app.design.get_node("AircraftGallery")
	print("PORTRAIT root=",root.size," app=",app.size," design=",app.design.get_global_transform()," studio-vp=",studio.viewport.size)
	app.music.stop()
	await create_timer(.25).timeout
	app.queue_free()
	await create_timer(.25).timeout
	quit()
