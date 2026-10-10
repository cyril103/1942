extends SceneTree
var failures: Array[String] = []
var checks := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)
func _initialize() -> void: _run.call_deferred()
func capture(label: String) -> void:
	if not "--capture-lives" in OS.get_cmdline_user_args(): return
	for i in range(4): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("C:/ChatGPT/1942/renders/lives-"+label+".png")
func _run() -> void:
	var app = load("res://scenes/campaign.tscn").instantiate()
	app.testing = true
	root.add_child(app)
	current_scene = app
	await process_frame
	app.profile.reset()
	app._launch(1)
	var d = app.director
	var c = d.combat
	var p = d.player
	var w = d.weapons
	var departure = app.cockpit.flight.get_node("Departure")
	departure.finish_immediately()
	for node in [d,c,p,w]: node.set_physics_process(false)
	d.elapsed = 25
	d.event_index = 0
	while d.event_index < d.mission.events.size() and d.mission.events[d.event_index].time <= 25:
		d.event_index += 1
	var event_cursor: int = d.event_index
	c.score = 4321
	p.invulnerable_time = 0
	p.take_damage(1)
	check(p.alive and p.health==1 and c.remaining_lives==3,"Armor absorbs the first hit without consuming a life")
	await capture("armor")
	p.invulnerable_time = 0
	p.take_damage(1)
	check(not p.alive and c.remaining_lives==2 and not c.game_over,"Destruction consumes exactly one life")
	check(app.page=="playing" and c.respawn_time>0,"Surviving lives stay in the current mission")
	await capture("incoming")
	for i in range(91):
		c._physics_process(1.0/60)
		d.advance(1.0/60)
	p.set_physics_process(false)
	check(p.alive and p.visible and p.controls_enabled and p.health==p.max_health,"Player returns with full armor and immediate control")
	check(app.director==d and d.elapsed>=25 and d.event_index==event_cursor and c.score==4321,"Same mission, event cursor and score survive respawn")
	check(not departure.active and not departure.landing_active,"Respawn does not restart carrier takeoff")
	check(p.invulnerable_time>3.9,"Four seconds of respawn protection")
	p.take_damage(100)
	check(p.alive and p.health==p.max_health,"Protection blocks lethal damage")
	var on := 0
	var off := 0
	for i in range(60):
		p._physics_process(1.0/60)
		if p.bank.visible: on += 1
		else: off += 1
	check(on>15 and off>15,"Respawning model visibly alternates on and off")
	p.bank.show()
	await capture("protected")
	for i in range(190): p._physics_process(1.0/60)
	check(p.invulnerable_time==0 and p.bank.visible,"Protection expires and model remains visible")
	p.take_damage(p.max_health)
	check(c.remaining_lives==1 and not c.game_over,"Penultimate life still respawns")
	for i in range(91): c._physics_process(1.0/60)
	p.set_physics_process(false)
	p.invulnerable_time = 0
	p.take_damage(p.max_health)
	check(c.remaining_lives==0 and c.game_over and c.respawn_time==0,"Final loss sets game over without scheduling a respawn")
	d.advance(.1)
	check(d.active and app.page=="playing","Final explosion is visible before result screen")
	await capture("over-flight")
	for i in range(145):
		c._physics_process(1.0/60)
		d.advance(1.0/60)
	await process_frame
	check(app.page=="result" and not app.result.won and app.result.lives==0,"Game over reaches loss result after the transition")
	var has_title := false
	for child in app.design.get_children():
		if child is Label and child.text=="GAME OVER": has_title=true
	check(has_title and app.result.score==4321,"Game Over title and final accumulated score are displayed")
	check(paused,"Defeat freezes remaining gameplay")
	await capture("game-over")
	app._launch(1)
	check(app.page=="playing" and not paused and app.cockpit.combat.remaining_lives>0,"Explicit retry starts a playable saved checkpoint")
	# Drain all active voices before discarding the last test flight.
	for voice in app.find_children("*","AudioStreamPlayer",true,false): voice.stop()
	for voice in app.find_children("*","AudioStreamPlayer3D",true,false): voice.stop()
	app.music.stop()
	await create_timer(.2).timeout
	app._show_main()
	app.music.stop()
	await create_timer(.2).timeout
	app.queue_free()
	await process_frame
	var report := {"checks":checks,"failures":failures}
	FileAccess.open("C:/ChatGPT/1942/game/tests/life-cycle-results.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("LIFE CYCLE: ",report)
	quit(0 if failures.is_empty() else 1)
