extends SceneTree

var failures: Array[String] = []
var checks: int = 0
var flight: Node3D
var player: Node3D


func _initialize() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)


func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func release_keys() -> void:
	for code in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]:
		key(code, false)


func reset_player() -> void:
	release_keys()
	player.position = Vector3.ZERO
	player.bank.rotation = Vector3.ZERO


func inside() -> bool:
	var bounds: Rect2 = player.get_screen_bounds()
	var size: Vector2 = root.get_visible_rect().size
	var margin: float = player.screen_margin_pixels - 0.05
	return bounds.position.x >= margin and bounds.position.y >= margin \
		and bounds.end.x <= size.x - margin and bounds.end.y <= size.y - margin


func _run() -> void:
	flight = load("res://scenes/main.tscn").instantiate()
	root.add_child(flight)
	current_scene = flight
	flight.get_node("Departure").finish_immediately()
	await process_frame
	player = flight.get_node("Player")
	player.set_physics_process(false)
	check(Engine.get_version_info().string.begins_with("4.7.2"), "Must run on Godot 4.7.2")
	check(ProjectSettings.get_setting("display/window/size/mode") == 3, "Default must be fullscreen")
	check(player._bounds_initialized, "Imported model must have real mesh bounds")
	check(player._model_bounds.size.x > 3.0, "Bounds must include complete scaled wings")
	check(inside(), "Initial aircraft must be fully on screen")

	reset_player()
	key(KEY_RIGHT, true)
	player._physics_process(0.1)
	check(is_equal_approx(player.position.x, 0.9), "Right arrow moves right at configured speed")
	check(player.bank.rotation.z < 0.0, "Right arrow lowers right wing")
	reset_player()
	key(KEY_LEFT, true)
	player._physics_process(0.1)
	check(player.position.x < 0.0 and player.bank.rotation.z > 0.0, "Left arrow moves and banks left")
	reset_player()
	key(KEY_UP, true)
	player._physics_process(0.1)
	check(is_equal_approx(player.position.z, -0.9), "Up arrow moves toward screen top")
	reset_player()
	key(KEY_DOWN, true)
	player._physics_process(0.1)
	check(is_equal_approx(player.position.z, 0.9), "Down arrow moves toward screen bottom")
	reset_player()
	key(KEY_RIGHT, true)
	key(KEY_UP, true)
	player._physics_process(0.1)
	check(absf(player.position.length() - 0.9) < 0.001, "Diagonal motion must not be faster")
	release_keys()
	for frame in range(90):
		player._physics_process(1.0 / 60.0)
	check(absf(player.bank.rotation.z) < 0.0001, "Aircraft returns level after key release")

	# All edges and corners, held input, bank return, and multiple aspect ratios.
	for window_size in [Vector2i(1920, 1080), Vector2i(1280, 1024), Vector2i(2560, 1080), Vector2i(720, 1280)]:
		root.size = window_size
		await process_frame
		await process_frame
		for codes in [[KEY_LEFT], [KEY_RIGHT], [KEY_UP], [KEY_DOWN], [KEY_LEFT, KEY_UP], [KEY_RIGHT, KEY_UP], [KEY_LEFT, KEY_DOWN], [KEY_RIGHT, KEY_DOWN]]:
			reset_player()
			for code in codes:
				key(code, true)
			for frame in range(240):
				player._physics_process(1.0 / 60.0)
				check(inside(), "Edge containment failed at %s / %s / frame %s" % [window_size, codes, frame])
			release_keys()
			for frame in range(60):
				player._physics_process(1.0 / 60.0)
				check(inside(), "Returning level must keep wing tips on screen")

	reset_player()
	key(KEY_RIGHT, true)
	key(KEY_LEFT, true)
	player._physics_process(0.1)
	check(player.position.is_zero_approx(), "Opposite arrows cancel movement")

	# Equivalent half-second displacement and banking at 30, 60, and 144 Hz.
	var positions: Array[Vector3] = []
	var banks: Array[float] = []
	for hz in [30, 60, 144]:
		reset_player()
		key(KEY_UP, true)
		key(KEY_RIGHT, true)
		for frame in range(hz / 2):
			player._physics_process(1.0 / hz)
		positions.append(player.position)
		banks.append(player.bank.rotation.z)
	check(positions[0].distance_to(positions[2]) < 0.001, "Movement must be frame-rate independent")
	check(absf(banks[0] - banks[2]) < 0.001, "Bank smoothing must be frame-rate independent")
	release_keys()
	var report := {"godot": Engine.get_version_info().string, "checks": checks, "failures": failures,
		"aspect_ratios": ["16:9", "5:4", "ultrawide", "portrait"], "escape": "Input event dispatched; exit code 0 required"}
	var file := FileAccess.open("res://tests/results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	if not failures.is_empty():
		quit(1)
		return
	print("PASS: %d flight checks. Dispatching Escape through Input." % checks)
	key(KEY_ESCAPE, true)
	await create_timer(2.0).timeout
	push_error("Escape did not quit the game")
	quit(1)
