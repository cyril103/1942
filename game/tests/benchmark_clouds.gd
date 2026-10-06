extends SceneTree
func _initialize() -> void: _run.call_deferred()
func summarize(samples: Array[float]) -> Dictionary:
	samples.sort()
	var total := 0.0
	for v in samples: total += v
	return {"mean":total/samples.size(),"p50":samples[samples.size()/2],"p95":samples[int(samples.size()*.95)]}
func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	root.size = Vector2i(1920,1080)
	var app = load("res://scenes/campaign.tscn").instantiate()
	app.testing = true
	root.add_child(app)
	current_scene = app
	await process_frame
	app.profile.reset()
	app.profile.data.unlocked = 32
	app._launch(31)
	var d = app.director
	var flight = app.cockpit.flight
	var field = flight.get_node("Clouds")
	flight.get_node("Departure").finish_immediately()
	for node_name in ["Seascape","Clouds","Combat","Player","Weapons"]:
		flight.get_node(node_name).set_physics_process(false)
	d.set_physics_process(false)
	d.player.set_process(false)
	d.feedback_time = 0
	for wave in range(4): d.combat.spawn_wave()
	for i in range(d.combat.enemies.size()):
		d.combat.enemies[i].position = Vector3(-18+(i%8)*5.0,0,-9+(i/8)*4.0)
	d._spawn_naval(1)
	d._spawn_boss("fortress")
	d.boss.position.z = -7
	for i in range(96):
		var origin := Vector3(-19+(i%16)*2.5,0,-8+(i/16)*3.0)
		d.combat._launch_enemy_round(origin,d.player.position,14)
	for i in range(8): d.combat._explode(Vector3(-15+(i%4)*10,0,-3+(i/4)*8),1.0,false)
	d.combat._update_effects(.42)
	for i in range(24):
		var shot = d.weapons.projectiles[i]
		shot.position = Vector3(-.5+(i%2),0,9-(i/2)*1.5)
		shot.show()
	for i in range(field.POOL_SIZE):
		field.clouds[i].position = Vector3([-12.0,9.0,-4.0,15.0,-14.0,12.0,0.0,0.0][i],field.ALTITUDE-i*.035,[-7.0,-2.0,7.0,11.0,2.0,-8.0,-70.0,-90.0][i])
		field._sync_shadow(i)
	for i in range(field.POOL_SIZE): field._update_opacity(i)
	var rid: RID = app.cockpit.viewport.get_viewport_rid()
	var root_rid := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid,true)
	RenderingServer.viewport_set_measure_render_time(root_rid,true)
	for frame in range(180): await process_frame
	var results := []
	# ABBA order reduces temperature/clock drift; geometry and effect ages frozen.
	for enabled in [false,true,true,false]:
		field.visible = enabled
		for frame in range(45): await process_frame
		var gpu: Array[float] = []
		var wall: Array[float] = []
		var last := Time.get_ticks_usec()
		for frame in range(240):
			await process_frame
			var now := Time.get_ticks_usec()
			wall.append((now-last)/1000.0)
			last = now
			gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(rid)+RenderingServer.viewport_get_measured_render_time_gpu(root_rid))
		results.append({"clouds":enabled,"gpu_ms":summarize(gpu),"frame_ms":summarize(wall),"draw_calls":RenderingServer.viewport_get_render_info(rid,RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)})
	field.visible = true
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("C:/ChatGPT/1942/renders/clouds-stress.png")
	var update_start := Time.get_ticks_usec()
	for step in range(600):
		field._on_scrolled(2.5/60)
		field._physics_process(1.0/60)
	var update_ms := float(Time.get_ticks_usec()-update_start)/600000.0
	var report := {"gpu":RenderingServer.get_video_adapter_name(),"resolution":root.size,"flight_resolution":app.cockpit.viewport.size,"vsync":"off","fighters":d.combat.enemies.size(),"enemy_bullets":96,"explosions":8,"cloud_update_cpu_ms":update_ms,"runs":results}
	FileAccess.open("C:/ChatGPT/1942/game/tests/cloud-performance-results.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("CLOUD PERFORMANCE: ",report)
	app._show_main()
	app.music.stop()
	await process_frame
	quit()
