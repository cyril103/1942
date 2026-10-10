extends SceneTree
## Actual menu actions with an isolated profile. No campaign save is loaded.
var app: Control
var failures: Array[String] = []
var checks := 0
var capture_enabled := false
const OUTPUT := "C:/ChatGPT/1942/renders/sublime-showroom"
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)
func capture(label: String) -> void:
	if not capture_enabled: return
	for frame in range(12): await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(OUTPUT.path_join(label+".png"))==OK,"Write "+label)
func geometry() -> void:
	for button in app.buttons:
		check(Rect2(0,0,1920,1080).encloses(button.get_rect()),"Button inside canvas "+str(button.name))
		check(button.get_minimum_size().y<=button.size.y+.1,"Button caption fits "+str(button.name))
	for child in app.design.get_children():
		if child is Label: check(child.get_minimum_size().y<=child.size.y+.1,"Label fits "+str(child.name))
func _run() -> void:
	capture_enabled = "--capture" in OS.get_cmdline_user_args()
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	root.size = Vector2i(1920,1080)
	app = load("res://scenes/campaign.tscn").instantiate()
	app.testing = true
	app.profile.path = "user://gallery-never-saved.json"
	root.add_child(app)
	app.profile.reset()
	app.profile.data.settings.shake = false
	app._show_hangar()
	await process_frame
	geometry()
	await capture("hangar-1080")
	check(app.design.has_node("InspectAircraft"),"Hangar exposes keyboard-accessible inspection")
	var before: Dictionary = app.profile.data.duplicate(true)
	app.design.get_node("InspectAircraft").pressed.emit()
	for index in range(3):
		await process_frame
		check(app.page=="aircraft_gallery","Inspection page remains active")
		var studio: Control = app.design.get_node("AircraftGallery")
		check(studio.aircraft_index==index and studio._meshes>0,"Real aircraft geometry loaded "+str(index))
		check(studio.viewport.own_world_3d and studio.viewport.size.x<=1440,"Bounded isolated viewport")
		check(app.profile.data==before,"Inspection leaves campaign profile unchanged")
		geometry()
		await capture("aircraft-%d-1080" % index)
		for view in ["GalleryProfile","GalleryTop","GalleryThreeQuarter"]:
			app.design.get_node(view).pressed.emit()
			check(studio.camera.transform.is_finite(),"Valid camera for "+view)
		if index<2: app.design.get_node("GalleryNext").pressed.emit()
	root.size = Vector2i(1280,720)
	await process_frame
	geometry()
	await capture("aircraft-2-720")
	app.design.get_node("GalleryAssign").pressed.emit()
	check(app.page=="hangar" and app.profile.data.aircraft==2,"Assignment uses real loadout callback")
	app._show_aircraft_gallery()
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	app._input(escape)
	check(app.page=="hangar","Escape returns inspection to hangar")
	app._show_aircraft_gallery(1)
	app.design.get_node("GalleryBack").pressed.emit()
	check(app.page=="hangar","Back action returns to hangar")
	app.music.stop()
	app.queue_free()
	await process_frame
	await create_timer(.3).timeout
	print("AIRCRAFT GALLERY: %d checks; failures %s" % [checks,str(failures)])
	quit(0 if failures.is_empty() else 1)
