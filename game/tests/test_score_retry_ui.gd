extends SceneTree
## Real menu actions, rendered criteria and the real departure handoff; no fake kills.
const RULES := preload("res://scripts/campaign/scoring_rules.gd")
const FIXTURE := "user://score-retry-ui-regression.json"
var app: Control
var checks := 0
var failures: Array[String] = []
var observations: Array[Dictionary] = []
var output_dir := "user://score-retry-ui-review"

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output-dir="): output_dir = argument.trim_prefix("--output-dir=")
	DirAccess.make_dir_recursive_absolute(output_dir)
	_run.call_deferred()

func _cleanup() -> void:
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(FIXTURE+suffix): DirAccess.remove_absolute(FIXTURE+suffix)

func _press(text: String) -> void:
	for button in app.buttons:
		if button.text.begins_with(text) and not button.disabled:
			button.pressed.emit()
			return
	check(false,"Real menu button available: "+text)

func _escape() -> void:
	var event := InputEventAction.new()
	event.action = "quit_game"
	event.pressed = true
	app._input(event)

func _geometry(context: String) -> void:
	var canvas := Rect2(Vector2.ZERO,Vector2(1920,1080))
	for child in app.design.get_children():
		if child is not Control: continue
		check(canvas.encloses(child.get_rect()),context+" contains "+str(child.name))
		if child is Label: check(child.get_minimum_size().y<=child.size.y+.2,context+" fits every wrapped line of "+str(child.name))
	for i in range(app.buttons.size()):
		for j in range(i+1,app.buttons.size()): check(not app.buttons[i].get_rect().intersects(app.buttons[j].get_rect()),context+" keeps buttons separate")
	for pair in [["ScoreGuideMain","ScoreGuideMainPanel"],["ScoreGuideChain","ScoreGuideChainPanel"],["MedalCriteria","MedalCriteriaPanel"],["RankCriteria","RankCriteriaPanel"]]:
		if app.design.has_node(pair[0]): check(app.design.get_node(pair[1]).get_rect().encloses(app.design.get_node(pair[0]).get_rect()),context+" keeps scoring text on its measured panel")

func _capture(name: String) -> void:
	if "--capture-ui" not in OS.get_cmdline_user_args(): return
	await create_timer(.3).timeout
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output_dir.path_join("score-retry-"+name+".png"))==OK,"Save scoring/retry evidence: "+name)

func _resize(dimensions: Vector2i) -> void:
	root.size = dimensions
	await process_frame
	await process_frame

func _fixture_report(won: bool, damage: int, chain: int, objective_met := true) -> Dictionary:
	var report := {"won":won,"score":15430,"mission_score":2000,"kills":28,"naval_kills":2,"ground_kills":4,"deaths":0 if won else 3,"damage":damage,"bonus":1000,"lives":5,"power":"laser","best_chain":chain,"accuracy":.62,"secondary":true,"objective_met":objective_met}
	report.grade = RULES.medal(won,int(report.deaths),damage,objective_met)
	report.rank = RULES.rank(won,int(report.deaths),damage,true,chain)
	return report

func _guide_and_results() -> void:
	for dimensions in [Vector2i(1280,720),Vector2i(1920,1080)]:
		await _resize(dimensions)
		app.profile.reset()
		app.profile.data.unlocked = 32
		app._show_briefing(3)
		_press("GUIDE DE SCORE")
		check(app.page=="rules" and app.selected_mission==3 and app.play_mode=="campaign","Before takeoff, guide preserves mission and campaign context")
		var sections: PackedStringArray = RULES.guide().split("\n\n")
		check(app.design.get_node("ScoreGuideMain").text==sections[0]+"\n\n"+sections[1] and app.design.get_node("ScoreGuideChain").text==sections[2],"The whole guide comes directly from rules used by actual scoring")
		_geometry("Score guide "+str(dimensions))
		await _capture("guide-%d" % dimensions.y)
		_escape()
		check(app.page=="briefing" and app.selected_mission==3,"Escape returns the guide to the selected briefing")
		for scenario in [["gold-A",true,2,8,true],["silver-S",true,1,16,false],["defeat",false,8,2,false]]:
			var report := _fixture_report(scenario[1],scenario[2],scenario[3],scenario[4])
			app._launch(3)
			app.cockpit.flight.process_mode = Node.PROCESS_MODE_DISABLED
			app._show_result(report)
			var saved_profile: Dictionary = app.profile.data.duplicate(true)
			var earned: int = app.result_earned
			var original_score_text: String = app.design.get_node("ResultScoreDetails").text
			_press("MÉDAILLE & RANG")
			check(app.page=="criteria","Result opens the actual criteria screen: "+scenario[0])
			check(app.design.get_node("MedalCriteria").text==RULES.criteria_text(RULES.medal_checks(3,report)),"Medal explanation matches actual gold conditions: "+scenario[0])
			check(app.design.get_node("RankCriteria").text==RULES.criteria_text(RULES.rank_checks("S",report)),"Rank explanation matches actual S conditions: "+scenario[0])
			check(app.design.get_node("RankObtained").text.ends_with(report.rank),"Debriefing retains the rank actually awarded")
			if scenario[0]=="gold-A": check(report.grade==3 and report.rank=="A" and app.design.get_node("RankCriteria").text.contains("À atteindre"),"Gold plus A correctly leaves S criteria unmet")
			if scenario[0]=="silver-S": check(report.grade==2 and report.rank=="S" and app.design.get_node("MedalCriteria").text.contains("À atteindre : Objectif principal"),"S can coexist with silver when the main gold objective was missed")
			_geometry("Result criteria "+scenario[0]+" "+str(dimensions))
			await _capture(scenario[0]+"-%d" % dimensions.y)
			_press("GUIDE DE SCORE")
			_escape()
			check(app.page=="criteria","Guide from a result returns to its criteria screen")
			_escape()
			check(app.page=="result" and app.profile.data==saved_profile and app.result_earned==earned,"Returning from analysis never awards credits or persists the result a second time")
			check(app.design.get_node("ResultScoreDetails").text==original_score_text,"The same result retains its original earned-credit summary")
			_geometry("Returned result "+str(dimensions))
			app._show_main()
			await process_frame
		app._show_graphics()
		var option: CheckButton = app.design.get_node("ShortRetryIntro")
		check(not option.button_pressed,"Short retry is visibly disabled by default")
		option.button_pressed = true
		check(app.profile.data.settings.short_retry_intro,"The actual comfort checkbox enables the saved option")
		check(app.design.get_node("ShortRetryExplanation").text.contains("Sans effet en entraînement") and app.design.get_node("ShortRetryExplanation").text.contains("porte-avions"),"The option explains both first discovery and practice limitations")
		_geometry("Comfort options "+str(dimensions))
		await _capture("comfort-%d" % dimensions.y)
		option.button_pressed = false
		check(not app.profile.data.settings.short_retry_intro,"The same checkbox reverses the option immediately")
		app._show_main()

func _freeze() -> void:
	app.cockpit.flight.process_mode = Node.PROCESS_MODE_DISABLED
	app.cockpit._stop_audio(app.cockpit)

func _transition() -> Dictionary:
	var departure = app.cockpit.flight.get_node("Departure")
	var sea = app.cockpit.flight.get_node("Seascape")
	var combat = app.cockpit.combat
	var director = app.director
	var dt := 1.0/60.0
	var steps := 0
	var charge: float = director.charge
	Input.action_press("fire")
	while departure.active and steps<800:
		sea._physics_process(dt)
		app.cockpit.player._physics_process(dt)
		director.weapons._physics_process(dt)
		departure._physics_process(dt)
		combat._physics_process(dt)
		director.advance(dt)
		steps += 1
		if departure.active:
			check(director.elapsed==0 and director.event_index==0,"Real transition never advances mission time or event index")
			check(director.charge==charge and director.ability_time==0,"Real transition never grants charge or an ability")
			check(combat.enemies.is_empty() and combat.bombers.is_empty() and combat.red_enemies.is_empty() and director.navals.is_empty() and not is_instance_valid(director.boss),"No aircraft, naval or boss wave spawns during transition")
			check(not app.cockpit.player.controls_enabled,"Player remains uncontrollable until actual departure handoff")
			check(director.weapons.active_count==0 and not director.weapons.laser.visible,"Holding fire never emits rounds or laser before control handoff")
	Input.action_release("fire")
	check(not departure.active and steps<800,"Departure actually completes and hands over controls")
	check(app.cockpit.player.controls_enabled and departure.phase==departure.Phase.FLIGHT,"Both intros finish through the normal flight handoff")
	observations.append({"mode":app.play_mode,"mission":app.selected_mission,"plane":app.profile.data.aircraft,"transition_seconds":steps*dt,"event_index":director.event_index,"charge":director.charge})
	return {"duration":steps*dt,"state":_state()}

func _state() -> Dictionary:
	var player = app.cockpit.player
	var director = app.director
	var weapons = director.weapons
	var camera: Camera3D = app.cockpit.flight.get_node("Camera")
	return {"score":app.cockpit.combat.score,"lives":app.cockpit.combat.remaining_lives,"power":weapons.power_type,"health":player.health,"max_health":player.max_health,"alive":player.alive,"controls":player.controls_enabled,"protection":player.invulnerable_time,"mission_time":director.elapsed,"combat_time":app.cockpit.combat.combat_time,"event_index":director.event_index,"charge":director.charge,"bombs":director.bombs,"ability":director.ability_time,"deaths":director.deaths,"damage_taken":director.damage_taken,"speed":player.speed,"interval":weapons.shot_interval,"damage":weapons.projectile_damage,"laser_interval":weapons.laser_interval_multiplier,"weapon_cooldown":weapons._cooldown,"laser_cooldown":weapons.laser_clock,"projectiles":weapons.active_count,"position":player.position,"bank_position":player.bank.position,"bank_rotation":player.bank.rotation,"bank_scale":player.bank.scale,"camera_position":camera.position,"camera_rotation":camera.rotation,"camera_size":camera.size,"scroll_speed":app.cockpit.flight.get_node("Seascape").scroll_speed}

func _first_event() -> Dictionary:
	var director = app.director
	var combat = app.cockpit.combat
	var attempts := 0
	while director.event_index==0 and attempts<1800:
		director.advance(1.0/60.0)
		attempts += 1
	check(director.event_index>0,"First authored encounter is dispatched without skipping mission time")
	var signatures: Array = []
	for enemy in combat.enemies: signatures.append([enemy.get_script().resource_path,enemy.health,enemy.flight_speed,enemy.shot_limit,enemy.position])
	return {"event_index":director.event_index,"time":director.elapsed,"kind":director.mission.events[0].kind,"fighters":signatures,"bombers":combat.bombers.size(),"red":combat.red_enemies.size(),"navals":director.navals.size(),"boss":is_instance_valid(director.boss),"score":combat.score,"lives":combat.remaining_lives}

func _departure_variants() -> void:
	app.profile.reset()
	app.profile.data.unlocked = 32
	app.profile.data.settings.short_retry_intro = true
	app.profile.data.run_score = 9012
	app.profile.data.run_lives = 5
	app.profile.data.power = "laser"
	app.profile.data.upgrades = [1,1,1]
	app.profile.data.owned_modules = ["precision","prepared"]
	app.profile.data.equipped_modules = ["precision","prepared"]
	for plane in range(3):
		app.profile.data.aircraft = plane
		for scenario in [["campaign",1],["campaign",3],["arcade",1]]:
			var mode: String = scenario[0]
			var number: int = scenario[1]
			var key := "%s:%d" % [mode,number]
			app.seen_departures.erase(key)
			app._launch(number,mode,true)
			_freeze()
			await process_frame
			var normal_departure = app.cockpit.flight.get_node("Departure")
			check(normal_departure.elapsed==0 and not app.seen_departures.has(key),"An unseen mission takes off normally even when retry and option are requested")
			var normal := _transition()
			check(app.seen_departures.has(key),"Only completing the normal intro records that mission as seen")
			var normal_event := _first_event()
			app._show_pause()
			_press("RECOMMENCER LA MISSION")
			_freeze()
			await process_frame
			var short_departure = app.cockpit.flight.get_node("Departure")
			check(app.play_mode==mode and app.selected_mission==number and short_departure.elapsed==short_departure.LOOP_END,"The actual retry callback preserves mode and enters airborne settling")
			var short := _transition()
			check(absf(float(short.duration)-float(short_departure.SETTLE_DURATION))<.025 and float(short.duration)<float(normal.duration),"Opt-in retry lasts one settling phase, shorter than the complete takeoff")
			for field in normal.state: check(normal.state[field]==short.state[field],"Normal and short retry restore identical actual combat state: "+field+" / "+mode+" / plane"+str(plane))
			var short_event := _first_event()
			check(normal_event==short_event,"First authored event, aircraft positions, timing and pressure remain identical after either intro")
			app._show_main()
			await process_frame
	# An interrupted discovery never qualifies for the optional shortened retry.
	app.seen_departures.clear()
	app._launch(1,"campaign")
	_freeze()
	await process_frame
	var interrupted = app.cockpit.flight.get_node("Departure")
	interrupted._physics_process(.35)
	app._show_pause()
	_press("RECOMMENCER LA MISSION")
	_freeze()
	check(not app.seen_departures.has("campaign:1") and app.cockpit.flight.get_node("Departure").elapsed==0,"Interrupted first takeoff remains a complete discovery on retry")
	_transition()
	app._show_main()
	await process_frame
	# A normal menu launch always shows the full carrier sequence, even if seen.
	app._launch(1,"campaign")
	_freeze()
	check(app.cockpit.flight.get_node("Departure").elapsed==0,"Briefing/new launches keep the complete carrier departure")
	app._show_main()
	await process_frame
	app.profile.data.settings.short_retry_intro = false
	app._launch(1,"campaign",true)
	_freeze()
	check(app.cockpit.flight.get_node("Departure").elapsed==0,"Disabling the comfort setting restores the complete retry intro")
	app._show_main()
	await process_frame
	app.profile.data.settings.short_retry_intro = true
	app._launch(4,"practice",true)
	_freeze()
	var practice_state := _state()
	check(app.play_mode=="practice" and not app.cockpit.flight.get_node("Departure").active and is_instance_valid(app.director.boss),"Practice retains the direct boss start")
	app._show_pause()
	_press("RECOMMENCER LA MISSION")
	_freeze()
	check(app.play_mode=="practice" and _state()==practice_state and not app.seen_departures.has("practice:4"),"Practice retry remains identical and never marks a carrier departure as discovered")
	app._show_main()
	await process_frame

func _run() -> void:
	_cleanup()
	app = load("res://scenes/campaign.tscn").instantiate()
	app.testing = true
	app.profile.path = FIXTURE
	root.add_child(app)
	current_scene = app
	await process_frame
	await _guide_and_results()
	await _departure_variants()
	app.profile.data.settings.short_retry_intro = true
	check(app.profile.save()==OK,"Actual short-retry setting saves to an isolated profile")
	var restored = app.PROFILE.new()
	restored.path = FIXTURE
	check(restored.load_profile() and restored.data.settings.short_retry_intro,"Actual setting survives profile reload")
	app._dispose_run()
	if is_instance_valid(app.music): app.music.stop()
	app.queue_free()
	await process_frame
	await create_timer(.2).timeout
	_cleanup()
	FileAccess.open("res://tests/score-retry-ui-results.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"departures":observations,"human_controller_check":"NOT_PERFORMED"},"\t"))
	print("SCORE / RETRY UI ",checks," checks, ",failures.size()," failures: ",failures)
	quit(0 if failures.is_empty() else 1)
