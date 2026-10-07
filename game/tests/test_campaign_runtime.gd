extends SceneTree
## GPU/packaged integration test: real physics, real swept projectiles, real audio.
var failures: Array[String] = []
var checks := 0
var frame_times: Array[float] = []
const OUTPUT := "C:/ChatGPT/1942/game/tests/"
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var app = load("res://scenes/campaign.tscn").instantiate()
	app.testing = true
	app.profile.path = "user://campaign-runtime-test.json"
	root.add_child(app)
	current_scene = app
	await process_frame
	check(app.missions.size()==32,"Pack includes mission JSON")
	app._show_credits()
	app.profile.reset()
	app.profile.path = "user://campaign-runtime-test.json"
	check(app.profile.save()==OK,"Standalone can save to its user directory")
	app.profile.data.pow_ready = true
	app.profile.data.power = "spread"
	app.profile.save()
	var profile = load("res://scripts/campaign/profile.gd").new()
	profile.path = app.profile.path
	check(profile.load_profile() and profile.data.pow_ready,"POW state persists")
	app._launch(1)
	var d = app.director
	var p = app.cockpit.player
	var w = d.weapons
	p.invulnerable_time = 30
	check(w.spread_enabled,"Campaign restores POW at mission checkpoint")
	w.set_power("none")
	var recording := AudioEffectRecord.new()
	recording.format = AudioStreamWAV.FORMAT_16_BITS
	AudioServer.add_bus_effect(0,recording)
	recording.set_recording_active(true)
	# Real takeoff runs to completion with the original engine sound and new music.
	for frame in range(780): await physics_frame
	check(not app.cockpit.flight.get_node("Departure").active and p.controls_enabled,"Takeoff completes in the full campaign")
	p.invulnerable_time = 30
	Input.action_press("fire")
	for frame in range(360):
		await physics_frame
		p.position.x = sin(frame/90.0)*3.0
		frame_times.append(get_process_delta_time_safe())
	check(w.shots_fired > 40,"Continuous fire runs in the exported game")
	# Isolate a ship, then exercise the real ray sweep rather than direct damage.
	d.event_index = d.mission.events.size()
	d._clear_actors()
	d._spawn_naval(0)
	var ship = d.navals[0]
	ship.position = Vector3(0,0,-3)
	p.position.x = 0
	for frame in range(240):
		await physics_frame
		# The ship follows the real ocean channel and no longer stays at x=0.
		# Track its actual lane, as this test already does for the boss below.
		if is_instance_valid(ship) and ship.alive: p.position.x = ship.position.x
	check(not is_instance_valid(ship) or not ship.alive,"Player bullets destroy a naval collider")
	d._clear_actors()
	d._spawn_boss("bomber")
	d.boss.age = 4
	var hp: int = d.boss.health
	for frame in range(300):
		await physics_frame
		p.position.x = d.boss.position.x
	check(d.boss.health < hp-20,"Real projectiles damage the boss")
	Input.action_release("fire")
	d.combat.clear_enemy_bullets()
	d.boss.cooldown = 100
	d.boss.telegraph = 0
	p.invulnerable_time = 0
	var hull: int = p.health
	d.combat._launch_enemy_round(p.global_position+Vector3(0,0,-1),p.global_position,10)
	for frame in range(20): await physics_frame
	check(p.health==hull-1,"Enemy projectile removes one hull point")
	recording.set_recording_active(false)
	var audio := recording.get_recording()
	if "--packaged" not in OS.get_cmdline_user_args():
		audio.save_to_wav("C:/ChatGPT/1942/audio/campaign-mix-validation.wav")
	var peak := 0
	var bytes := audio.data
	for offset in range(0,bytes.size(),2): peak=maxi(peak,absi(bytes.decode_s16(offset)))
	check(peak>1000 and peak<32700,"Music/engine/weapons mix has headroom")
	AudioServer.remove_bus_effect(0,AudioServer.get_bus_effect_count(0)-1)
	app._show_pause()
	await RenderingServer.frame_post_draw
	if "--packaged" not in OS.get_cmdline_user_args():
		root.get_texture().get_image().save_png("C:/ChatGPT/1942/renders/campaign-runtime.png")
	app._show_main()
	app.music.stop()
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(profile.path+suffix): DirAccess.remove_absolute(profile.path+suffix)
	frame_times.sort()
	var report := {"checks":checks,"failures":failures,"audio_peak":peak,"sampled_frame_p95_ms":frame_times[int(frame_times.size()*.95)]*1000}
	if "--packaged" not in OS.get_cmdline_user_args():
		FileAccess.open(OUTPUT+"campaign-runtime-results.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("CAMPAIGN RUNTIME: ",report)
	await create_timer(.3).timeout
	quit(0 if failures.is_empty() else 1)
func get_process_delta_time_safe() -> float:
	return float(Performance.get_monitor(Performance.TIME_PROCESS))
