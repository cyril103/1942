extends SceneTree
var app: Control
func _initialize() -> void: _run.call_deferred()
func capture(label: String) -> void:
	for frame in range(5): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../renders/dynamic-"+label+".png"))
func _run() -> void:
	app = load("res://scenes/campaign.tscn").instantiate()
	app.testing = true
	root.add_child(app)
	current_scene = app
	await process_frame
	app.profile.reset()
	app.profile.data.run_score = 25600
	app.profile.data.unlocked = 32
	app._launch(5)
	var c = app.cockpit.combat
	var d = app.director
	var w = d.weapons
	var p = d.player
	var departure = app.cockpit.flight.get_node("Departure")
	departure.finish_immediately()
	for node in [c,d,w,p,app.cockpit.flight.get_node("Seascape")]: node.set_physics_process(false)
	p.invulnerable_time = 100
	for frame in range(960):
		c._physics_process(1.0/60)
		d.advance(1.0/60)
		app.cockpit.flight.get_node("Seascape")._physics_process(1.0/60)
		if frame%120==0: await process_frame
	w._fire_salvo()
	w._physics_process(.12)
	c._explode(Vector3(-5,0,-2))
	c._update_effects(.15)
	await capture("combat-wide")
	for ship in d.navals:
		if is_instance_valid(ship): ship.retire()
	d.navals.clear()
	d._spawn_naval(1)
	for ship in d.navals: ship.position.z = -5
	p.position.x = d.navals[0].position.x
	w.set_power("laser")
	Input.action_press("fire")
	await physics_frame
	await physics_frame
	w._physics_process(.016)
	c.pickup.activate(Vector3(4,0,4),p,"life")
	await capture("laser-life")
	Input.action_release("fire")
	w.cease_fire()
	c.pickup.active = false
	c.pickup.hide()
	d.event_index = d.mission.events.size()
	d.elapsed = d.mission.duration
	d.advance(.016)
	for frame in range(210):
		c._physics_process(1.0/60)
		d.advance(1.0/60)
		app.cockpit.flight.get_node("Seascape")._physics_process(1.0/60)
	await capture("landing-approach")
	for frame in range(180):
		c._physics_process(1.0/60)
		d.advance(1.0/60)
		app.cockpit.flight.get_node("Seascape")._physics_process(1.0/60)
	await capture("landing-deck")
	app._show_main()
	app.music.stop()
	await create_timer(.2).timeout
	print("DYNAMIC CAPTURES COMPLETE")
	quit()
