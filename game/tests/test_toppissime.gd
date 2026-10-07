extends SceneTree
var failures: Array[String] = []
var checks := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var mastery = load("res://scripts/campaign/mastery.gd").new()
	for i in range(40): mastery.kill(100)
	check(mastery.multiplier==5 and mastery.best_chain==40,"Chain capped at five, best retained")
	mastery.advance(5)
	check(mastery.multiplier==1 and mastery.best_chain==40,"Expired chain resets without losing record")
	check(mastery.objective("formation")==2500 and mastery.objective("formation")==0,"Objective reward exactly once")
	check(mastery.rank(true,0,0)=="S","Mastery produces S rank")
	mastery.hit()
	check(mastery.chain==0,"Damage breaks chain")
	root.size = Vector2i(1920,1080)
	var app = load("res://scenes/campaign.tscn").instantiate()
	app.testing = true
	app.profile.path = "user://toppissime-test-fixture.json"
	root.add_child(app)
	current_scene = app
	await process_frame
	app.profile.reset()
	app.profile.data.unlocked = 32
	app.profile.data.run_score = 4321
	app.profile.data.upgrades = [2,1,1]
	for mission in app.missions:
		check(mission.acts.size()==4,"Four acts in every mission")
		check(mission.events.all(func(e): return float(e.time)<float(mission.duration)),"Events reachable")
		if mission.secondary=="bomber": check(mission.events.any(func(e): return e.kind=="bomber"),"Bomber objective reachable")
		if mission.secondary=="naval": check(mission.events.any(func(e): return e.kind=="naval"),"Naval objective reachable")
	check(app.missions[0].boss=="bomber","Showcase has a command bomber finale")
	for aircraft in range(3):
		app.profile.data.aircraft = aircraft
		app._launch(1)
		var d = app.director
		app.cockpit.flight.get_node("Departure").finish_immediately()
		d.set_physics_process(false)
		d.combat.set_physics_process(false)
		d.charge = 100
		check(d.use_strike(),"Aircraft ability available")
		d._update_ability(.1)
		if aircraft==0: check(d.weapons.shot_interval<d.base_interval,"Vanguard increases cadence")
		if aircraft==1: check(d.player.speed>d.base_speed and d.weapons.projectile_damage>d.base_damage,"P38 pursuit boosts speed and damage")
		if aircraft==2: check(d.player.invulnerable_time>0 and d.weapons.projectile_damage>d.base_damage,"Corsair bastion protects and boosts shells")
		d._update_ability(10)
		check(d.player.speed==d.base_speed and d.weapons.shot_interval==d.base_interval and d.weapons.projectile_damage==d.base_damage,"Ability restores baseline")
		d._spawn_boss("bomber")
		var boss = d.boss
		boss.age = 5
		boss.collision_layer = 2
		for i in range(2):
			boss.take_hit_at(999,boss.to_global(boss.component_position(i)))
			if boss.dying and i==0:
				# Start a fresh boss so both local hit lanes can be verified independently.
				check(boss.component_health[0]==0,"Left weak point accepts aimed hits")
				boss.dying = false; boss.health = boss.max_health; boss.collision_layer = 2
		check(boss.component_health[1]==0,"Right weak point accepts aimed hits")
		for i in range(100): d.details.burst(Vector3.ZERO,true)
		check(d.details.batch.multimesh.instance_count==64 and d.details.trails.size()==2,"Fragment and wing-trail pools stay bounded under a burst")
		for i in range(180): d.details._physics_process(1.0/60)
		check(d.details.lifetimes.count(0.0)==64,"Fragments retire after their lifetime")
		app._dispose_run()
		await process_frame
	var campaign: Dictionary = app.profile.data.duplicate(true)
	app._start_mode("arcade",2)
	check(app.director.combat.score==0 and app.director.profile.data.upgrades==[0,0,0],"Arcade starts with fixed equipment and zero score")
	check(app.profile.data==campaign,"Arcade launch leaves campaign untouched")
	app.director._end(false)
	await process_frame
	await process_frame
	check(app.profile.data.run_score==campaign.run_score and app.profile.data.records==campaign.records,"Arcade results never overwrite campaign progress")
	check(app.profile.data.arcade_records.has("2:2"),"Arcade record stored per mission and aircraft")
	app._dispose_run()
	await process_frame
	campaign = app.profile.data.duplicate(true)
	app._start_mode("practice",4)
	check(app.director.practice and is_instance_valid(app.director.boss) and app.director.event_index==app.director.mission.events.size(),"Practice jumps straight to boss")
	check(app.profile.data==campaign,"Practice leaves campaign untouched")
	app._show_pause()
	app._show_bindings()
	check(paused and app.buttons.size()>=10,"Binding menu remains paused and navigable")
	app.profile.data.bindings.fire = KEY_F
	app._apply_bindings()
	var found := false
	var pad := false
	for e in InputMap.action_get_events("fire"):
		if e is InputEventKey and e.keycode==KEY_F: found = true
		if e is InputEventJoypadButton: pad = true
	check(found and pad,"Rebinding keyboard preserves gamepad")
	app.profile.data.settings.quality = 0
	app._apply_graphics()
	check(not app.director.details.enabled and not app.cockpit.flight.get_node("KeyLight").shadow_enabled,"Performance preset removes optional costs")
	check(app.profile.save()==OK,"Extended profile saves")
	var restored = load("res://scripts/campaign/profile.gd").new()
	restored.path = app.profile.path
	check(restored.load_profile() and restored.data.bindings.fire==KEY_F and restored.data.settings.quality==0,"Extended profile roundtrip")
	app._show_main()
	app._launch(6)
	app.cockpit.flight.get_node("Departure").finish_immediately()
	var escort = app.director
	escort.set_physics_process(false)
	escort.combat.set_physics_process(false)
	escort.elapsed = float(escort.mission.duration)*.27
	escort._update_acts()
	check(is_instance_valid(escort.convoy) and escort.convoy.collision_layer==4,"Friendly escort spawns in the convoy act")
	await physics_frame
	await physics_frame
	var ship = escort.convoy
	escort.combat._launch_enemy_round(ship.global_position+Vector3(0,0,-5),ship.global_position,14)
	escort.combat._update_bullets(.5)
	check(ship.health==5,"Enemy bullet sweep really damages the friendly ship")
	ship.remaining = .01
	ship.advance(.02,escort.combat)
	check(escort.mastery.secondary_complete,"Surviving convoy completes secondary objective")
	app._show_main()
	app.music.stop()
	await process_frame
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(app.profile.path+suffix): DirAccess.remove_absolute(app.profile.path+suffix)
	print("TOPPISSIME: ",checks," checks; failures: ",failures)
	quit(0 if failures.is_empty() else 1)
