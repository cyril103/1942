extends SceneTree

class Target extends StaticBody3D:
	var damage := 0
	func take_damage(amount: int) -> void:
		damage += amount

var failures: Array[String] = []

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var weapons = scene.get_node("Weapons")
	var player = scene.get_node("Player")
	var departure = scene.get_node("Departure")
	for name_text in ["Weapons", "Player", "Departure", "Seascape"]:
		scene.get_node(name_text).set_physics_process(false)
	await process_frame
	Input.action_press("fire")
	weapons._physics_process(0.1)
	check(weapons.active_count == 0, "No shooting during takeoff")
	departure.finish_immediately()
	var initial_nodes: int = weapons.get_child_count()
	for tick in range(60 * 60 * 5):
		weapons._physics_process(1.0 / 60.0)
	check(weapons.shots_fired >= 4798 and weapons.shots_fired <= 4802, "Eight twin salvos per second over five minutes")
	check(weapons.get_child_count() == initial_nodes and initial_nodes == weapons.CAPACITY + 9, "Projectile, impact and audio pools stay fixed after prolonged continuous fire")
	check(weapons.audio.salvos_played * 2 == weapons.shots_fired, "Exactly one sound per twin salvo")
	check(weapons.audio.get_child_count() == 8, "Audio voice count stays bounded")
	check(weapons.active_count < 32, "Offscreen projectiles are reclaimed while firing")
	Input.action_release("fire")
	for tick in range(240):
		weapons._physics_process(1.0 / 60.0)
	check(weapons.active_count == 0, "All projectiles reclaimed after release")
	for shot in weapons.projectiles:
		check(not shot.visible, "Inactive projectile is hidden")
	# A thin enemy crossed entirely in one frame must still be hit.
	var target := Target.new()
	target.collision_layer = 2
	target.collision_mask = 0
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3.0, 2.0, 0.05)
	collision.shape = box
	target.add_child(collision)
	scene.add_child(target)
	target.position = Vector3(0.0, 0.0, 3.0)
	await physics_frame
	await physics_frame
	weapons._fire_salvo()
	weapons._physics_process(0.1)
	check(target.damage == 2, "Both swept projectiles damage a thin target without tunneling")
	check(weapons.active_count == 0, "Hits immediately reclaim projectile slots")
	target.queue_free()
	await process_frame
	player.bank.rotation.z = 0.4
	weapons._fire_salvo()
	check(weapons.projectiles[0].global_position.is_equal_approx(player.bank.to_global(weapons.MUZZLES[0])), "Shot starts at banked wing muzzle")
	weapons.projectiles[0].position.x = 1000.0
	weapons._physics_process(0.01)
	check(not weapons.projectiles[0].visible, "Side exits are reclaimed too")
	weapons._physics_process(4.0)
	check(weapons.active_count == 0, "Lifetime guard empties pool even after a large timestep")
	print("WEAPONS: ", "PASS" if failures.is_empty() else failures, "; fixed pool=", initial_nodes, "; simulated seconds=300")
	scene.queue_free()
	await process_frame
	# Let the audio thread release queued playback references before exiting.
	await create_timer(0.4).timeout
	quit(0 if failures.is_empty() else 1)
