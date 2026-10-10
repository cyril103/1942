extends SceneTree
## Authored visual fixtures of the production flight HUD; not a playthrough.
var output := "C:/ChatGPT/1942/renders/ultimate-hud"
func _initialize() -> void: _run.call_deferred()
func freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children(): freeze(child)
func silence(node: Node) -> void:
	if node is AudioStreamPlayer or node is AudioStreamPlayer3D: node.stop()
	for child in node.get_children(): silence(child)
func capture(label: String) -> void:
	for i in range(6): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label+".png"))
func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1920,1080)
	var app: Node = load("res://scenes/campaign.tscn").instantiate()
	app.testing = true
	app.profile.path = "user://hud-capture-fixture.json"
	root.add_child(app)
	app.profile.reset()
	app.profile.data.settings.fullscreen = false
	app._launch(1)
	app.cockpit.flight.get_node("Departure").finish_immediately()
	freeze(app)
	var director: Node = app.director
	var hud: Control = app.cockpit.get_node("CampaignHUD")
	director._spawn_boss("bomber")
	director.player.invulnerable_time = 0
	director.mastery.chain = 38
	director.mastery.multiplier = 4
	director.mastery.window = 2.8
	director.combat.score = 148650
	director.charge = 100
	hud._process(.016)
	await capture("boss-arrival-1080")
	director.boss.age = 7
	director.boss.position = Vector3(0,0,-6.3)
	director.boss.health = director.boss.max_health*.51
	director.boss.phase = 1
	director.feedback_time = 0
	hud.boss_intro_time = 0
	hud.boss_health_trail = .53
	if director.boss.get("attack_label") != null:
		director.boss.attack_label = "ÉVENTAIL CROISÉ"
		director.boss.attack_hint = "PASSEZ ENTRE LES SALVES"
		director.boss.attack_state = "charging"
		director.boss.attack_progress = .63
	Input.action_press("focus_flight")
	hud._process(0)
	await capture("boss-pattern-1080")
	root.size = Vector2i(1280,720)
	await process_frame
	hud._process(0)
	await capture("boss-pattern-720")
	# The final encounter uses its production warning planner and projectile pool.
	# Only its starting phase/loadout are authored for these visual fixtures.
	silence(app)
	app._show_main()
	await process_frame
	root.size = Vector2i(1920,1080)
	app.profile.data.unlocked = 32
	app._launch(32,"practice")
	freeze(app)
	director = app.director
	hud = app.cockpit.get_node("CampaignHUD")
	director.player.invulnerable_time = 0
	director.combat.score = 743250
	director.charge = 72
	director.mastery.chain = 25
	director.mastery.multiplier = 3
	director.mastery.window = 2.6
	director.mastery.grazes = 48
	director.boss.age = 9
	director.boss.health = director.boss.max_health*.22
	director.boss.previous_phase = 2
	director.boss.phase = 2
	director.boss.motion_age = 1.5
	director.boss.volley = 1
	director.boss.cooldown = 0
	director.boss.advance(.016,director)
	director.boss.advance(.45,director)
	director.feedback_time = 0
	hud._process(.016)
	await capture("citadel-telegraph-phase3-1080")
	for step in range(100):
		director.boss.advance(1.0/60,director)
		director.combat._update_bullets(1.0/60)
		if step%15==0: await process_frame
	hud._process(0)
	await capture("citadel-live-pattern-phase3-1080")
	Input.action_release("focus_flight")
	silence(app)
	app.queue_free()
	await process_frame
	await process_frame
	print("HUD captures: ",output)
	quit()
