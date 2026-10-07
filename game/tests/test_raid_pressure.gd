extends SceneTree
## Authentic base guns against authentic target HP: no scripted damage or kills.
## A 60 Hz manual simulation waits for physics before each weapon sweep. The
## physics server runs at 240 Hz only to shorten wall time; gameplay always uses DT.
const DT := 1.0/60.0
const MEASURE_SECONDS := 25.0
var app: Node
var failures: Array[String] = []
var checks := 0
var missions: Array[Dictionary] = []

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func _freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children(): _freeze(child)

func _stop_audio(node: Node) -> void:
	if node is AudioStreamPlayer or node is AudioStreamPlayer3D: node.stop()
	for child in node.get_children(): _stop_audio(child)

func _mission(number: int) -> void:
	seed(194200+number)
	app._launch(number)
	var d: Node = app.director
	var a: Node = d.assault
	var c: Node = d.combat
	var w: Node = d.weapons
	var p: Node3D = d.player
	var sea: Node = app.cockpit.flight.get_node("Seascape")
	for connection in d.finished.get_connections(): d.finished.disconnect(connection.callable)
	app.cockpit.flight.get_node("Departure").finish_immediately()
	_freeze(app.cockpit)
	app.music.stop()
	check(w.power_type=="none" and w.projectile_damage==1 and is_equal_approx(w.shot_interval,.105),"Mission %d starts with authentic unupgraded Vanguard guns" % number)
	var authentic_health := true
	for target in a.targets:
		var expected: int = int(target.HEALTH[target.variant])+mini(4,int(d.mission.sector)/2)
		authentic_health = authentic_health and target.health==expected and target.max_health==expected
	check(authentic_health,"Mission %d preserves the authored health of every installation" % number)
	var low_seconds := 0.0
	var first_low_time := -1.0
	var first_dca_time := -1.0
	var emitted := 0
	var peak_bullets := 0
	var kills_at_start := 0
	var hits_at_start := 0
	var gunshots_at_start := 0
	var firing_installations := {}
	var damaged_firing_installations := {}
	var aircraft_during_low := false
	var ignored_powers := 0
	var aim_target: Node3D
	var target_hold := 0.0
	Input.action_press("fire")
	for frame in range(100*60):
		p.invulnerable_time = 1000.0
		var half_width: float = absf(c.camera.project_position(Vector2.ZERO,1.0).x)
		if not is_instance_valid(aim_target) or not aim_target.alive or aim_target.global_position.z>4.5 or target_hold>=2.0:
			var previous_id := aim_target.get_instance_id() if is_instance_valid(aim_target) else 0
			aim_target = null
			target_hold = 0.0
			var best_cost := INF
			for target in a.targets:
				if not is_instance_valid(target) or not target.alive or target.variant not in ["battery","bunker"]: continue
				if target.get_instance_id()==previous_id: continue
				var at: Vector3 = target.global_position
				if at.z<c.screen_top()+.25 or at.z>4.5 or absf(at.x)>half_width-2.0: continue
				var cost := absf(at.x-p.position.x)-at.z*.25
				if cost<best_cost:
					best_cost = cost
					aim_target = target
		var desired_x := sin(float(frame)*DT*.45)*minf(15.0,half_width-2.0)
		if is_instance_valid(aim_target):
			desired_x = aim_target.global_position.x
			# Count the two-second attack only after lining up; travelling toward
			# a gun is not an aimed burst. Never teleport or exceed player speed.
			if absf(desired_x-p.position.x)<.4: target_hold += DT
		p.position = Vector3(move_toward(p.position.x,desired_x,p.speed*DT),0,6.5)
		sea._physics_process(DT)
		c._physics_process(DT)
		# Collected POWs must not change this fixed base-weapon scenario.
		if w.power_type!="none":
			ignored_powers += 1
			w.set_power("none")
		var shots_before: int = c.enemy_shots
		d.advance(DT)
		var measuring: bool = a.low_flight>.95
		if measuring:
			if first_low_time<0:
				first_low_time = d.elapsed
				kills_at_start = a.kills
				hits_at_start = w.hits_landed
				gunshots_at_start = w.shots_fired
			low_seconds += DT
			emitted += int(c.enemy_shots)-shots_before
			if c.enemy_shots>shots_before and first_dca_time<0: first_dca_time=d.elapsed
			peak_bullets = maxi(peak_bullets,c.BULLET_CAPACITY-c.lifetimes.count(0.0))
			aircraft_during_low = aircraft_during_low or not c.enemies.is_empty() or not c.bombers.is_empty() or not c.red_enemies.is_empty()
			for target in a.targets:
				if is_instance_valid(target) and target.alive and target.muzzle_time>.099:
					firing_installations[target.get_instance_id()] = true
					if target.health<target.max_health: damaged_firing_installations[target.get_instance_id()] = true
		# Synchronize the real moving colliders before each machine-gun ray sweep.
		await physics_frame
		w._physics_process(DT)
		for target in a.targets:
			if is_instance_valid(target) and not target.alive and not target.is_queued_for_deletion():
				target.set_process(false)
				target._process(DT)
		if low_seconds>=MEASURE_SECONDS: break
	Input.action_release("fire")
	var ground_kills: int = a.kills-kills_at_start
	var landed: int = w.hits_landed-hits_at_start
	check(low_seconds>=MEASURE_SECONDS,"Mission %d measures at least 25 seconds of genuine low flight" % number)
	check(emitted>=40,"Mission %d DCA emits at least 40 rounds under continuous player fire (actual %d)" % [number,emitted])
	check(firing_installations.size()>=4,"Mission %d has at least four different guns survive long enough to fire (actual %d)" % [number,firing_installations.size()])
	check(landed>20 and ground_kills>0,"Mission %d real player rounds hit and destroy authentic ground targets (%d hits, %d kills)" % [number,landed,ground_kills])
	check(not aircraft_during_low,"Mission %d keeps all aircraft out of the measured ground fight" % number)
	check(peak_bullets<=c.BULLET_CAPACITY,"Mission %d stays within the fixed enemy projectile budget" % number)
	missions.append({"mission":number,"measured_low_seconds":low_seconds,"first_low_mission_second":first_low_time,"first_dca_mission_second":first_dca_time,"enemy_rounds":emitted,"peak_enemy_bullets":peak_bullets,"different_firing_installations":firing_installations.size(),"damaged_installations_that_fired":damaged_firing_installations.size(),"ground_kills":ground_kills,"player_hits":landed,"player_rounds":int(w.shots_fired)-gunshots_at_start,"ignored_collected_powers":ignored_powers,"authored_target_count":int(d.mission.ground_count),"aircraft_during_low":aircraft_during_low})
	print("RAID PRESSURE ",JSON.stringify(missions.back()))
	_stop_audio(app.cockpit)
	app._dispose_run()
	await process_frame

func _run() -> void:
	root.size = Vector2i(1920,1080)
	Engine.physics_ticks_per_second = 240
	Engine.max_fps = 0
	app = load("res://scenes/campaign.tscn").instantiate()
	app.testing = true
	app.profile.path = "user://raid-pressure-test-fixture.json"
	root.add_child(app)
	current_scene = app
	await process_frame
	app.set_process(false)
	app.profile.reset()
	app.profile.data.unlocked = 32
	app.profile.data.settings.vsync = false
	for number in [3,31]: await _mission(number)
	app.music.stop()
	_stop_audio(app)
	await create_timer(.25).timeout
	var fixture_path: String = app.profile.path
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(fixture_path+suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture_path+suffix))
	app.queue_free()
	current_scene = null
	await process_frame
	await process_frame
	await create_timer(.1).timeout
	if "--packaged" not in OS.get_cmdline_user_args():
		FileAccess.open("res://tests/raid-pressure-results.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"missions":missions},"\t"))
	print("RAID PRESSURE TEST ",checks," checks, ",failures.size()," failures: ",failures)
	quit(0 if failures.is_empty() else 1)
