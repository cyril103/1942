extends SceneTree
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	root.size = Vector2i(1920,1080)
	var app = load("res://scenes/campaign.tscn").instantiate()
	app.testing = true
	root.add_child(app)
	current_scene = app
	await process_frame
	app.profile.reset()
	app.profile.data.unlocked = 32
	for number in [1,17,25]:
		app._launch(number)
		var d = app.director
		var flight = app.cockpit.flight
		var sea = flight.get_node("Seascape")
		for node_name in ["Seascape","Combat","Player","Weapons"]:
			flight.get_node(node_name).set_physics_process(false)
		d.set_physics_process(false)
		flight.get_node("Departure").finish_immediately()
		d.player.get_node("Hurtbox").collision_layer = 0
		for frame in range(60*48):
			sea._physics_process(1.0/60)
			d.combat._physics_process(1.0/60)
			d.advance(1.0/60)
			if frame%60==0: await process_frame
		for frame in range(4): await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("C:/ChatGPT/1942/renders/archipelago-gameplay-%02d.png" % number)
		if number==1:
			d._clear_actors()
			d.combat.clear_enemy_bullets()
			d.ending = true
			d.feedback = "SECTEUR SÉCURISÉ  /  APPROCHE DU PORTE-AVIONS"
			d.feedback_time = 10
			var departure = flight.get_node("Departure")
			departure.begin_landing()
			for frame in range(330):
				sea._physics_process(1.0/60)
				departure.advance_landing(1.0/60)
			for frame in range(4): await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("C:/ChatGPT/1942/renders/archipelago-landing.png")
		app._show_main()
		await process_frame
	app.music.stop()
	quit()
