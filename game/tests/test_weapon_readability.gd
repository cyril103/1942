extends SceneTree
const FIXTURE := "user://weapon-readability-isolated.json"
var failures: Array[String] = []
var checks := 0
class Target extends Area3D:
	var health := 100
	func take_damage(amount: int) -> void: health -= amount
class StationaryShooter extends Area3D:
	var alive := true
	var age := 0.0
	func advance(delta: float, _combat: Node) -> void: age += delta
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
func _cleanup_fixture() -> void:
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(FIXTURE+suffix): DirAccess.remove_absolute(FIXTURE+suffix)
func _stop_audio(node: Node) -> void:
	if node is AudioStreamPlayer or node is AudioStreamPlayer3D: node.stop()
	for child in node.get_children(): _stop_audio(child)
func _run() -> void:
	_cleanup_fixture()
	var app = load("res://scenes/campaign.tscn").instantiate()
	app.testing = true
	app.profile.path = FIXTURE
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
	check(w.shots_fired-shots >= 22 and w.shots_fired-shots <= 24,"Base Vanguard delivers 11.11 twin salvos per second, including one initially ready salvo")
	w.cease_fire()
	# Use the same registered-enemy walker that consumes campaign fire warnings.
	# This stationary fixture never requests its own shots or automatic waves.
	c.automatic_waves = false
	c.bombers_enabled = false
	c.special_enabled = false
	c.clear_enemy_bullets()
	var shooter := StationaryShooter.new()
	shooter.collision_layer = 0
	shooter.collision_mask = 0
	c.add_child(shooter)
	shooter.position = Vector3(0,0,-4)
	c.enemies.append(shooter)
	check(c.dense_waves and c.enemies.size()==1 and c.bombers.is_empty() and c.red_enemies.is_empty(),"Campaign fixture has one stationary registered shooter and no automatic aircraft sources")
	var enemy_shots: int = c.enemy_shots
	for i in range(3):
		c.fire_enemy(shooter)
		check(shooter.has_meta("fire_warning") and c.enemy_shots==enemy_shots+i,"Attack %d queues its 220 ms warning without an immediate projectile" % (i+1))
		c._physics_process(.210)
		check(shooter.has_meta("fire_warning") and c.enemy_shots==enemy_shots+i,"Attack %d still emits no projectile after 210 ms of warning" % (i+1))
		c._physics_process(.011)
	check(c.enemy_shots-enemy_shots == 3,"Campaign fighter burst has 3 rounds instead of 6")
	check(c.lifetimes.count(0.0)==c.BULLET_CAPACITY-3 and c.bullets.filter(func(bullet): return bullet.visible).size()==3,"Three advertised attacks occupy exactly three reusable enemy projectile slots")
	c.clear_enemy_bullets()
	check(c.lifetimes.count(0.0)==c.BULLET_CAPACITY and c.bullets.all(func(bullet): return not bullet.visible),"Clearing the telegraphed fighter burst releases and hides every enemy projectile slot")
	c.enemies.erase(shooter)
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
	check(not w.laser.visible and not w.laser_contact.visible and not w.laser_muzzle.visible,"Releasing fire clears all beam effects immediately")
	# Since 1.9 audio ends with a 70 ms release, independent of collision ticks.
	w.audio.advance(.08)
	w._update_laser(.08)
	check(not w.laser_audio.playing and near.health==97 and far.health==97,"Laser audio drains within 80 ms without residual damage")
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
	app.set_process(false)
	_stop_audio(app)
	app._dispose_run()
	await create_timer(.25).timeout
	app.queue_free()
	current_scene = null
	await process_frame
	await process_frame
	await create_timer(.10).timeout
	_cleanup_fixture()
	var report := {"checks":checks,"failures":failures}
	FileAccess.open("res://tests/weapon-readability-results.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("WEAPON READABILITY: ",report)
	quit(0 if failures.is_empty() else 1)
