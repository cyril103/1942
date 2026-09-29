extends SceneTree
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var cockpit = load("res://scenes/cockpit.tscn").instantiate()
	cockpit.persistence_enabled = false
	root.add_child(cockpit)
	current_scene = cockpit
	await process_frame
	cockpit.flight.get_node("Departure").finish_immediately()
	for name_text in ["Combat","Player","Weapons","Seascape"]:
		cockpit.flight.get_node(name_text).set_physics_process(false)
	cockpit.player.get_node("Hurtbox").collision_layer = 0
	var combat = cockpit.combat
	combat.wave_count = 1
	combat.next_wave = 100
	combat.spawn_wave()
	var downward := {}
	var failures: Array[String] = []
	for frame in range(720):
		combat._physics_process(1.0/60.0)
		for enemy in combat.enemies:
			if enemy.attack_phase == enemy.AttackPhase.DIVE and not downward.has(enemy.get_instance_id()):
				downward[enemy.get_instance_id()] = true
				if absf(enemy.heading)>0.32: failures.append("Roll must finish facing downward within 18 degrees")
		if frame%60==0: await process_frame
	if downward.size()!=4: failures.append("All four side arrivals complete the roll and descend")
	if combat.enemy_shots!=24: failures.append("All four fire three twin salvos before leaving the portrait screen")
	if not combat.enemies.is_empty(): failures.append("Side enemies must retire after their pass")
	print("PORTRAIT SIDE ATTACKS: ","PASS" if failures.is_empty() else "FAIL", " / shots=",combat.enemy_shots," / ",failures)
	cockpit._stop_audio(cockpit.flight)
	await create_timer(0.12).timeout
	quit(0 if failures.is_empty() else 1)
