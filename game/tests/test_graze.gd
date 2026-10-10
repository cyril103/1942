extends SceneTree
## Production projectile pool + physics: a graze must be a completed safe pass.
const MASTERY := preload("res://scripts/campaign/mastery.gd")
const FIXTURE := "user://graze-isolated.json"
var checks := 0
var failures: Array[String] = []
var app: Node
var director: Node
var combat: Node3D
var player: Node3D
var report: Dictionary = {}
var rush_finishes := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func _initialize() -> void: _run.call_deferred()

func _freeze(node: Node) -> void:
	node.set_physics_process(false)
	node.set_process(false)
	for child in node.get_children(): _freeze(child)

func _stop_audio(node: Node) -> void:
	if node is AudioStreamPlayer or node is AudioStreamPlayer3D: node.stop()
	for child in node.get_children(): _stop_audio(child)

func _reset() -> void:
	combat.clear_enemy_bullets()
	combat.game_over = false
	combat.remaining_lives = 3
	combat.respawn_time = 0
	combat.score = 0
	combat.projectile_speed_scale = 1
	player.position = Vector3(0,0,2)
	player.alive = true
	player.controls_enabled = true
	player.invulnerable_time = 0
	player.health = 3
	player.show()
	director.mastery = MASTERY.new()
	director.active = true
	director.paused = false
	director.ending = false
	director.ring_time = 0
	director.ability_time = 0
	director.charge = 0
	director.graze_charge_gain = 0
	director.graze_feedback_time = 0
	director.graze_feedback_count = 0
	director.graze_feedback_cooldown = 0
	director._graze_pending = 0
	combat._update_bullets(0)

func _round(x := .8, z := -2.0, speed := 10.0) -> void:
	var origin: Vector3 = player.global_position+Vector3(x,0,z)
	check(combat._launch_enemy_round(origin,origin+Vector3(0,0,10),speed),"Production pool accepts test round")

func _safe_pass() -> void:
	_round()
	combat._update_bullets(.4)

func _test_passage() -> void:
	_reset()
	_round()
	combat._update_bullets(.2)
	check(director.mastery.grazes==0,"Entering the ring grants no premature reward")
	combat.velocities[0] = Vector3.ZERO
	for i in range(20): combat._update_bullets(.1)
	check(director.mastery.grazes==0,"Lingering beside a projectile cannot farm grazes")
	combat.velocities[0] = Vector3(0,0,10)
	combat._update_bullets(.2)
	check(director.mastery.grazes==1 and combat.score==25 and is_equal_approx(director.charge,.6),"One completed safe pass grants 25 points and .6 charge")
	combat.velocities[0] = Vector3(0,0,-10)
	combat._update_bullets(.4)
	check(director.mastery.grazes==1,"Returning through the ring cannot reward the same round twice")
	combat.clear_enemy_bullets()
	_safe_pass()
	check(director.mastery.grazes==2,"A reused pool slot can reward its new projectile once")
	_reset()
	_round(1.2)
	combat._update_bullets(.4)
	check(director.mastery.grazes==0,"Ordinary distant dodges do not earn graze score")
	_reset()
	_round(.8,0)
	combat._update_bullets(.2)
	check(director.mastery.grazes==0,"A round spawned inside the ring cannot manufacture a near miss")
	_reset()
	_round(.4)
	combat._update_bullets(.4)
	check(director.mastery.grazes==0,"Crossing the conservative inner hitbox margin never rewards a graze")

func _test_sweep() -> void:
	for hz in [30,60,144]:
		_reset()
		_round()
		for frame in range(hz): combat._update_bullets(1.0/hz)
		check(director.mastery.grazes==1,"A safe pass yields one reward at %d updates per second" % hz)
	_reset()
	_safe_pass()
	check(director.mastery.grazes==1,"A complete crossing within one long frame is still recognized")
	_reset()
	player.position = Vector3(-2,0,2)
	combat._update_bullets(0)
	var origin := Vector3(0,0,2.8)
	combat._launch_enemy_round(origin,origin+Vector3(0,0,1),0)
	player.position = Vector3(2,0,2)
	combat._update_bullets(.2)
	check(director.mastery.grazes==1,"Swept relative motion recognizes a player's lateral dodge")
	_reset()
	combat.set_presentation_altitude(-5.8)
	_safe_pass()
	check(director.mastery.grazes==1,"Low-flight presentation altitude preserves the same graze geometry")
	combat.set_presentation_altitude(0)

func _test_protection() -> void:
	for blocked in ["invulnerable","entry","paused","ending","inactive","dead","respawn","bomb"]:
		_reset()
		match blocked:
			"invulnerable": player.invulnerable_time = 2
			"entry": player.controls_enabled = false
			"paused": director.paused = true
			"ending": director.ending = true
			"inactive": director.active = false
			"dead": player.alive = false
			"respawn": combat.respawn_time = 1
			"bomb": director.ring_time = .7
		_safe_pass()
		check(director.mastery.grazes==0 and combat.score==0 and director.charge==0,"No graze reward during "+blocked)
		player.invulnerable_time = 0
		player.controls_enabled = true
		player.alive = true
		director.active = true
		director.paused = false
		director.ending = false
		director.ring_time = 0
		combat.respawn_time = 0
		combat.velocities[0] = Vector3(0,0,-10)
		combat._update_bullets(.4)
		check(director.mastery.grazes==0,"A blocked passage cannot be banked and rewarded later: "+blocked)
	_reset()
	_round()
	combat._update_bullets(.2)
	director.bombs = 2
	check(director.use_bomb(),"Production bomb can clear the pending passage")
	combat._update_bullets(.3)
	check(director.mastery.grazes==0 and combat.lifetimes.count(0.0)==combat.BULLET_CAPACITY,"Bomb clear releases every slot without awarding pending grazes")

func _test_collision() -> void:
	_reset()
	await physics_frame
	await physics_frame
	_round(0)
	combat._update_bullets(.4)
	check(player.health==2 and director.mastery.grazes==0,"An actual production hurtbox collision damages the player and grants no reward")
	check(combat.lifetimes[0]==0 and not combat.bullets[0].visible,"A hitting bullet is consumed once")
	combat._update_bullets(.1)
	check(player.health==2 and director.mastery.grazes==0,"A consumed hitting bullet neither damages nor rewards again")

func _test_rewards() -> void:
	_reset()
	director.charge = 99.8
	director.mastery.kill(100)
	var chain: int = director.mastery.chain
	var window: float = director.mastery.window
	_safe_pass()
	check(director.charge==100 and is_equal_approx(director.graze_charge_gain,.2),"Graze charge is capped at 100 and reports only the actual gain")
	check(director.mastery.chain==chain and director.mastery.window==window,"Grazing does not extend or increment the kill chain")
	_reset()
	director.ability_time = 3
	_safe_pass()
	check(director.mastery.grazes==1 and director.charge==0,"A non-shield ability permits risk score without recharging itself")
	_reset()
	director.feedback = "MISSION PRIORITAIRE"
	director.feedback_time = 3
	for i in range(3): _safe_pass()
	director._update_graze_feedback(.01)
	check(director.graze_feedback_count==3 and is_equal_approx(director.graze_feedback_time,.7),"A dense group shares one feedback pulse")
	_safe_pass()
	director._update_graze_feedback(.1)
	check(director.graze_feedback_count==3 and director._graze_pending==1,"Feedback cadence suppresses rapid pulse stacking")
	director._update_graze_feedback(.09)
	check(director.graze_feedback_count==1 and director._graze_pending==0,"The next feedback interval reports the queued group")
	check(director.feedback=="MISSION PRIORITAIRE" and director.feedback_time==3,"Graze feedback cannot overwrite mission or radio information")
	for connection in director.finished.get_connections(): director.finished.disconnect(connection.callable)
	director.finished.connect(func(value): report=value)
	director._end(true)
	check(report.get("grazes",0)==4 and report.get("graze_score",0)==100 and is_equal_approx(report.get("graze_charge",0),2.4),"Debrief reports exact graze count, fixed score, and charge gained")

func _test_rush_finish() -> void:
	app._begin_boss_rush()
	director = app.director
	combat = director.combat
	player = director.player
	_freeze(app)
	var departure: Node3D = app.cockpit.flight.get_node("Departure")
	check(director.boss_rush and director.practice and director.boss_spawned,"Real rush entry configures the production boss director")
	check(not departure.active and not departure.landing_active,"Rush starts in active flight without departure or landing choreography")
	director.finished.connect(func(_value): rush_finishes+=1)
	# Use the actual hull death sequence and its signal, not a fabricated result.
	director.boss.age = 5
	director.boss.collision_layer = 2
	director.boss.transition_time = 0
	director.boss.take_damage(director.boss.health)
	check(director.boss.dying and not director.boss_won,"Lethal damage begins the real boss destruction sequence")
	director.advance(2.7)
	check(director.boss_won and director.ending and rush_finishes==0,"Real boss defeat enters the rush intermission before emitting a result")
	check(not departure.landing_active and not departure.landed,"Rush victory never starts carrier landing")
	director.advance(1.49)
	check(rush_finishes==0 and director.active,"Rush keeps the 1.5-second victory beat before ending")
	director.paused = true
	director.advance(5)
	check(rush_finishes==0 and is_equal_approx(director.ending_time,1.49),"Pausing freezes the rush victory countdown")
	director.paused = false
	director.advance(.02)
	check(rush_finishes==1 and not director.active,"Resuming emits one production result once the victory beat completes")
	director.advance(2)
	check(rush_finishes==1,"Repeated director updates cannot emit duplicate rush results")
	await process_frame
	check(app.page=="result" and app.boss_rush.cleared==1 and app.boss_rush.stage_open==false,"The genuine result is accepted by the app ledger exactly once")
	var earned: int = app.boss_rush.score
	app._next_boss_rush()
	director = app.director
	combat = director.combat
	player = director.player
	_freeze(app)
	check(app.selected_mission==8 and director.active and not director.ending and player.controls_enabled,"Continue creates an active second duel after the real result")
	check(combat.score==earned and combat.remaining_lives==3 and is_instance_valid(director.boss),"The next real duel preserves score and lives with a fresh boss")

func _run() -> void:
	root.size = Vector2i(1920,1080)
	app = load("res://scenes/campaign.tscn").instantiate()
	app.testing = true
	app.profile.path = FIXTURE
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
	_test_passage()
	_test_sweep()
	_test_protection()
	await _test_collision()
	_test_rewards()
	await _test_rush_finish()
	_stop_audio(app)
	await create_timer(.25).timeout
	app.queue_free()
	current_scene = null
	await process_frame
	await process_frame
	await create_timer(.1).timeout
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(FIXTURE+suffix): DirAccess.remove_absolute(FIXTURE+suffix)
	print("GRAZE: ",checks," checks; failures: ",failures)
	quit(0 if failures.is_empty() else 1)
