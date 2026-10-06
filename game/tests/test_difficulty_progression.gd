extends SceneTree
var failures: Array[String] = []
var checks := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var tuning = load("res://scripts/campaign/balance.gd")
	for mode in range(3):
		var previous: Dictionary = tuning.settings(1,mode)
		for mission_id in range(2,33):
			var next: Dictionary = tuning.settings(mission_id,mode)
			check(next.salvos >= previous.salvos and next.interval <= previous.interval and next.speed >= previous.speed,"Pressure rises monotonically: %d/%d" % [mode,mission_id])
			previous = next
	var app = load("res://scenes/campaign.tscn").instantiate()
	app.testing = true
	root.add_child(app)
	current_scene = app
	await process_frame
	app.profile.reset()
	app.profile.data.unlocked = 32
	var measured := {}
	for mission_id in [1,4,8,12,20,32]:
		app._launch(mission_id)
		var d = app.director
		var c = d.combat
		d.set_physics_process(false)
		c.set_physics_process(false)
		d.player.set_physics_process(false)
		d.weapons.set_physics_process(false)
		app.cockpit.flight.get_node("Departure").finish_immediately()
		d.player.invulnerable_time = 1000
		check(d.player.max_health == 2 and is_equal_approx(d.weapons.shot_interval,.105),"Balance works with unupgraded Vanguard")
		var counts: Array[int] = []
		for variant in [0,1]:
			c.wave_count = variant
			c.spawn_wave()
			check(c.enemies.size()==8,"Keep eight active targets per wave")
			var expected := 0
			for enemy in c.enemies: expected += enemy.shot_limit
			var start: int = c.enemy_shots
			for frame in range(1200): c._physics_process(1.0/60)
			counts.append(c.enemy_shots-start)
			check(c.enemy_shots-start==expected,"Real fighter bursts honor assigned quota: %d/%d" % [mission_id,variant])
			check(c.enemies.is_empty(),"Both fighter types complete maneuvers and exit")
			c.clear_enemy_bullets()
		measured[mission_id] = counts
		if mission_id==1: check(counts==[8,8],"Opening waves fire 8 rounds instead of 24")
		if mission_id>=20: check(counts==[24,24],"Late missions retain full bursts")
		d._spawn_naval(0)
		var ship = d.navals[0]
		ship.position.z = c.screen_top()+3.0
		ship.cooldown = 0
		ship.advance(.01,c)
		check(is_equal_approx(ship.cooldown,3.1*c.enemy_interval_scale),"Naval salvo cadence uses mission pressure")
		d._spawn_boss("bomber")
		d.boss.phase = 2
		d.boss.volley = 2
		d.boss.telegraph_target = d.player.position
		var before: int = c.enemy_shots
		d.boss._fire(d)
		var expected_boss := 3 if mission_id<=4 else (5 if mission_id<=8 else 10)
		check(c.enemy_shots-before==expected_boss,"Early boss patterns are sparse; later rings retained")
		app._show_main()
		await process_frame
	app.music.stop()
	print("DIFFICULTY PROGRESSION: ",checks," checks; failures: ",failures,"; rounds per wave: ",measured)
	quit(0 if failures.is_empty() else 1)
