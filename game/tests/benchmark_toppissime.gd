extends SceneTree
func _initialize() -> void: _run.call_deferred()
func summary(values: Array[float]) -> Dictionary:
	values.sort()
	var total := 0.0
	for value in values: total+=value
	return {"mean":total/values.size(),"p50":values[values.size()/2],"p95":values[int(values.size()*.95)],"p99":values[int(values.size()*.99)],"max":values.back()}
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
	app._launch(29)
	var d = app.director
	app.cockpit.flight.get_node("Departure").finish_immediately()
	d.event_index = d.mission.events.size()
	d.mission.duration = 10000
	d._spawn_boss("fortress")
	d.boss.health = 1000000
	d.boss.max_health = 2000000
	d._spawn_naval(1)
	Input.action_press("fire")
	d.weapons.set_power("spread")
	var rid: RID = app.cockpit.viewport.get_viewport_rid()
	var root_rid := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid,true)
	RenderingServer.viewport_set_measure_render_time(root_rid,true)
	var reports := []
	for quality in [1,0,2]:
		app.profile.data.settings.quality = quality
		app._apply_graphics()
		var start := Time.get_ticks_msec()
		var last := Time.get_ticks_usec()
		var next_spawn := 0
		var next_blast := 0
		var frames: Array[float] = []
		var gpu: Array[float] = []
		var cpu: Array[float] = []
		var peak_contacts := 0
		var peak_bullets := 0
		while Time.get_ticks_msec()-start<16000:
			await process_frame
			var now := Time.get_ticks_usec()
			var ms := Time.get_ticks_msec()-start
			d.player.invulnerable_time = 100
			d.player.position.x = sin(float(ms)/1300.0)*11
			if ms>=next_spawn:
				d.combat.spawn_wave()
				next_spawn = ms+900
			if ms>=next_blast:
				d.combat._explode(Vector3(sin(float(ms))*12,0,cos(float(ms))*7),1.3,false)
				next_blast = ms+220
			if ms>3000:
				frames.append((now-last)/1000.0)
				gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(rid)+RenderingServer.viewport_get_measured_render_time_gpu(root_rid))
				cpu.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000)
			last = now
			peak_contacts = maxi(peak_contacts,d.combat.get_radar_contacts().size())
			var bullets := 0
			for life in d.combat.lifetimes: if life>0: bullets+=1
			peak_bullets = maxi(peak_bullets,bullets)
		reports.append({"quality":quality,"frame_ms":summary(frames),"gpu_ms":summary(gpu),"cpu_ms":summary(cpu),"peak_contacts":peak_contacts,"peak_bullets":peak_bullets,"samples":frames.size()})
		print("LIVE BENCHMARK: ",reports.back())
	Input.action_release("fire")
	FileAccess.open("res://tests/toppissime-performance.json",FileAccess.WRITE).store_string(JSON.stringify({"gpu":RenderingServer.get_video_adapter_name(),"resolution":root.size,"runs":reports},"\t"))
	app._show_main()
	app.music.stop()
	await process_frame
	quit()
