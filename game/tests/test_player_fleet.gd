extends SceneTree
var failures: Array[String] = []
var checks := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)
func _initialize() -> void: _run.call_deferred()
func capture(label: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	for i in range(8): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("C:/ChatGPT/1942/renders/player-fleet/game-"+label+".png")
func _run() -> void:
	var app = load("res://scenes/campaign.tscn").instantiate()
	app.testing = true
	app.profile.path = "user://fleet-validation-fixture.json"
	root.add_child(app)
	current_scene = app
	await process_frame
	app.profile.reset()
	for index in range(3):
		app.profile.data.aircraft = index
		app._launch(1)
		var d = app.director
		var p = d.player
		var w = d.weapons
		var c = d.combat
		var departure = app.cockpit.flight.get_node("Departure")
		check(p.aircraft_index==index,"Selected aircraft index matches gameplay")
		check(p.propellers.size()==[0,2,1][index],"Expected propeller pivots")
		check(is_equal_approx(p.speed,[12.0,14.0,10.4][index]) and p.max_health==[2,2,3][index],"Aircraft speed and hull preserved")
		check(d.bombs==[2,2,3][index],"Bomb capacity follows selected aircraft")
		check(is_equal_approx(w.shot_interval,[.090,.100,.110][index]),"Cadence follows the aircraft's documented mobility/firepower tradeoff")
		for node in [d,c,w,p,departure]: node.set_physics_process(false)
		if index>0:
			check(p.bank.get_node("Aircraft").scene_file_path.ends_with("p38.glb" if index==1 else "f4u.glb"),"Distinct imported GLB instantiated")
			var prop: Node3D = p.propellers[0]
			var before: Basis = prop.basis
			p._process(.016)
			check(not prop.basis.is_equal_approx(before),"Propeller animation active")
		departure.finish_immediately()
		check(p._model_bounds.size.x>1.6 and p._model_bounds.size.x<2.1,"Wing span remains consistent with gameplay scale")
		for pos in [Vector3(-100,0,0),Vector3(100,0,0),Vector3(0,0,-100),Vector3(0,0,100)]:
			p.position=pos
			p._keep_inside_screen()
			var bounds: Rect2 = p.get_screen_bounds()
			check(bounds.position.x>=-1 and bounds.end.x<=app.cockpit.viewport.size.x+1 and bounds.position.y>=-1 and bounds.end.y<=app.cockpit.viewport.size.y+1,"Selected model stays inside screen")
		p.position=Vector3(0,0,4)
		w._fire_salvo()
		check(w.active_count==2,"Selected aircraft fires twin projectile salvo")
		check(w.projectiles[0].position.distance_to(p.bank.to_global(w.muzzle_positions[0]))<.01,"Projectile originates at model-specific gun")
		if index == 1:
			for frame in range(5): w._physics_process(1.0/60)
			var spacing: float = w.projectiles[1].position.x-w.projectiles[0].position.x
			check(is_equal_approx(spacing,w.MUZZLES[1].x-w.MUZZLES[0].x),"P-38 opens to the Vanguard firing width")
			p.position.x += 1.0
			w._physics_process(.1)
			check(is_equal_approx(w.projectiles[1].position.x-w.projectiles[0].position.x,spacing),"Opened rounds remain parallel while player moves")
			check(absf(w.projectiles[0].rotation.y)<.001,"Trace turns forward after opening")
			p.position.x = 0
			w.cease_fire()
			w._fire_salvo()
			w._physics_process(.08)
			check(is_equal_approx(w.projectiles[1].position.x-w.projectiles[0].position.x,spacing),"Pool reuse and a large timestep preserve firing width")
		await capture(str(index))
		if index > 0 and "--capture" in OS.get_cmdline_user_args():
			c.camera.size = 5
			p.position = Vector3.ZERO
			w.cease_fire()
			await capture("detail-"+str(index))
			c.camera.size = 25
			p.position = Vector3(0,0,4)
		w.cease_fire()
		p.invulnerable_time=0
		p.take_damage(p.max_health)
		for frame in range(91): c._physics_process(1.0/60)
		p.set_physics_process(false)
		check(p.alive and p.aircraft_index==index and p.health==p.max_health,"Respawn preserves aircraft and restores hull")
		departure.begin_landing()
		for frame in range(421): departure.advance_landing(1.0/60)
		check(departure.landed and is_equal_approx(p.position.y,departure.DECK_ALTITUDE),"Selected aircraft lands on carrier")
		app._show_main()
		await process_frame
	app._show_hangar()
	await create_timer(.3).timeout
	await capture("hangar")
	app._show_main()
	app.music.stop()
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(app.profile.path + suffix): DirAccess.remove_absolute(app.profile.path + suffix)
	await create_timer(.2).timeout
	print("PLAYER FLEET: ",checks," checks; failures: ",failures)
	quit(0 if failures.is_empty() else 1)
