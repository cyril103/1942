extends RefCounted

# Native Controls handle the first direction event. This helper only generates
# the subsequent repeats, without changing gameplay actions or consuming input.
const INITIAL_DELAY := 0.4
const REPEAT_INTERVAL := 0.12
const STICK_THRESHOLD := 0.55
const STICK_RELEASE := 0.35
const AXIS_SWITCH_MARGIN := 0.15
const DIRECTIONS := {
	JOY_BUTTON_DPAD_LEFT: Vector2.LEFT,
	JOY_BUTTON_DPAD_RIGHT: Vector2.RIGHT,
	JOY_BUTTON_DPAD_UP: Vector2.UP,
	JOY_BUTTON_DPAD_DOWN: Vector2.DOWN,
}

var blocked := false:
	set(value):
		if blocked != value: reset()
		blocked = value

var _owner: Control
var _page := ""
var _device := -1
var _stick := Vector2.ZERO
var _dpad: Dictionary = {}
var _action := ""
var _remaining := INITIAL_DELAY

func _init(owner: Control) -> void:
	_owner = owner
	_page = str(owner.get("page"))

func reset() -> void:
	_device = -1
	_stick = Vector2.ZERO
	_dpad.clear()
	_action = ""
	_remaining = INITIAL_DELAY

func handle_input(event: InputEvent) -> void:
	_sync_page()
	if not _active():
		reset()
		return
	if event is InputEventKey or event is InputEventMouseButton:
		if event.is_pressed(): reset()
		return
	if event is InputEventJoypadButton:
		if not DIRECTIONS.has(event.button_index):
			if event.pressed: reset()
			return
		if event.device != _device:
			if not event.pressed: return
			reset()
			_device = event.device
		if event.pressed: _dpad[event.button_index] = true
		else: _dpad.erase(event.button_index)
	elif event is InputEventJoypadMotion:
		if event.axis not in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y]: return
		if event.device != _device:
			if absf(event.axis_value) < STICK_THRESHOLD: return
			reset()
			_device = event.device
		if event.axis == JOY_AXIS_LEFT_X: _stick.x = event.axis_value
		else: _stick.y = event.axis_value
	else:
		return
	var direction := Vector2.ZERO
	for button in _dpad: direction += DIRECTIONS[button]
	var next := _direction_action(direction if not _dpad.is_empty() else _stick)
	if next != _action:
		_action = next
		_remaining = INITIAL_DELAY

func update(delta: float) -> void:
	_sync_page()
	if not _active():
		reset()
		return
	if _action.is_empty(): return
	# Synthetic devices are allowed by the isolated tests, never by a real menu.
	if not bool(_owner.get("testing")) and not Input.get_connected_joypads().has(_device):
		reset()
		return
	_remaining -= maxf(0.0, delta)
	if _remaining > 0.0: return
	# At most one repeat per frame; do not flood menus following a loading stall.
	_remaining = REPEAT_INTERVAL
	var event := InputEventAction.new()
	event.action = _action
	event.pressed = true
	event.strength = 1.0
	_owner.get_viewport().push_input(event)
	event = event.duplicate()
	event.pressed = false
	event.strength = 0.0
	_owner.get_viewport().push_input(event)

func _sync_page() -> void:
	if not is_instance_valid(_owner): return
	var current := str(_owner.get("page"))
	if current != _page:
		reset()
		_page = current

func _active() -> bool:
	if blocked or not is_instance_valid(_owner) or not _owner.is_inside_tree(): return false
	if _page in ["playing", "loading", "resuming"]: return false
	if bool(_owner.get("preparing")) or str(_owner.get("waiting_binding")) != "": return false
	if not bool(_owner.get("testing")) and not _owner.get_window().has_focus(): return false
	return is_instance_valid(_owner.get_viewport().gui_get_focus_owner())

func _direction_action(direction: Vector2) -> String:
	var x := absf(direction.x)
	var y := absf(direction.y)
	var horizontal := x > y
	# Retain the dominant direction near diagonals, until another axis clearly
	# takes over. Release uses a lower threshold than the initial activation.
	if _action in ["ui_left", "ui_right"] and x >= STICK_RELEASE and y <= x + AXIS_SWITCH_MARGIN:
		horizontal = true
	elif _action in ["ui_up", "ui_down"] and y >= STICK_RELEASE and x <= y + AXIS_SWITCH_MARGIN:
		horizontal = false
	var magnitude := x if horizontal else y
	var candidate := ("ui_left" if direction.x < 0.0 else "ui_right") if horizontal else ("ui_up" if direction.y < 0.0 else "ui_down")
	var threshold := STICK_RELEASE if candidate == _action else STICK_THRESHOLD
	return candidate if magnitude >= threshold else ""
