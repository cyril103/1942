extends SceneTree

var failures: Array[String] = []
var checks: int = 0


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)


func _run() -> void:
	for dimensions in [Vector2i(1920, 1080), Vector2i(720, 1280)]:
		root.size = dimensions
		var scene: Node3D = load("res://scenes/main.tscn").instantiate()
		root.add_child(scene)
		current_scene = scene
		var departure = scene.get_node("Departure")
		var sea = scene.get_node("Seascape")
		var player = scene.get_node("Player")
		departure.set_physics_process(false)
		sea.set_physics_process(false)
		player.set_physics_process(false)
		await process_frame
		check(not player.controls_enabled, "Opening locks steering until the maneuver is finished")
		check(is_equal_approx(player.position.y, departure.DECK_ALTITUDE), "Aircraft starts at deck height")
		check(player.bank.scale.x < 0.75, "Aircraft starts smaller at low altitude")
		check(absf(player.position.z - departure.carrier.position.z - 8.1) < 0.01, "Aircraft starts on the rear flight deck")
		check(preload("res://assets/environment/carrier.png").get_image().has_mipmaps(), "Deck texture has mipmaps")
		var phases: Dictionary = {}
		var maximum_height: float = -100.0
		var maximum_pitch: float = 0.0
		var deck_advance: float = 0.0
		var previous_pitch: float = 0.0
		var previous_position: Vector3 = player.position
		Input.action_press("move_right")
		for frame in range(600):
			var distance: float = sea.scroll_speed / 60.0
			var ship_before: float = departure.carrier.position.z
			sea._physics_process(1.0 / 60.0)
			check(absf(departure.carrier.position.z - ship_before - distance) < 0.0001, "Ship scroll remains exactly synchronized with scenery")
			departure._physics_process(1.0 / 60.0)
			phases[departure.phase] = true
			maximum_height = maxf(maximum_height, player.position.y)
			maximum_pitch = maxf(maximum_pitch, player.bank.rotation.x)
			var bounds: Rect2 = player.get_screen_bounds()
			var viewport_size: Vector2 = root.get_visible_rect().size
			check(bounds.position.x >= 11.9 and bounds.position.y >= 11.9 and bounds.end.x <= viewport_size.x - 11.9 and bounds.end.y <= viewport_size.y - 11.9, "Aircraft remains fully visible throughout takeoff and loop")
			if not departure.active:
				break
			if departure.elapsed > departure.LIFT_START + 0.1 and departure.elapsed < departure.CLIMB_END:
				check(player.bank.rotation.x > 0.01, "Aircraft pitches up throughout the climb")
				check(player.bank.rotation.x >= previous_pitch - 0.001, "Pull-up never flattens before the loop")
			if departure.elapsed > departure.LIFT_START + 0.1 and departure.elapsed < departure.LOOP_END:
				var air_motion: Vector3 = player.position - previous_position - Vector3(0.0, 0.0, distance)
				var forward := Vector3(0.0, sin(player.bank.rotation.x), -cos(player.bank.rotation.x))
				check(air_motion.normalized().dot(forward) > 0.995, "Nose follows flight direction relative to the ocean")
			previous_pitch = player.bank.rotation.x
			previous_position = player.position
			var before: Vector3 = player.position
			player._physics_process(1.0 / 60.0)
			check(before.is_equal_approx(player.position), "Held arrows cannot interfere with departure")
			if departure.phase == departure.Phase.TAKEOFF or departure.phase == departure.Phase.CLIMB:
				deck_advance = 8.1 - (player.position.z - departure.carrier.position.z)
		Input.action_release("move_right")
		check(phases.size() == 6, "All six departure phases occur")
		check(deck_advance > 16.0, "Aircraft traverses the flight deck before leaving")
		check(maximum_height > 3.1, "Loop has a real vertical arc")
		check(maximum_pitch > TAU - 0.10, "Loop completes a full pitch rotation")
		check(player.controls_enabled and not departure.active, "Pilot regains control after intro")
		check(player.bank.rotation.is_zero_approx() and player.bank.scale.is_equal_approx(Vector3.ONE), "Aircraft returns level at its normal scale")
		check(absf(player.position.y) < 0.001, "Cruise altitude is restored")
		check(is_equal_approx(sea.scroll_speed, 2.4), "Normal background speed is restored")
		var x_before: float = player.position.x
		Input.action_press("move_right")
		player._physics_process(0.1)
		Input.action_release("move_right")
		check(player.position.x > x_before, "Arrows work immediately after the loop")
		for frame in range(360):
			sea._physics_process(1.0 / 60.0)
			departure._physics_process(1.0 / 60.0)
		check(not departure.carrier.visible, "Carrier retires after leaving the screen")
		scene.queue_free()
		await process_frame

	var report := {"checks": checks, "failures": failures, "formats": ["16:9", "portrait"], "intro_seconds": 8.95}
	var file := FileAccess.open("res://tests/departure-results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	if not failures.is_empty():
		quit(1)
		return
	# Escape must still work before controls are handed back to the player.
	var escape_scene: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(escape_scene)
	current_scene = escape_scene
	print("DEPARTURE PASS: ", JSON.stringify(report), "; dispatching Escape during ON_DECK")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	Input.parse_input_event(escape)
	Input.flush_buffered_events()
	await create_timer(2.0).timeout
	push_error("Escape did not quit during the intro")
	quit(1)
