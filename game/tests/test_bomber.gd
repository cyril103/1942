extends SceneTree
var failures: Array[String] = []
var checks := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var cockpit = load("res://scenes/cockpit.tscn").instantiate()
	cockpit.persistence_enabled = false
	root.add_child(cockpit)
	current_scene = cockpit
	await process_frame
	var combat = cockpit.combat
	combat.special_enabled = false
	var player = cockpit.player
	var weapons = cockpit.flight.get_node("Weapons")
	for node_name in ["Combat","Weapons","Seascape","Player","Departure"]:
		cockpit.flight.get_node(node_name).set_physics_process(false)
	combat._physics_process(30)
	check(combat.bomber_count == 0,"No bomber during takeoff")
	cockpit.flight.get_node("Departure").finish_immediately()
	player.get_node("Hurtbox").collision_layer = 0
	combat.next_wave = 1000
	for frame in range(1799): combat._physics_process(1.0/60)
	check(combat.bomber_count == 0,"No bomber before 30 seconds")
	combat._physics_process(1.0/60)
	combat._physics_process(1.0/60)
	check(combat.bomber_count == 1,"First bomber at 30 seconds")
	var bomber = combat.bombers[0]
	check(bomber.position.z > combat.screen_bottom() and bomber.visual.position.y < -1.7,"Starts below screen and below player altitude")
	var min_x := 100.0
	var max_x := -100.0
	var max_bank := 0.0
	var max_pitch := 0.0
	var previous_heading: float = bomber.heading
	var max_yaw_rate := 0.0
	for frame in range(60*24):
		combat._physics_process(1.0/60)
		max_pitch = maxf(max_pitch,absf(bomber.pitch))
		max_bank = maxf(max_bank,absf(bomber.bank))
		max_yaw_rate = maxf(max_yaw_rate,absf(wrapf(bomber.heading-previous_heading,-PI,PI))*60)
		previous_heading = bomber.heading
		if bomber.age > 9 and bomber.age < 22:
			min_x = minf(min_x,bomber.position.x)
			max_x = maxf(max_x,bomber.position.x)
			check(absf(bomber.visual.position.y) < 0.001,"Patrol at player altitude")
			check(absf(bomber.position.x)+2.5 < 9.375,"Wings remain within vertical playfield")
	check(max_x-min_x > 8.5,"Patrol covers left and right sides")
	check(max_bank > 0.15 and max_bank <= 0.501 and max_yaw_rate <= 1.01,"Smooth heading and bank")
	check(max_pitch > 0.02,"Climb pitches nose upwards")
	check(combat.bomber_shots >= 20,"Rear cannons fire during patrol")
	for frame in range(60*6): combat._physics_process(1.0/60)
	await process_frame
	check(combat.bomber_count == 2 and combat.bombers.size() == 1,"Second bomber after 30 seconds; first retired")
	bomber = combat.bombers[0]
	# Put one bomber into its vulnerable flight state and exercise real projectile collision.
	bomber.age = 7
	bomber.advance(1.0/60,combat)
	bomber.position = Vector3.ZERO
	bomber.rotation = Vector3(0,PI,0)
	bomber.visual.rotation = Vector3.ZERO
	player.position = Vector3(0,0,4)
	for index in range(combat.BULLET_CAPACITY):
		combat.lifetimes[index] = 0
		combat.bullets[index].hide()
	await physics_frame
	await physics_frame
	for hit in range(10):
		weapons.projectiles[0].global_position = Vector3(0,0,3)
		weapons.projectiles[0].show()
		weapons.lifetimes[0] = 3
		weapons.active_count = 1
		weapons._physics_process(0.1)
		check(bomber.health == 9-hit,"Exactly one damage per actual projectile")
		check(bomber.hit_material.get_shader_parameter("strength") == 1.0,"White flash on impact")
		if hit < 9: check(bomber.alive and not bomber.dying,"Survives first nine hits")
	check(bomber.dying and bomber.collision_layer == 0,"Tenth hit disables combat and starts breakup")
	check(combat.score == 500 and combat.kills == 1,"Bomber score awarded once")
	bomber.take_damage(1)
	check(combat.score == 500,"No double score during destruction")
	for frame in range(68): bomber.advance(1.0/60,combat)
	check(bomber.blast_count == 7 and not bomber.visual.visible,"Seven staggered blasts then model hidden")
	bomber.advance(0.4,combat)
	check(not bomber.alive,"Destroyed bomber retires")
	await process_frame
	combat.bombers.clear()
	combat.spawn_bomber()
	bomber = combat.bombers[0]
	bomber.age = 7
	bomber.advance(1.0/60,combat)
	bomber.position = Vector3.ZERO
	bomber.rotation.y = PI
	bomber.visual.rotation = Vector3.ZERO
	player.get_node("Hurtbox").collision_layer = 4
	player.invulnerable_time = 0
	await physics_frame
	await physics_frame
	combat.fire_bomber(bomber)
	combat._update_bullets(0.4)
	check(not player.alive and combat.remaining_lives == 2,"Rear cannon projectile damages player")
	combat._physics_process(2.3)
	check(player.alive,"Player respawns normally")
	var baseline: int = combat.get_child_count()
	for index in range(100): combat._explode(Vector3.ZERO,0.72,false)
	check(combat.get_child_count() == baseline and combat.effects.size() == 8 and combat.bullets.size() == 64,"Fixed VFX and projectile pools")
	combat._explode(Vector3.ZERO)
	var last: int = (combat._effect_cursor+7)%8
	check(is_equal_approx(combat.effects[last].scale.x,0.5625),"Fighter explosion scale restored after bomber reuse")
	combat._update_effects(4)
	combat._update_bullets(7)
	check(combat.lifetimes.count(0.0) == 64,"Expired bullets released")
	# Repeated encounters alongside both fighter types must remain bounded.
	for active in combat.bombers: active.retire()
	combat.bombers.clear()
	await process_frame
	player.get_node("Hurtbox").collision_layer = 0
	combat.next_bomber = 30
	combat.next_wave = 1.5
	var count_before: int = combat.bomber_count
	var max_bombers := 0
	var saw_coexistence := false
	for frame in range(60*181):
		combat._physics_process(1.0/60)
		max_bombers = maxi(max_bombers,combat.bombers.size())
		if not combat.bombers.is_empty() and not combat.enemies.is_empty(): saw_coexistence = true
		if frame % 60 == 0: await process_frame
	check(combat.bomber_count-count_before == 6,"Six bomber appearances over 181 seconds")
	check(max_bombers == 1 and saw_coexistence,"Bomber remains bounded and coexists with fighter waves")
	check(combat.wave_count == 9,"Independent twenty-second fighter cadence")
	var report := {"checks":checks,"failures":failures,"max_bank":max_bank,"max_yaw_rate":max_yaw_rate,"max_pitch":max_pitch,"patrol_width":max_x-min_x}
	FileAccess.open("res://tests/bomber-results.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("BOMBER TEST ",JSON.stringify(report))
	cockpit._stop_audio(cockpit.flight)
	await create_timer(0.12).timeout
	quit(0 if failures.is_empty() else 1)
