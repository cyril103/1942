extends SceneTree
## Pattern geometry plus the production warning/burst/phase state machine.
const BOSS := preload("res://scripts/campaign/boss.gd")
const PATTERNS := preload("res://scripts/campaign/boss_patterns.gd")
const BALANCE := preload("res://scripts/campaign/balance.gd")
var checks := 0
var failures: Array[String] = []

class Pilot extends Node3D:
	var alive := true

class Combat extends Node3D:
	var camera: Camera3D
	var presentation_altitude := 0.0
	var enemy_interval_scale := 1.0
	var campaign_driver: Node
	var shots: Array[Dictionary] = []
	var clears := 0
	func _launch_enemy_round(origin: Vector3,target: Vector3,speed: float) -> bool:
		shots.append({"origin":origin,"direction":(target-origin).normalized(),"speed":speed})
		return true
	func clear_enemy_bullets() -> void: clears += 1
	func navigate_naval(_ship: Node3D,_offset := 0.0) -> void: pass
	func _explode(_at: Vector3,_size: float,_sound := false) -> void: pass

class Director extends Node:
	var combat: Combat
	var player: Pilot
	var mission := {"sector":8}
	var balance := BALANCE.settings(32,1)
	var feedback := ""
	var feedback_time := 0.0
	var reinforcements := 0
	func spawn_reinforcement() -> void: reinforcements += 1

func check(ok: bool,message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func _initialize() -> void: _run.call_deferred()

func _has_trajectory_mesh(boss: Node3D) -> bool:
	# The removed warning pool was world-aligned thin BoxMeshes. Check actual
	# scene children, including hidden nodes, rather than just current visibility.
	for child in boss.get_children():
		if child is MeshInstance3D and (child.top_level or child.mesh is BoxMesh):
			return true
	return false

func _emission_contracts(boss: Node3D, director: Director) -> void:
	for phase in range(3):
		for attack in range(1,7):
			boss._cancel_attack()
			boss.age = 5
			boss.phase = phase
			boss.previous_phase = phase
			boss.health = boss.max_health*(1.0-phase*.34)
			boss.volley = attack-1
			boss.position = Vector3(1,0,-6)
			director.player.position = Vector3(3,0,8)
			director.combat.shots.clear()
			var nodes := boss.get_child_count()
			var expected := PATTERNS.build(boss.kind,phase,attack,boss.global_position+Vector3(0,.22,1),director.player.global_position,int(director.mission.sector),director.balance,boss.component_health)
			var context := "%s phase%d attack%d" % [boss.kind,phase,attack]
			boss._begin_attack(director)
			check(not _has_trajectory_mesh(boss) and boss.get_child_count()==nodes,"No prediction geometry is allocated for "+context)
			check(is_equal_approx(boss.telegraph,float(expected.warning)),"Original warning duration retained for "+context)
			var hud: Dictionary = boss.presentation()
			check(hud.state=="charging" and hud.label==expected.label and hud.hint==expected.hint and boss.flare.visible,"HUD and local warning remain available for "+context)
			director.player.position = Vector3(-7,0,12)
			boss.advance(float(expected.warning)-.0001,director)
			check(director.combat.shots.is_empty(),"No projectile before the complete original delay for "+context)
			boss.advance(.0002,director)
			for tick in range(14):
				if tick>0: boss.advance(.05,director)
				var expected_count := 0
				for round in expected.rounds:
					if float(round.delay)<=tick*.05+.00001: expected_count+=1
				check(director.combat.shots.size()==expected_count,"Original burst schedule at %.2fs: %s" % [tick*.05,context])
			var same_rounds: bool = director.combat.shots.size()==expected.rounds.size()
			for index in range(mini(director.combat.shots.size(),expected.rounds.size())):
				var fired: Dictionary = director.combat.shots[index]
				var planned: Dictionary = expected.rounds[index]
				same_rounds = same_rounds and fired.origin.is_equal_approx(planned.origin) and fired.direction.is_equal_approx(planned.direction) and is_equal_approx(fired.speed,planned.speed)
			check(same_rounds,"Origins, locked aim and projectile speeds unchanged for "+context)
			check(is_equal_approx(boss.cooldown,(1.55-phase*.18)*director.combat.enemy_interval_scale-.65),"Original inter-attack cadence retained for "+context)
			check(not boss.flare.visible and not _has_trajectory_mesh(boss) and boss.get_child_count()==nodes,"Attack release leaves no prediction geometry for "+context)
	boss._cancel_attack()
	boss.phase = 0
	boss.previous_phase = 0
	boss.health = boss.max_health
	boss.volley = 0
	boss.motion_age = 0
	boss.position = Vector3.ZERO

func _geometry() -> void:
	var signatures := {}
	var intact: Array[float] = [24,24]
	var origin := Vector3(1,.22,-5)
	var target := Vector3(2,0,8)
	for kind in BOSS.MODELS:
		var signature := ""
		for phase in range(3):
			for mission in [4,8,32]:
				for volley in range(1,7):
					var balance := BALANCE.settings(mission,1)
					var plan := PATTERNS.build(kind,phase,volley,origin,target,8,balance,intact)
					var context := "%s phase%d mission%d volley%d" % [kind,phase,mission,volley]
					check(plan.rounds.size()>0 and plan.rounds.size()<=PATTERNS.MAX_ROUNDS,"Projectile budget: "+context)
					check(plan.warning>=.7 and plan.warning<=1.1 and not str(plan.label).is_empty() and not str(plan.hint).is_empty(),"Usable warning: "+context)
					var previous := -1.0
					var valid := true
					for round in plan.rounds:
						valid = valid and round.origin.is_finite() and round.direction.is_finite() and is_equal_approx(round.direction.length(),1.0)
						valid = valid and round.speed>0 and round.speed<=11 and round.delay>=previous and round.delay<=PATTERNS.MAX_BURST_TIME
						previous = float(round.delay)
					check(valid,"Finite sorted readable trajectories: "+context)
					var broken: Array[float] = [0,0]
					var weakened := PATTERNS.build(kind,phase,volley,origin,target,8,balance,broken)
					check(weakened.rounds.size()<plan.rounds.size(),"Both destroyed components reduce every pattern: "+context)
					if phase==2 and mission==32: signature += var_to_str(plan.rounds)
		signatures[signature] = true
	# Each signature spans all its phases; no boss is a cosmetic rename.
	check(signatures.size()==8,"Eight distinct authored boss signatures")
	var gate_signatures: Array[float] = []
	for volley in [2,4,8,10]:
		var plan := PATTERNS.build("citadel",2,volley,origin,target,7,BALANCE.settings(32,1),intact)
		var centroid := 0.0
		for round in plan.rounds: centroid += float(round.origin.x)
		gate_signatures.append(centroid)
	check(not is_equal_approx(gate_signatures[0],gate_signatures[1]),"Citadel's announced gate really changes between successive combs")
	check(is_equal_approx(gate_signatures[0],gate_signatures[2]) and is_equal_approx(gate_signatures[1],gate_signatures[3]),"Intervening rings do not break the alternating escape-lane sequence")
	# Without projected trajectories, the verbal warning itself identifies the
	# escape side. Measure the actual largest angular gap, independently of the hint.
	for volley in [3,6,9,12]:
		var plan := PATTERNS.build("citadel",2,volley,origin,target,8,BALANCE.settings(32,1),intact)
		var angles: Array[float] = []
		for round in plan.rounds: angles.append(fposmod(atan2(round.direction.x,round.direction.z),TAU))
		angles.sort()
		var largest := 0.0
		var opening := 0.0
		for index in range(angles.size()):
			var next := angles[(index+1)%angles.size()] + (TAU if index==angles.size()-1 else 0.0)
			var width := next-angles[index]
			if width>largest:
				largest = width
				opening = angles[index]+width*.5
		var expected_side := "DROITE" if sin(opening)>0 else "GAUCHE"
		check(str(plan.hint).ends_with(expected_side),"Citadel HUD warning names its measured escape side for volley %d" % volley)
		check(is_equal_approx(largest,PI*.5) and cos(opening)>0,"Announced Citadel exit is a forward 90-degree gap")
	for kind in ["bomber","fortress","carrier","citadel"]:
		var plan := PATTERNS.build(kind,2,3,origin,target,8,BALANCE.settings(32,1),intact)
		var gap := clampf(atan2(target.x-origin.x,target.z-origin.z),-.55,.55)
		if kind=="fortress": gap=-.4
		if kind=="citadel": gap=-.55
		check(plan.rounds.size()==10,"Ring quota preserved for "+kind)
		var clear_gap := true
		for round in plan.rounds:
			var angle := atan2(round.direction.x,round.direction.z)
			clear_gap = clear_gap and absf(wrapf(angle-gap,-PI,PI))>=PI*.25-.0001
		check(clear_gap,"Forward ring exit remains 90 degrees wide for "+kind)
	for mission in [4,8,32]:
		var plan := PATTERNS.build("bomber",2,3,origin,target,8,BALANCE.settings(mission,1),intact)
		check(plan.rounds.size()==(3 if mission==4 else (5 if mission==8 else 10)),"Opening/mid/late campaign projectile quotas preserved")

func _runtime() -> void:
	var director := Director.new()
	director.combat = Combat.new()
	director.player = Pilot.new()
	root.add_child(director)
	root.add_child(director.combat)
	root.add_child(director.player)
	director.combat.campaign_driver = director
	director.combat.camera = Camera3D.new()
	director.combat.add_child(director.combat.camera)
	director.combat.camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	director.combat.camera.size = 24
	director.combat.camera.position = Vector3(0,25,0)
	director.combat.camera.rotation.x = -PI*.5
	for kind in BOSS.MODELS:
		var boss := BOSS.new()
		boss.kind = kind
		boss.combat = director.combat
		director.combat.add_child(boss)
		director.player.alive = true
		_emission_contracts(boss,director)
		boss.age = 5
		boss.cooldown = 0
		director.player.position = Vector3(3,0,8)
		director.player.alive = true
		director.combat.shots.clear()
		boss.advance(.01,director)
		check(boss.attack_state=="charging" and director.combat.shots.is_empty(),kind+" warns before its first round")
		var locked: Array = boss.attack_plan.rounds.duplicate(true)
		var frozen: Vector3 = boss.global_position
		var charge: float = boss.telegraph
		director.player.position = Vector3(-7,0,12)
		boss.advance(charge*.5,director)
		check(director.combat.shots.is_empty() and boss.global_position.is_equal_approx(frozen),kind+" locks aim and origins for the complete warning")
		check(is_equal_approx(boss.attack_progress,.5),kind+" exposes accurate HUD progress")
		boss.advance(charge*.5+.001,director)
		boss.advance(PATTERNS.MAX_BURST_TIME+.01,director)
		check(director.combat.shots.size()==locked.size(),kind+" releases exactly its announced pattern")
		var faithful := true
		for i in range(locked.size()):
			faithful = faithful and director.combat.shots[i].origin.is_equal_approx(locked[i].origin) and director.combat.shots[i].direction.is_equal_approx(locked[i].direction)
		check(faithful,kind+" never retargets already announced rounds")
		check(not boss.flare.visible and not _has_trajectory_mesh(boss),kind+" clears its local warning without any prediction lines")
		boss._begin_attack(director)
		var before: int = director.combat.shots.size()
		boss.health = boss.max_health*.6
		boss.advance(.01,director)
		check(boss.attack_state=="transition" and boss.attack_plan.is_empty() and boss.pending_rounds.is_empty(),kind+" phase transition cancels all queued fire")
		var protected_health: float = boss.health
		boss.take_damage(50)
		boss.advance(1.2,director)
		check(director.combat.shots.size()==before and boss.health==protected_health,kind+" transition is a genuine invulnerable ceasefire")
		boss.advance(.01,director)
		check(boss.telegraph==0 and boss.cooldown>0,kind+" grants recovery after its transition")
		boss._begin_attack(director)
		boss.advance(boss.telegraph+.001,director)
		before = director.combat.shots.size()
		boss.health = boss.max_health*.25
		boss.advance(.01,director)
		boss.advance(1.2,director)
		check(director.combat.shots.size()==before and boss.pending_rounds.is_empty(),kind+" interrupts even a partly released burst on the next phase")
		boss._begin_attack(director)
		director.player.alive = false
		boss.advance(.1,director)
		check(boss.telegraph==0 and boss.pending_rounds.is_empty() and director.combat.shots.size()==before,kind+" cancels attacks when player dies")
		director.player.alive = true
		boss._begin_attack(director)
		boss.take_damage(boss.health)
		check(boss.dying and boss.attack_state=="defeated" and boss.attack_plan.is_empty() and boss.pending_rounds.is_empty(),kind+" death retires every attack")
		boss.queue_free()
		await process_frame
	director.combat.queue_free()
	director.player.queue_free()
	director.queue_free()
	await process_frame

func _run() -> void:
	_geometry()
	await _runtime()
	print("BOSS PATTERNS: ",checks," checks; failures: ",failures)
	quit(0 if failures.is_empty() else 1)
