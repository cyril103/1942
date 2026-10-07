extends SceneTree
## Real camera, visual, input bounds and physics regression for the coastal descent.
## Keeps the logical collision plane at Y=0 while rendering aircraft below clouds.
const DT := 1.0 / 60.0
var failures: Array[String] = []
var checks := 0
var app: Node

class DamageProbe extends Area3D:
	var health := 100
	func _ready() -> void:
		collision_layer = 2
		collision_mask = 0
		monitoring = false
		var collider := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(3, 1, 1.5)
		collider.shape = shape
		add_child(collider)
	func take_damage(amount: int) -> void:
		health -= amount

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func _freeze(node: Node) -> void:
	node.set_physics_process(false)
	node.set_process(false)
	for child in node.get_children():
		_freeze(child)

func _stop_audio(node: Node) -> void:
	if node is AudioStreamPlayer or node is AudioStreamPlayer3D:
		node.stop()
	for child in node.get_children():
		_stop_audio(child)

func _step(d: Node) -> void:
	d.cockpit.flight.get_node("Seascape")._physics_process(DT)
	d.combat._physics_process(DT)
	d.advance(DT)
	# Respawn intentionally enables player processing; keep simulation owned here.
	d.player.set_physics_process(false)

func _aircraft(index: int) -> void:
	app.profile.data.aircraft = index
	app._launch(3)
	var d: Node = app.director
	var a: Node = d.assault
	var p: Node3D = d.player
	var c: Node3D = d.combat
	var w: Node3D = d.weapons
	var camera: Camera3D = c.camera
	var departure: Node3D = d.cockpit.flight.get_node("Departure")
	var clouds: Node3D = d.cockpit.flight.get_node("Clouds")
	departure.finish_immediately()
	_freeze(d.cockpit.flight)
	d.set_physics_process(false)
	p.invulnerable_time = 1000
	var cruise_camera := camera.position
	var cruise_size := camera.size
	var cruise_plane_width: float = p.get_screen_bounds().size.x
	var original_cloud_heights := PackedFloat32Array()
	for cloud in clouds.clouds:
		original_cloud_heights.append(cloud.global_position.y)
	check(camera.projection == Camera3D.PROJECTION_ORTHOGONAL, "Aircraft %d: cruise uses the orthographic gameplay camera" % index)
	check(clouds.clouds.all(func(cloud): return not camera.is_position_behind(cloud.global_position)), "Aircraft %d: clouds start in front of the cruise camera" % index)
	var smooth_descent := true
	var previous_y := camera.position.y
	var previous_size := camera.size
	var transition_seen := false
	var approach_aircraft_seen := false
	for frame in range(60 * 70):
		_step(d)
		if a.low_flight<=.02 and c.aircraft_enabled:
			approach_aircraft_seen = approach_aircraft_seen or not c.enemies.is_empty() or not c.bombers.is_empty()
		transition_seen = transition_seen or (a.low_flight > .02 and a.low_flight < .98)
		if absf(camera.position.y - previous_y) > .65 or absf(camera.size - previous_size) > .12:
			smooth_descent = false
		previous_y = camera.position.y
		previous_size = camera.size
		if a.low_flight >= .999:
			break
		if frame % 180 == 0:
			await process_frame
	check(transition_seen and a.low_flight >= .999 and smooth_descent, "Aircraft %d: authored coast approach smoothly descends and zooms" % index)
	check(approach_aircraft_seen and not c.aircraft_enabled and c.enemies.is_empty() and c.bombers.is_empty() and c.red_enemies.is_empty(), "Aircraft %d: ocean patrols disappear when the plane descends beneath the clouds" % index)
	check(c.air_withdrawals.is_empty(), "Aircraft %d: decorative aircraft exits finish before low-flight gameplay" % index)
	check(camera.position.y < -2 and camera.position.y > -4.5, "Aircraft %d: camera physically descends below the cloud deck" % index)
	check(camera.position.distance_to(p.bank.global_position) < 12, "Aircraft %d: low camera approaches the aircraft" % index)
	check(camera.size < cruise_size and p.get_screen_bounds().size.x > cruise_plane_width * 1.12, "Aircraft %d: descent gives a visible zoom onto the aircraft" % index)
	check(camera.global_basis.z.is_equal_approx(Vector3.UP), "Aircraft %d: camera preserves the vertical aim projection" % index)
	check(clouds.clouds.all(func(cloud): return camera.is_position_behind(cloud.global_position)), "Aircraft %d: every cloud is naturally behind the low camera" % index)
	var cloud_heights_unchanged := true
	for cloud_index in range(clouds.clouds.size()):
		cloud_heights_unchanged = cloud_heights_unchanged and is_equal_approx(clouds.clouds[cloud_index].global_position.y, original_cloud_heights[cloud_index])
	check(cloud_heights_unchanged and clouds.clouds.all(func(cloud): return cloud.visible), "Aircraft %d: clouds retain their world altitude and are not switched off" % index)
	check(not camera.is_position_behind(p.bank.global_position) and p.bank.global_position.y < -4, "Aircraft %d: the plane remains in front of the camera beneath the clouds" % index)
	check(is_zero_approx(p.get_node("Hurtbox").global_position.y), "Aircraft %d: lowered aircraft preserves the gameplay hurtbox plane" % index)
	check(camera.unproject_position(p.global_position).distance_to(camera.unproject_position(p.bank.global_position)) < .1, "Aircraft %d: HUD and logical collision position align with the lowered aircraft" % index)
	check(c.screen_top() < -8 and c.screen_bottom() > 8, "Aircraft %d: screen bounds remain valid with a negative camera altitude" % index)
	for position in [Vector3(-100,0,0), Vector3(100,0,0), Vector3(0,0,-100), Vector3(0,0,100)]:
		p.position = position
		p._keep_inside_screen()
		var bounds: Rect2 = p.get_screen_bounds()
		var viewport_size: Vector2i = d.cockpit.viewport.size
		check(bounds.position.x >= -.5 and bounds.position.y >= -.5 and bounds.end.x <= viewport_size.x + .5 and bounds.end.y <= viewport_size.y + .5, "Aircraft %d: full model stays inside the zoomed view" % index)
	p.position = Vector3(0,0,6)
	# Isolate real swept collision checks from the authored target layout.
	for target in a.targets:
		if is_instance_valid(target):
			target.collision_layer = 0
	var probe := DamageProbe.new()
	c.add_child(probe)
	probe.position = Vector3(0,0,0)
	await physics_frame
	await physics_frame
	var health_before := probe.health
	w._fire_salvo()
	var visible_rounds := 0
	for shot in w.projectiles:
		if shot.visible:
			visible_rounds += 1
			check(not camera.is_position_behind(shot.global_position), "Aircraft %d: machine-gun rounds render below the camera" % index)
	check(visible_rounds == 2, "Aircraft %d: both original gun lanes remain visible during low flight" % index)
	for frame in range(18):
		w._physics_process(DT)
		await physics_frame
	check(probe.health < health_before, "Aircraft %d: low-flight projectiles hit the actual Y=0 physics collider" % index)
	check(w.impacts.any(func(impact): return impact.visible and not camera.is_position_behind(impact.global_position)), "Aircraft %d: bullet impact is rendered beneath the low camera" % index)
	w.cease_fire()
	health_before = probe.health
	w.set_power("laser")
	Input.action_press("fire")
	w._physics_process(DT)
	Input.action_release("fire")
	check(probe.health < health_before and w.laser_contact.visible, "Aircraft %d: laser hits the same logical collision plane" % index)
	check([w.laser,w.laser_muzzle,w.laser_contact].all(func(effect): return effect.visible and not camera.is_position_behind(effect.global_position)), "Aircraft %d: laser, muzzle and contact stay visible below clouds" % index)
	w.cease_fire()
	w.set_power("none")
	probe.queue_free()
	await physics_frame
	await physics_frame
	# Low-altitude enemy bullets must be visible and retain actual player damage.
	p.invulnerable_time = 0
	health_before = p.health
	c.clear_enemy_bullets()
	c._launch_enemy_round(p.global_position + Vector3(0,.2,-6), p.global_position, 20)
	check(c.bullets.any(func(round): return round.visible and not camera.is_position_behind(round.global_position)), "Aircraft %d: enemy bullets render beneath the low camera" % index)
	c._update_bullets(.8)
	check(p.health == health_before - 1, "Aircraft %d: low-flight enemy bullet sweep damages the real player hurtbox" % index)
	p.invulnerable_time = 1000
	# Once descended, every airborne encounter is rejected, including direct calls.
	c.spawn_wave()
	c.spawn_bomber()
	c.spawn_special()
	check(c.enemies.is_empty() and c.bombers.is_empty() and c.red_enemies.is_empty(), "Aircraft %d: low flight is defended exclusively by ground targets" % index)
	c.clear_enemy_bullets()
	var pickup: Node3D = c.pickup
	pickup.activate(p.global_position + Vector3(3,0,0),p,"spread")
	a._apply_flight_view()
	pickup.advance(DT,c)
	check(not camera.is_position_behind(pickup.visual.global_position) and not camera.is_position_behind(pickup.halo.global_position), "Aircraft %d: POW icon and halo remain below the camera" % index)
	var collected: int = pickup.collected_count
	p.position.x += 3
	pickup.advance(DT,c)
	check(pickup.collected_count == collected + 1 and w.power_type == "spread", "Aircraft %d: lowered POW still collects on its logical path" % index)
	d.charge = 100
	check(d.use_strike() and d.special_ring.visible and not camera.is_position_behind(d.special_ring.global_position), "Aircraft %d: ability ring renders at low-flight altitude" % index)
	var elapsed_before: float = d.elapsed
	var progress_before: int = a.kills
	p.invulnerable_time = 0
	p.take_damage(p.health)
	for frame in range(95):
		c._physics_process(DT)
		a._apply_flight_view()
		p.set_physics_process(false)
	check(p.alive and p.invulnerable_time > 0 and p.bank.global_position.y < -4 and not camera.is_position_behind(p.bank.global_position), "Aircraft %d: respawn stays beneath clouds with protection" % index)
	check(is_equal_approx(d.elapsed,elapsed_before) and a.kills == progress_before, "Aircraft %d: low-flight respawn retains mission progress" % index)
	check(not c.aircraft_enabled and c.enemies.is_empty() and c.bombers.is_empty() and c.red_enemies.is_empty(), "Aircraft %d: low-flight respawn retains the exclusion of aircraft" % index)
	p.invulnerable_time = 3.9
	p._physics_process(0)
	var blink_off: bool = not p.bank.visible
	p.invulnerable_time = 3.8
	p._physics_process(0)
	check(blink_off and p.bank.visible, "Aircraft %d: low-flight respawn preserves the visible protection blink" % index)
	p.position = Vector3(0,0,5)
	# Move the real battlefield beyond the exit coast, then exercise normal ascent.
	a.position.z = a.length * .5 + c.screen_bottom() + 40
	for frame in range(240):
		_step(d)
		if a.low_flight < .001:
			break
	check(a.approach_clear() and a.low_flight < .001, "Aircraft %d: ocean exit completes the ascent before recovery" % index)
	check(camera.position.is_equal_approx(cruise_camera) and is_equal_approx(camera.size,cruise_size) and is_zero_approx(p.bank.position.y), "Aircraft %d: ascent restores cruise camera, zoom and player altitude" % index)
	check(is_zero_approx(c.presentation_altitude) and is_zero_approx(w.presentation_altitude), "Aircraft %d: ascent restores projectile presentation altitude" % index)
	check(c.aircraft_enabled and not c.enemies.is_empty(), "Aircraft %d: returning to ocean cruise immediately resumes fighter waves" % index)
	check(clouds.clouds.all(func(cloud): return not camera.is_position_behind(cloud.global_position)), "Aircraft %d: clouds return below the camera after climbing" % index)
	a.finish()
	departure.begin_landing()
	for frame in range(425):
		departure.advance_landing(DT)
	check(departure.landed and is_equal_approx(p.position.y,departure.DECK_ALTITUDE), "Aircraft %d: carrier recovery still reaches the physical deck" % index)
	check(not camera.is_position_behind(departure.carrier.global_position), "Aircraft %d: carrier remains in front of restored cruise camera" % index)
	app._dispose_run()
	await process_frame

func _run() -> void:
	root.size = Vector2i(1920,1080)
	app = load("res://scenes/campaign.tscn").instantiate()
	app.testing = true
	app.profile.path = "user://lowflight-camera-test-fixture.json"
	root.add_child(app)
	current_scene = app
	await process_frame
	app.set_process(false)
	app.profile.reset()
	app.profile.data.unlocked = 32
	for index in range(3):
		await _aircraft(index)
	app._launch(1)
	check(not is_instance_valid(app.director.assault) and is_equal_approx(app.director.combat.camera.position.y,35) and is_equal_approx(app.director.combat.camera.size,25), "Following ocean mission starts with its original cruise camera")
	app._dispose_run()
	Input.action_release("fire")
	app.music.stop()
	_stop_audio(app)
	await create_timer(.25).timeout
	app.queue_free()
	current_scene = null
	await process_frame
	await process_frame
	await create_timer(.1).timeout
	print("LOW-FLIGHT CAMERA: ",checks," checks; ",failures.size()," failures: ",failures)
	quit(0 if failures.is_empty() else 1)
