extends SceneTree
var app: Control
func _initialize() -> void: _run.call_deferred()
func capture(label: String) -> void:
	for frame in range(5): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("C:/ChatGPT/1942/renders/toppissime-"+label+".png")
func _run() -> void:
	root.size = Vector2i(1920,1080)
	app = load("res://scenes/campaign.tscn").instantiate()
	app.testing = true
	root.add_child(app)
	current_scene = app
	await process_frame
	app.profile.reset()
	app.profile.data.unlocked = 32
	await capture("accueil")
	app._show_briefing(1)
	await capture("briefing")
	app._launch(1)
	var d = app.director
	var flight = app.cockpit.flight
	flight.get_node("Departure").finish_immediately()
	for name_text in ["Seascape","Clouds","Combat","Player","Weapons","Departure"]: flight.get_node(name_text).set_physics_process(false)
	d.set_physics_process(false)
	d.details.set_physics_process(false)
	d.player.invulnerable_time = 1000
	var sea = flight.get_node("Seascape")
	var clouds = flight.get_node("Clouds")
	for frame in range(60*37):
		d.combat._physics_process(1.0/60)
		d.advance(1.0/60)
		sea._physics_process(1.0/60)
		clouds._physics_process(1.0/60)
		d.details._physics_process(1.0/60)
		if frame%120==0: await process_frame
	d.weapons._fire_salvo()
	d.weapons._physics_process(.12)
	d.combat._explode(Vector3(-4,0,-2))
	d.combat._update_effects(.18)
	await capture("combat")
	d._clear_actors()
	d._spawn_boss("bomber")
	for frame in range(270): d.boss.advance(1.0/60,d)
	d.boss.take_hit_at(int(d.boss.component_health[0]),d.boss.to_global(d.boss.component_position(0)))
	d.boss.advance(.1,d)
	await capture("boss")
	app._show_pause()
	app._show_graphics()
	await capture("graphismes")
	app._show_bindings()
	await capture("commandes")
	app._show_main()
	app._show_challenges("arcade")
	await capture("arcade")
	app._show_main()
	app.music.stop()
	await process_frame
	quit()
