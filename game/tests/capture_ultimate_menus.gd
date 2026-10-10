extends SceneTree
## Authored UI fixtures; does not claim human playtesting.
var app: Control
var output := "C:/ChatGPT/1942/renders/ultimate-2.0"
func _initialize() -> void: _run.call_deferred()
func capture(label: String) -> void:
	for i in range(5): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label+".png"))
func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1920,1080)
	app = load("res://scenes/campaign.tscn").instantiate()
	app.testing = true
	app.profile.path = "user://ultimate-capture-never-saved.json"
	root.add_child(app)
	app.profile.reset()
	app._show_main()
	await capture("01-accueil")
	app._show_boss_rush()
	await capture("02-boss-rush")
	app._show_pilot_guide()
	await capture("03-guide-pilote")
	app._begin_boss_rush()
	app.cockpit.flight.process_mode = Node.PROCESS_MODE_DISABLED
	app._show_result({"won":true,"mission":4,"score":12500,"lives":2,"seconds":74.0,"grazes":17})
	await capture("04-rush-resultat")
	app._dispose_run()
	if is_instance_valid(app.music): app.music.stop()
	app.queue_free()
	await process_frame
	await create_timer(.2).timeout
	quit()
