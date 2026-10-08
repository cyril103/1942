extends "benchmark_full_mission.gd"
## Multi-mission lifecycle probe. Uses the immutable pack's replay pilot and
## counters, but retains one real App across launches, results and short retries.
## Automated/invulnerable; never a campaign progression or human-play claim.
const SESSION_MISSIONS := [3, 3, 7, 7, 19, 19, 31, 31]

func _run() -> void:
	var engine_args := OS.get_cmdline_args()
	var audio_at := engine_args.find("--audio-driver")
	if audio_at < 0 or audio_at + 1 >= engine_args.size() or engine_args[audio_at + 1] != "Dummy":
		push_error("Session endurance requires --audio-driver Dummy before creating voices")
		quit(1)
		return
	if repeats != SESSION_MISSIONS.size():
		push_error("Session endurance requires exactly eight passes")
		quit(1)
		return
	Engine.physics_ticks_per_second = 60
	Engine.max_fps = 0
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(dimensions)
	root.size = dimensions
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var initial_memory := memory_snapshot()
	app = load("res://scenes/campaign.tscn").instantiate()
	app.testing = true
	app.profile.path = "user://benchmark-session-endurance-fixture.json"
	root.add_child(app)
	current_scene = app
	await process_frame
	app.profile.reset()
	app.profile.data.unlocked = 32
	app.profile.data.settings.quality = quality
	app.profile.data.settings.fullscreen = false
	app.profile.data.settings.vsync = false
	app.profile.data.settings.short_retry_intro = true
	var app_id := app.get_instance_id()
	for index in range(repeats):
		await _session_pass(index)
		if not is_instance_valid(app) or app.get_instance_id() != app_id:
			failures.append("App replaced during the session")
			break
	app.music.stop()
	app.queue_free()
	await create_timer(.25).timeout
	var final_idle_start := Time.get_unix_time_from_system()
	await create_timer(3.0).timeout
	var final_memory := memory_snapshot()
	if reports.size() != repeats: failures.append("Incomplete session")
	if int(final_memory.nodes) != 1 or int(final_memory.orphan_nodes) != 0:
		failures.append("Scene nodes remain after final App disposal")
	var report := {
		"schema": 3, "kind": "persistent_app_multi_mission_endurance",
		"build_id": build_id, "engine": Engine.get_version_info(),
		"gpu": RenderingServer.get_video_adapter_name(), "cpu": OS.get_processor_name(),
		"resolution": [dimensions.x, dimensions.y], "quality": quality,
		"mission_sequence": SESSION_MISSIONS, "physics_hz": 60,
		"duration_ticks_per_pass": duration_seconds * 60, "audio_driver": "Dummy",
		"player_invulnerable": true, "initial_memory": initial_memory,
		"final_memory": final_memory, "passes": reports, "failures": failures,
		"final_idle_window_unix_s": [final_idle_start, Time.get_unix_time_from_system()],
		"limits": "Prepared arcade profile; one App, four distinct raids and their actual short retries. No saved campaign progression, human play or second hardware. Process memory and the hashed external base-script snapshot are in the separate Windows observer report."
	}
	# Keep the observer's expected filename; kind/schema prevent confusing this
	# lifecycle report with the paired deterministic full-mission benchmark.
	var filename := "full-mission-%02d-q%d-%dx%d.json" % [mission_number, quality, dimensions.x, dimensions.y]
	write_report(output_dir.path_join(filename), report)
	print("SESSION ENDURANCE ", filename, " passes=", reports.size(), " failures=", failures)
	quit(0 if failures.is_empty() else 1)

func _session_pass(index: int) -> void:
	seed(1942)
	var number: int = SESSION_MISSIONS[index]
	var retry := index % 2 == 1
	var started := Time.get_ticks_usec()
	app._launch(number, "arcade", retry)
	var d: Node = app.director
	var loadout := {"aircraft": app.session_profile.data.aircraft,
		"difficulty": app.session_profile.data.difficulty,
		"upgrades": app.session_profile.data.upgrades.duplicate(),
		"power": app.session_profile.data.power}
	var flight: Node = app.cockpit.flight
	var departure: Node = flight.get_node("Departure")
	# The actual launch chooses short/full choreography; do not seed seen_departures.
	var seen_before: bool = app.seen_departures.has("arcade:%d" % number)
	if retry and not seen_before: failures.append("Normal takeoff not remembered before retry %d" % number)
	d.weapons.audio._rng.seed = 1942
	for action in InputMap.get_actions():
		Input.action_release(action)
		InputMap.action_erase_events(action)
	var prototype: Script = flight.get_script()
	for method in prototype.get_script_method_list():
		if str(method.name) in ["_process", "_physics_process"]:
			failures.append("Prototype acquired a gameplay callback")
	flight.set_script(null)
	pilot = ReplayPilot.new()
	pilot.director = d
	pilot.process_mode = Node.PROCESS_MODE_ALWAYS
	pilot.process_physics_priority = -1000
	root.add_child(pilot)
	var finished_tick := -1
	var departure_tick := -1
	var peak_contacts := 0
	var peak_bullets := 0
	var phases := {}
	var memory: Array[Dictionary] = []
	var next_memory_tick := 0
	while pilot.ticks < duration_seconds * 60:
		await process_frame
		var playing: bool = app.page == "playing" and is_instance_valid(d)
		if playing:
			var phase := phase_of(d, flight)
			phases[phase] = int(phases.get(phase, 0)) + 1
			if departure_tick < 0 and not departure.active: departure_tick = pilot.ticks
			peak_contacts = maxi(peak_contacts, d.combat.get_radar_contacts().size())
			var bullets := 0
			for life in d.combat.lifetimes:
				if life > 0: bullets += 1
			peak_bullets = maxi(peak_bullets, bullets)
		elif finished_tick < 0:
			finished_tick = pilot.ticks
		if pilot.ticks >= next_memory_tick:
			memory.append({"tick": pilot.ticks, "memory": memory_snapshot()})
			next_memory_tick = pilot.ticks + 300
		if (Time.get_ticks_usec() - started) / 1000000.0 > duration_seconds * 2.5:
			failures.append("Session pass wall timeout")
			break
	if finished_tick < 0: failures.append("No result for mission %d retry=%s" % [number, retry])
	for phase in ["takeoff", "approach", "descent", "ground", "climb", "return_combat", "landing"]:
		if not phases.has(phase): failures.append("Missing %s in pass %d" % [phase, index])
	if retry and (departure_tick < 0 or departure_tick > 110): failures.append("Short retry did not finish within its 1.6 s allowance")
	if not retry and departure_tick <= 110: failures.append("First launch unexpectedly used short departure")
	var item := {"pass": index, "mission": number, "retry": retry, "loadout": loadout,
		"physics_ticks": pilot.ticks, "finished_tick": finished_tick,
		"departure_tick": departure_tick, "phases": phases,
		"peak_contacts": peak_contacts, "peak_bullets": peak_bullets,
		"result": app.result.duplicate(true), "memory_samples": memory,
		"elapsed_ms": (Time.get_ticks_usec() - started) / 1000.0}
	for action in ["move_left", "move_right", "move_up", "move_down", "fire"]: Input.action_release(action)
	pilot.queue_free()
	app._dispose_run()
	app._show_main()
	await create_timer(.25).timeout
	# A three-second settled menu window lets the independent 1 Hz Windows
	# observer sample memory AFTER actors are freed, without guessed alignment.
	item.idle_start_unix_s = Time.get_unix_time_from_system()
	await create_timer(3.0).timeout
	item.idle_end_unix_s = Time.get_unix_time_from_system()
	item.after_dispose_memory = memory_snapshot()
	if is_instance_valid(app.director) or is_instance_valid(app.cockpit): failures.append("Run actors remain owned after disposal")
	write_report(output_dir.path_join("session-pass-%02d.json" % index), item)
	item.erase("memory_samples")
	reports.append(item)
	print("SESSION PASS ", index, " mission=", number, " retry=", retry, " departure_tick=", departure_tick, " result_tick=", finished_tick, " memory=", item.after_dispose_memory)
