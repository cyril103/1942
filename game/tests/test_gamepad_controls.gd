extends SceneTree
## Real input-dispatch regression. Launch through Tester-Silencieux.ps1.
const PROFILE := preload("res://scripts/campaign/profile.gd")
const PAD := preload("res://scripts/campaign/gamepad_bindings.gd")
const L10N := preload("res://scripts/campaign/localization.gd")
const COMMANDS := preload("res://scripts/campaign/command_labels.gd")
const FIXTURE := "user://gamepad-controls-regression.json"
var checks := 0
var failures: Array[String] = []
var app: Control
var input_device := 3
var captures := false
var output := ProjectSettings.globalize_path("res://../renders/controller-settings").simplify_path()

func _initialize() -> void:
	captures = "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless"
	if AudioServer.get_driver_name() != "Dummy":
		push_error("Gamepad regression requires --audio-driver Dummy")
		quit(1)
		return
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func cleanup() -> void:
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(FIXTURE + suffix): DirAccess.remove_absolute(FIXTURE + suffix)

func button(index: int, pressed := true, device := -99) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.device = input_device if device == -99 else device
	event.button_index = index
	event.pressed = pressed
	return event

func axis(index: int, value: float, device := -99) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.device = input_device if device == -99 else device
	event.axis = index
	event.axis_value = value
	return event

func key(code: int, pressed := true) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = pressed
	return event

func dispatch(event: InputEvent) -> void:
	Input.parse_input_event(event)
	await process_frame
	await process_frame

func tap(index: int) -> void:
	await dispatch(button(index))
	await dispatch(button(index, false))

func press_key(code: int) -> void:
	await dispatch(key(code))
	await dispatch(key(code, false))

func _capture(name: String) -> void:
	if not captures: return
	DirAccess.make_dir_recursive_absolute(output)
	for frame in range(3): await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(name + ".png")) == OK, "Screenshot: " + name)

func _geometry(context: String) -> void:
	var bounds := Rect2(0, 0, 1920, 1080)
	for child in app.design.get_children():
		if child is not Control or not child.visible: continue
		check(bounds.encloses(child.get_rect()), context + " contains " + str(child.name))
		if child is Label:
			check(child.get_minimum_size().y <= child.size.y + .2, context + " text fits " + str(child.name))
	for i in range(app.buttons.size()):
		for j in range(i + 1, app.buttons.size()):
			check(not app.buttons[i].get_rect().intersects(app.buttons[j].get_rect()), context + " buttons remain separated")

func _profile_checks() -> void:
	var profile := PROFILE.new()
	profile.data.run_score = 7820
	profile.data.unlocked = 12
	profile.data.bindings = {"fire": KEY_F}
	profile.data.erase("gamepad_profiles")
	var migrated: Dictionary = profile._decode_candidate(profile.data)
	check(not migrated.is_empty() and migrated.run_score == 7820 and migrated.unlocked == 12, "Legacy controller migration retains campaign progress")
	check(migrated.bindings.fire == KEY_F and PAD.bindings_for(migrated, -1).fire == [{"kind": "button", "index": JOY_BUTTON_A}], "Legacy keyboard controls survive alongside gamepad defaults")
	profile.data = migrated
	var displaced: Array[String] = PAD.assign(profile.data, -1, "fire", {"kind": "button", "index": JOY_BUTTON_B})
	var bindings: Dictionary = PAD.bindings_for(profile.data, -1)
	check(displaced.has("bomb") and bindings.fire == [{"kind": "button", "index": JOY_BUTTON_B}] and bindings.bomb == [{"kind": "button", "index": JOY_BUTTON_A}], "Choosing an occupied button swaps fire and bomb without losing either action")
	PAD.assign(profile.data, -1, "fire", {"kind": "axis", "index": JOY_AXIS_TRIGGER_RIGHT, "direction": 1})
	PAD.set_deadzone(profile.data, -1, .31)
	profile.path = FIXTURE
	check(profile.save() == OK, "Custom gamepad controls save to isolated profile")
	var restored := PROFILE.new()
	restored.path = FIXTURE
	check(restored.load_profile(), "Custom controller profile reloads")
	bindings = PAD.bindings_for(restored.data, -1)
	check(bindings.fire == [{"kind": "axis", "index": JOY_AXIS_TRIGGER_RIGHT, "direction": 1}] and is_equal_approx(PAD.deadzone_for(restored.data, -1), .31), "Trigger and deadzone survive a restart: " + str(bindings.fire) + " / " + str(PAD.deadzone_for(restored.data, -1)))
	check(restored.data.bindings.fire == KEY_F and restored.data.run_score == 7820 and restored.data.unlocked == 12, "Controller persistence leaves keyboard and campaign progress intact")
	for malformed in [null, [], "invalid", {"default": {"bindings": {"fire": [{"kind": "button", "index": -1}]}, "deadzone": "bad"}}]:
		var invalid: Dictionary = restored.data.duplicate(true)
		invalid.gamepad_profiles = malformed
		var decoded: Dictionary = restored._decode_candidate(invalid)
		check(not decoded.is_empty() and decoded.run_score == 7820 and not PAD.bindings_for(decoded, -1).fire.is_empty(), "Malformed optional gamepad preferences cannot invalidate a valid campaign: " + str(malformed))
	PAD.reset(restored.data, -1)
	check(PAD.bindings_for(restored.data, -1) == PAD.defaults() and restored.data.bindings.fire == KEY_F, "Resetting controller controls preserves custom keyboard controls")
	check(PAD.event_binding(button(JOY_BUTTON_A, false)).is_empty(), "Button releases are not captured as new assignments")
	check(PAD.event_binding(axis(JOY_AXIS_LEFT_X, .12)).is_empty(), "Ordinary stick drift is ignored by assignment capture")
	check(PAD.event_binding(axis(JOY_AXIS_TRIGGER_LEFT, -1)).is_empty(), "Resting negative trigger cannot be captured as a held button")
	check(PAD.event_binding(axis(JOY_AXIS_TRIGGER_RIGHT, .9)) == {"kind": "axis", "index": JOY_AXIS_TRIGGER_RIGHT, "direction": 1}, "Full analog trigger press becomes a configurable control")
	cleanup()

func _navigation_checks() -> void:
	app._show_main()
	var first: Control = root.gui_get_focus_owner()
	await tap(JOY_BUTTON_DPAD_DOWN)
	check(root.gui_get_focus_owner() != first, "Real D-pad events move focus in the main menu")
	app._show_main()
	app.set_process(false)
	await dispatch(button(JOY_BUTTON_DPAD_DOWN))
	first = root.gui_get_focus_owner()
	app.menu_gamepad_navigation.update(.5)
	check(root.gui_get_focus_owner() != first, "Holding a D-pad direction repeats focus movement through the integrated menu helper")
	await dispatch(button(JOY_BUTTON_DPAD_DOWN, false))
	first = root.gui_get_focus_owner()
	app.menu_gamepad_navigation.update(1.0)
	check(root.gui_get_focus_owner() == first, "Releasing the D-pad stops automatic menu repeats")
	app.set_process(true)
	app._show_main()
	first = root.gui_get_focus_owner()
	await dispatch(axis(JOY_AXIS_LEFT_Y, .9))
	check(root.gui_get_focus_owner() != first, "Real left-stick event moves menu focus")
	await dispatch(axis(JOY_AXIS_LEFT_Y, 0))
	app._show_main()
	await dispatch(button(JOY_BUTTON_A))
	await dispatch(button(JOY_BUTTON_A, false))
	check(app.page == "briefing", "Physical fire/confirm button opens the selected menu entry through actual GUI input")
	for frame in range(4): await process_frame
	check(app.page == "briefing" and not is_instance_valid(app.cockpit), "One confirm press and release cannot also activate the next page or launch a mission")
	await tap(JOY_BUTTON_B)
	check(app.page == "main", "Controller back returns to the main menu")
	await tap(JOY_BUTTON_B)
	check(app.page == "main" and not app.quitting, "Back never quits the main menu")
	await press_key(KEY_ENTER)
	check(app.page == "briefing", "Keyboard Enter retains menu activation")
	await press_key(KEY_ESCAPE)
	check(app.page == "main", "Keyboard Escape retains menu navigation")
	app._show_bindings()
	var automatic: CheckButton = app.design.get_node("AutomaticFire")
	automatic.grab_focus()
	var before: bool = automatic.button_pressed
	await tap(JOY_BUTTON_A)
	check(automatic.button_pressed != before and app.profile.data.settings.auto_fire == automatic.button_pressed, "One controller confirm toggles a real CheckButton exactly once")
	app.design.get_node("GamepadTab").grab_focus()
	await tap(JOY_BUTTON_A)
	check(app.page == "gamepad", "Controller confirm reaches controller setup from the keyboard commands page")

func _capture_checks() -> void:
	app._select_controller(input_device)
	PAD.reset(app.profile.data, input_device)
	PAD.apply(app.profile.data, input_device)
	app._show_gamepad()
	var first: Button = app.design.get_node("PadBind_fire")
	# A virtual device has no OS connection. Enable just this fixture entry to
	# exercise the same real GUI activation path during a headless test.
	first.disabled = false
	first.grab_focus()
	await tap(JOY_BUTTON_A)
	check(app.controller_menu.waiting == "fire" and app.page == "gamepad", "Confirm opens assignment capture without capturing its own release")
	check(PAD.bindings_for(app.profile.data, input_device).fire == PAD.defaults().fire, "Opening capture leaves the previous assignment untouched")
	await dispatch(axis(JOY_AXIS_LEFT_X, .12))
	check(app.controller_menu.waiting == "fire", "Stick drift cannot finish an assignment")
	await dispatch(axis(JOY_AXIS_LEFT_X, 0))
	await tap(JOY_BUTTON_B)
	var bindings: Dictionary = PAD.bindings_for(app.profile.data, input_device)
	check(app.page == "gamepad" and app.controller_menu.waiting.is_empty(), "B can be assigned without taking the Back action")
	check(bindings.fire == [{"kind": "button", "index": JOY_BUTTON_B}] and bindings.bomb == [{"kind": "button", "index": JOY_BUTTON_A}], "UI reports a real conflict swap and keeps both actions usable")
	check(app.notice.text.contains(L10N.text("Affectations échangées avec : %s") % L10N.text("Bombe")), "Conflict swap is explained to the player")
	app.controller_menu.begin_capture("fire")
	await dispatch(axis(JOY_AXIS_TRIGGER_RIGHT, .9))
	check(app.controller_menu.waiting.is_empty() and app.page == "gamepad", "A trigger press completes assignment without activating another UI element")
	await dispatch(axis(JOY_AXIS_TRIGGER_RIGHT, 0))
	await dispatch(axis(JOY_AXIS_TRIGGER_RIGHT, .9))
	check(Input.is_action_pressed("fire") and COMMANDS.gamepad("fire").contains("RT"), "Assigned analog trigger drives the real fire action and its displayed hint")
	await dispatch(axis(JOY_AXIS_TRIGGER_RIGHT, 0))
	check(not Input.is_action_pressed("fire"), "Releasing an assigned trigger releases fire")
	check(key(KEY_SPACE).is_action_pressed("fire"), "Rebinding controller fire preserves keyboard Space")
	app.controller_menu.begin_capture("strike")
	var before: Dictionary = PAD.bindings_for(app.profile.data, input_device)
	await press_key(KEY_ESCAPE)
	check(app.page == "gamepad" and app.controller_menu.waiting.is_empty() and PAD.bindings_for(app.profile.data, input_device) == before, "Escape cancels assignment without changing controls or leaving the setup screen")
	app.controller_menu.begin_capture("strike")
	app.controller_menu.update(13.0)
	check(app.controller_menu.waiting.is_empty() and PAD.bindings_for(app.profile.data, input_device) == before, "Assignment timeout restores usable controls without changing any bindings")
	await dispatch(button(JOY_BUTTON_RIGHT_SHOULDER))
	app.controller_menu.begin_capture("strike")
	await dispatch(button(JOY_BUTTON_RIGHT_SHOULDER))
	check(app.controller_menu.waiting == "strike", "A button held before capture must first be released")
	await dispatch(button(JOY_BUTTON_RIGHT_SHOULDER, false))
	await tap(JOY_BUTTON_RIGHT_SHOULDER)
	check(app.controller_menu.waiting.is_empty() and PAD.bindings_for(app.profile.data, input_device).strike == [{"kind": "button", "index": JOY_BUTTON_RIGHT_SHOULDER}], "A fresh press after neutral captures the held button correctly")
	app.controller_menu.begin_capture("fire")
	await tap(JOY_BUTTON_START)
	check(app.page == "gamepad" and app.controller_menu.waiting.is_empty(), "Start is assignable during capture without taking the normal menu-back path")
	app.controller_menu.begin_test()
	await tap(JOY_BUTTON_A)
	check(app.controller_menu.testing_inputs and app.page == "gamepad", "Live input test consumes confirm without clicking another control")
	await tap(JOY_BUTTON_B)
	check(not app.controller_menu.testing_inputs and app.page == "gamepad", "B exits live input test once and remains on controller setup")
	before = PAD.bindings_for(app.profile.data, input_device)
	app.controller_menu.begin_capture("fire")
	Input.joy_connection_changed.emit(input_device, false)
	check(app.page == "gamepad" and app.controller_menu.waiting.is_empty(), "Unplugging during capture cancels it and redraws the setup safely")
	Input.joy_connection_changed.emit(input_device, true)
	check(PAD.bindings_for(app.profile.data, input_device) == before, "Reconnection preserves the controller's saved assignments")
	app._select_controller(input_device)
	app._show_gamepad()
	app.profile.data.bindings.fire = KEY_F
	app._apply_bindings()
	app.controller_menu._restore()
	check(PAD.bindings_for(app.profile.data, input_device) == PAD.defaults() and key(KEY_F).is_action_pressed("fire"), "Controller Reset restores pad defaults while retaining the custom keyboard control")
	app._show_bindings()
	app.waiting_binding = "fire"
	await press_key(KEY_G)
	check(app.waiting_binding.is_empty() and app.profile.data.bindings.fire == KEY_G and button(JOY_BUTTON_A).is_action_pressed("fire"), "Existing keyboard remapping remains usable and preserves the controller assignment")
	app._show_gamepad()
	await tap(JOY_BUTTON_B)
	check(app.page == "bindings", "B exits controller setup through the expected keyboard commands page")

func _reset_scope_checks() -> void:
	PAD.assign(app.profile.data, input_device, "fire", {"kind": "axis", "index": JOY_AXIS_TRIGGER_LEFT, "direction": 1})
	PAD.set_deadzone(app.profile.data, input_device, .33)
	PAD.apply(app.profile.data, input_device)
	var controls: Dictionary = app.profile.data.gamepad_profiles.duplicate(true)
	app._new_campaign()
	check(app.profile.data.gamepad_profiles == controls and app.profile.data.bindings.fire == KEY_G, "New Campaign retains custom controller and keyboard preferences")
	app._show_bindings()
	var reset_button: Button
	for candidate in app.buttons:
		if candidate.text == L10N.text("RÉTABLIR"): reset_button = candidate
	check(is_instance_valid(reset_button), "Keyboard page exposes its own Reset control")
	if is_instance_valid(reset_button):
		reset_button.grab_focus()
		await tap(JOY_BUTTON_A)
	check(app.profile.data.bindings.is_empty() and key(KEY_SPACE).is_action_pressed("fire"), "Keyboard Reset restores the keyboard defaults")
	check(app.profile.data.gamepad_profiles == controls and axis(JOY_AXIS_TRIGGER_LEFT, .9).is_action_pressed("fire"), "Keyboard Reset leaves the controller's custom trigger and deadzone untouched")
	app._show_main()
	await tap(JOY_BUTTON_A)
	check(app.page == "briefing", "Menu confirm stays on A after fire is assigned to a trigger")
	app._show_gamepad()
	app.controller_menu._restore()

func _hotplug_suppression_checks() -> void:
	app._show_gamepad()
	app.controller_menu.begin_capture("fire")
	await dispatch(button(JOY_BUTTON_A))
	var token := str(input_device) + ":b" + str(JOY_BUTTON_A)
	check(app.controller_menu.suppressed.has(token), "Captured confirm remains suppressed until its release")
	# A real unplug may never deliver the release event. The connection signal
	# must retire that device's held capture token before it reconnects.
	Input.joy_connection_changed.emit(input_device, false)
	check(not app.controller_menu.suppressed.has(token), "Disconnect clears capture suppression even when no button release arrived")
	Input.joy_connection_changed.emit(input_device, true)
	app._select_controller(input_device)
	await dispatch(button(JOY_BUTTON_A, false))
	app._show_main()
	await tap(JOY_BUTTON_A)
	check(app.page == "briefing", "The reconnected controller can confirm a menu entry immediately")

func _save_failure_checks() -> void:
	app._show_gamepad()
	var saved_path: String = app.profile.path
	var saved_error: Error = app.profile.last_error
	var missing_directory := "user://gamepad-unavailable-%d" % OS.get_process_id()
	check(not DirAccess.dir_exists_absolute(missing_directory), "Save-error fixture deliberately has no parent directory")
	app.profile.path = missing_directory.path_join("controller.json")
	app.testing = false
	app.controller_menu.begin_capture("fire")
	await tap(JOY_BUTTON_Y)
	var save_error := L10N.text("SAUVEGARDE IMPOSSIBLE — progression conservée pour cette session.")
	check(app.profile.last_error != OK and app.notice.text == save_error, "An assignment save failure remains visible after the controller page redraw")
	check(PAD.bindings_for(app.profile.data, input_device).fire == [{"kind": "button", "index": JOY_BUTTON_Y}], "Failed disk save retains the new controller assignment for this session")
	app.controller_menu._restore()
	check(app.profile.last_error != OK and app.notice.text == save_error, "A controller-reset save failure is not overwritten by its success message")
	app.testing = true
	app.profile.path = saved_path
	app.profile.last_error = saved_error

func _analog_pause_checks() -> void:
	var countdown: bool = app.profile.data.settings.resume_countdown
	app.profile.data.settings.resume_countdown = false
	app._launch(4, "practice")
	check(app.page == "playing" and is_instance_valid(app.cockpit), "Analog pause fixture launches a real practice flight")
	if not is_instance_valid(app.cockpit): return
	app.cockpit.flight.process_mode = Node.PROCESS_MODE_DISABLED
	PAD.assign(app.profile.data, input_device, "quit_game", {"kind": "axis", "index": JOY_AXIS_TRIGGER_RIGHT, "direction": 1})
	PAD.apply(app.profile.data, input_device)
	await dispatch(axis(JOY_AXIS_TRIGGER_RIGHT, .85))
	check(app.page == "pause" and paused and Input.is_action_pressed("quit_game"), "Crossing the assigned analog pause threshold pauses the actual flight")
	await tap(JOY_BUTTON_A)
	check(app.page == "playing" and not paused and Input.is_action_pressed("quit_game"), "The menu resumes flight while the pause trigger is still held")
	await dispatch(axis(JOY_AXIS_TRIGGER_RIGHT, .91))
	await dispatch(axis(JOY_AXIS_TRIGGER_RIGHT, .76))
	check(app.page == "playing" and not paused, "Small changes in a held pause trigger cannot immediately pause the resumed flight again")
	await dispatch(axis(JOY_AXIS_TRIGGER_RIGHT, 0))
	check(not Input.is_action_pressed("quit_game"), "Releasing the pause trigger returns its real action to neutral")
	await dispatch(axis(JOY_AXIS_TRIGGER_RIGHT, .9))
	check(app.page == "pause" and paused, "A fresh pause-trigger press works again after release")
	await dispatch(axis(JOY_AXIS_TRIGGER_RIGHT, 0))
	app._show_main()
	app.profile.data.settings.resume_countdown = countdown
	PAD.reset(app.profile.data, input_device)
	PAD.apply(app.profile.data, input_device)

func _presentation_checks() -> void:
	for locale in ["fr", "en"]:
		L10N.set_locale(locale)
		for dimensions in [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1080)]:
			root.size = dimensions
			app._show_gamepad()
			await process_frame
			_geometry(locale + " controller " + str(dimensions))
			if dimensions == Vector2i(1920, 1080): await _capture(locale + "-controller")
		app.controller_menu.begin_capture("focus_flight")
		await process_frame
		_geometry(locale + " assignment capture")
		await _capture(locale + "-capture")
		app.controller_menu.cancel()
	check(L10N.has_translation("Pause") and L10N.has_translation("Pavé tactile"), "Composed controller action and hardware labels also have English copy")

func _run() -> void:
	cleanup()
	_profile_checks()
	app = load("res://scenes/campaign.tscn").instantiate()
	app.testing = true
	app.profile.path = FIXTURE
	root.add_child(app)
	current_scene = app
	await process_frame
	var connected := Input.get_connected_joypads()
	if not connected.is_empty(): input_device = connected[0]
	app._select_controller(input_device)
	await _navigation_checks()
	await _capture_checks()
	await _reset_scope_checks()
	await _hotplug_suppression_checks()
	await _save_failure_checks()
	await _analog_pause_checks()
	await _presentation_checks()
	check(L10N.catalogue_errors.is_empty(), "Gamepad translations load without catalogue conflicts")
	app._dispose_run()
	app.music.stop()
	app.queue_free()
	await process_frame
	await create_timer(.15).timeout
	cleanup()
	print("GAMEPAD CONTROLS: ", checks, " checks, ", failures.size(), " failures: ", failures)
	quit(0 if failures.is_empty() else 1)
