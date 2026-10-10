extends SceneTree
## Authored visual fixtures; not evidence of successful human play.
var app: Node
var output := "C:/ChatGPT/1942/renders/finish-1.10"
func _initialize() -> void: _run.call_deferred()
func freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children(): freeze(child)
func stop_audio(node: Node) -> void:
	if node is AudioStreamPlayer or node is AudioStreamPlayer3D: node.stop()
	for child in node.get_children(): stop_audio(child)
func capture(label: String) -> void:
	for i in range(6): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label+".png"))
func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1920,1080)
	app = load("res://scenes/campaign.tscn").instantiate()
	app.testing = true
	app.profile.path = "user://finish-capture.json"
	root.add_child(app)
	app.profile.reset()
	app.profile.data.unlocked = 32
	app.profile.data.settings.fullscreen = false
	for mission in [1,3,19,27]:
		app._launch(mission)
		var d: Node = app.director
		var flight: Node = app.cockpit.flight
		flight.get_node("Departure").finish_immediately()
		freeze(flight)
		d.set_physics_process(false)
		d.player.invulnerable_time = 1000
		for frame in range(60*(37 if mission!=1 else 18)):
			d.combat._physics_process(1.0/60)
			d.advance(1.0/60)
			flight.get_node("Seascape")._physics_process(1.0/60)
			flight.get_node("Clouds")._physics_process(1.0/60)
			d.details._physics_process(1.0/60)
			if frame%120==0: await process_frame
		freeze(flight)
		d.weapons.set_power("laser")
		Input.action_press("fire")
		await physics_frame
		d.weapons._update_laser(.02)
		Input.action_release("fire")
		if mission==1:
			for enemy in d.combat.enemies: enemy.retire()
			d.combat.enemies.clear()
			d.combat.spawn_wave()
			for index in range(d.combat.enemies.size()):
				var enemy: Node3D = d.combat.enemies[index]
				enemy.position = Vector3(-6+index*1.7,0,-3-sin(index)*1.5)
				enemy.take_damage(999)
			d.score_bursts.advance(.24)
			d.combat._explode(Vector3(-3,0,-3))
			d.combat._update_effects(.17)
		else:
			for target in d.assault.contacts():
				if target.position.z > -5 and target.position.z < 1:
					target.take_damage(999)
					break
			d.combat._update_effects(.17)
		d.details.impact(d.player.bank.global_position+Vector3(0,.2,-4),true)
		d.details._physics_process(.035)
		await capture("mission-%02d" % mission)
		stop_audio(app)
		await create_timer(.2).timeout
		app._show_main()
		await process_frame
	for aircraft in range(3):
		app.profile.data.aircraft = aircraft
		app._launch(1)
		var d: Node = app.director
		app.cockpit.flight.get_node("Departure").finish_immediately()
		freeze(app.cockpit.flight)
		d.charge = 100
		d.use_strike()
		d.player.invulnerable_time = 0
		d.ring_time = 0
		d.special_ring.hide()
		d.details._physics_process(.016)
		d.weapons._fire_salvo()
		d.weapons._physics_process(.1)
		await capture("capacity-%d" % aircraft)
		stop_audio(app)
		await create_timer(.2).timeout
		app._show_main()
		await process_frame
	app._show_briefing(1)
	app._show_rules()
	await capture("score-guide")
	app.music.stop()
	await create_timer(.2).timeout
	app.queue_free()
	await process_frame
	quit()
