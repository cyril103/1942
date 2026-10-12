extends SceneTree

const NAVIGATION := preload("res://scripts/campaign/menu_gamepad_navigation.gd")
class MenuFixture extends Control:
	var page := "main"
	var preparing := false
	var waiting_binding := ""
	var testing := true
	var navigation: RefCounted
	func _input(event: InputEvent) -> void:
		if navigation != null: navigation.handle_input(event)

var fixture: MenuFixture
var navigation: RefCounted
var buttons: Array[Button] = []
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func button_event(index: int, pressed := true, device := 7) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = index
	event.pressed = pressed
	event.device = device
	root.push_input(event)

func axis_event(axis: int, value: float, device := 7) -> void:
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = value
	event.device = device
	# The helper observes the real event; action-state-dependent native stick
	# transitions are covered separately from this repeat timer's behavior.
	navigation.handle_input(event)

func focused() -> int:
	return buttons.find(root.gui_get_focus_owner())

func restart() -> void:
	navigation.reset()
	fixture.page = "main"
	fixture.waiting_binding = ""
	fixture.preparing = false
	navigation.blocked = false
	navigation.update(0.0)
	buttons[0].grab_focus()

func _run() -> void:
	fixture = MenuFixture.new()
	fixture.size = Vector2(480, 400)
	root.add_child(fixture)
	for index in 8:
		var button := Button.new()
		button.position = Vector2(20, 10 + index * 44)
		button.size = Vector2(260, 40)
		button.text = "Item %d" % index
		fixture.add_child(button)
		buttons.append(button)
	navigation = NAVIGATION.new(fixture)
	fixture.navigation = navigation
	await process_frame
	restart()
	button_event(JOY_BUTTON_DPAD_DOWN)
	check(focused() == 1, "Original D-pad event moves exactly once")
	navigation.update(0.39)
	check(focused() == 1, "Initial hold delay does not skip items")
	navigation.update(0.02)
	check(focused() == 2, "Held D-pad repeats after initial delay")
	navigation.update(0.13)
	check(focused() == 3, "Subsequent repeat uses short interval")
	button_event(JOY_BUTTON_DPAD_DOWN, false)
	navigation.update(1.0)
	check(focused() == 3, "Release cancels future repeats")
	restart()
	button_event(JOY_BUTTON_DPAD_DOWN)
	navigation.update(10.0)
	check(focused() == 2, "A long stalled frame emits at most one repeat")
	fixture.page = "settings"
	navigation.update(1.0)
	check(focused() == 2, "Page transition clears held direction")
	for forbidden in ["playing", "loading", "resuming"]:
		restart()
		button_event(JOY_BUTTON_DPAD_DOWN)
		fixture.page = forbidden
		navigation.update(1.0)
		check(focused() == 1, "No repeated navigation during " + forbidden)
	restart()
	button_event(JOY_BUTTON_DPAD_DOWN)
	fixture.waiting_binding = "fire"
	navigation.update(1.0)
	check(focused() == 1, "Keyboard binding capture suspends repeats")
	restart()
	button_event(JOY_BUTTON_DPAD_DOWN)
	navigation.blocked = true
	navigation.update(1.0)
	check(focused() == 1, "Controller capture/test suspension clears repeats")
	navigation.blocked = false
	navigation.update(1.0)
	check(focused() == 1, "Leaving capture/test does not restore old hold")
	restart()
	axis_event(JOY_AXIS_LEFT_Y, 0.54)
	navigation.update(1.0)
	check(focused() == 0, "Low stick motion does not arm repeat")
	axis_event(JOY_AXIS_LEFT_Y, 0.7)
	navigation.update(0.41)
	check(focused() == 1, "Stick crossing threshold arms repeat")
	axis_event(JOY_AXIS_LEFT_Y, 0.4)
	navigation.update(0.13)
	check(focused() == 2, "Stick hysteresis tolerates small changes")
	axis_event(JOY_AXIS_LEFT_Y, 0.3)
	navigation.update(1.0)
	check(focused() == 2, "Stick returning below release threshold stops repeat")
	restart()
	axis_event(JOY_AXIS_LEFT_Y, 0.8)
	axis_event(JOY_AXIS_LEFT_X, 0.79)
	navigation.update(0.41)
	check(focused() == 1, "Near diagonal input keeps dominant vertical direction")
	axis_event(JOY_AXIS_LEFT_Y, 0.0, 2)
	navigation.update(0.13)
	check(focused() == 2, "Neutral event from other controller does not cancel active hold")
	restart()
	button_event(JOY_BUTTON_DPAD_DOWN)
	buttons[1].release_focus()
	navigation.update(1.0)
	buttons[1].grab_focus()
	navigation.update(1.0)
	check(focused() == 1, "Lost GUI focus clears repeats permanently")
	print("MENU GAMEPAD NAVIGATION: ", checks, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
