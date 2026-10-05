extends SceneTree
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var app = load("res://scenes/campaign.tscn").instantiate()
	app.testing = true
	root.add_child(app)
	current_scene = app
	await process_frame
	app.profile.data.unlocked = 32
	app._show_missions()
	app._show_hangar()
	app._show_settings(false)
	app._show_briefing(1)
	app._launch(1)
	app.cockpit.flight.get_node("Departure").finish_immediately()
	for node_name in ["Combat","Player","Weapons","Seascape"]: app.cockpit.flight.get_node(node_name).set_physics_process(false)
	app.director.set_physics_process(false)
	app.cockpit.player.get_node("Hurtbox").collision_layer = 0
	for frame in range(600):
		app.cockpit.combat._physics_process(1.0/60)
		app.director.advance(1.0/60)
	app._show_pause()
	app._resume()
	app._show_main()
	await process_frame
	if is_instance_valid(app.music): app.music.stop()
	print("CAMPAIGN SMOKE COMPLETE")
	await create_timer(0.2).timeout
	quit()
