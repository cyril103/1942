extends SceneTree
var failures: Array[String] = []
var checks := 0
class Target extends Area3D:
	var health := 100
	func take_damage(amount: int) -> void: health -= amount
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)
func target_at(position: Vector3, parent: Node) -> Target:
	var target := Target.new()
	target.collision_layer = 2
	target.collision_mask = 0
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(.20,1,.30)
	collision.shape = box
	target.add_child(collision)
	parent.add_child(target)
	target.position = position
	return target
func _initialize() -> void: _run.call_deferred()
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
	app.cockpit.flight.get_node("Departure").finish_immediately()
	for n in [d,c,p,w]: n.set_physics_process(false)
	p.position = Vector3(0,0,5)
	var before: Vector3 = p.position
	Input.action_press("move_right")
	p._physics_process(.25)
	Input.action_release("move_right")
	check(is_equal_approx(p.position.x-before.x,3.0),"Base aircraft crosses 3 world units in 250ms")
	p.position = Vector3(0,0,5)
	w.set_power("none")
	var shots: int = w.shots_fired
	Input.action_press("fire")
	for i in range(60): w._physics_process(1.0/60)
	Input.action_release("fire")
	check(w.shots_fired-shots >= 18 and w.shots_fired-shots <= 20,"Base gun delivers 9-10 twin salvos per second")
	w.cease_fire()
	var shooter := Area3D.new()
	c.add_child(shooter)
	shooter.position = Vector3(0,0,-4)
	var enemy_shots: int = c.enemy_shots
	for i in range(3): c.fire_enemy(shooter)
	check(c.enemy_shots-enemy_shots == 3,"Campaign fighter burst has 3 rounds instead of 6")
	c.clear_enemy_bullets()
	var near := target_at(Vector3(.42,0,-2),c)
	var far := target_at(Vector3(0,0,-5),c)
	await physics_frame
	await physics_frame
	w.set_power("laser")
	Input.action_press("fire")
	w._update_laser(.016)
	check(near.health == 97 and far.health == 100,"Wide beam catches its edge and stops at nearest target; one damage tick")
	check(w.laser_contact.visible and w.laser_muzzle.visible,"Beam has persistent source and contact effects")
	near.position.x = 2
	await physics_frame
	await physics_frame
	w._update_laser(.1)
	check(near.health == 97 and far.health == 97,"Outside beam is safe and unobstructed central target takes damage")
	Input.action_release("fire")
	w._update_laser(.016)
	check(not w.laser.visible and not w.laser_contact.visible and not w.laser_muzzle.visible and not w.laser_audio.playing,"Releasing fire clears all beam effects and audio")
	w.set_power("spread")
	check(w.active_count == 0 and not w.laser.visible,"Switching weapons leaves no residual laser")
	Input.action_press("fire")
	for i in range(180): w._physics_process(1.0/60)
	Input.action_release("fire")
	for i in range(240): w._physics_process(1.0/60)
	check(w.active_count == 0,"Faster spread firing drains the projectile pool after release")
	near.free()
	far.free()
	shooter.free()
	app._show_main()
	app.music.stop()
	await create_timer(.2).timeout
	var report := {"checks":checks,"failures":failures}
	FileAccess.open("res://tests/weapon-readability-results.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("WEAPON READABILITY: ",report)
	quit(0 if failures.is_empty() else 1)
