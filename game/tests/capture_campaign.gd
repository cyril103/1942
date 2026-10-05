extends SceneTree
func _initialize() -> void: _run.call_deferred()
func capture(name: String) -> void:
	for frame in range(8): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../renders/campaign-"+name+".png"))
func _run() -> void:
	var app = load("res://scenes/campaign.tscn").instantiate()
	app.testing = true
	root.add_child(app)
	current_scene = app
	for frame in range(12): await process_frame
	await capture("title")
	app.profile.data.unlocked = 32
	app.profile.data.credits = 12
	app._show_missions()
	await capture("map")
	app._show_hangar()
	await capture("hangar")
	app._show_briefing(8)
	await capture("briefing")
	app._show_settings(false)
	await capture("options")
	for spec in [[4,"boss-bomber"],[8,"boss-cruiser"],[16,"boss-fortress"],[20,"volcano"],[28,"arctic-carrier"],[32,"final-boss"]]:
		app._launch(spec[0])
		app.cockpit.flight.get_node("Departure").finish_immediately()
		app.cockpit.player.get_node("Hurtbox").collision_layer = 0
		for node_name in ["Combat","Player","Weapons","Seascape"]: app.cockpit.flight.get_node(node_name).set_physics_process(false)
		app.director.set_physics_process(false)
		app.director.event_index = app.director.mission.events.size()
		app.director.elapsed = app.director.mission.duration-3
		app.director._spawn_boss(app.director.mission.boss)
		for frame in range(420):
			app.cockpit.combat._physics_process(1.0/60)
			app.director.advance(1.0/60)
			app.cockpit.flight.get_node("Seascape")._physics_process(1.0/60)
		app.cockpit.flight.get_node("Weapons")._fire_salvo()
		app.cockpit.flight.get_node("Weapons")._physics_process(0.12)
		await capture(spec[1])
	app._show_pause()
	await capture("pause")
	app._resume()
	app._show_result({"won":true,"mission":32,"score":45000,"kills":34,"naval_kills":6,"deaths":0,"damage":1,"grade":3,"bonus":1800,"seconds":124})
	await capture("victory")
	app._show_main()
	app.music.stop()
	await create_timer(0.2).timeout
	print("CAMPAIGN CAPTURES COMPLETE")
	quit()
