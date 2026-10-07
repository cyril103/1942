extends SceneTree
## Controlled 60 Hz sortie pilot, using the live scene and live physics server.
## Only the player's Hurtbox layer is neutralized. No target/HP/quota mutation,
## teleports, scripted kills, direct POW collections or ammunition refills.
## Success proves this policy reaches quota AND priorities under this laboratory
## protection. Failure does not prove that the mission is impossible for a human.
const PROFILE_PATH := "user://raid-quota-weapons-isolated.json"
const DEFAULT_OUTPUT_PATH := "res://tests/raid-quota-weapons-results.json"
const DT := 1.0/60.0
const CASES := [
	{"mission":3,"upgrades":[0,0,0]},
	{"mission":7,"upgrades":[0,0,0]},
	{"mission":11,"upgrades":[1,1,1]},
	{"mission":15,"upgrades":[1,1,1]},
	{"mission":19,"upgrades":[2,1,1]},
	{"mission":23,"upgrades":[2,2,2]},
	{"mission":27,"upgrades":[3,2,2]},
	{"mission":31,"upgrades":[3,3,3]}
]
const LOADOUT := preload("res://scripts/campaign/loadout.gd")

class SortiePilot extends Node:
	var director: Node
	var ticks := 0
	var flight_ticks := 0
	var ground_ticks := 0
	var wrong_delta_ticks := 0
	var max_movement_step := 0.0
	var excessive_movement_ticks := 0
	var pool_overflows := 0
	var peak_player_rounds := 0
	var peak_enemy_rounds := 0
	var peak_effects := 0
	var aircraft_during_low := false
	var bomb_uses := 0
	var strike_uses := 0
	var last_bomb_at := -100.0
	var current_target: Area3D
	var previous_position := Vector3.ZERO
	var previous_speed := 0.0
	var previously_flying := false
	var previous_shots := 0
	var previous_hits := 0
	var previous_power := "none"
	var previous_collections := 0
	var max_collection_distance := 0.0
	var shots_by_power := {"none":0,"spread":0,"laser":0,"life":0}
	var hits_by_power := {"none":0,"spread":0,"laser":0,"life":0}
	var power_log: Array[Dictionary] = []
	var attack_log: Array[Dictionary] = []
	var kill_log: Array[Dictionary] = []
	var snapshots: Array[Dictionary] = []
	var initial_hp: Dictionary = {}
	var previous_target_positions: Dictionary = {}
	var target_velocities: Dictionary = {}
	var node_counts := {}
	var target_allocations := false
	var last_snapshot_tick := -60

	func configure(d: Node) -> void:
		director = d
		process_mode = Node.PROCESS_MODE_ALWAYS
		process_physics_priority = -1000
		previous_position = d.player.position
		previous_speed = d.player.speed
		previous_shots = d.weapons.shots_fired
		previous_hits = d.weapons.hits_landed
		previous_power = d.weapons.power_type
		previous_collections = d.combat.pickup.collected_count
		for target in d.assault.targets:
			initial_hp[target.tactical_id] = {"variant":target.variant,"health":target.health,"max_health":target.max_health}
			node_counts[target.tactical_id] = target.get_child_count()
			target.destroyed.connect(_on_ground_destroyed.bind(target))

	func _on_ground_destroyed(at: Vector3, target: Area3D) -> void:
		kill_log.append({"id":target.tactical_id,"variant":target.variant,"mission_seconds":director.elapsed,"at":[at.x,at.y,at.z],"player_shots":director.weapons.shots_fired,"hits":director.weapons.hits_landed,"attack_uses":director.attacks_used})

	func _release_inputs() -> void:
		for action in ["move_left","move_right","move_up","move_down","fire","focus_flight","bomb","strike"]:
			Input.action_release(action)

	func _physics_process(delta: float) -> void:
		ticks += 1
		if absf(delta-DT)>.00001: wrong_delta_ticks += 1
		_release_inputs()
		if not is_instance_valid(director): return
		_sample()
		var flying: bool = director.active and not director.paused and not director.ending and director.player.alive and director.player.controls_enabled
		if flying and previously_flying:
			var step: float = director.player.position.distance_to(previous_position)
			max_movement_step = maxf(max_movement_step,step)
			if step>maxf(previous_speed,float(director.player.speed))*DT+.04:
				excessive_movement_ticks += 1
		previous_position = director.player.position
		previous_speed = director.player.speed
		previously_flying = flying
		if not flying: return
		flight_ticks += 1
		if director.assault.low_flight>.02: ground_ticks += 1
		var goal: Vector3
		if director.assault.deployed and not director.assault.cleared:
			goal = _ground_goal()
		else:
			goal = _ocean_goal()
		var pickup: Node3D = director.combat.pickup
		if pickup.active and _can_chase_pickup(pickup):
			goal = Vector3(pickup.global_position.x,0.0,pickup.global_position.z)
		_move_towards(goal)
		Input.action_press("fire")
		_use_attacks()

	func _sample() -> void:
		var d: Node = director
		var w: Node3D = d.weapons
		# Weapons processes before Combat's pickup in main.tscn. The power stored
		# at the previous input tick therefore labels that tick's real shot count.
		var new_shots: int = maxi(0,w.shots_fired-previous_shots)
		var new_hits: int = maxi(0,w.hits_landed-previous_hits)
		shots_by_power[previous_power] = int(shots_by_power.get(previous_power,0))+new_shots
		hits_by_power[previous_power] = int(hits_by_power.get(previous_power,0))+new_hits
		previous_shots = w.shots_fired
		previous_hits = w.hits_landed
		previous_power = w.power_type
		if d.combat.pickup.collected_count>previous_collections:
			var relative := Vector2(d.player.position.x-d.combat.pickup.global_position.x,d.player.position.z-d.combat.pickup.global_position.z)
			max_collection_distance = maxf(max_collection_distance,relative.length())
			power_log.append({"kind":d.combat.pickup.power_kind,"mission_seconds":d.elapsed,"player_at":[d.player.position.x,d.player.position.z],"pickup_at":[d.combat.pickup.global_position.x,d.combat.pickup.global_position.z],"observed_distance":relative.length(),"count":d.combat.pickup.collected_count})
		previous_collections = d.combat.pickup.collected_count
		var active_player := 0
		var active_enemy := 0
		var active_effects := 0
		for life in w.lifetimes: if life>0: active_player += 1
		for life in d.combat.lifetimes: if life>0: active_enemy += 1
		for life in d.combat.effect_times: if life>0: active_effects += 1
		peak_player_rounds = maxi(peak_player_rounds,active_player)
		peak_enemy_rounds = maxi(peak_enemy_rounds,active_enemy)
		peak_effects = maxi(peak_effects,active_effects)
		if active_player>w.CAPACITY or active_enemy>d.combat.BULLET_CAPACITY or active_effects>d.combat.EFFECT_CAPACITY: pool_overflows += 1
		if d.assault.low_flight>.02:
			aircraft_during_low = aircraft_during_low or not d.combat.enemies.is_empty() or not d.combat.bombers.is_empty() or not d.combat.red_enemies.is_empty()
		for target in d.assault.targets:
			if not is_instance_valid(target) or not target.alive: continue
			var id: String = target.tactical_id
			var at: Vector3 = target.global_position
			if previous_target_positions.has(id):
				var previous_at: Vector3 = previous_target_positions[id]
				target_velocities[id] = (at-previous_at)/DT
			previous_target_positions[id] = at
			if target.get_child_count()!=int(node_counts[id]): target_allocations = true
		if ticks-last_snapshot_tick>=60:
			last_snapshot_tick = ticks
			var status: Dictionary = d.assault.objective_status()
			snapshots.append({"tick":ticks,"mission_seconds":d.elapsed,"player_at":[d.player.position.x,d.player.position.z],"low_flight":d.assault.low_flight,"kills":status.kills,"quota":status.quota,"priority_destroyed":status.priority_destroyed,"priority_total":status.priority_total,"main_met":status.main_met,"power":w.power_type,"shots":w.shots_fired,"hits":w.hits_landed,"bombs":d.bombs,"charge":d.charge,"ability_seconds":d.ability_time,"enemy_rounds":active_enemy,"player_rounds":active_player})

	func _ground_goal() -> Vector3:
		var d: Node = director
		var c: Node3D = d.combat
		var p: Node3D = d.player
		var raid: Node3D = d.assault
		var top: float = c.screen_top()
		var bottom: float = c.screen_bottom()
		var baseline := bottom-2.1
		var best: Area3D
		var best_score := -INF
		for target in raid.targets:
			if not is_instance_valid(target) or not target.alive or target.collision_layer==0: continue
			var at: Vector3 = target.global_position
			if at.z<top-1.0 or at.z>bottom-.15: continue
			var priority: bool = raid.layout.priority_ids.has(target.tactical_id)
			var score := (1000.0 if priority else 0.0)-absf(at.x-p.position.x)*2.5-float(target.health)*.40
			# Targets moving toward the retirement edge gain urgency. Affordable
			# fuel clusters and active guns come next, without any armor mutation.
			score += (at.z-top)*1.1
			if target.variant=="fuel": score += 32.0+_nearby_installations(target)*9.0
			elif target.variant=="radar": score += 20.0
			elif target.variant=="battery": score += 16.0
			elif target.variant=="bunker": score += 10.0
			if target==current_target: score += 15.0
			if score>best_score:
				best_score = score
				best = target
		current_target = best
		if not is_instance_valid(best): return Vector3(0,0,baseline)
		var destination: Vector3 = best.global_position
		if bool(best.mobile) and target_velocities.has(best.tactical_id):
			var velocity: Vector3 = target_velocities[best.tactical_id]
			var travel := maxf(0.0,p.position.z-destination.z)/float(d.weapons.SPEED)
			destination.x += clampf(velocity.x*travel,-1.5,1.5)
		# Stay below the current target while there is room, using normal input
		# and the player's own screen constraint even near the retirement edge.
		return Vector3(destination.x,0,maxf(baseline,minf(bottom-.85,destination.z+1.65)))

	func _nearby_installations(center: Area3D) -> int:
		var count := 0
		for other in director.assault.targets:
			if is_instance_valid(other) and other.alive and other!=center and other.global_position.distance_to(center.global_position)<5.5: count += 1
		return count

	func _ocean_goal() -> Vector3:
		var c: Node3D = director.combat
		var bottom: float = c.screen_bottom()
		var best: Area3D
		var best_cost := INF
		for enemy in c.get_radar_contacts():
			if not is_instance_valid(enemy) or not enemy.alive: continue
			if enemy.global_position.z<c.screen_top() or enemy.global_position.z>director.player.position.z-1.0: continue
			var cost := absf(enemy.global_position.x-director.player.position.x)
			if c.red_enemies.has(enemy): cost -= 15.0
			if cost<best_cost:
				best_cost = cost
				best = enemy
		if is_instance_valid(best): return Vector3(best.global_position.x,0,bottom-2.1)
		return Vector3(sin(float(ticks)*DT*.4)*3.0,0,bottom-2.1)

	func _can_chase_pickup(pickup: Node3D) -> bool:
		var d: Node = director
		if pickup.global_position.z<d.combat.screen_top() or pickup.global_position.z>d.combat.screen_bottom()-.6: return false
		var distance := Vector2(pickup.global_position.x-d.player.position.x,pickup.global_position.z-d.player.position.z).length()
		if distance/float(d.player.speed)>4.0: return false
		if is_instance_valid(current_target) and d.assault.layout.priority_ids.has(current_target.tactical_id):
			var remaining: float = (d.combat.screen_bottom()-current_target.global_position.z)/maxf(.1,float(d.cockpit.flight.get_node("Seascape").scroll_speed))
			if remaining<4.0: return false
		return true

	func _move_towards(goal: Vector3) -> void:
		var delta: Vector3 = goal-director.player.position
		if absf(delta.x)>.15: Input.action_press("move_right" if delta.x>0 else "move_left")
		if absf(delta.z)>.15: Input.action_press("move_down" if delta.z>0 else "move_up")
		if absf(delta.x)<.60 and absf(delta.z)<.60: Input.action_press("focus_flight")

	func _use_attacks() -> void:
		var d: Node = director
		if not d.assault.deployed or d.assault.main_objective_met(): return
		var visible := 0
		var focused := 0
		var urgent_priority := false
		var urgent_in_lane := false
		var viewport: Rect2 = d.cockpit.viewport.get_visible_rect()
		for target in d.assault.contacts():
			if not viewport.has_point(d.combat.camera.unproject_position(target.global_position)): continue
			visible += 1
			if absf(target.global_position.x-d.player.position.x)<3.6: focused += 1
			if d.assault.layout.priority_ids.has(target.tactical_id) and target.global_position.z>d.player.position.z-3.0:
				urgent_priority = true
				if absf(target.global_position.x-d.player.position.x)<3.6: urgent_in_lane = true
		var strike_has_targets := focused>=2 if bool(d.equipment.strike_focused) else visible>=3
		var strike_is_urgent := urgent_in_lane if bool(d.equipment.strike_focused) else urgent_priority
		if d.charge>=100 and d.ability_time<=0 and (strike_has_targets or strike_is_urgent):
			if d.use_strike():
				strike_uses += 1
				attack_log.append({"kind":"strike","mission_seconds":d.elapsed,"visible_targets":visible,"focused_targets":focused,"urgent_priority":urgent_priority,"bombs_remaining":d.bombs})
				return # Re-evaluate surviving contacts before spending another reserve.
		if d.bombs>0 and d.elapsed-last_bomb_at>=3.0 and (visible>=4 or urgent_priority):
			if d.use_bomb():
				bomb_uses += 1
				last_bomb_at = d.elapsed
				attack_log.append({"kind":"bomb","mission_seconds":d.elapsed,"visible_targets":visible,"urgent_priority":urgent_priority,"bombs_remaining":d.bombs})

var app: Node
var checks := 0
var failures: Array[String] = []
var reports: Array[Dictionary] = []
var factor := 4
var only_mission := -1
var only_aircraft := -1
var include_filter_requested := false
var included_missions: Array[int] = []
var output_path := DEFAULT_OUTPUT_PATH
var dimensions := Vector2i(1920,1080)
var expected_fixtures := 24
var old_physics_hz := 60
var old_time_scale := 1.0
var old_steps := 8
var old_max_fps := 0

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--time-factor="): factor = clampi(argument.trim_prefix("--time-factor=").to_int(),1,8)
		if argument.begins_with("--mission="): only_mission = argument.trim_prefix("--mission=").to_int()
		if argument.begins_with("--aircraft="): only_aircraft = argument.trim_prefix("--aircraft=").to_int()
		if argument.begins_with("--include-missions="):
			include_filter_requested = true
			for part in argument.trim_prefix("--include-missions=").split(","):
				if not part.is_valid_int():
					failures.append("Invalid included mission: "+part)
					continue
				var number := part.to_int()
				if not included_missions.has(number): included_missions.append(number)
		if argument.begins_with("--output-path="): output_path = argument.trim_prefix("--output-path=")
		if argument.begins_with("--size="):
			var parts := argument.trim_prefix("--size=").split("x")
			if parts.size()==2: dimensions = Vector2i(maxi(640,parts[0].to_int()),maxi(360,parts[1].to_int()))
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func _stop_audio(node: Node) -> void:
	if node is AudioStreamPlayer or node is AudioStreamPlayer3D: node.stop()
	for child in node.get_children(): _stop_audio(child)

func _cleanup_profile() -> void:
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(PROFILE_PATH+suffix): DirAccess.remove_absolute(PROFILE_PATH+suffix)

func _release_inputs() -> void:
	for action in InputMap.get_actions(): Input.action_release(action)

func _selected(spec: Dictionary, aircraft: int) -> bool:
	if only_mission>=0 and int(spec.mission)!=only_mission: return false
	if only_aircraft>=0 and aircraft!=only_aircraft: return false
	if include_filter_requested and not included_missions.has(int(spec.mission)): return false
	return true

func _write(complete: bool) -> void:
	var data := {"schema":2,"complete":complete,"checks":checks,"failures":failures,"fixtures_executed":reports.size(),"fixtures_expected":expected_fixtures,"full_24_fixture_matrix":expected_fixtures==CASES.size()*3,"selection":{"mission":only_mission,"aircraft":only_aircraft,"include_filter_requested":include_filter_requested,"include_missions":included_missions.duplicate()},"output_path":output_path,"resolution":[dimensions.x,dimensions.y],"gameplay_hz":60,"engine_physics_hz":60*factor,"time_factor":factor,"mode":"live production sorties, real physics, Input movement and weapons","laboratory_protection":"Player Hurtbox collision_layer=0 only; enemy fire remains active; no HP, target positions, quotas or weapon clocks changed.","objective_contract":"Ground kills >= authored quota AND every authored priority ID destroyed.","human_campaign_viability":"NOT_PERFORMED","fps_measurement":"NOT_PERFORMED","failure_interpretation":"A failed quota records this deterministic policy's result, not impossibility for human players.","cases":reports}
	var file := FileAccess.open(output_path,FileAccess.WRITE)
	if file==null:
		var message := "Cannot write quota/weapon evidence: "+output_path
		if not failures.has(message): failures.append(message)
		push_error(message)
		return
	file.store_string(JSON.stringify(data,"\t"))
	file.close()

func _fixture(spec: Dictionary, aircraft: int) -> void:
	_release_inputs()
	app._dispose_run()
	await physics_frame
	await physics_frame
	app.profile.reset()
	app.profile.data.unlocked = 32
	app.profile.data.aircraft = aircraft
	app.profile.data.upgrades = spec.upgrades.duplicate()
	app.profile.data.settings.fullscreen = false
	app.profile.data.settings.vsync = false
	app.profile.data.settings.music = 0.0
	app.profile.data.settings.effects = 0.0
	app.profile.data.settings.quality = 1
	seed(1942+int(spec.mission)*37+aircraft)
	app._launch(int(spec.mission),"campaign")
	app._apply_settings()
	var d: Node = app.director
	check(is_instance_valid(d) and is_instance_valid(d.assault),"M%02d aircraft%d launches its real prepared sortie" % [spec.mission,aircraft])
	if not is_instance_valid(d) or not is_instance_valid(d.assault): return
	for connection in d.finished.get_connections(): d.finished.disconnect(connection.callable)
	var result_box := {"report":{}}
	d.finished.connect(func(report): result_box.report=report.duplicate(true))
	var hurtbox: Area3D = d.player.get_node("Hurtbox")
	var original_hurtbox_layer := hurtbox.collision_layer
	hurtbox.collision_layer = 0
	var pilot := SortiePilot.new()
	pilot.configure(d)
	root.add_child(pilot)
	var armor_intact := true
	for target in d.assault.targets:
		var spec_target: Dictionary = {}
		for source in d.assault.layout.targets:
			if source.id==target.tactical_id:
				spec_target = source
				break
		var authored_health: float = float(target.HEALTH[target.variant])+float(spec_target.get("health_bonus",0))
		armor_intact = armor_intact and target.health==authored_health and target.max_health==authored_health
	check(armor_intact,"Fixture retains every production target's authored HP without adaptation")
	check(d.weapons.power_type=="none","Fixture starts with the selected aircraft's normal weapon")
	var initial_gear: Dictionary = d.equipment.duplicate(true)
	var initial_bombs: int = d.bombs
	var initial_charge: float = d.charge
	var initial_quota: int = d.assault.layout.quota
	var initial_priority_ids: Array = d.assault.layout.priority_ids.duplicate()
	var original_targets: int = d.assault.targets.size()
	var wall_started := Time.get_ticks_msec()
	var timeout_ticks := int((float(d.mission.duration)+80.0)*60.0)
	while result_box.report.is_empty() and pilot.ticks<timeout_ticks:
		await physics_frame
	pilot.set_physics_process(false)
	pilot._release_inputs()
	pilot._sample()
	var status: Dictionary = d.assault.objective_status()
	var finish_report: Dictionary = result_box.report
	check(not finish_report.is_empty(),"The live sortie reaches a real carrier-return result within its bounded clock")
	check(pilot.wrong_delta_ticks==0,"Every live gameplay physics tick remains 1/60 s under acceleration")
	check(pilot.excessive_movement_ticks==0,"Every controlled movement stays within the actual aircraft speed")
	check(d.assault.layout.quota==initial_quota and d.assault.layout.priority_ids==initial_priority_ids,"Quota and required IDs remain exactly authored for the whole sortie")
	check(pilot.pool_overflows==0 and d.weapons.projectiles.size()==96 and d.combat.bullets.size()==192 and d.combat.effects.size()==18,"Live sortie respects all fixed projectile and explosion pools")
	check(not pilot.target_allocations,"Mobile movement and attacks add no child nodes to a living ground target")
	check(not pilot.aircraft_during_low,"Aircraft waves are absent throughout the actual low-flight raid")
	check(pilot.bomb_uses==initial_bombs-d.bombs and pilot.bomb_uses+pilot.strike_uses==d.attacks_used,"Only successful production bomb/strike calls consume the original reserves")
	check(pilot.power_log.size()==d.combat.pickup.collected_count and pilot.max_collection_distance<1.2,"Observed POW collections occur at the moving pilot, without direct collection calls")
	check(pilot.kill_log.size()==d.assault.kills and d.assault.destroyed_ids.size()==d.assault.kills,"Every ground kill is a real unique destruction recorded by the sortie")
	check(d.weapons.hits_landed>0 and d.assault.kills>0,"The real moving pilot lands weapon sweeps and destroys authentic targets")
	check(bool(status.main_met),"This protected input policy reaches quota AND every required target ID")
	check(bool(finish_report.get("won",false)) and bool(finish_report.get("objective_met",false)),"The actual mission report confirms the shared quota-plus-priorities objective")
	var stats := {"mission":int(spec.mission),"aircraft_index":aircraft,"aircraft_id":LOADOUT.aircraft(aircraft).id,"upgrades":spec.upgrades.duplicate(),"equipped_modules":app.profile.data.equipped_modules.duplicate(),"initial_power":"none","initial_stats":initial_gear,"initial_bombs":initial_bombs,"initial_charge":initial_charge,"initial_targets":original_targets,"initial_quota":initial_quota,"priority_ids":initial_priority_ids,"width_variant":d.assault.layout.get("width_variant","unknown"),"initial_target_health":pilot.initial_hp,"physics_ticks":pilot.ticks,"simulated_seconds":pilot.ticks*DT,"mission_seconds":d.elapsed,"wall_seconds":float(Time.get_ticks_msec()-wall_started)/1000.0,"flight_seconds":pilot.flight_ticks*DT,"ground_seconds":pilot.ground_ticks*DT,"objective_status":status,"actual_report":finish_report,"ground_kills":d.assault.kills,"total_kills":d.combat.kills,"escaped_ground_targets":d.assault.escaped,"ground_kill_log":pilot.kill_log,"player_shots":d.weapons.shots_fired,"player_hits":d.weapons.hits_landed,"shots_by_power":pilot.shots_by_power,"hits_by_power":pilot.hits_by_power,"enemy_shots":d.combat.enemy_shots,"pow_collected":d.combat.pickup.collected_count,"physical_collections":pilot.power_log,"bomb_uses":pilot.bomb_uses,"strike_uses":pilot.strike_uses,"attack_log":pilot.attack_log,"bombs_remaining":d.bombs,"charge_remaining":d.charge,"peak_player_rounds":pilot.peak_player_rounds,"peak_enemy_rounds":pilot.peak_enemy_rounds,"peak_effects":pilot.peak_effects,"max_movement_step":pilot.max_movement_step,"excessive_movement_ticks":pilot.excessive_movement_ticks,"wrong_delta_ticks":pilot.wrong_delta_ticks,"original_hurtbox_layer":original_hurtbox_layer,"snapshots":pilot.snapshots}
	reports.append(stats)
	_write(false)
	print("RAID QUOTA WEAPONS M",spec.mission," aircraft",aircraft," kills=",status.kills,"/",status.quota," priorities=",status.priority_destroyed,"/",status.priority_total," main_met=",status.main_met," seconds=",pilot.ticks*DT)
	pilot.director = null
	pilot.queue_free()
	_stop_audio(app)
	app._dispose_run()
	await physics_frame
	await physics_frame

func _run() -> void:
	_cleanup_profile()
	old_physics_hz = Engine.physics_ticks_per_second
	old_time_scale = Engine.time_scale
	old_steps = Engine.max_physics_steps_per_frame
	old_max_fps = Engine.max_fps
	Engine.physics_ticks_per_second = 60*factor
	Engine.time_scale = factor
	Engine.max_physics_steps_per_frame = maxi(16,factor*4)
	Engine.max_fps = 120
	root.size = dimensions
	app = load("res://scenes/campaign.tscn").instantiate()
	app.testing = true
	app.profile.path = PROFILE_PATH
	root.add_child(app)
	current_scene = app
	await process_frame
	app.set_process(false)
	for action in InputMap.get_actions():
		Input.action_release(action)
		InputMap.action_erase_events(action)
	expected_fixtures = 0
	for spec in CASES:
		for aircraft in range(3):
			if not _selected(spec,aircraft): continue
			expected_fixtures += 1
	check(expected_fixtures>0,"Requested filter selects at least one authored fixture")
	for spec in CASES:
		for aircraft in range(3):
			if not _selected(spec,aircraft): continue
			await _fixture(spec,aircraft)
	check(reports.size()==expected_fixtures,"Every requested mission/aircraft fixture actually executed")
	_release_inputs()
	paused = false
	_stop_audio(app)
	app._dispose_run()
	Engine.time_scale = old_time_scale
	Engine.physics_ticks_per_second = old_physics_hz
	Engine.max_physics_steps_per_frame = old_steps
	Engine.max_fps = old_max_fps
	await create_timer(.25).timeout
	app.queue_free()
	current_scene = null
	await physics_frame
	await physics_frame
	await create_timer(.10).timeout
	_cleanup_profile()
	_write(reports.size()==expected_fixtures and expected_fixtures>0)
	print("RAID QUOTA WEAPONS: ",checks," checks; fixtures ",reports.size(),"/",expected_fixtures,"; failures: ",failures)
	quit(0 if failures.is_empty() else 1)
