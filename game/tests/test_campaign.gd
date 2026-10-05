extends SceneTree
var failures: Array[String] = []
var checks := 0
var results: Array[Dictionary] = []
var stage_report: Dictionary = {}
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var app = load("res://scenes/campaign.tscn").instantiate()
	app.testing = true
	app.profile.path = "res://tests/campaign-save-fixture.json"
	root.add_child(app)
	current_scene = app
	await process_frame
	app.profile.reset()
	check(app.missions.size()==32,"Campaign has 32 missions")
	var bosses := 0
	var signatures := {}
	for index in range(32):
		var mission: Dictionary = app.missions[index]
		check(int(mission.id)==index+1,"Mission ids contiguous")
		var previous := -1.0
		for event in mission.events:
			check(float(event.time)>=previous and event.time<mission.duration,"Mission events ordered and reachable")
			previous = event.time
		var signature := JSON.stringify(mission.events)
		signatures[signature] = true
		if mission.boss != "": bosses += 1
	check(bosses==8 and signatures.size()==32,"Eight boss missions and 32 distinct authored schedules")
	var save = app.profile
	check(save.save()==OK,"Profile can be saved atomically")
	save.record_victory(1,2000,3)
	check(save.data.unlocked==2 and save.data.credits==5,"Victory unlocks next stage and pays first-clear medals")
	check(save.record_victory(1,1000,2)==0 and save.data.credits==5,"Replay cannot farm first-clear rewards")
	check(save.buy_upgrade(0) and save.data.upgrades[0]==1 and save.data.credits==3,"Upgrade purchase and save")
	var reload_profile = load("res://scripts/campaign/profile.gd").new()
	reload_profile.path = save.path
	check(reload_profile.load_profile() and reload_profile.data.upgrades[0]==1,"Save round-trip")
	# A corrupt latest file must recover the previous complete snapshot.
	FileAccess.open(save.path,FileAccess.WRITE).store_string("{broken")
	check(reload_profile.load_profile(),"Backup recovers corrupt save")
	save.reset()
	save.data.unlocked = 32
	for number in range(1,33):
		stage_report = {}
		app._launch(number)
		var director = app.director
		for connection in director.finished.get_connections(): director.finished.disconnect(connection.callable)
		director.finished.connect(func(report): stage_report=report)
		var combat = app.cockpit.combat
		var player = app.cockpit.player
		app.cockpit.flight.get_node("Departure").finish_immediately()
		player.get_node("Hurtbox").collision_layer = 0
		for node_name in ["Combat","Player","Weapons","Seascape"]: app.cockpit.flight.get_node(node_name).set_physics_process(false)
		director.set_physics_process(false)
		var phases := {}
		var max_contacts := 0
		for frame in range(60*180):
			combat._physics_process(1.0/60)
			director.advance(1.0/60)
			max_contacts = maxi(max_contacts,combat.get_radar_contacts().size())
			if frame%15==0:
				for enemy in combat.get_radar_contacts():
					if not is_instance_valid(enemy) or enemy==director.boss: continue
					if enemy.global_position.z > -9 and enemy.global_position.z < 10: enemy.take_damage(2)
				if is_instance_valid(director.boss) and director.boss.collision_layer==2:
					phases[director.boss.phase] = true
					director.boss.take_damage(3)
			if frame%120==0: await process_frame
			if not stage_report.is_empty(): break
		check(stage_report.get("won",false),"Mission %02d reaches victory" % number)
		check(director.event_index==director.mission.events.size(),"Mission %02d dispatches every event" % number)
		check(max_contacts <= 25,"Mission %02d keeps actors bounded" % number)
		if director.mission.boss != "":
			check(director.boss_won and phases.size()==3,"Boss %02d traverses three phases before defeat" % number)
		if stage_report.get("won",false): save.record_victory(number,stage_report.score,stage_report.grade)
		results.append({"mission":number,"won":stage_report.get("won",false),"elapsed":director.elapsed,"max_contacts":max_contacts,"phases":phases.size()})
		app._dispose_run()
		await process_frame
	check(save.data.completed and save.data.unlocked==32,"Completing mission 32 finishes campaign")
	check(save.save()==OK,"Completed campaign saves")
	check(reload_profile.load_profile() and reload_profile.data.completed,"Completed campaign reloads")
	app._launch(2)
	app.cockpit.flight.get_node("Departure").finish_immediately()
	var d = app.director
	var p = app.cockpit.player
	p.invulnerable_time = 0
	p.take_damage(1)
	check(p.alive and p.health==p.max_health-1,"Campaign hull absorbs a hit")
	var health: int = p.health
	p.take_damage(1)
	check(p.health==health,"Post-hit invulnerability prevents duplicate damage")
	d.charge = 100
	check(d.use_strike() and d.charge==0,"Charged strike consumes gauge")
	check(d.use_bomb() and d.bombs==1,"Bomb consumes inventory")
	app._show_pause()
	var frozen: float = d.elapsed
	for frame in range(8): await process_frame
	check(d.elapsed==frozen and paused,"Pause freezes campaign")
	app._resume()
	check(not paused and not d.paused,"Resume restores processing")
	app._show_pause()
	app._show_settings(true)
	check(paused and app.settings_from_pause,"Options keep flight paused")
	app._show_pause()
	app._resume()
	# Defeat is a result, not a dead-end scene; retry creates fresh state.
	for connection in d.finished.get_connections(): d.finished.disconnect(connection.callable)
	stage_report = {}
	d.finished.connect(func(report): stage_report=report)
	app.cockpit.combat.remaining_lives = 1
	p.health = 1
	p.invulnerable_time = 0
	p.take_damage(1)
	d.advance(0.1)
	check(not stage_report.is_empty() and not stage_report.won,"Defeat produces a retryable result")
	app._launch(2)
	check(app.cockpit.combat.remaining_lives==3 and app.director.elapsed==0,"Retry resets mission")
	app._show_main()
	await process_frame
	if is_instance_valid(app.music): app.music.stop()
	for suffix in ["",".bak",".tmp"]: if FileAccess.file_exists(save.path+suffix): DirAccess.remove_absolute(save.path+suffix)
	var report := {"checks":checks,"failures":failures,"missions":results}
	FileAccess.open("res://tests/campaign-results.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("CAMPAIGN TEST ",checks," checks, ",failures.size()," failures: ",failures)
	await create_timer(0.2).timeout
	quit(0 if failures.is_empty() else 1)
