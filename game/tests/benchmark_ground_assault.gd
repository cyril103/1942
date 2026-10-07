extends SceneTree
## Real rendered frames, fixed 1080p view, VSync off. Each setting reloads the
## same DCA-only raid and uses the same movement; first 3 seconds warm up.
func _initialize() -> void: _run.call_deferred()
func summary(values: Array[float]) -> Dictionary:
	values.sort()
	var sum := 0.0
	for value in values: sum+=value
	return {"mean":sum/values.size(),"p50":values[values.size()/2],"p95":values[int(values.size()*.95)],"p99":values[int(values.size()*.99)],"max":values.back()}
func _run() -> void:
	root.size = Vector2i(1920,1080)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var app = load("res://scenes/campaign.tscn").instantiate()
	app.testing = true
	root.add_child(app)
	current_scene = app
	await process_frame
	app.profile.reset()
	app.profile.data.unlocked = 32
	var reports := []
	for quality in [1,0,2]:
		var load_start := Time.get_ticks_usec()
		app._launch(31)
		var build_ms := (Time.get_ticks_usec()-load_start)/1000.0
		var d = app.director
		var raid = d.assault
		app.cockpit.flight.get_node("Departure").finish_immediately()
		d.elapsed = 35
		d.event_index = d.mission.events.size()
		d.mission.duration = 10000
		raid.advance(0)
		raid.position.z = -28
		for target in raid.targets:
			target.health = 10000
			target.max_health = 10000
		app.profile.data.settings.quality = quality
		app._apply_graphics()
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Input.action_press("fire")
		d.weapons.set_power("spread")
		var rid: RID = app.cockpit.viewport.get_viewport_rid()
		var root_rid := root.get_viewport_rid()
		RenderingServer.viewport_set_measure_render_time(rid,true)
		RenderingServer.viewport_set_measure_render_time(root_rid,true)
		var start := Time.get_ticks_msec()
		var last := Time.get_ticks_usec()
		var next_blast := 0
		var frame_times: Array[float] = []
		var gpu_times: Array[float] = []
		var peak_contacts := 0
		var peak_bullets := 0
		while Time.get_ticks_msec()-start<16000:
			await process_frame
			var now := Time.get_ticks_usec()
			var ms := Time.get_ticks_msec()-start
			d.player.invulnerable_time = 100
			d.player.position.x = sin(float(ms)/1300.0)*11
			if ms>=next_blast:
				d.combat._explode(Vector3(sin(float(ms)) * 12,-.25,cos(float(ms)) * 7),1.15,false)
				next_blast = ms+220
			if ms>3000:
				frame_times.append((now-last)/1000.0)
				gpu_times.append(RenderingServer.viewport_get_measured_render_time_gpu(rid)+RenderingServer.viewport_get_measured_render_time_gpu(root_rid))
			last = now
			peak_contacts = maxi(peak_contacts,d.combat.get_radar_contacts().size())
			var bullets := 0
			for life in d.combat.lifetimes: if life>0: bullets+=1
			peak_bullets = maxi(peak_bullets,bullets)
		reports.append({"quality":quality,"build_ms":build_ms,"frame_ms":summary(frame_times),"gpu_ms":summary(gpu_times),"peak_contacts":peak_contacts,"peak_bullets":peak_bullets,"triangles":raid.terrain.triangle_count,"prop_instances":raid.terrain.prop_count,"samples":frame_times.size()})
		print("GROUND BENCHMARK: ",reports.back())
		Input.action_release("fire")
		app._dispose_run()
		await process_frame
	FileAccess.open("res://tests/ground-performance.json",FileAccess.WRITE).store_string(JSON.stringify({"gpu":RenderingServer.get_video_adapter_name(),"resolution":root.size,"warmup_seconds":3,"measured_seconds":13,"runs":reports},"\t"))
	app._show_main()
	app.music.stop()
	await create_timer(.25).timeout
	quit()
