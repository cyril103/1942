extends SceneTree
const RUSH := preload("res://scripts/campaign/boss_rush.gd")
var checks := 0
var failures: Array[String] = []
var app: Control

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func geometry(context: String) -> void:
	var bounds := Rect2(0,0,1920,1080)
	for child in app.design.get_children():
		if child is not Control: continue
		check(bounds.encloses(child.get_rect()),context+" contains "+str(child.name))
		if child is Label: check(child.get_minimum_size().y<=child.size.y+.2,context+" wraps "+str(child.name))
	for i in range(app.buttons.size()):
		for j in range(i+1,app.buttons.size()): check(not app.buttons[i].get_rect().intersects(app.buttons[j].get_rect()),context+" buttons do not overlap")

func report(won: bool, mission: int, score: int, lives: int) -> Dictionary:
	return {"won":won,"mission":mission,"score":score,"mission_score":1000,"lives":lives,"seconds":30.0,"grazes":4,"kills":1,"naval_kills":0,"deaths":0,"bonus":0,"grade":3,"power":"spread"}

func _run() -> void:
	var ledger := RUSH.new()
	ledger.begin(1)
	check(not ledger.advance(),"Cannot skip a boss before victory")
	check(not ledger.accept(report(true,8,100,3)),"Cannot claim a different boss")
	for i in range(8):
		var result := report(true,RUSH.ROUTE[i],(i+1)*1000,2)
		check(ledger.accept(result),"Accept each real route stage once")
		check(not ledger.accept(result),"Duplicate result cannot double time, grazes or clears")
		check(ledger.advance()==(i<7),"Advance only between completed route stages")
	check(ledger.complete() and ledger.score==8000 and ledger.grazes==32 and ledger.seconds==240,"Eight bosses aggregate score, grazes and time once")
	ledger.begin(2)
	check(ledger.accept(report(false,4,900,0)) and not ledger.active and not ledger.advance(),"Defeat ends the run without a continuation")
	ledger.begin(0)
	check(ledger.score==0 and ledger.lives==3 and ledger.cleared==0 and ledger.seconds==0,"Restart is a fresh single credit")
	app = load("res://scenes/campaign.tscn").instantiate()
	app.testing = true
	app.profile.path = "user://ultimate-mode-fixture-never-saved.json"
	root.add_child(app)
	app.profile.reset()
	app.profile.data.merge({"run_score":4567,"run_lives":5,"credits":23,"upgrades":[3,2,1],"power":"laser","aircraft":1},true)
	var campaign_before: Dictionary = app.profile.data.duplicate(true)
	for dimensions in [Vector2i(1280,720),Vector2i(1920,1080),Vector2i(2560,1080)]:
		root.size = dimensions
		await process_frame
		app._show_main()
		geometry("main "+str(dimensions))
		app._show_pilot_guide()
		geometry("guide "+str(dimensions))
		app._show_boss_rush()
		geometry("rush lobby "+str(dimensions))
		app._show_bindings()
		geometry("bindings "+str(dimensions))
	app._begin_boss_rush()
	for i in range(8):
		app.cockpit.flight.process_mode = Node.PROCESS_MODE_DISABLED
		check(app.play_mode=="boss_rush" and app.selected_mission==RUSH.ROUTE[i],"Real app launches route boss "+str(i+1))
		check(app.director.boss_rush and app.director.practice and is_instance_valid(app.director.boss),"Rush starts an actual boss directly")
		check(app.session_profile!=app.profile and app.session_profile.data.upgrades==[0,0,0],"Rush has an isolated fixed loadout")
		check(app.director.combat.score==i*1000 and app.director.combat.remaining_lives==(3 if i==0 else 2),"Score and shared lives transfer between duels")
		check(app.director.weapons.power_type=="spread" and app.director.player.health==app.director.player.max_health,"Each duel restores hull and spread")
		var result := report(true,RUSH.ROUTE[i],(i+1)*1000,2)
		app._show_result(result)
		geometry("rush result "+str(i+1))
		app._show_result(result)
		check(app.boss_rush.cleared==i+1,"Duplicate app result cannot grant a second boss clear")
		if i<7:
			check(not app.profile.data.arcade_records.has("rush:1"),"Partial routes do not create completed records")
			app._next_boss_rush()
			await process_frame
	check(int(app.profile.data.arcade_records.get("rush:1",0))==8000,"Full route records the cumulative score for this aircraft")
	var after: Dictionary = app.profile.data.duplicate(true)
	after.arcade_records = campaign_before.arcade_records
	check(after==campaign_before,"Rush preserves every campaign field")
	app._show_main()
	app._begin_boss_rush()
	var previous_generation: int = app.run_generation
	app._begin_boss_rush()
	app._accept_run_result(report(true,4,99999,3),previous_generation)
	check(app.page=="playing" and app.boss_rush.cleared==0 and app.boss_rush.score==0,"A queued result from an abandoned flight cannot finish its replacement")
	app.cockpit.flight.process_mode = Node.PROCESS_MODE_DISABLED
	app._show_pause()
	for button in app.buttons:
		if button.text=="RECOMMENCER LA TRAVERSÉE":
			button.pressed.emit()
			break
	check(app.selected_mission==4 and app.boss_rush.score==0 and app.boss_rush.lives==3 and not paused,"Pause restart creates a fresh route and resumes")
	app.cockpit.flight.process_mode = Node.PROCESS_MODE_DISABLED
	app._show_result(report(false,4,200,0))
	check(not app.boss_rush.active and not app.boss_rush.complete(),"Defeat stops rush")
	check(int(app.profile.data.arcade_records.get("rush:1",0))==8000,"Defeat preserves prior complete record")
	app._show_main()
	app.profile.data.settings.auto_fire = true
	app._launch(1,"campaign")
	app.cockpit.flight.process_mode = Node.PROCESS_MODE_DISABLED
	var weapons: Node = app.director.weapons
	check(weapons.auto_fire,"Saved autofire applies on launch")
	var initial_shots: int = weapons.shots_fired
	weapons._physics_process(.2)
	check(weapons.shots_fired==initial_shots,"Autofire cannot shoot during departure")
	app.cockpit.flight.get_node("Departure").finish_immediately()
	weapons.set_power("none")
	weapons._physics_process(.2)
	check(weapons.shots_fired>initial_shots,"Autofire fires standard rounds in live flight")
	weapons.set_power("laser")
	weapons._update_laser(.1)
	check(weapons.laser.visible,"Autofire sustains the laser")
	app.director.player.controls_enabled = false
	weapons._update_laser(.1)
	check(not weapons.laser.visible,"Autofire laser stops when flight is disabled")
	var decoded: Dictionary = app.profile._decode_candidate(app.profile.data)
	check(bool(decoded.settings.auto_fire),"Autofire setting survives profile decoding")
	var old_profile: Dictionary = app.profile.data.duplicate(true)
	old_profile.settings.erase("auto_fire")
	check(not app.profile._decode_candidate(old_profile).settings.auto_fire,"Old saves retain manual fire by default")
	app._dispose_run()
	if is_instance_valid(app.music): app.music.stop()
	app.queue_free()
	await process_frame
	await create_timer(.2).timeout
	print("ULTIMATE MODES TEST ",checks," checks, ",failures.size()," failures: ",failures)
	quit(0 if failures.is_empty() else 1)
