extends SceneTree
const RECORDER := preload("res://scripts/campaign/flight_analysis.gd")
const ENEMY := preload("res://scripts/enemy_zero.gd")
var failures: Array[String] = []
var checks := 0
var app: Node
var director: Node
var combat: Node3D
var player: Node3D
var report: Dictionary = {}

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func _initialize() -> void: _run.call_deferred()

func _freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children(): _freeze(child)

func _stop_audio(node: Node) -> void:
	if node is AudioStreamPlayer or node is AudioStreamPlayer3D: node.stop()
	for child in node.get_children(): _stop_audio(child)

func _reset() -> void:
	combat.clear_enemy_bullets()
	combat.game_over = false
	combat.automatic_waves = false
	combat.bombers_enabled = false
	combat.special_enabled = false
	combat.respawn_time = 0
	combat.projectile_speed_scale = 1
	player.alive = true
	player.controls_enabled = true
	player.health = 3
	player.invulnerable_time = 0
	player.position = Vector3(-2,0,2)
	player.get_node("Hurtbox").collision_layer = 4
	player.get_node("Hurtbox/Shape").disabled = false
	director.active = true
	director.paused = false
	director.ending = false
	director.ring_time = 0
	director.mastery = preload("res://scripts/campaign/mastery.gd").new()
	combat._update_bullets(0)

func _test_contacts() -> void:
	_reset()
	combat._launch_enemy_round(Vector3(0,0,2),Vector3(0,0,3),0)
	player.position.x = 2
	combat._update_bullets(.2)
	check(player.health==2,"Lateral crossing of a stationary round hits the real moving hurtbox")
	check(combat.lifetimes[0]==0 and director.mastery.grazes==0,"A moving-player hit consumes once and never rewards a graze")
	combat._update_bullets(.2)
	check(player.health==2,"Consumed contact cannot damage twice")
	_reset()
	combat._launch_enemy_round(Vector3(2,0,-2),Vector3(2,0,6),40)
	player.position.x = 2
	combat._update_bullets(.2)
	check(player.health==3,"Bullet and player paths crossing at different times do not produce an endpoint-only false hit")
	_reset()
	combat._launch_enemy_round(Vector3(0,0,2.8),Vector3(0,0,3),0)
	player.position.x = 2
	combat._update_bullets(.2)
	check(player.health==3 and director.mastery.grazes==1,"A safe lateral near miss preserves one genuine graze")
	for mode in ["protected","layer_disabled","shape_disabled"]:
		_reset()
		if mode=="protected": player.invulnerable_time = 2
		if mode=="layer_disabled": player.get_node("Hurtbox").collision_layer = 0
		if mode=="shape_disabled": player.get_node("Hurtbox/Shape").disabled = true
		combat._launch_enemy_round(Vector3(0,0,2),Vector3(0,0,3),0)
		player.position.x = 2
		combat._update_bullets(.2)
		check(player.health==3 and director.mastery.grazes==0,"Moving contact honors "+mode)
		check((combat.lifetimes[0]==0)==(mode=="protected"),"Only an enabled protected hull consumes a crossing round: "+mode)
	for hz in [30,60,144]:
		_reset()
		player.position.x = -1
		combat._update_bullets(0)
		combat._launch_enemy_round(Vector3(0,0,2),Vector3(0,0,3),0)
		for frame in range(ceili(float(hz)/6.0)):
			player.position.x += 12.0/hz
			combat._update_bullets(1.0/hz)
		check(player.health==2,"Relative hit agrees at %d physics updates per second" % hz)
	_reset()
	combat.set_presentation_altitude(-5.8)
	combat._launch_enemy_round(Vector3(0,0,2),Vector3(0,0,3),0)
	player.position.x = 2
	combat._update_bullets(.2)
	check(player.health==2,"Low-flight visual altitude cannot change relative hit geometry")
	combat.set_presentation_altitude(0)
	_reset()
	combat.clear_enemy_bullets()
	player.position.x = 2
	combat._launch_enemy_round(Vector3(0,0,2),Vector3(0,0,3),0)
	combat._update_bullets(.2)
	check(player.health==3,"Clearing on respawn resets movement history, preventing a teleport contact")

func _test_warning() -> void:
	_reset()
	var enemy := ENEMY.new()
	enemy.position = Vector3(0,0,-.1)
	enemy.loop_z = 0
	enemy.shot_limit = 1
	combat.add_child(enemy)
	combat.enemies.append(enemy)
	var before: int = combat.enemy_shots
	combat._physics_process(.3)
	check(combat.enemy_shots==before and is_equal_approx(float(enemy.get_meta("fire_warning",0)),.22),"A long scheduling frame preserves the full newly created firing warning")
	combat._physics_process(.21)
	check(combat.enemy_shots==before,"A fighter cannot shoot before its visible warning expires")
	combat._physics_process(.011)
	check(combat.enemy_shots==before+1,"The warned fighter shot releases once when the full warning has elapsed")
	enemy.retire()
	combat.enemies.clear()

func _test_convoy_order() -> void:
	_reset()
	player.position = Vector3(0,0,5)
	combat._update_bullets(0)
	var ship = preload("res://scripts/campaign/convoy.gd").new()
	ship.position = Vector3.ZERO
	combat.add_child(ship)
	await physics_frame
	await physics_frame
	combat._launch_enemy_round(Vector3(0,0,-5),Vector3(0,0,7),24)
	combat._update_bullets(.5)
	check(ship.health==5 and player.health==3,"The convoy receives an earlier world contact before the player in the same sweep")
	ship.position.z = 8
	ship.protection = 0
	await physics_frame
	await physics_frame
	combat._launch_enemy_round(Vector3(0,0,2),Vector3(0,0,12),20)
	combat._update_bullets(.5)
	check(ship.health==5 and player.health==2,"An earlier relative player contact consumes the round before the convoy")
	ship.retire()
	await process_frame

func _test_recorder() -> void:
	var recorder := RECORDER.new()
	for tick in range(481):
		recorder.capture(tick*.1,{"score":tick*25,"kills":tick/10,"damage":tick/120,"grazes":tick/4})
	var snapshot := recorder.snapshot()
	check(snapshot.samples.size()==6 and snapshot.samples[0].score==0,"Twelve-second bins keep a zero origin plus bounded cumulative observations")
	check(snapshot.totals.score==12000 and is_equal_approx(snapshot.elapsed,48.0),"Final partial-bin observation retains the exact combat totals")
	snapshot.samples[1].score = -1
	snapshot.totals.score = -1
	check(recorder.snapshot().samples[1].score>=0 and recorder.snapshot().totals.score==12000,"Exported flight data never aliases the live recorder")
	for i in range(120): recorder.mark(i,"hit")
	check(recorder.snapshot().events.size()==96 and recorder.dropped_events==24,"The event budget stays bounded without silently claiming all events are shown")
	for i in range(4000): recorder.capture(float(i)*12,{"score":i*100})
	check(recorder.snapshot().samples.size()<=257 and recorder.elapsed==47988.0,"Long sessions retain final totals within the fixed sample budget")
	var elapsed: float = recorder.elapsed
	recorder.capture(-1,{"score":999999})
	recorder.capture(NAN,{"score":999999})
	check(recorder.elapsed==elapsed,"Invalid and backward observations cannot corrupt recorder time")

func _test_director_recording() -> void:
	_reset()
	director.flight_analysis = RECORDER.new()
	director.elapsed = 0
	director.event_index = director.mission.events.size()
	director.act_index = 3
	director.damage_taken = 0
	director.deaths = 0
	director.start_score = 1000
	combat.score = 1000
	combat.kills = 0
	director.previous_kills = 0
	player.controls_enabled = false
	director.advance(10)
	check(director.flight_analysis.snapshot().samples.size()==1 and director.elapsed==0,"Takeoff records no flight time or samples")
	player.controls_enabled = true
	director.paused = true
	director.advance(10)
	director._record_flight_event("bomb")
	check(director.flight_analysis.events.is_empty() and director.elapsed==0,"Paused flight records no time or events")
	director.paused = false
	combat.score += 100
	combat.kills += 1
	director.advance(12.1)
	check(director.flight_analysis.snapshot().totals.score==100 and director.flight_analysis.snapshot().totals.kills==1,"Production recorder observes mission-local score and real combat counts")
	player.invulnerable_time = 0
	player.take_damage(1)
	check(director.flight_analysis.events.back().kind=="hit" and director.flight_analysis.totals.damage==1,"Production damage signal records the matching hit without granting points")
	director.bombs = 2
	check(director.use_bomb() and director.flight_analysis.events.back().kind=="bomb","A successful bomb records its activation")
	director.charge = 100
	check(director.use_strike() and director.flight_analysis.events.back().kind=="strike","A successful special records its activation")
	var events_before: int = director.flight_analysis.events.size()
	check(not director.use_strike() and director.flight_analysis.events.size()==events_before,"Rejected inputs do not manufacture recorder events")
	player.invulnerable_time = 0
	player.health = 1
	player.take_damage(1)
	check(director.flight_analysis.events.back().kind=="death" and director.flight_analysis.events[director.flight_analysis.events.size()-2].kind=="hit","Lethal damage records one hit followed by the real death signal")
	events_before = director.flight_analysis.events.size()
	director.ending = true
	director._record_flight_event("boss")
	check(director.flight_analysis.events.size()==events_before,"Landing cannot add combat events")
	for connection in director.finished.get_connections(): director.finished.disconnect(connection.callable)
	director.finished.connect(func(value): report=value)
	director._end(true)
	check(report.flight_analysis.totals.score==100 and report.mission_score==100+report.bonus,"Result flight analysis excludes the separate survival bonus")
	check(is_equal_approx(report.flight_analysis.elapsed,report.seconds),"Result and analysis use the same active-flight clock")

func _run() -> void:
	_test_recorder()
	root.size = Vector2i(1920,1080)
	app = load("res://scenes/campaign.tscn").instantiate()
	app.testing = true
	app.profile.path = "user://flight-integrity-isolated.json"
	root.add_child(app)
	current_scene = app
	await process_frame
	app.profile.reset()
	app._launch(1)
	director = app.director
	combat = director.combat
	player = director.player
	app.cockpit.flight.get_node("Departure").finish_immediately()
	_freeze(app)
	_test_contacts()
	_test_warning()
	await _test_convoy_order()
	_test_director_recording()
	# Lethal-hit and bomb fixtures can leave WAV playback pending in the
	# audio server. Stop all players and let the server drain before freeing
	# their scene resources, even when the device is the silent Dummy driver.
	app.music.stop()
	_stop_audio(app)
	await create_timer(.25).timeout
	app.queue_free()
	current_scene = null
	await process_frame
	await process_frame
	await create_timer(.1).timeout
	for suffix in ["",".bak",".tmp"]:
		var path: String = "user://flight-integrity-isolated.json"+suffix
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	print("FLIGHT INTEGRITY: ",checks," checks; failures: ",failures)
	quit(0 if failures.is_empty() else 1)
