extends SceneTree
var failures: Array[String] = []
var checks := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var app = load("res://scenes/campaign.tscn").instantiate()
	app.testing = true
	app.profile.path = "res://tests/dynamic-save-test.json"
	root.add_child(app)
	current_scene = app
	await process_frame
	app.profile.reset()
	app.profile.data.unlocked = 32
	app.profile.data.run_score = 12345
	app.profile.data.run_lives = 4
	app.profile.data.power = "laser"
	check(app.profile.save()==OK,"Save cumulative run state")
	var restored = load("res://scripts/campaign/profile.gd").new()
	restored.path = app.profile.path
	check(restored.load_profile() and restored.data.run_score==12345 and restored.data.power=="laser" and restored.data.run_lives==4,"Score, lives and exclusive weapon survive reload")
	var legacy := {"version":1,"unlocked":3,"next_mission":3,"pow_ready":true,"records":{"1":{"score":400,"grade":1},"2":{"score":600,"grade":2}}}
	FileAccess.open(restored.path,FileAccess.WRITE).store_string(JSON.stringify(legacy))
	check(restored.load_profile() and restored.data.run_score==1000 and restored.data.power=="spread","Old campaign migrates totals and POW without losing progress")
	app.profile.save()
	for m in app.missions: check(m.events.size()>=19,"Each stage has at least 19 encounters")
	app._launch(2)
	var cockpit = app.cockpit
	var d = app.director
	var c = cockpit.combat
	var w = d.weapons
	var p = d.player
	var departure = cockpit.flight.get_node("Departure")
	check(departure.active and not p.controls_enabled,"Mission 2 starts on carrier too")
	check(c.score==12345 and c.remaining_lives==4 and w.power_type=="laser","Mission loads campaign score and loadout")
	check(cockpit.play_rect.size.x >= cockpit.size.x*.99 and cockpit.play_rect.size.y>=cockpit.size.y*.88,"Game uses full width and at least 88 percent of screen height")
	p.position.x = 100
	p._keep_inside_screen()
	check(p.get_screen_bounds().end.x<=cockpit.viewport.size.x+1,"Player remains inside widened screen")
	departure.finish_immediately()
	check(is_equal_approx(cockpit.flight.get_node("Seascape").scroll_speed,float(d.mission.scroll)),"Takeoff restores the mission scroll speed")
	d.event_index = d.mission.events.size()
	c.set_physics_process(false)
	d.set_physics_process(false)
	var pickup = c.pickup
	for kind in ["spread","laser","life","laser","spread"]:
		var old_lives: int = c.remaining_lives
		pickup.activate(p.position,p,kind)
		pickup.collect(c)
		check(w.power_type==kind and w.spread_enabled==(kind=="spread"),"Exclusive pickup: "+kind)
		check(c.remaining_lives==old_lives+(1 if kind=="life" else 0),"Only life icon grants extra life")
	# Genuine beam raycasts, without passing damage directly to the collider.
	d._spawn_naval(0)
	var ship = d.navals[0]
	ship.position = Vector3(p.position.x,0,-3)
	ship.health = 100
	w.set_power("laser")
	Input.action_press("fire")
	for frame in range(40): await physics_frame
	check(ship.health<100 and ship.health>=70,"Laser hits at a bounded tick rate")
	check(w.laser.visible and w.active_count==0,"Laser replaces projectiles, no stacked weapons")
	Input.action_release("fire")
	await physics_frame
	await physics_frame
	check(not w.laser.visible and not w.laser_audio.playing,"Releasing fire stops laser and audio")
	# Carrier recovery completes before results; no shooting or damage during landing.
	d.elapsed = d.mission.duration
	d.advance(.016)
	check(d.ending and departure.landing_active and not p.controls_enabled,"Victory starts landing before results")
	var start_score: int = c.score
	for frame in range(419): d.advance(1.0/60)
	check(d.active,"Results wait for completed approach and braking")
	for frame in range(4): d.advance(1.0/60)
	await process_frame
	check(departure.landed and is_equal_approx(p.position.y,departure.DECK_ALTITUDE),"Player ends on the flight deck")
	check(absf(p.position.z-departure.carrier.position.z)<10 and is_equal_approx(p.bank.rotation.x,0),"Aircraft stops level inside carrier")
	check(app.page=="result" and app.profile.data.run_score>start_score,"Result saves cumulative score after landing")
	var total: int = app.profile.data.run_score
	app._launch(3)
	check(app.cockpit.combat.score==total,"Next stage preserves cumulative score")
	check(app.cockpit.flight.get_node("Departure").active,"Next mission always launches from carrier")
	app._show_main()
	app.music.stop()
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(restored.path+suffix): DirAccess.remove_absolute(restored.path+suffix)
	var report := {"checks":checks,"failures":failures}
	FileAccess.open("res://tests/dynamic-results.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("DYNAMIC CAMPAIGN: ",report)
	await create_timer(.2).timeout
	quit(0 if failures.is_empty() else 1)
