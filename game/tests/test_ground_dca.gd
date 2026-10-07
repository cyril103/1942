extends SceneTree
## Behavior tests use the real installation and a shot recorder. No rendering,
## physics timing or campaign scheduler is needed to audit DCA telegraphs.
const TARGET := preload("res://scripts/campaign/ground_target.gd")
const DT := 1.0/120.0
var checks := 0
var failures: Array[String] = []
var summaries: Array[Dictionary] = []

class Pilot extends Node3D:
	var alive := true
	var controls_enabled := true

class RangeRecorder extends Node3D:
	var player: Pilot
	var camera: Camera3D
	var game_over := false
	var enemy_interval_scale := 1.0
	var rounds: Array[Dictionary] = []
	var clock := 0.0
	var attempts := 0
	var accepting := true
	func screen_top() -> float: return -12.0
	func screen_bottom() -> float: return 12.0
	func _launch_enemy_round(origin: Vector3, destination: Vector3, speed: float, _visual_origin := false) -> bool:
		attempts += 1
		if not accepting: return false
		rounds.append({"time":clock,"origin":origin,"target":destination,"speed":speed})
		return true

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func _initialize() -> void: _run.call_deferred()

func _range() -> RangeRecorder:
	var combat := RangeRecorder.new()
	combat.player = Pilot.new()
	root.add_child(combat)
	combat.add_child(combat.player)
	combat.player.position = Vector3(2,0,8)
	combat.camera = Camera3D.new()
	combat.add_child(combat.camera)
	combat.camera.position = Vector3(0,35,0)
	combat.camera.rotation.x = -PI/2.0
	combat.camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	combat.camera.size = 24.0
	return combat

func _target(combat: RangeRecorder, kind: String, sector: int, stagger := 0.0) -> Area3D:
	var target := TARGET.new()
	target.variant = kind
	combat.add_child(target)
	target.position = Vector3(0,0,-4)
	target.configure_defense(sector,stagger)
	return target

func _step(target: Area3D, combat: RangeRecorder, seconds: float) -> void:
	for frame in range(int(ceil(seconds/DT))):
		combat.clock += DT
		target.advance(DT,combat)

func _wait_for_warning(target: Area3D, combat: RangeRecorder) -> bool:
	for frame in range(120*12):
		_step(target,combat,DT)
		if target.warning_time>0: return true
	return false

func _wait_for_round(target: Area3D, combat: RangeRecorder) -> bool:
	for frame in range(120*3):
		_step(target,combat,DT)
		if not combat.rounds.is_empty(): return true
	return false

func _pattern(kind: String, sector: int, rapid := false) -> void:
	var combat := _range()
	var target := _target(combat,kind,sector)
	target.rapid_fire = rapid
	check(_wait_for_warning(target,combat),"%s sector %d announces its next attack" % [kind,sector])
	var warning_start := combat.clock
	var original_aim := combat.player.position
	check(combat.rounds.is_empty(),"%s sector %d never shoots before its warning" % [kind,sector])
	# Dodge after the tell. The pending shot must not track this late movement.
	combat.player.position.x = -7
	check(_wait_for_round(target,combat),"%s sector %d eventually fires after the tell" % [kind,sector])
	if not combat.rounds.is_empty():
		var tell_duration: float = float(combat.rounds[0].time)-warning_start
		check(tell_duration>=.35 and tell_duration<=.51,"%s sector %d gives a brisk but readable 350-510 ms warning" % [kind,sector])
	_step(target,combat,.65)
	check(combat.rounds.size()>=6 and combat.rounds.size()<=21,"%s sector %d fires one forceful bounded pattern" % [kind,sector])
	var min_x := INF
	var max_x := -INF
	var mean_x := 0.0
	for round in combat.rounds:
		var direction: Vector3 = round.target-round.origin
		var intercept: float = round.origin.x+direction.x*(original_aim.z-round.origin.z)/direction.z
		var halfway: float = lerpf(round.origin.x,intercept,.5)
		min_x = minf(min_x,halfway)
		max_x = maxf(max_x,halfway)
		mean_x += intercept
		check(float(round.speed)>0 and float(round.speed)<=18.0,"DCA rounds preserve a dodgeable finite velocity")
	mean_x /= maxi(1,combat.rounds.size())
	check(absf(mean_x-original_aim.x)<1.0,"%s sector %d keeps its telegraphed aim after the player dodges" % [kind,sector])
	check(max_x-min_x>.25,"%s sector %d separates its projectiles instead of stacking them" % [kind,sector])
	summaries.append({"kind":kind,"sector":sector,"rapid":rapid,"first_attack_shots":combat.rounds.size(),"spread":max_x-min_x,"first_shot_at":combat.rounds[0].time})
	combat.free()

func _interruptions() -> void:
	for interruption in ["jam","destroy","behind","above","side","dead_pilot","takeoff","game_over"]:
		var combat := _range()
		var target := _target(combat,"battery",7)
		check(_wait_for_warning(target,combat) and _wait_for_round(target,combat),"Battery begins a burst before interruption: "+interruption)
		var count_before := combat.rounds.size()
		match interruption:
			"jam": target.jammed = true
			"destroy": target.take_damage(target.health)
			"behind": target.position.z = 8
			"above": target.position.z = -20
			"side": target.position.x = 100
			"dead_pilot": combat.player.alive = false
			"takeoff": combat.player.controls_enabled = false
			"game_over": combat.game_over = true
		_step(target,combat,1.5)
		check(combat.rounds.size()==count_before,"Pending burst is cancelled by "+interruption)
		check(target.warning_time==0 and target.salvo_remaining==0,"No delayed attack survives "+interruption)
		if interruption=="jam":
			target.jammed = false
			_step(target,combat,.20)
			check(combat.rounds.size()==count_before,"Clearing radar disruption cannot release an unannounced backlog")
			check(_wait_for_warning(target,combat),"Battery resumes with a fresh warning after disruption")
		combat.free()

func _silent_targets_and_pool() -> void:
	for kind in ["radar","fuel","runway"]:
		var combat := _range()
		var target := _target(combat,kind,7)
		_step(target,combat,20)
		check(combat.rounds.is_empty(),kind+" remains an objective rather than an invisible gun")
		combat.free()
	var combat := _range()
	var target := _target(combat,"battery",7)
	combat.accepting = false
	_step(target,combat,25)
	check(combat.rounds.is_empty() and combat.attempts>0 and combat.attempts<240,"An exhausted projectile pool drops shots without an unbounded retry loop")
	combat.accepting = true
	var resumed_at := combat.clock
	_step(target,combat,6)
	check(not combat.rounds.is_empty() and combat.rounds.size()<=60,"Free pool slots permit normal bounded attacks after saturation")
	if not combat.rounds.is_empty(): check(float(combat.rounds[0].time)>=resumed_at,"Pool recovery never resurrects expired projectiles")
	combat.free()

func _progression() -> void:
	for kind in ["battery","bunker"]:
		var counts: Array[int] = []
		for sector in [0,7]:
			var combat := _range()
			var target := _target(combat,kind,sector)
			_step(target,combat,20)
			counts.append(combat.rounds.size())
			combat.free()
		check(counts[0]>=55 and counts[1]>counts[0],kind+" sustains pressure throughout early raids and scales up later")
		summaries.append({"kind":kind,"shots_in_20s_early":counts[0],"shots_in_20s_late":counts[1]})
	var combat := _range()
	var first := _target(combat,"battery",0,0)
	var second := _target(combat,"battery",0,.24)
	var first_tell := -1.0
	var second_tell := -1.0
	for frame in range(120*8):
		combat.clock += DT
		first.advance(DT,combat)
		second.advance(DT,combat)
		if first.warning_time>0 and first_tell<0: first_tell=combat.clock
		if second.warning_time>0 and second_tell<0: second_tell=combat.clock
	check(first_tell>=0 and second_tell-first_tell>=.20 and second_tell<=.32,"Neighbouring emplacements stagger promptly without leaving a slow gun silent")
	combat.free()

func _entry_and_endurance() -> void:
	for kind in ["battery","bunker"]:
		var combat := _range()
		var target := _target(combat,kind,0)
		target.position.z = combat.screen_top()+.35
		_step(target,combat,.62)
		check(not combat.rounds.is_empty(),kind+" fires within 620 ms of appearing at the top edge")
		combat.free()
		combat = _range()
		target = _target(combat,kind,0,.28)
		target.position.z = combat.screen_top()+.35
		_step(target,combat,.85)
		check(not combat.rounds.is_empty(),kind+" fires within 850 ms even at the maximum entry stagger")
		combat.free()
		combat = _range()
		target = _target(combat,kind,0)
		# A sustained twin-gun hit every 80 ms should damage an armed emplacement,
		# not erase the full defense line before its first visible counterattack.
		var damage_clock := 0.0
		for frame in range(120):
			_step(target,combat,DT)
			damage_clock += DT
			if damage_clock>=.08:
				damage_clock -= .08
				target.take_damage(2)
			if not target.alive or not combat.rounds.is_empty(): break
		check(target.alive and not combat.rounds.is_empty(),kind+" survives incoming standard fire long enough to counterattack")
		check(target.health<target.max_health,kind+" remains damageable during its initial warning")
		target.take_damage(target.health)
		check(not target.alive,kind+" has finite armor and can still be destroyed normally")
		combat.free()

func _run() -> void:
	for kind in ["battery","bunker"]:
		for sector in [0,3,7]: _pattern(kind,sector)
	for sector in [0,3,7]: _pattern("battery",sector,true)
	_interruptions()
	_silent_targets_and_pool()
	_progression()
	_entry_and_endurance()
	await process_frame
	if "--packaged" not in OS.get_cmdline_user_args():
		FileAccess.open("res://tests/ground-dca-results.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"patterns":summaries},"\t"))
	print("GROUND DCA TEST ",checks," checks, ",failures.size()," failures: ",failures)
	quit(0 if failures.is_empty() else 1)
