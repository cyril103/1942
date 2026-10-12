extends SceneTree

# Read-only diagnostic: no campaign scene or player profile is loaded.
# Run with --audio-driver Dummy. Use a rendered driver to inspect real hardware.
var activation_count := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	print("CONTROLLER PROBE engine=", Engine.get_version_info().string, " display=", DisplayServer.get_name())
	for action in ["ui_accept", "ui_cancel", "ui_select", "ui_left", "ui_right", "ui_up", "ui_down"]:
		var records: Array = []
		for event in InputMap.action_get_events(action):
			records.append({"class": event.get_class(), "device": event.device, "text": event.as_text()})
		print("DEFAULT ACTION ", action, " ", JSON.stringify(records))
	await create_timer(1.0).timeout
	var devices := Input.get_connected_joypads()
	print("CONNECTED JOYPADS ", devices)
	for device in devices:
		var axes: Array = []
		var pressed: Array = []
		for axis in JOY_AXIS_MAX:
			axes.append({"axis": axis, "value": Input.get_joy_axis(device, axis)})
		for button in JOY_BUTTON_MAX:
			if Input.is_joy_button_pressed(device, button): pressed.append(button)
		print("PHYSICAL ", JSON.stringify({"device": device, "name": Input.get_joy_name(device), "guid": Input.get_joy_guid(device), "known": Input.is_joy_known(device), "info": Input.get_joy_info(device), "axes": axes, "pressed_buttons": pressed}))
	var button := Button.new()
	button.text = "Controller diagnostic"
	button.position = Vector2(20, 20)
	button.size = Vector2(250, 70)
	button.pressed.connect(func(): activation_count += 1)
	root.add_child(button)
	await process_frame
	button.grab_focus()
	await process_frame
	await _probe_accept("DEFAULT", button)
	var accept := InputEventJoypadButton.new()
	accept.device = -1
	accept.button_index = JOY_BUTTON_A
	InputMap.action_add_event("ui_accept", accept)
	await _probe_accept("EXPLICIT A", button)
	button.queue_free()
	await process_frame
	await _probe_native_hold()
	quit()

func _probe_accept(label: String, button: Button) -> void:
	for device in [0, 1, 2, 7]:
		var event := InputEventJoypadButton.new()
		event.device = device
		event.button_index = JOY_BUTTON_A
		event.pressed = true
		var baseline := activation_count
		var action_matches := event.is_action_pressed("ui_accept")
		root.push_input(event)
		event = event.duplicate()
		event.pressed = false
		root.push_input(event)
		await process_frame
		print("NATIVE ACCEPT ", label, " device=", device, " action_matches=", action_matches, " activations=", activation_count - baseline, " focus=", root.gui_get_focus_owner() == button)

func _probe_native_hold() -> void:
	var buttons: Array[Button] = []
	var panel := Control.new()
	panel.size = Vector2(480, 240)
	root.add_child(panel)
	for index in 6:
		var item := Button.new()
		item.text = "Navigation %d" % index
		item.position = Vector2(20, 5 + index * 35)
		item.size = Vector2(250, 32)
		panel.add_child(item)
		buttons.append(item)
	await process_frame
	buttons[0].grab_focus()
	var down := InputEventJoypadButton.new()
	down.device = 7
	down.button_index = JOY_BUTTON_DPAD_DOWN
	down.pressed = true
	Input.parse_input_event(down)
	Input.flush_buffered_events()
	await process_frame
	print("NATIVE HOLD after press focus=", buttons.find(root.gui_get_focus_owner()))
	await create_timer(1.5).timeout
	print("NATIVE HOLD after 1.5s focus=", buttons.find(root.gui_get_focus_owner()))
	down = down.duplicate()
	down.pressed = false
	Input.parse_input_event(down)
