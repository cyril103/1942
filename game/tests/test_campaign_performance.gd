extends SceneTree
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var app = load("res://scenes/campaign.tscn").instantiate()
	app.testing = true
	root.add_child(app)
	current_scene = app
	await process_frame
	app._launch(31)
	app.cockpit.flight.get_node("Departure").finish_immediately()
	app.director.event_index = app.director.mission.events.size()
	app.cockpit.player.invulnerable_time = 60
	app.director._dispatch({"kind":"hayabusa","pattern":1})
	app.director._spawn_naval(2)
	Input.action_press("fire")
	var results := []
	for shadows in [true,false]:
		app.cockpit.flight.get_node("KeyLight").shadow_enabled = shadows
		await create_timer(2).timeout
		var start := Time.get_ticks_msec()
		var frames := Engine.get_process_frames()
		var samples: Array[float] = []
		for frame in range(300):
			await physics_frame
			samples.append(float(Performance.get_monitor(Performance.TIME_PROCESS))*1000)
		samples.sort()
		results.append({"shadows":shadows,"render_fps":float(Engine.get_process_frames()-frames)*1000/(Time.get_ticks_msec()-start),"cpu_frame_p95_ms":samples[int(samples.size()*.95)]})
	Input.action_release("fire")
	print("PERFORMANCE: ",results)
	FileAccess.open("res://tests/campaign-performance-results.json",FileAccess.WRITE).store_string(JSON.stringify(results,"\t"))
	app._show_main()
	app.music.stop()
	await create_timer(.2).timeout
	quit()
