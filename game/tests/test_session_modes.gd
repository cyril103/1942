extends SceneTree
## Exercise the real app callbacks without reading or writing the player's save.
const FIXTURE_PATH := "user://session-modes-regression-fixture.json"
const CAMPAIGN_FIELDS := ["unlocked","next_mission","completed","credits","high_score","records","run_score","run_lives","power","pow_ready","upgrades","difficulty"]
var failures: Array[String] = []
var checks := 0
var app: Control

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func _initialize() -> void:
	_run.call_deferred()

func _campaign_snapshot(data: Dictionary) -> Dictionary:
	var snapshot := {}
	for key in CAMPAIGN_FIELDS: snapshot[key] = data[key]
	return snapshot.duplicate(true)

func _fixture(unlocked := 4) -> void:
	app._show_main()
	app.profile.reset()
	app.profile.data.merge({"unlocked":unlocked,"next_mission":mini(2,unlocked),"aircraft":1,"difficulty":2,"credits":42,"upgrades":[3,3,3],"run_score":9999,"run_lives":5,"power":"laser","high_score":20000},true)
	app.profile.data.records["1"] = {"score":9999,"grade":3,"rank":"A","best_chain":20}
	check(app.profile.save()==OK,"Isolated campaign fixture saves")
	app._show_main()

func _press(prefix: String) -> void:
	for button in app.buttons:
		if button.text.begins_with(prefix) and not button.disabled:
			button.pressed.emit()
			return
	check(false,"Reachable menu button: "+prefix)

func _freeze_run() -> void:
	app.cockpit.flight.process_mode = Node.PROCESS_MODE_DISABLED

func _report(won: bool) -> Dictionary:
	return {"won":won,"score":10699,"mission_score":700,"kills":5,"naval_kills":0,"ground_kills":0,"deaths":0 if won else 5,"bonus":0,"grade":3 if won else 0,"lives":4,"power":"spread","rank":"A","best_chain":18,"accuracy":.5,"secondary":true}

func _save_and_reload() -> RefCounted:
	# Use the app's normal save path as well as the production profile loader.
	app.testing = false
	app._save()
	app.testing = true
	var restored = app.PROFILE.new()
	restored.path = FIXTURE_PATH
	check(restored.load_profile(),"Transition result survives a profile reload")
	return restored

func _check_campaign_launch(number: int, expected_score: int, expected_lives: int) -> void:
	check(app.page=="playing" and app.play_mode=="campaign" and app.selected_mission==number,"Campaign briefing launches its displayed accessible mission")
	check(app.session_profile==app.profile and app.director.profile==app.profile and not app.director.practice,"Campaign launch uses the displayed persistent profile")
	check(app.director.profile.data.upgrades==[3,3,3] and app.director.profile.data.difficulty==2,"Campaign launch retains real upgrades and difficulty")
	check(app.cockpit.combat.score==expected_score and app.cockpit.combat.remaining_lives==expected_lives,"Campaign launch retains saved cumulative score and lives")
	check(app.cockpit.flight.get_node("Weapons").power_type==app.profile.data.power,"Campaign launch retains the displayed saved weapon")
	_freeze_run()

func _result_hangar_path(mode: String, won: bool, unlocked := 4) -> void:
	_fixture(unlocked)
	var before := _campaign_snapshot(app.profile.data)
	var number := 2 if mode=="campaign" else 4
	app._start_mode(mode,number)
	check(app.page=="playing" and app.play_mode==mode,"Start "+mode+" before "+("victory" if won else "defeat"))
	_freeze_run()
	if mode!="campaign":
		check(app.session_profile!=app.profile and app.director.profile==app.session_profile,"Isolated "+mode+" uses a separate session profile")
		check(app.session_profile.data.upgrades==[0,0,0] and app.cockpit.combat.score==0,"Isolated "+mode+" starts with fixed equipment and zero score")
		check(app.session_profile.data.difficulty==1 and app.director.practice==(mode=="practice"),"Isolated "+mode+" uses its own rules")
		check(app.cockpit.flight.get_node("Weapons").power_type==("spread" if mode=="practice" else "none"),"Isolated "+mode+" uses its expected weapon")
		if mode=="practice": check(is_instance_valid(app.director.boss),"Practice starts a real supported boss")
	app._show_result(_report(won))
	check(app.page=="result" and paused,"Result pauses the ended session")
	var restored = _save_and_reload()
	if mode!="campaign":
		check(_campaign_snapshot(app.profile.data)==before and _campaign_snapshot(restored.data)==before,"Isolated "+mode+" result preserves campaign progression in memory and on disk")
		check(app.profile.data.arcade_records.has("4:1")== (mode=="arcade"),"Only Arcade records a score-attack result")
	elif won:
		check(restored.data.next_mission==3 and restored.data.run_score==10699 and restored.data.run_lives==4,"Campaign victory saves the next mission and cumulative run")
	else:
		check(_campaign_snapshot(restored.data)==before,"Campaign defeat preserves the last mission checkpoint")
	_press("HANGAR")
	var expected_mission := 3 if mode=="campaign" and won else mini(2,unlocked)
	check(app.page=="hangar" and app.play_mode=="campaign" and app.session_profile==app.profile,"Result → Hangar explicitly enters campaign context")
	check(app.selected_mission==expected_mission and app.selected_mission<=app.profile.data.unlocked,"Hangar selects an accessible campaign mission")
	check(not paused and not is_instance_valid(app.cockpit),"Hangar disposes the previous isolated session and unpauses menus")
	_press("RETOUR AU BRIEFING")
	check(app.page=="briefing" and app.play_mode=="campaign","Hangar returns to a campaign briefing")
	_press("DÉCOLLER")
	_check_campaign_launch(expected_mission,10699 if mode=="campaign" and won else 9999,4 if mode=="campaign" and won else 5)
	app._show_main()
	await process_frame

func _replay_and_pause(mode: String) -> void:
	_fixture(2 if mode=="campaign" else 4)
	var number := 2 if mode=="campaign" else 4
	app._start_mode(mode,number)
	_freeze_run()
	app._show_result(_report(false))
	_press("RÉESSAYER LA MISSION")
	check(app.page=="playing" and app.play_mode==mode and app.selected_mission==number,"Result retry retains "+mode+" and its mission")
	check((app.session_profile==app.profile)==(mode=="campaign"),"Result retry retains "+mode+" profile isolation")
	_freeze_run()
	app._show_pause()
	_press("RECOMMENCER LA MISSION")
	check(app.page=="playing" and app.play_mode==mode and app.selected_mission==number and not paused,"Pause restart retains "+mode+" and unpauses")
	_freeze_run()
	app._show_result(_report(true))
	if mode=="campaign":
		_press("MISSION SUIVANTE")
		check(app.page=="briefing" and app.play_mode=="campaign" and app.selected_mission==3,"Campaign victory still offers the next mission")
		_press("DÉCOLLER")
		_check_campaign_launch(3,10699,4)
	else:
		_press("REJOUER LA MISSION")
		check(app.page=="playing" and app.play_mode==mode and app.selected_mission==4,"Victory replay retains "+mode+" without advancing to a non-boss mission")
		_freeze_run()
	app._show_main()
	check(app.page=="main" and app.play_mode=="campaign" and app.session_profile==app.profile,"Return home resets "+mode+" to campaign context")
	await process_frame

func _refused_launches() -> void:
	_fixture(1)
	app._show_briefing(1)
	var before := _campaign_snapshot(app.profile.data)
	for request in [[2,"campaign"],[0,"campaign"],[33,"arcade"],[5,"practice"],[4,"invalid"]]:
		app._start_mode(request[1],request[0])
		check(app.page=="briefing" and app.play_mode=="campaign" and app.selected_mission==1 and not is_instance_valid(app.cockpit),"Invalid/locked request is rejected without changing the menu: "+str(request))
	app._start_mode("practice",4)
	check(app.page=="playing" and is_instance_valid(app.director.boss),"A supported boss remains available in Practice independently of campaign unlocks")
	_freeze_run()
	var existing: Control = app.cockpit
	var kind: String = app.missions[3].boss
	app.missions[3].boss = ""
	app._start_mode("practice",4)
	check(app.cockpit==existing and app.page=="playing" and app.play_mode=="practice","An absent practice boss cannot replace a valid active session")
	app.missions[3].boss = "unknown_boss"
	app._start_mode("practice",4)
	check(app.cockpit==existing,"An unsupported practice boss is rejected before instantiation")
	app.missions[3].boss = kind
	check(_campaign_snapshot(app.profile.data)==before,"Rejected launch requests cannot mutate campaign progression")
	app._show_main()
	await process_frame

func _corrupt_profile_notice() -> void:
	app._dispose_run()
	if is_instance_valid(app.music): app.music.stop()
	app.queue_free()
	await process_frame
	var primary := "{\"version\":1,\"credits\":{\"invalid\":true}}"
	var backup := "{broken backup"
	FileAccess.open(FIXTURE_PATH,FileAccess.WRITE).store_string(primary)
	FileAccess.open(FIXTURE_PATH+".bak",FileAccess.WRITE).store_string(backup)
	app = load("res://scenes/campaign.tscn").instantiate()
	app.testing = true
	app.profile.path = FIXTURE_PATH
	root.add_child(app)
	current_scene = app
	await process_frame
	check(app.profile.last_error==ERR_FILE_CORRUPT and app.notice.text.contains("SAUVEGARDE ILLISIBLE"),"Startup displays unrecoverable save status instead of silently replacing it")
	check(app.profile.data.records.is_empty(),"Failed load does not invent a completed campaign")
	_press("NOUVELLE CAMPAGNE")
	check(app.page=="new_campaign","A fresh profile after corruption requires the existing explicit confirmation")
	_press("CONSERVER MA CAMPAGNE")
	check(app.page=="main" and app.notice.text.contains("SAUVEGARDE ILLISIBLE"),"Cancelling a fresh campaign keeps the save warning visible")
	app.testing = false
	app._save()
	app.testing = true
	check(app.profile.last_error==ERR_FILE_CORRUPT and app.notice.text.contains("SAUVEGARDE IMPOSSIBLE"),"Blocked write reports failure to the player")
	check(FileAccess.get_file_as_string(FIXTURE_PATH)==primary and FileAccess.get_file_as_string(FIXTURE_PATH+".bak")==backup,"Startup and save attempt preserve both unreadable files byte for byte")

func _run() -> void:
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(FIXTURE_PATH+suffix): DirAccess.remove_absolute(FIXTURE_PATH+suffix)
	app = load("res://scenes/campaign.tscn").instantiate()
	app.testing = true
	app.profile.path = FIXTURE_PATH
	root.add_child(app)
	current_scene = app
	await process_frame
	for mode in ["campaign","arcade","practice"]:
		for won in [false,true]: await _result_hangar_path(mode,won,2 if mode=="campaign" else 4)
		await _replay_and_pause(mode)
	# In particular, boss 04 → Hangar must remain usable with only mission 01 unlocked.
	await _result_hangar_path("practice",true,1)
	await _refused_launches()
	await _corrupt_profile_notice()
	app._dispose_run()
	if is_instance_valid(app.music): app.music.stop()
	app.queue_free()
	await process_frame
	await create_timer(.2).timeout
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(FIXTURE_PATH+suffix): DirAccess.remove_absolute(FIXTURE_PATH+suffix)
	print("SESSION MODES TEST ",checks," checks, ",failures.size()," failures: ",failures)
	quit(0 if failures.is_empty() else 1)
