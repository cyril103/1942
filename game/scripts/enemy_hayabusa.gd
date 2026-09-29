extends "res://scripts/enemy_zero.gd"
enum AttackPhase { ENTRY, ROLL, DIVE, EXIT }
var attack_phase := AttackPhase.ENTRY
var side := -1.0
var roll_duration := 1.4
var roll_completed := false
var target_offset := 0.0
var maneuver_time := 0.0
var roll_radius := 0.45
var entry_heading := 1.35
var attack_heading := 0.55
var turn_rate := 0.0
var roll_offset := Vector3.ZERO
var attack_target := Vector3.ZERO
var roll_path_heading := 0.0
var roll_angle := 0.0

func _ready() -> void:
	model_scene = preload("res://assets/enemies/hayabusa.glb")
	propeller_name = "Hayabusa_Propeller"
	heading = -side * entry_heading
	rotation.y = heading
	super._ready()

func advance(delta: float, combat: Node) -> void:
	if not alive: return
	age += delta
	flash_time = maxf(0, flash_time - delta)
	flash.visible = flash_time > 0
	if is_instance_valid(propeller): propeller.rotate_z(delta * 65.0)
	if attack_phase == AttackPhase.ENTRY:
		position += Vector3(sin(heading), 0, cos(heading)) * flight_speed * delta
		var half_width := absf(combat.camera.project_position(Vector2.ZERO, combat.camera.position.y).x)
		if absf(position.x) < half_width - 2.0:
			attack_phase = AttackPhase.ROLL
			maneuver_time = 0.0
	elif attack_phase == AttackPhase.ROLL:
		maneuver_time += delta
		var p := clampf(maneuver_time / roll_duration, 0, 1)
		var ease := p*p*p*(10.0+p*(-15.0+6.0*p))
		roll_angle = side * TAU * ease
		roll_path_heading = -side * lerpf(entry_heading, attack_heading, ease)
		var forward := Vector3(sin(roll_path_heading), 0, cos(roll_path_heading))
		var right := Vector3(cos(roll_path_heading), 0, -sin(roll_path_heading))
		# A tapered helix, not a stationary rotation: climb, lateral sweep, descent.
		var envelope := pow(sin(PI*p), 2.0)
		var offset := right * roll_radius * 0.35 * sin(roll_angle) * envelope
		offset.y = roll_radius * (1.0-cos(roll_angle)) * envelope
		var displacement := forward * flight_speed * delta + offset - roll_offset
		position += Vector3(displacement.x, 0, displacement.z)
		visual.position.y = offset.y
		heading = atan2(displacement.x, displacement.z)
		visual.rotation.x = -atan2(displacement.y, Vector2(displacement.x,displacement.z).length())
		visual.rotation.z = roll_angle
		roll_offset = offset
		if p >= 1.0:
			roll_completed = true
			visual.rotation = Vector3.ZERO
			visual.position.y = 0
			attack_phase = AttackPhase.DIVE
			maneuver_time = 0
			attack_target = combat.player.position + Vector3(target_offset,0,2.0)
	elif attack_phase == AttackPhase.DIVE:
		maneuver_time += delta
		var to_target := attack_target - position
		var desired_heading := atan2(to_target.x, maxf(3.0, to_target.z))
		if position.z >= attack_target.z - 1.5:
			desired_heading = 0.0
		var error := wrapf(desired_heading-heading,-PI,PI)
		var desired_rate := clampf(error*2.0,-1.05,1.05)
		turn_rate = move_toward(turn_rate, desired_rate, delta*2.8)
		heading += turn_rate*delta
		position += Vector3(sin(heading),0,cos(heading))*flight_speed*delta
		bank = lerpf(bank,-clampf(atan(flight_speed*turn_rate/9.8),-0.70,0.70),1.0-exp(-delta*5.0))
		visual.rotation.z = bank
		shot_cooldown -= delta
		if maneuver_time >= 0.12 and shot_count < 3 and shot_cooldown <= 0:
			combat.fire_enemy(self)
			shot_count += 1
			shot_cooldown = 0.23
			flash_time = 0.065
		if absf(heading) < 0.06 and position.z >= attack_target.z:
			attack_phase = AttackPhase.EXIT
			phase = Phase.EXIT
	else:
		heading = move_toward(heading,0,delta*0.4)
		position += Vector3(sin(heading),0,cos(heading))*flight_speed*delta
		bank = lerpf(bank,0.0,1.0-exp(-delta*5.0))
		visual.rotation.z = bank
	rotation.y = heading
	if position.z > combat.screen_bottom() + 2.0 or age > 25.0: retire()
