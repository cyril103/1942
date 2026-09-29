extends SceneTree
var failures: Array[String] = []
var checks := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	for name_text in ["Combat", "Departure", "Player", "Weapons", "Seascape"]:
		scene.get_node(name_text).set_physics_process(false)
	var combat = scene.get_node("Combat")
	var player = scene.get_node("Player")
	var weapons = scene.get_node("Weapons")
	combat._physics_process(30.0)
	check(combat.wave_count == 0, "No waves during takeoff")
	scene.get_node("Departure").finish_immediately()
	# Disable only this collision shape during long deterministic wave simulation.
	player.get_node("Hurtbox").collision_layer = 0
	var previous_wave := 0
	var spawn_times: Array[float] = []
	var observed_loop := false
	var observed_exit := false
	var observed_turn := false
	var max_bank := 0.0
	var max_curve := 0.0
	var last_headings := {}
	var max_heading_rate := 0.0
	var max_pitch := 0.0
	var max_height := 0.0
	var baseline: int = combat.get_child_count()
	for frame in range(60 * 180):
		combat._physics_process(1.0 / 60.0)
		if combat.wave_count != previous_wave:
			spawn_times.append(combat.combat_time)
			check(combat.enemies.size() == 4, "Each wave contains two groups of two Zero")
			check(combat.enemies[0].position.z < combat.screen_top(), "Wave enters from above the screen")
			var half_width := absf(combat.camera.project_position(Vector2.ZERO, combat.camera.position.y).x)
			check(combat.enemies[3].position.x - combat.enemies[0].position.x > half_width * 1.5, "Enemies cover most of the screen width")
			for i in range(1, 4):
				check(combat.enemies[i].position.x - combat.enemies[i-1].position.x > 4.0, "Independent spaced entry lanes")
				check(combat.enemies[i].flight_speed != combat.enemies[i-1].flight_speed and combat.enemies[i].loop_z != combat.enemies[i-1].loop_z, "Independent speed and maneuver timing")
			for enemy in combat.enemies:
				check(absf(enemy.approach_target_x) < absf(enemy.entry.x), "Approaches converge toward the centre with centred player")
			previous_wave = combat.wave_count
		for enemy in combat.enemies:
			var id: int = enemy.get_instance_id()
			if last_headings.has(id):
				max_heading_rate = maxf(max_heading_rate, absf(wrapf(enemy.heading - last_headings[id], -PI, PI)) * 60.0)
			last_headings[id] = enemy.heading
			if enemy.phase == enemy.Phase.APPROACH:
				max_curve = maxf(max_curve, absf(enemy.position.x - enemy.entry.x))
			if enemy.phase == enemy.Phase.TURN:
				observed_turn = true
				max_bank = maxf(max_bank, absf(enemy.bank))
				check(enemy.shot_count == 3, "Three salvos before banked turn")
				check(absf(enemy.rotation.y - enemy.heading) < 0.001, "Nose follows turn heading")
			if enemy.phase == enemy.Phase.LOOP:
				observed_loop = true
				max_pitch = maxf(max_pitch, absf(enemy.visual.rotation.x))
				max_height = maxf(max_height, enemy.visual.position.y)
				check(enemy.shot_count == 3, "Three salvos fired before looping")
			if enemy.phase == enemy.Phase.EXIT:
				observed_exit = true
				check(enemy.visual.position.y == 0 and enemy.visual.rotation.x == 0, "Exit is level toward bottom")
		if frame % 60 == 0:
			await process_frame
			check(combat.get_child_count() <= baseline + 4, "No accumulation of enemy nodes across waves")
	for index in range(1, spawn_times.size()):
		check(absf(spawn_times[index] - spawn_times[index - 1] - 20.0) < 0.02, "Waves remain 20 seconds apart")
	check(observed_turn and max_bank > 0.2 and max_bank < 0.7 and max_curve > 0.8, "Converging approaches and gentle banked turns")
	check(max_heading_rate < 2.0, "No abrupt heading changes across maneuver transitions")
	check(combat.BULLET_SPEED == 14.0, "Faster enemy projectiles")
	check(combat.wave_count == 9, "Nine waves over three minutes")
	check(observed_loop and observed_exit and max_height > 3.0 and max_pitch > 6.1, "Full 3D loop followed by departure")
	check(combat.enemy_shots == 216, "Four planes times three twin salvos per wave")
	for enemy in combat.enemies: enemy.retire()
	combat.enemies.clear()
	for index in range(combat.BULLET_CAPACITY): combat.lifetimes[index] = 0
	await process_frame
	# Real engine collision: both player rounds cross the actual Zero hitbox.
	combat.spawn_wave()
	var target = combat.enemies[0]
	target.position = Vector3.ZERO
	combat.enemies[1].position = Vector3(6, 0, -2)
	player.position = Vector3(0, 0, 5)
	player.get_node("Hurtbox").collision_layer = 4
	await physics_frame
	await physics_frame
	weapons._fire_salvo()
	weapons._physics_process(0.20)
	check(not target.alive and combat.kills == 1, "Player projectiles destroy the actual Zero")
	check(weapons.active_count == 0, "Player rounds are recycled after enemy hits")
	var kills_before: int = combat.kills
	target.take_damage(1)
	check(combat.kills == kills_before, "Dead enemy cannot count twice")
	await process_frame
	var shooter = combat.enemies[1]
	shooter.position = Vector3(0, 0, 2)
	combat.fire_enemy(shooter)
	combat._update_bullets(0.4)
	check(not player.alive and not player.controls_enabled, "Enemy projectile destroys and disables player")
	check(combat.game_over and combat.death_panel.visible, "Destruction displays restart prompt")
	check(not player.visible, "Destroyed player disappears")
	var waves_before: int = combat.wave_count
	combat._physics_process(40.0)
	check(combat.wave_count == waves_before, "No new waves after game over")
	check(combat.lifetimes.count(0.0) == combat.BULLET_CAPACITY, "Enemy bullets cleared on defeat")
	# Exercise actual restart input and scene ownership cleanup.
	var old_id: int = scene.get_instance_id()
	var key := InputEventKey.new()
	key.keycode = KEY_R
	key.pressed = true
	Input.parse_input_event(key)
	Input.flush_buffered_events()
	await process_frame
	await process_frame
	check(current_scene.get_instance_id() != old_id, "R reloads the encounter")
	check(current_scene.get_node("Player").alive and current_scene.get_node("Combat").wave_count == 0, "Restart resets player and waves")
	var report := {"checks": checks, "failures": failures, "simulated_seconds": 180, "wave_interval": 20, "max_heading_rate": max_heading_rate}
	var file := FileAccess.open("res://tests/combat-results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("COMBAT ", "PASS" if failures.is_empty() else "FAIL", ": ", JSON.stringify(report))
	current_scene.queue_free()
	await process_frame
	await create_timer(0.4).timeout
	quit(0 if failures.is_empty() else 1)
