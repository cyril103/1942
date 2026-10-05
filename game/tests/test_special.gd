extends SceneTree
var failures: Array[String] = []
var checks := 0
func check(ok: bool,message: String) -> void:
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
	var weapons = cockpit.flight.get_node("Weapons")
	var player = cockpit.player
	for node_name in ["Combat","Weapons","Seascape","Player","Departure"]:
		cockpit.flight.get_node(node_name).set_physics_process(false)
	combat.bombers_enabled = false
	combat.next_wave = 1000
	combat._physics_process(20)
	check(combat.special_count == 0,"No special wave during takeoff")
	cockpit.flight.get_node("Departure").finish_immediately()
	player.get_node("Hurtbox").collision_layer = 0
	for frame in range(719): combat._physics_process(1.0/60)
	check(combat.special_count == 0,"First special wave waits twelve seconds")
	combat._physics_process(0.04)
	check(combat.red_enemies.size() == 5,"Exactly five red aircraft")
	var max_turn := 0.0
	var last_heading := {}
	for frame in range(240):
		combat._physics_process(1.0/60)
		for red in combat.red_enemies:
			if red.distance < 0: continue
			check(red.position.distance_to(red.route.sample_baked(red.distance,true)) < 0.001,"Every aircraft follows fixed shared route")
			if last_heading.has(red.slot): max_turn = maxf(max_turn,absf(wrapf(red.heading-last_heading[red.slot],-PI,PI))*60)
			last_heading[red.slot] = red.heading
		for index in range(1,combat.red_enemies.size()):
			check(is_equal_approx(combat.red_enemies[index-1].distance-combat.red_enemies[index].distance,3.2),"Constant spacing along route")
	check(max_turn < 3.0,"Curve has no instantaneous heading jumps")
	# Destroy four with actual swept player projectiles; do not reward early.
	for index in range(4):
		var red = combat.red_enemies[index]
		red.position = Vector3(0,0,-3)
		red.rotation.y = 0
		player.position = Vector3(0,0,0)
		await physics_frame
		await physics_frame
		weapons._fire_salvo()
		weapons._physics_process(0.10)
		check(not red.alive,"Real twin shots destroy a red aircraft")
		check(combat.pow_spawn_count == 0,"No POW for an incomplete formation")
		await process_frame
	var last = combat.red_enemies[4]
	last.position = Vector3(0,0,-3)
	last.rotation.y = 0
	await physics_frame
	await physics_frame
	weapons._fire_salvo()
	weapons._physics_process(0.10)
	check(combat.pow_spawn_count == 1 and combat.pickup.active,"Fifth destroyed aircraft creates exactly one POW")
	check(combat.score == 750,"Five special aircraft award points once")
	player.alive = false
	player.position = combat.pickup.position
	combat.pickup.advance(0.01,combat)
	check(not weapons.spread_enabled,"Dead player cannot collect")
	player.alive = true
	player.controls_enabled = true
	combat.pickup.advance(0.01,combat)
	check(weapons.spread_enabled and not combat.pickup.active and combat.pickup.collected_count == 1,"Passing over POW upgrades the weapon")
	combat.pickup.collect(combat)
	check(combat.pickup.collected_count == 1,"Collection is idempotent")
	weapons._physics_process(4)
	player.position = Vector3(0,0,5)
	weapons._fire_salvo()
	check(weapons.active_count == 4,"Upgrade fires four projectiles")
	for index in range(4):
		check(weapons.projectiles[index].scale.x > 1.0,"Upgraded projectile is larger")
		check(weapons.velocities[index].z < 0,"Every upgraded shot travels forward")
	check(weapons.velocities[0].x < weapons.velocities[1].x and weapons.velocities[1].x < 0 and weapons.velocities[2].x > 0 and weapons.velocities[3].x > weapons.velocities[2].x,"Symmetric four-way fan")
	weapons._physics_process(4)
	check(weapons.active_count == 0,"Fan projectiles expire outside screen")
	await process_frame
	combat.red_enemies.clear()
	combat.spawn_special()
	check(combat.red_enemies[0].route.get_point_position(0).x > 0,"Next formation enters from opposite side")
	for red in combat.red_enemies: red.advance(2.0,combat)
	combat.red_enemies[0].retire()
	for index in range(1,5): combat.red_enemies[index].take_damage(2)
	check(combat.pow_spawn_count == 1 and combat.special_failed,"One escaped aircraft prevents POW despite four kills")
	await process_frame
	combat.red_enemies.clear()
	# Four independent thin targets verify actual fan direction and swept collision.
	weapons._fire_salvo()
	var targets: Array[Area3D] = []
	for index in range(4):
		var target = load("res://scripts/enemy_zero.gd").new()
		target.health = 1
		combat.add_child(target)
		target.position = weapons.projectiles[index].position+weapons.velocities[index]*0.25
		target.position.y = 0
		target.get_child(0).shape = BoxShape3D.new()
		target.get_child(0).shape.size = Vector3(0.30,1,0.05)
		targets.append(target)
	await physics_frame
	await physics_frame
	weapons._physics_process(0.3)
	for target in targets: check(not target.alive,"Each fan ray hits its own thin target without tunneling")
	check(weapons.active_count == 0,"Fan collision releases all four slots")
	await process_frame
	var baseline: int = weapons.get_child_count()
	Input.action_press("fire")
	for frame in range(60*180): weapons._physics_process(1.0/60)
	Input.action_release("fire")
	weapons._physics_process(4)
	check(weapons.get_child_count() == baseline and weapons.active_count == 0,"Three minutes of fan fire keep fixed pool and release all shots")
	player.invulnerable_time = 0
	player.take_damage(1)
	check(not weapons.spread_enabled,"Death resets upgrade")
	player.respawn(Vector3(0,0,5))
	weapons._fire_salvo()
	check(weapons.active_count == 2 and weapons.projectiles[0].scale == Vector3.ONE and weapons.projectiles[0].rotation.y == 0,"Reused slots restore standard size and direction")
	combat.pickup.activate(Vector3(5,0,-5),player)
	combat.pickup.advance(15,combat)
	check(not combat.pickup.active and not combat.pickup.visible,"Uncollected POW expires")
	combat.special_enabled = true
	combat.next_special = 0.01
	var initial: int = combat.special_count
	for frame in range(60*81):
		combat._physics_process(1.0/60)
		if frame % 60 == 0: await process_frame
	check(combat.special_count-initial == 3 and combat.red_enemies.size() <= 5,"Repeated special waves every forty seconds remain bounded")
	var report := {"checks":checks,"failures":failures,"max_turn_rate":max_turn}
	FileAccess.open("res://tests/special-results.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("SPECIAL TEST ",JSON.stringify(report))
	cockpit._stop_audio(cockpit.flight)
	await create_timer(0.12).timeout
	quit(0 if failures.is_empty() else 1)
