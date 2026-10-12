extends SceneTree
## Exercise real pause/input paths with an isolated profile and Dummy audio.
const PROFILE := preload("res://scripts/campaign/profile.gd")
const L10N := preload("res://scripts/campaign/localization.gd")
const FIXTURE := "user://flight-comfort-regression.json"
var checks := 0
var failures: Array[String] = []
var app: Control
var captures := false
var output := ProjectSettings.globalize_path("res://").path_join("../renders/command-2.4").simplify_path()

func _initialize() -> void:
	captures = "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name()!="headless"
	_run.call_deferred()

func _capture(name: String) -> void:
	if not captures: return
	DirAccess.make_dir_recursive_absolute(output)
	for frame in range(3): await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(name+".png"))==OK,"Screenshot: "+name)

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func cleanup() -> void:
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(FIXTURE+suffix): DirAccess.remove_absolute(FIXTURE+suffix)

func pad(button: int, device := 3) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.device = device
	event.button_index = button
	event.pressed = true
	return event

func _profile_checks() -> void:
	var profile := PROFILE.new()
	profile.data.run_score = 7820
	profile.data.unlocked = 12
	profile.data.settings.erase("resume_countdown")
	profile.data.settings.erase("pause_on_disconnect")
	var migrated: Dictionary = profile._decode_candidate(profile.data)
	check(migrated.settings.resume_countdown and migrated.settings.pause_on_disconnect,"Legacy profiles enable comfort defaults")
	check(migrated.run_score==7820 and migrated.unlocked==12,"Comfort migration preserves campaign progress")
	profile.data = migrated
	profile.data.settings.resume_countdown = false
	profile.data.settings.pause_on_disconnect = false
	profile.path = FIXTURE
	check(profile.save()==OK,"Comfort preferences save to isolated profile")
	var restored := PROFILE.new()
	restored.path = FIXTURE
	check(restored.load_profile() and not restored.data.settings.resume_countdown and not restored.data.settings.pause_on_disconnect,"Both preferences survive restart")
	profile.data.settings.resume_countdown = "false"
	check(profile._decode_candidate(profile.data).is_empty(),"Invalid comfort types cannot be treated as enabled strings")
	cleanup()

func _geometry(context: String) -> void:
	var bounds := Rect2(0,0,1920,1080)
	for child in app.design.get_children():
		if child is not Control: continue
		check(bounds.encloses(child.get_rect()),context+" contains "+str(child.name))
		if child is Label: check(child.get_minimum_size().y<=child.size.y+.2,context+" text fits "+str(child.name))

func _run() -> void:
	cleanup()
	_profile_checks()
	app = load("res://scenes/campaign.tscn").instantiate()
	app.testing = true
	app.profile.path = FIXTURE
	root.add_child(app)
	current_scene = app
	await process_frame
	app.set_process(false)
	app.profile.reset()
	app._show_settings(false)
	app._show_graphics()
	app._show_flight_comfort()
	check(root.gui_get_focus_owner().name=="ResumeCountdown","Comfort starts on an actionable controller-focusable setting")
	for code in ["fr","en"]:
		L10N.set_locale(code)
		for dimensions in [Vector2i(1280,720),Vector2i(1920,1080),Vector2i(2560,1080)]:
			root.size = dimensions
			app._show_flight_comfort()
			await process_frame
			_geometry(code+" comfort "+str(dimensions))
			if dimensions==Vector2i(1920,1080): await _capture("comfort-"+code)
	L10N.set_locale("fr")
	app._input(pad(JOY_BUTTON_B))
	check(app.page=="graphics","Controller B returns from comfort to graphics")
	app._input(pad(JOY_BUTTON_B))
	check(app.page=="settings","Controller B returns from graphics to options")
	app._input(pad(JOY_BUTTON_B))
	check(app.page=="main","Controller B returns from options to main")
	app._input(pad(JOY_BUTTON_B))
	check(app.page=="main" and not app.quitting,"Controller B cannot accidentally quit from main")
	app._show_bindings()
	app.waiting_binding = "fire"
	app._input(pad(JOY_BUTTON_B))
	check(app.page=="bindings" and app.waiting_binding.is_empty(),"Controller B cancels a pending keyboard binding")
	app._launch(4,"practice")
	app._input(pad(JOY_BUTTON_B))
	check(app.page=="playing" and pad(JOY_BUTTON_B).is_action_pressed("bomb"),"Controller B remains bound to bomb during flight")
	app._show_pause()
	var elapsed: float = app.director.elapsed
	var position: Vector3 = app.director.player.position
	var score: int = app.director.combat.score
	app._resume()
	check(app.page=="resuming" and paused and app.director.paused and app.resume_label.text=="3","Resume begins a three-second frozen countdown")
	root.size = Vector2i(1920,1080)
	await _capture("resume-fr")
	app.set_process(true)
	for frame in range(8): await process_frame
	app.set_process(false)
	check(app.resume_remaining<3.0 and app.resume_remaining>0.0,"Countdown advances while the SceneTree is paused")
	check(app.director.elapsed==elapsed and app.director.player.position==position and app.director.combat.score==score,"Countdown never advances combat, player movement or score")
	app._advance_resume(1.0)
	check(app.resume_label.text=="2" and paused,"Countdown displays its remaining whole seconds")
	app._input(pad(JOY_BUTTON_B))
	check(app.page=="pause" and paused and app.resume_remaining==0.0,"Controller B cancels the countdown without resuming combat")
	app._advance_resume(10.0)
	check(app.page=="pause" and paused,"Cancelled countdown cannot later release the pause")
	app._resume()
	app._advance_resume(2.9)
	check(paused and app.resume_label.text=="1","Combat remains frozen until all three seconds expire")
	app._advance_resume(.1)
	check(app.page=="playing" and not paused and not app.director.paused,"Countdown completion resumes the existing flight")
	app._track_input_device(pad(JOY_BUTTON_A,3))
	var drift := InputEventJoypadMotion.new()
	drift.device = 9
	drift.axis = JOY_AXIS_LEFT_X
	drift.axis_value = .12
	app._track_input_device(drift)
	check(app.active_joypad==3,"Small stick drift on another controller cannot steal active-device tracking")
	Input.joy_connection_changed.emit(9,false)
	check(app.page=="playing","Disconnecting an unused controller does not pause keyboard or active controller play")
	Input.joy_connection_changed.emit(3,false)
	check(app.page=="pause" and paused and app.notice.text.contains("DÉCONNECTÉE"),"Disconnecting the active controller pauses and explains why")
	Input.joy_connection_changed.emit(3,true)
	check(app.page=="pause" and paused and app.notice.text.contains("RECONNECTÉE"),"Reconnection acknowledges the controller without resuming automatically")
	app._resume()
	app._track_input_device(pad(JOY_BUTTON_A,3))
	Input.joy_connection_changed.emit(3,false)
	check(app.page=="pause" and paused,"Controller loss also cancels an in-progress resume countdown")
	app._track_input_device(pad(JOY_BUTTON_A,3))
	app.preparing = true
	app.page = "loading"
	Input.joy_connection_changed.emit(3,false)
	check(app.page=="loading" and app.pending_controller_disconnect==3,"Controller loss during rendering preparation is deferred safely")
	app._build_run(4,"practice",false)
	app.preparing = false
	app._apply_launch_safety()
	check(app.page=="pause" and paused and app.disconnected_joypad==3,"Building the new flight preserves the pending disconnect and pauses before play")
	app._track_input_device(pad(JOY_BUTTON_A,3))
	app.preparing = true
	app.page = "loading"
	Input.joy_connection_changed.emit(3,false)
	Input.joy_connection_changed.emit(3,true)
	check(app.pending_controller_disconnect==-1 and app.active_joypad==3,"Reconnection during preparation clears the pending loss and tracks the returned controller")
	app.preparing = false
	app._show_pause()
	app.profile.data.settings.pause_on_disconnect = false
	app.profile.data.settings.resume_countdown = false
	app._resume()
	check(app.page=="playing" and not paused,"Disabling countdown restores immediate resume")
	app._track_input_device(pad(JOY_BUTTON_A,3))
	Input.joy_connection_changed.emit(3,false)
	check(app.page=="playing","Disconnect pause can be disabled explicitly")
	app.profile.data.settings.pause_on_disconnect = true
	app._track_input_device(pad(JOY_BUTTON_A,3))
	var key := InputEventKey.new()
	key.keycode = KEY_LEFT
	key.pressed = true
	app._track_input_device(key)
	Input.joy_connection_changed.emit(3,false)
	check(app.page=="playing","Switching back to keyboard makes the old controller irrelevant")
	app.profile.data.settings.resume_countdown = true
	app.profile.data.settings.shake = false
	app.profile.data.settings.flashes = false
	app._show_pause()
	app._resume()
	check(app.resume_label.scale==Vector2.ONE and app.resume_label.modulate==Color.WHITE,"Reduced-motion resume uses static text without animation or flashes")
	app.testing = false
	app._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	app.testing = true
	check(app.page=="pause" and paused,"Focus loss cancels countdown before combat can resume offscreen")
	app._set_language("en")
	app._resume()
	check(app.notice.text=="ESC / START / B  •  STAY PAUSED","Countdown navigation is localized")
	_geometry("English resume")
	await _capture("resume-en")
	app._show_main()
	app._advance_resume(10)
	check(app.page=="main" and not paused and not is_instance_valid(app.director),"Leaving a countdown disposes it without reviving an old flight")
	if is_instance_valid(app.music): app.music.stop()
	app.queue_free()
	await process_frame
	cleanup()
	L10N.set_locale("fr")
	print("FLIGHT COMFORT TEST ",checks," checks, ",failures.size()," failures: ",failures)
	await create_timer(.2).timeout
	quit(0 if failures.is_empty() else 1)
