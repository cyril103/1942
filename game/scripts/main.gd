extends Node3D

const CONTROLS: Dictionary = {
	"move_left": KEY_LEFT,
	"move_right": KEY_RIGHT,
	"move_up": KEY_UP,
	"move_down": KEY_DOWN,
	"fire": KEY_SPACE,
	"restart_test": KEY_R,
	"quit_game": KEY_ESCAPE,
}


func _ready() -> void:
	for action: String in CONTROLS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var key := InputEventKey.new()
			key.keycode = CONTROLS[action]
			InputMap.action_add_event(action, key)
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	# This optional path captures the real engine viewport for visual QA.
	if "--capture-preview" in OS.get_cmdline_user_args():
		_capture_preview()


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart_test") and not event.echo:
		get_viewport().set_input_as_handled()
		get_tree().reload_current_scene()
	if event.is_action_pressed("quit_game"):
		get_viewport().set_input_as_handled()
		get_tree().quit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		for action: String in CONTROLS:
			if InputMap.has_action(action):
				Input.action_release(action)


func _capture_preview() -> void:
	for frame in range(12):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path("res://../renders/godot-premier-vol.png")
	var result := get_viewport().get_texture().get_image().save_png(path)
	print("VIEWPORT_CAPTURE mode=%s window=%s viewport=%s result=%s" % [DisplayServer.window_get_mode(), DisplayServer.window_get_size(), get_viewport().get_visible_rect().size, result])
	if result != OK:
		push_error("Unable to save viewport: %s" % result)
	get_tree().quit(result)
