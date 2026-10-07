extends SceneTree
## Campaign integration: real physics weapons, ground tactics, respawn continuity,
## and complete eight coastal raids including carrier recovery and quota failure.
const DT := 1.0/60.0
const RAIDS := [3,7,11,15,19,23,27,31]
var failures: Array[String] = []
var checks := 0
var mission_results: Array[Dictionary] = []
var stage_report: Dictionary = {}
var app: Node

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func _initialize() -> void: _run.call_deferred()

func _freeze(node: Node) -> void:
	node.set_physics_process(false)
	node.set_process(false)
	for child in node.get_children(): _freeze(child)

func _stop_audio(node: Node) -> void:
	if node is AudioStreamPlayer or node is AudioStreamPlayer3D: node.stop()
	for child in node.get_children(): _stop_audio(child)

func _launch(number: int) -> Node:
	stage_report = {}
	app._launch(number)
	var director: Node = app.director
	for connection in director.finished.get_connections(): director.finished.disconnect(connection.callable)
	director.finished.connect(func(report): stage_report=report)
	app.cockpit.flight.get_node("Departure").finish_immediately()
	_freeze(app.cockpit.flight)
	director.player.get_node("Hurtbox").collision_layer = 0
	return director

func _step(director: Node, delta := DT) -> void:
	director.cockpit.flight.get_node("Seascape")._physics_process(delta)
	director.combat._physics_process(delta)
	director.advance(delta)
	# Runtime wreck processing remains real-time; the accelerated simulation owns
	# it explicitly so dead targets are not retained for minutes of simulated time.
	for target in director.assault.targets:
		if is_instance_valid(target) and not target.alive and not target.is_queued_for_deletion():
			target.set_process(false)
			target._process(delta)
	director.player.set_physics_process(false)

func _validate_layout(director: Node) -> void:
	var assault: Node = director.assault
	var kinds := {}
	var radars := 0
	var defenses := 0
	check(assault.targets.size()==int(director.mission.ground_count),"Mission %d builds its full target budget" % director.mission.id)
	check(assault.terrain.triangle_count<=assault.terrain.MAX_TRIANGLES and assault.terrain.prop_count<=assault.terrain.MAX_PROP_INSTANCES,"Mission %d respects terrain geometry and scenery bounds" % director.mission.id)
	for target in assault.targets:
		kinds[target.variant] = true
		if target.variant=="radar": radars += 1
		if target.variant in ["battery","bunker"]: defenses += 1
		var footprint: Vector2 = target.FOOTPRINT[target.variant]
		# Inspect the entire foundation, not just the centre of the building.
		for x in [-.5,0.0,.5]:
			for z in [-.5,0.0,.5]:
				var at := Vector2(target.position.x+x*footprint.x,target.position.z+z*footprint.y)
				check(absf(assault.terrain.surface_height(at)-assault.terrain.PLATEAU_Y)<.005,"Mission %d %s foundation rests on plateau" % [director.mission.id,target.variant])
		var base_y: float = target.visual.position.y+target.hull.mesh.get_aabb().position.y*target.visual.scale.y
		check(absf(base_y-assault.terrain.PLATEAU_Y)<.001,"Mission %d %s mesh meets the terrain" % [director.mission.id,target.variant])
		check(target.collision_layer==0,"Undeployed installation cannot absorb offscreen shots")
	check(kinds.size()==5,"Mission %d features all five ground silhouettes" % director.mission.id)
	check(radars==2,"Mission %d has two radar objectives" % director.mission.id)
	check(assault.targets.size()>=30 and assault.targets.size()<=45,"Mission %d builds the denser ground battlefield within its fixed budget" % director.mission.id)
	check(defenses>=int(ceil(assault.targets.size()*.8)),"Mission %d reserves at least four installations in five for active DCA" % director.mission.id)
	check(director.combat.aircraft_enabled,"Mission %d permits aircraft during its ocean approach" % director.mission.id)
	var overlaps: Array[String] = []
	for first_index in range(assault.targets.size()):
		var first: Area3D = assault.targets[first_index]
		var first_size: Vector2 = first.FOOTPRINT[first.variant]
		var first_rect := Rect2(Vector2(first.position.x,first.position.z)-first_size*.5,first_size)
		for second_index in range(first_index+1,assault.targets.size()):
			var second: Area3D = assault.targets[second_index]
			var second_size: Vector2 = second.FOOTPRINT[second.variant]
			var second_rect := Rect2(Vector2(second.position.x,second.position.z)-second_size*.5,second_size)
			if first_rect.intersects(second_rect): overlaps.append("%d:%s/%d:%s" % [first_index,first.variant,second_index,second.variant])
	check(overlaps.is_empty(),"Mission %d foundations stay separate at viewport %s: %s" % [director.mission.id,director.cockpit.viewport.size,overlaps])

func _compact_layouts() -> void:
	for window_size in [Vector2i(1280,720),Vector2i(960,1080)]:
		root.size = window_size
		await process_frame
		var d := _launch(3)
		_validate_layout(d)
		app._dispose_run()
		await process_frame
	root.size = Vector2i(1920,1080)
	await process_frame

func _extraction_schedule() -> void:
	var d := _launch(3)
	var a: Node = d.assault
	var combat: Node = d.combat
	# Reach the real ground phase before simulating a late coast exit. Existing
	# air patrols must have been retired, not merely absent from a synthetic scene.
	for frame in range(30*60):
		_step(d)
		if a.low_flight>.95: break
	check(not combat.aircraft_enabled and d.extraction_wave_count==0,"Low flight cannot start the return-wave scheduler")
	d.elapsed = float(d.mission.duration)-2.0
	a.position.z = a.length*.5+combat.screen_bottom()+40
	for frame in range(5*60):
		_step(d)
		if d.extraction_started_at>=0: break
	check(not d.ending and a.extraction_ready() and d.extraction_wave_count==1 and not combat.enemies.is_empty(),"A late ocean exit immediately resumes combat instead of landing during ascent")
	check(d.extraction_end_at>=d.extraction_started_at+12.0 and d.extraction_end_at>float(d.mission.duration),"A late exit reserves at least twelve seconds of return combat")
	var waves_before: int = d.extraction_wave_count
	var elapsed_before: float = d.elapsed
	var next_before: float = d.extraction_next_wave
	d.paused = true
	d.advance(20.0)
	check(d.extraction_wave_count==waves_before and is_equal_approx(d.elapsed,elapsed_before) and is_equal_approx(d.extraction_next_wave,next_before),"Pause freezes the extraction schedule and does not accumulate waves")
	d.paused = false
	d.advance(DT)
	check(d.extraction_wave_count==waves_before,"Resuming a paused extraction does not release catch-up waves")
	d.player.invulnerable_time = 0
	d.player.take_damage(d.player.health)
	elapsed_before = d.elapsed
	for frame in range(60): _step(d)
	check(not d.player.alive and d.extraction_wave_count==waves_before and is_equal_approx(d.elapsed,elapsed_before),"A dead pilot pauses return waves and the combat clock")
	for frame in range(35): _step(d)
	check(d.player.alive and d.extraction_wave_count==waves_before,"Respawn resumes the existing extraction without a burst of accumulated waves")
	var wave_during_quiet_window := false
	var wave_during_landing := false
	for frame in range(25*60):
		waves_before = d.extraction_wave_count
		var was_landing: bool = d.ending
		_step(d)
		if d.extraction_wave_count>waves_before:
			wave_during_quiet_window = wave_during_quiet_window or d.elapsed>=d.extraction_end_at-5.0
			wave_during_landing = wave_during_landing or was_landing or d.ending
		if not stage_report.is_empty(): break
	check(d.extraction_wave_count>=2,"The return battle includes successive waves after respawn")
	check(not wave_during_quiet_window and not wave_during_landing,"Return waves stop five seconds before recovery and stay stopped during landing")
	check(not stage_report.is_empty() and d.cockpit.flight.get_node("Departure").landed,"The extended sortie still returns to its carrier and produces a report")
	app._dispose_run()
	await process_frame

func _validate_ground_exclusivity(director: Node) -> void:
	var combat: Node = director.combat
	# Guard the public spawning paths as well as authored events. Otherwise an
	# emergency reinforcement or later schedule edit could reintroduce aircraft.
	combat.spawn_wave()
	combat.spawn_bomber()
	combat.spawn_special()
	director.spawn_reinforcement()
	for kind in ["zero","hayabusa","red","bomber"]:
		director._dispatch({"kind":kind,"pattern":0})
	check(not combat.aircraft_enabled and combat.enemies.is_empty() and combat.bombers.is_empty() and combat.red_enemies.is_empty(),"Low flight rejects direct, reinforcement and dispatched aircraft spawns")

func _approach_transition() -> void:
	var d := _launch(3)
	var a: Node = d.assault
	var combat: Node = d.combat
	var sea: Node = d.cockpit.flight.get_node("Seascape")
	# Keep the authored aircraft alive while the real terrain, clock and camera
	# approach the coast. Full missions below also exercise normal aircraft motion.
	for frame in range(9*60+2):
		sea._physics_process(DT)
		d.advance(DT)
	check(combat.aircraft_enabled and not combat.enemies.is_empty() and a.low_flight==0,"Ocean approach launches real patrols before descent")
	combat.spawn_bomber()
	combat.spawn_special()
	check(not combat.bombers.is_empty() and not combat.red_enemies.is_empty(),"All aircraft families can exist during the ocean approach")
	# This projectile is deliberately kept alive through the transition; it must
	# be cleared by the altitude handoff rather than by its normal lifetime.
	combat._launch_enemy_round(Vector3(8,0,-6),Vector3(8,0,6),2)
	check(combat.lifetimes.count(0.0)<combat.BULLET_CAPACITY,"An airborne projectile is present before the descent handoff")
	var score_before: int = combat.score
	var kills_before: int = combat.kills
	var pow_before: int = combat.pow_spawn_count
	var explosions_before: int = combat._effect_cursor
	var retired_actors: Array = []
	retired_actors.append_array(combat.enemies)
	retired_actors.append_array(combat.bombers)
	retired_actors.append_array(combat.red_enemies)
	for frame in range(30*60):
		sea._physics_process(DT)
		d.advance(DT)
		if not combat.aircraft_enabled: break
	check(a.low_flight>.02 or a.is_over_land(d.player.global_position),"Aircraft exclusion begins with physical descent or terrain entry")
	check(not combat.aircraft_enabled and combat.enemies.is_empty() and combat.bombers.is_empty() and combat.red_enemies.is_empty(),"Descent retires every existing aircraft family")
	check(retired_actors.all(func(actor): return not is_instance_valid(actor) or not actor.alive or actor.is_queued_for_deletion()),"Retired approach aircraft cannot continue processing or colliding")
	check(combat.lifetimes.count(0.0)==combat.BULLET_CAPACITY and combat.bullets.all(func(round): return not round.visible),"The descent handoff clears every airborne projectile")
	check(combat.score==score_before and combat.kills==kills_before and combat.pow_spawn_count==pow_before and combat._effect_cursor==explosions_before,"Changing altitude grants no fake kill, score, POW or aircraft explosion")
	_validate_ground_exclusivity(d)
	for frame in range(20*60):
		_step(d)
		if a.low_flight>.95: break
	check(a.low_flight>.95 and combat.air_withdrawals.is_empty(),"Departure-only aircraft visuals are gone before sustained low flight")
	app._dispose_run()
	await process_frame

func _supplies() -> void:
	var d := _launch(3)
	var a: Node = d.assault
	var combat: Node = d.combat
	var defenses: Array[Area3D] = []
	for target in a.targets:
		if target.variant in ["battery","bunker"]: defenses.append(target)
	# Destruction signals are the source of rewards; do not call the drop helper
	# or edit its counters directly. Avoid fuel chain kills for exact thresholds.
	for index in range(2): defenses[index].take_damage(defenses[index].health)
	check(a.kills==2 and a.supply_drops==0 and not combat.pickup.active,"Two ground kills do not prematurely grant a POW")
	defenses[2].take_damage(defenses[2].health)
	check(a.kills==3 and a.supply_drops==1 and combat.pickup.active,"The third real ground destruction releases the first POW")
	check(combat.pickup.power_kind=="spread" and combat.next_power_kind=="laser","Ground rewards follow the same weapon cycle as air formations")
	var first_at: Vector3 = combat.pickup.global_position
	check(first_at.z>=combat.screen_top()+1.5 and first_at.z<=combat.screen_bottom()-2.0,"A ground POW remains inside reachable viewport bounds")
	for index in range(3,9): defenses[index].take_damage(defenses[index].health)
	check(a.kills==9 and a.supply_drops==1 and combat.pickup.active and combat.pickup.global_position.is_equal_approx(first_at) and combat.pickup.power_kind=="spread","Passing the next reward threshold never overwrites an active POW")
	combat.pickup.collect(combat)
	check(d.weapons.power_type=="spread" and combat.pickup.burst_time>0,"The real ground reward can be collected and equips its weapon")
	defenses[9].take_damage(defenses[9].health)
	check(a.supply_drops==1 and not combat.pickup.active,"The collection burst is not overwritten by the pending reward")
	combat.pickup.advance(.7,combat)
	defenses[10].take_damage(defenses[10].health)
	check(a.supply_drops==2 and combat.pickup.active and combat.pickup.power_kind=="laser","The next destruction releases the deferred second POW after collection")
	combat.pickup.collect(combat)
	combat.pickup.advance(.7,combat)
	for target in a.targets:
		if is_instance_valid(target) and target.alive: target.take_damage(target.health)
	check(a.supply_drops==2 and combat.pow_spawn_count==2 and not combat.pickup.active,"Destroying the entire battlefield cannot exceed two ground POWs")
	app._dispose_run()
	await process_frame

func _weapons_and_tactics() -> void:
	var d := _launch(3)
	var a: Node = d.assault
	for frame in range(30*60):
		_step(d)
		if a.low_flight>.25: break
	check(a.deployed,"Ground battlefield deploys during the authored approach")
	_validate_ground_exclusivity(d)
	var target: Area3D
	for candidate in a.targets:
		if candidate.variant=="battery": target=candidate; break
	# Keep the target's authentic collider and place its entire parent battlefield
	# under the guns. This exercises the shared coordinate transform as well.
	a.position.z = -target.position.z
	d.player.position = Vector3(target.global_position.x,0,7)
	await physics_frame
	await physics_frame
	var health_before: int = target.health
	var hits_before: int = d.weapons.hits_landed
	d.weapons._fire_salvo()
	for frame in range(22):
		d.weapons._physics_process(DT)
		await physics_frame
	check(target.health<health_before and d.weapons.hits_landed>hits_before,"Real swept machine-gun projectiles damage the ground collider")
	d.weapons.cease_fire()
	health_before = target.health
	d.weapons.set_power("laser")
	Input.action_press("fire")
	d.weapons._physics_process(DT)
	Input.action_release("fire")
	check(target.health<health_before and d.weapons.laser_contact.visible,"Real laser sweeps hit the grounded target and show contact")
	d.weapons.set_power("none")
	var radar: Area3D
	for candidate in a.targets:
		if candidate.alive and candidate.variant=="radar": radar=candidate; break
	var radar_at: Vector3 = radar.global_position
	var effect_slot: int = d.combat._effect_cursor
	var terrain_at: Vector3 = a.terrain.global_position
	radar.take_damage(radar.health)
	var blast_at: Vector3 = d.combat.effects[effect_slot].global_position
	check(a.radar_kills==1 and a.jam_remaining==6.0,"Destroying a radar starts six seconds of DCA disruption")
	a.advance(DT)
	check(target.jammed and target.warning_time==0,"Radar disruption cancels the active battery warning")
	a._on_scrolled(.75)
	check(radar.global_position.is_equal_approx(radar_at+Vector3(0,0,.75)),"Destroyed wreck follows the same terrain scroll")
	check(d.combat.effects[effect_slot].global_position.is_equal_approx(blast_at+Vector3(0,0,.75)),"Ground blast remains attached to the moving installation")
	check(a.terrain.global_position.is_equal_approx(terrain_at+Vector3(0,0,.75)),"Terrain and wreck keep their relative placement")
	d.combat._effect_cursor = effect_slot
	d.combat._explode(Vector3(2,0,1),1,false)
	var air_blast_at: Vector3 = d.combat.effects[effect_slot].global_position
	a._on_scrolled(.5)
	check(d.combat.effects[effect_slot].global_position.is_equal_approx(air_blast_at),"Reusing a ground explosion slot for an aircraft clears its scenery binding")
	for frame in range(6*60+2): a.advance(DT)
	check(not target.jammed and a.jam_remaining==0,"DCA recovers after the bounded radar disruption")
	var fuel: Area3D
	var neighbour: Area3D
	for candidate in a.targets:
		if candidate.alive and candidate.variant=="fuel":
			for other in a.targets:
				if other!=candidate and other.alive and other.global_position.distance_to(candidate.global_position)<5.5:
					fuel=candidate; neighbour=other; break
		if is_instance_valid(fuel): break
	check(is_instance_valid(fuel) and is_instance_valid(neighbour),"An authored fuel depot has a neighbouring installation")
	if is_instance_valid(fuel) and is_instance_valid(neighbour):
		var previous_health: int = neighbour.health
		fuel.take_damage(fuel.health)
		check(neighbour.health<previous_health,"Fuel destruction damages a nearby authentic installation")
	var progress_before: int = a.kills
	var elapsed_before: float = d.elapsed
	d.player.invulnerable_time = 0
	d.player.take_damage(d.player.health)
	check(not d.player.alive and d.combat.respawn_time>0,"Losing the plane schedules an in-mission respawn")
	for frame in range(95): _step(d)
	check(d.player.alive and d.player.invulnerable_time>0,"Respawn returns the protected plane without restarting the raid")
	check(a.kills==progress_before and d.elapsed>=elapsed_before and a.deployed,"Respawn retains ground objective progress and battlefield state")
	check(not d.combat.aircraft_enabled and d.combat.enemies.is_empty() and d.combat.bombers.is_empty() and d.combat.red_enemies.is_empty(),"Respawn over land cannot re-enable aerial encounters")
	var bomb_target: Area3D
	for candidate in a.targets:
		if is_instance_valid(candidate) and candidate.alive: bomb_target=candidate; break
	a.position.z = -bomb_target.position.z
	a.advance(0)
	d.advance(0)
	await physics_frame
	await physics_frame
	check(d.combat.get_radar_contacts().has(bomb_target),"Ground installations join the real bomb/radar contact list")
	check(d.use_bomb(),"Bomb command is accepted during low flight")
	check(not bomb_target.alive,"The real bomb damages and destroys a visible ground installation")
	app._dispose_run()
	await process_frame

func _mission(number: int, destroy_targets: bool) -> void:
	var d := _launch(number)
	_validate_layout(d)
	var low_seen := false
	var landing_seen := false
	var maximum_targets: int = d.assault.targets.size()
	var approach_aircraft_seen := false
	var low_aircraft_seen := false
	var low_withdrawal_seen := false
	var extraction_aircraft_seen := false
	var landing_aircraft_seen := false
	var landing_wave_count := -1
	var landing_spawns_seen := false
	var extraction_patterns_ok := true
	var return_wave_times: Array[float] = []
	var maximum_bullets := 0
	var timeout := int((float(d.mission.duration)+50)*60)
	for frame in range(timeout):
		var return_waves_before: int = d.extraction_wave_count
		_step(d)
		if d.extraction_wave_count>return_waves_before:
			return_wave_times.append(d.elapsed)
			var expected_script := "enemy_zero.gd" if d.extraction_wave_count%2==1 else "enemy_hayabusa.gd"
			var fresh: Array = d.combat.enemies.filter(func(actor): return is_instance_valid(actor) and is_zero_approx(actor.age))
			extraction_patterns_ok = extraction_patterns_ok and not fresh.is_empty() and fresh.all(func(actor): return actor.get_script().resource_path.ends_with(expected_script))
		maximum_targets = maxi(maximum_targets,d.assault.targets.size())
		var has_aircraft: bool = not d.combat.enemies.is_empty() or not d.combat.bombers.is_empty() or not d.combat.red_enemies.is_empty()
		if d.assault.low_flight>.02 or d.assault.is_over_land(d.player.global_position):
			low_aircraft_seen = low_aircraft_seen or has_aircraft
		elif not low_seen:
			approach_aircraft_seen = approach_aircraft_seen or has_aircraft
		elif d.assault.low_flight<=.001 and not d.ending:
			extraction_aircraft_seen = extraction_aircraft_seen or has_aircraft
		maximum_bullets = maxi(maximum_bullets,d.combat.BULLET_CAPACITY-d.combat.lifetimes.count(0.0))
		if d.assault.low_flight>.9: low_withdrawal_seen = low_withdrawal_seen or not d.combat.air_withdrawals.is_empty()
		low_seen = low_seen or d.assault.low_flight>.95
		if destroy_targets and frame%15==0:
			for actor in d.combat.get_radar_contacts():
				if is_instance_valid(actor) and actor.alive and actor.global_position.z>-9 and actor.global_position.z<9:
					actor.take_damage(50)
		if d.ending and not landing_seen:
			landing_seen = true
			landing_wave_count = d.extraction_wave_count
			check(d.assault.approach_clear(),"Mission %d waits until the ground clears before carrier landing" % number)
			check(d.assault.global_position.z-d.assault.length*.5>d.combat.screen_bottom()+18,"Mission %d has open sea throughout carrier approach" % number)
			check(d.assault.low_flight<.01 and d.player.bank.position.y==0,"Mission %d restores cruise altitude before landing" % number)
		if d.ending:
			landing_spawns_seen = landing_spawns_seen or d.extraction_wave_count!=landing_wave_count
			for group in [d.combat.enemies,d.combat.bombers,d.combat.red_enemies]:
				landing_aircraft_seen = landing_aircraft_seen or group.any(func(actor): return is_instance_valid(actor) and actor.alive and not actor.is_queued_for_deletion())
		if frame%120==0: await process_frame
		if not stage_report.is_empty(): break
	check(low_seen,"Mission %d includes sustained low-level flight" % number)
	check(approach_aircraft_seen,"Mission %d encounters aircraft above the ocean before descent" % number)
	check(not low_aircraft_seen,"Mission %d keeps the descent and low-level battlefield free of hostile aircraft" % number)
	check(not low_withdrawal_seen,"Mission %d removes visual aircraft exits before sustained low flight" % number)
	check(extraction_aircraft_seen,"Mission %d resumes aerial combat over the ocean after climbing" % number)
	check(d.extraction_wave_count>=2 and extraction_patterns_ok,"Mission %d alternates successive Zero and Hayabusa return waves" % number)
	check(not return_wave_times.is_empty() and absf(return_wave_times[0]-d.extraction_started_at)<DT*1.1,"Mission %d starts its return wave immediately upon cruise recovery" % number)
	check(is_equal_approx(d.extraction_end_at,maxf(float(d.mission.duration),d.extraction_started_at+12.0)),"Mission %d only extends its deadline when needed for the return battle" % number)
	check(return_wave_times.all(func(at): return at<d.extraction_end_at-5.0),"Mission %d stops new waves ahead of carrier recovery" % number)
	check(not landing_aircraft_seen,"Mission %d keeps carrier landing free of active enemy aircraft" % number)
	check(not landing_spawns_seen,"Mission %d cannot schedule a new return wave during landing" % number)
	check(maximum_bullets<=d.combat.BULLET_CAPACITY and d.combat.bullets.size()==d.combat.BULLET_CAPACITY,"Mission %d keeps reinforced DCA inside the fixed projectile pool" % number)
	check(d.combat.lifetimes.count(0.0)==d.combat.BULLET_CAPACITY,"Mission %d releases every DCA projectile before recovery" % number)
	check(landing_seen and d.cockpit.flight.get_node("Departure").landed,"Mission %d recovers on the carrier" % number)
	check(maximum_targets<=int(d.mission.ground_count),"Mission %d never exceeds prebuilt installation budget" % number)
	check(not stage_report.is_empty(),"Mission %d produces a finished report" % number)
	check(stage_report.get("won",false)==destroy_targets,"Mission %d victory follows the terrestrial quota" % number)
	check(stage_report.get("objective_failed",false)==not destroy_targets,"Mission %d reports an unfulfilled ground objective explicitly" % number)
	if destroy_targets:
		check(int(stage_report.get("ground_kills",0))>=int(d.mission.quota),"Mission %d reports real installation kills" % number)
	else:
		check(int(stage_report.get("ground_kills",-1))==0 and int(stage_report.get("lives",0))>0,"Missing targets fails the objective without inventing a player death")
	mission_results.append({"mission":number,"attack":destroy_targets,"report":stage_report.duplicate(),"max_targets":maximum_targets,"max_bullets":maximum_bullets,"approach_aircraft_seen":approach_aircraft_seen,"low_aircraft_seen":low_aircraft_seen,"extraction_aircraft_seen":extraction_aircraft_seen,"landing_aircraft_seen":landing_aircraft_seen,"return_wave_times":return_wave_times,"extraction_started_at":d.extraction_started_at,"extraction_end_at":d.extraction_end_at})
	print("GROUND MISSION ",number," attack=",destroy_targets," won=",stage_report.get("won",false)," seconds=",d.elapsed," kills=",d.assault.kills)
	app._dispose_run()
	await process_frame

func _run() -> void:
	root.size = Vector2i(1920,1080)
	app = load("res://scenes/campaign.tscn").instantiate()
	app.testing = true
	app.profile.path = "user://ground-assault-test-fixture.json"
	root.add_child(app)
	current_scene = app
	await process_frame
	app.profile.reset()
	app.profile.data.unlocked = 32
	app.profile.data.settings.quality = 1
	var count := 0
	for m in app.missions:
		if not m.get("ground_assault",false): continue
		count += 1
		check(RAIDS.has(int(m.id)) and m.objective=="ground","Low-level missions occupy the eight intended campaign slots")
		check(m.secondary=="radar" and int(m.secondary_target)==2,"Radar side objective matches the two physical stations")
		check(m.boss=="" and not m.events.any(func(event): return event.kind in ["boss","naval","convoy"]),"Ground raids cannot spawn ships or bosses inside land")
		check(not m.events.is_empty() and m.events.all(func(event): return event.kind in ["zero","hayabusa","red","bomber"] and float(event.time)<12.0),"Ground raids reserve aerial encounters for the ocean approach")
		check(int(m.quota)>=6 and int(m.quota)<=int(m.ground_count)*.65,"Ground quota leaves room for missed installations")
	check(count==8,"Campaign includes exactly eight low-altitude ground raids")
	await _compact_layouts()
	await _extraction_schedule()
	await _approach_transition()
	await _supplies()
	await _weapons_and_tactics()
	for number in RAIDS: await _mission(number,true)
	await _mission(3,false)
	check(mission_results.size()==RAIDS.size()+1,"Every requested raid simulation completes without a script interruption")
	Input.action_release("fire")
	app.set_process(false)
	if is_instance_valid(app.music): app.music.stop()
	_stop_audio(app)
	# Let the audio server release queued playback handles before destroying the
	# application; two headless process frames alone can be shorter than its tick.
	await create_timer(.25).timeout
	app.queue_free()
	current_scene = null
	await process_frame
	await process_frame
	await create_timer(.10).timeout
	var report := {"checks":checks,"failures":failures,"missions":mission_results}
	if "--packaged" not in OS.get_cmdline_user_args():
		FileAccess.open("res://tests/ground-assault-results.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("GROUND ASSAULT TEST ",checks," checks, ",failures.size()," failures: ",failures)
	quit(0 if failures.is_empty() else 1)
