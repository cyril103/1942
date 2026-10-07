extends SceneTree
## Real-time, rendered replay. Run one GPU process at a time.
## The probe keeps the pilot alive for measurement; this is never a human playtest.
class ReplayPilot extends Node:
	var director: Node
	var ticks := 0
	var input_signature := 0
	var state_signature := 0
	func _physics_process(_delta: float) -> void:
		ticks += 1
		if is_instance_valid(director) and ticks % 60 == 0:
			# Sample actual gameplay state independently of render frame count.
			var state := "%d|%d|%d|%d|%d|%d" % [roundi(director.player.position.x*1000),roundi(director.player.position.z*1000),roundi(director.elapsed*60),director.event_index,director.combat.kills,director.combat.enemy_shots]
			state_signature = (state_signature*31+state.hash())%2147483647
		var flying: bool = is_instance_valid(director) and director.player.controls_enabled and not director.ending
		for action in ["move_left","move_right","move_up","move_down","fire"]: Input.action_release(action)
		if not flying: return
		director.player.invulnerable_time = 100.0
		# Predetermined input sequence at 60 physics ticks/s, using real movement.
		var horizontal := sin(float(ticks)*.011)
		var vertical := sin(float(ticks)*.003)*.25
		Input.action_press("move_right" if horizontal>=0 else "move_left",absf(horizontal))
		Input.action_press("move_down" if vertical>=0 else "move_up",absf(vertical))
		Input.action_press("fire")
		input_signature = (input_signature*31+ticks)%2147483647

var output_dir := OS.get_user_data_dir().path_join("performance-review")
var mission_number := 31
var quality := 1
var dimensions := Vector2i(1920,1080)
var repeats := 2
var duration_seconds := 140
var build_id := "unidentified"
var app: Control
var pilot: ReplayPilot
var reports: Array[Dictionary] = []
var failures: Array[String] = []
const FRAME_BUDGET := 1000.0/60.0

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output-dir="): output_dir = argument.trim_prefix("--output-dir=")
		if argument.begins_with("--mission="): mission_number = clampi(argument.trim_prefix("--mission=").to_int(),1,32)
		if argument.begins_with("--quality="): quality = clampi(argument.trim_prefix("--quality=").to_int(),0,2)
		if argument.begins_with("--repeats="): repeats = clampi(argument.trim_prefix("--repeats=").to_int(),1,20)
		if argument.begins_with("--duration="): duration_seconds = clampi(argument.trim_prefix("--duration=").to_int(),10,300)
		if argument.begins_with("--build-id="): build_id = argument.trim_prefix("--build-id=")
		if argument.begins_with("--size="):
			var parts := argument.trim_prefix("--size=").split("x")
			if parts.size()==2: dimensions = Vector2i(maxi(640,parts[0].to_int()),maxi(360,parts[1].to_int()))
	DirAccess.make_dir_recursive_absolute(output_dir)
	_run.call_deferred()

func summarize(values: Array[float]) -> Dictionary:
	if values.is_empty(): return {"samples":0}
	var ordered := values.duplicate()
	ordered.sort()
	var sum := 0.0
	var over_60 := 0
	var over_30 := 0
	for value in ordered:
		sum += value
		if value>FRAME_BUDGET: over_60 += 1
		if value>1000.0/30.0: over_30 += 1
	return {"samples":ordered.size(),"mean_ms":sum/ordered.size(),"p95_ms":ordered[mini(ordered.size()-1,int(ordered.size()*.95))],"p99_ms":ordered[mini(ordered.size()-1,int(ordered.size()*.99))],"max_ms":ordered.back(),"over_16_67ms":over_60,"over_33_33ms":over_30}

func memory_snapshot() -> Dictionary:
	return {"engine_static_bytes":int(Performance.get_monitor(Performance.MEMORY_STATIC)),"render_estimated_bytes":int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)),"nodes":int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),"resources":int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),"orphan_nodes":int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))}

func write_report(path: String, data: Dictionary) -> bool:
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file==null:
		failures.append("Cannot save benchmark evidence: "+path)
		return false
	file.store_string(JSON.stringify(data,"\t"))
	file.close()
	return true

func phase_of(d: Node, flight: Node) -> String:
	if flight.get_node("Departure").active: return "takeoff"
	if d.ending: return "landing"
	if is_instance_valid(d.assault):
		# Extraction begins only once cruise altitude is restored. The rear
		# coastline identifies the climb earlier, even when the quota was missed.
		var over_rear_half: bool = d.player.position.z<d.assault.position.z
		if d.assault.low_flight>.02 and d.assault.low_flight<.98:
			return "climb" if over_rear_half else "descent"
		if d.assault.low_flight>=.98: return "ground"
		if over_rear_half and d.assault.airspace_closed: return "climb"
		if d.extraction_started_at>=0: return "return_combat"
	return "approach"

func counters(d: Node) -> Dictionary:
	return {"event":d.event_index,"wave":d.combat.wave_count,"bomber":d.combat.bomber_count,"special":d.combat.special_count,"enemy_shots":d.combat.enemy_shots,"player_shots":d.weapons.shots_fired,"kills":d.combat.kills,"boss_phase":d.last_boss_phase,"boss_spawned":d.boss_spawned,"terrain_deployed":is_instance_valid(d.assault) and d.assault.deployed,"jammed":is_instance_valid(d.assault) and d.assault.jam_remaining>0}

func _run() -> void:
	Engine.physics_ticks_per_second = 60
	Engine.max_fps = 0
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(dimensions)
	root.size = dimensions
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var initial_memory := memory_snapshot()
	for pass_index in range(repeats):
		await _pass(pass_index)
		await process_frame
		if reports.size()>pass_index:
			reports[pass_index].after_probe_release_memory = memory_snapshot()
	if reports.size()!=repeats:
		failures.append("Incomplete benchmark: expected %d passes, received %d" % [repeats,reports.size()])
	for index in range(1,reports.size()):
		for field in ["physics_ticks","input_signature","state_signature","finished_tick"]:
			if reports[index][field]!=reports[0][field]:
				failures.append("Replay mismatch for %s in pass %d" % [field,index])
	var report := {"schema":1,"build_id":build_id,"engine":Engine.get_version_info(),"gpu":RenderingServer.get_video_adapter_name(),"os":OS.get_name(),"cpu":OS.get_processor_name(),"resolution":[dimensions.x,dimensions.y],"quality":quality,"mission":mission_number,"physics_hz":60,"duration_ticks":duration_seconds*60,"rng_seed":1942,"vsync":false,"other_gpu_processes":"operator_must_verify_none","cache_note":"First pass is a fresh process with existing driver/disk caches; no hardware cache was erased. Later passes reuse the same process.","player_invulnerable":true,"inputs":"Predetermined horizontal/vertical/fire actions on physics ticks; actual player movement and weapon collisions","gpu_timing_note":"Completed viewport GPU measurements can lag process callback timing. They are correlations, not proof of a stall cause.","memory_note":"Engine/static and estimated graphics allocations are not full process private bytes or physical VRAM occupancy; zero can mean unavailable.","initial_memory":initial_memory,"final_memory":memory_snapshot(),"passes":reports,"failures":failures}
	var filename := "full-mission-%02d-q%d-%dx%d.json" % [mission_number,quality,dimensions.x,dimensions.y]
	report.schema = 2
	report.audio_rng_seed = 1942
	report.input_isolation = "Hardware bindings are erased inside the fixture; the pilot uses the real Input actions and movement code."
	report.cpu_timing_note = "TIME_PROCESS is a process-callback monitor, not total CPU cost; it can be stale relative to the current frame."
	report.memory_note += " after_probe_release_memory is taken after raw frame arrays and detailed telemetry have been released; compact summaries remain resident."
	write_report(output_dir.path_join(filename),report)
	print("FULL MISSION BENCHMARK ",filename," passes=",reports.size()," failures=",failures)
	quit(0 if failures.is_empty() else 1)

func _pass(pass_index: int) -> void:
	seed(1942)
	var init_started := Time.get_ticks_usec()
	app = load("res://scenes/campaign.tscn").instantiate()
	app.testing = true
	app.profile.path = "user://benchmark-full-mission-fixture.json"
	root.add_child(app)
	current_scene = app
	await process_frame
	var init_ms := (Time.get_ticks_usec()-init_started)/1000.0
	app.profile.reset()
	app.profile.data.unlocked = 32
	app.profile.data.upgrades = [3,3,3]
	app.profile.data.settings.quality = quality
	app.profile.data.settings.fullscreen = false
	app.profile.data.settings.vsync = false
	var launch_started := Time.get_ticks_usec()
	app._launch(mission_number)
	var launch_ms := (Time.get_ticks_usec()-launch_started)/1000.0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var d: Node = app.director
	d.weapons.audio._rng.seed = 1942
	for action in InputMap.get_actions():
		Input.action_release(action)
		InputMap.action_erase_events(action)
	var flight: Node = app.cockpit.flight
	var viewport_size: Vector2i = app.cockpit.viewport.size
	var flight_rid: RID = app.cockpit.viewport.get_viewport_rid()
	var root_rid := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(flight_rid,true)
	RenderingServer.viewport_set_measure_render_time(root_rid,true)
	pilot = ReplayPilot.new()
	pilot.director = d
	pilot.process_mode = Node.PROCESS_MODE_ALWAYS
	pilot.process_physics_priority = -1000
	root.add_child(pilot)
	var buckets := {}
	var overall: Array[float] = []
	var gameplay: Array[float] = []
	var gpu_samples: Array[float] = []
	var cpu_samples: Array[float] = []
	var probe_samples: Array[float] = []
	var markers: Array[Dictionary] = [{"kind":"scene_build","init_ms":init_ms,"launch_ms":launch_ms,"tick":0}]
	var spikes: Array[Dictionary] = []
	var memory: Array[Dictionary] = []
	var previous_counts := {}
	var previous_phase := "takeoff"
	var peak_bullets := 0
	var peak_contacts := 0
	var first_occurrences := {}
	var result := {}
	var finished_tick := -1
	var next_memory_tick := 0
	var started := Time.get_ticks_usec()
	var last := started
	while pilot.ticks<duration_seconds*60:
		await process_frame
		var now := Time.get_ticks_usec()
		var frame_ms := (now-last)/1000.0
		last = now
		var probe_started := Time.get_ticks_usec()
		var playing: bool = app.page=="playing" and is_instance_valid(d)
		var phase := phase_of(d,flight) if playing else "result_idle"
		var mission_seconds: float = d.elapsed if playing else -1.0
		var changed: Array[String] = []
		if phase!=previous_phase:
			markers.append({"kind":"phase","phase":phase,"tick":pilot.ticks,"mission_s":mission_seconds})
			changed.append("phase:"+phase)
		if playing:
			var count := counters(d)
			for key in count:
				if previous_counts.get(key)!=count[key]:
					changed.append(key+":"+str(count[key]))
					if not first_occurrences.has(key) and bool(count[key]):
						first_occurrences[key] = pilot.ticks
						changed.append("first:"+key)
			if not changed.is_empty(): markers.append({"kind":"state","phase":phase,"tick":pilot.ticks,"mission_s":mission_seconds,"changes":changed.duplicate()})
			previous_counts = count
			peak_contacts = maxi(peak_contacts,d.combat.get_radar_contacts().size())
			var bullets := 0
			for life in d.combat.lifetimes: if life>0: bullets+=1
			peak_bullets = maxi(peak_bullets,bullets)
			gpu_samples.append(RenderingServer.viewport_get_measured_render_time_gpu(flight_rid)+RenderingServer.viewport_get_measured_render_time_gpu(root_rid))
			cpu_samples.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000.0)
			gameplay.append(frame_ms)
		elif finished_tick<0:
			finished_tick = pilot.ticks
			result = app.result.duplicate(true)
		if not buckets.has(phase): buckets[phase] = []
		buckets[phase].append(frame_ms)
		overall.append(frame_ms)
		if frame_ms>FRAME_BUDGET:
			spikes.append({"frame_ms":frame_ms,"interval_started_in_phase":previous_phase,"observed_phase":phase,"tick":pilot.ticks,"mission_s":mission_seconds,"associated_markers":changed.duplicate(),"cause":"unknown; markers indicate correlation only"})
		previous_phase = phase
		if pilot.ticks>=next_memory_tick:
			var snapshot := memory_snapshot()
			snapshot.tick = pilot.ticks
			snapshot.phase = phase
			memory.append(snapshot)
			next_memory_tick = pilot.ticks+300
		probe_samples.append((Time.get_ticks_usec()-probe_started)/1000.0)
		if (now-started)/1000000.0>float(duration_seconds)*2.5:
			failures.append("Pass %d exceeded its wall-clock limit" % pass_index)
			break
	var phases := {}
	for phase in buckets:
		var values: Array[float] = []
		values.assign(buckets[phase])
		phases[phase] = summarize(values)
	if finished_tick<0: failures.append("Mission did not reach its result during pass %d" % pass_index)
	if mission_number in [3,7,11,15,19,23,27,31]:
		for phase in ["takeoff","approach","descent","ground","climb","return_combat","landing"]:
			if not phases.has(phase): failures.append("Missing phase %s in pass %d" % [phase,pass_index])
	var pass_report := {"pass":pass_index,"cache":"first_scene_in_fresh_process" if pass_index==0 else "warm_same_process","init_ms":init_ms,"launch_ms":launch_ms,"viewport":[viewport_size.x,viewport_size.y],"wall_seconds":(Time.get_ticks_usec()-started)/1000000.0,"physics_ticks":pilot.ticks,"finished_tick":finished_tick,"input_signature":pilot.input_signature,"state_signature":pilot.state_signature,"overall":summarize(overall),"gameplay":summarize(gameplay),"gpu_ms":summarize(gpu_samples),"cpu_process_ms":summarize(cpu_samples),"instrumentation_ms":summarize(probe_samples),"phases":phases,"markers":markers,"spikes":spikes,"memory_samples":memory,"peak_bullets":peak_bullets,"peak_contacts":peak_contacts,"result":result}
	for action in ["move_left","move_right","move_up","move_down","fire"]: Input.action_release(action)
	pilot.queue_free()
	app._dispose_run()
	app.music.stop()
	app.queue_free()
	await create_timer(.25).timeout
	pass_report.after_dispose_memory = memory_snapshot()
	# Write detailed markers immediately, then retain only compact summaries.
	# Otherwise a long session measures the probe's telemetry accumulation.
	var detail_name := "details-m%02d-q%d-%dx%d-pass%02d.json" % [mission_number,quality,dimensions.x,dimensions.y,pass_index]
	write_report(output_dir.path_join(detail_name),pass_report)
	var compact := pass_report.duplicate(false)
	for field in ["markers","spikes","memory_samples"]: compact.erase(field)
	compact.details_file = detail_name
	reports.append(compact)
	print("BENCHMARK PASS ",pass_index," gameplay=",JSON.stringify(pass_report.gameplay)," ticks=",pass_report.physics_ticks," result_tick=",finished_tick)
