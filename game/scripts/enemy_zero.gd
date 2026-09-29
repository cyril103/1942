extends Area3D

signal destroyed(at: Vector3)
const MODEL := preload("res://assets/enemies/zero.glb")
const SPEED := 10.0
const LOOP_DURATION := 2.5
enum Phase { APPROACH, LOOP, TURN, EXIT }

var model_scene: PackedScene = MODEL
var propeller_name := "Zero_Propeller"
var phase := Phase.APPROACH
var health := 2
var alive := true
var age := 0.0
var loop_time := 0.0
var shot_count := 0
var shot_cooldown := 0.0
var visual: Node3D
var propeller: Node3D
var flash: MeshInstance3D
var flash_time := 0.0
var loop_z := 0.0
var maneuver := 0 # 0: vertical loop, 1: broad banked arc
var turn_sign := 1.0
var entry := Vector3.ZERO
var anchor := Vector3.ZERO
var heading := 0.0
var bank := 0.0
var flight_speed := SPEED
var loop_duration := LOOP_DURATION
var approach_target_x := 0.0
var turn_duration := 2.6
var turn_angle := 0.55

func _ready() -> void:
	entry = position
	collision_layer = 2
	collision_mask = 0
	monitoring = false
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.575, 1.0, 1.040625)
	collider.shape = shape
	add_child(collider)
	visual = Node3D.new()
	add_child(visual)
	var model := model_scene.instantiate()
	model.scale = Vector3.ONE * 0.1575
	visual.add_child(model)
	propeller = model.find_child(propeller_name, true, false)
	flash = MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(0.365625, 0.478125)
	flash.mesh = mesh
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/bullet_impact.gdshader")
	flash.material_override = material
	flash.position = Vector3(0, 0.1125, 0.5625)
	visual.add_child(flash)
	flash.hide()

func advance(delta: float, combat: Node) -> void:
	if not alive:
		return
	age += delta
	flash_time = maxf(0, flash_time - delta)
	flash.visible = flash_time > 0
	if is_instance_valid(propeller):
		propeller.rotate_z(delta * 65.0)
	var target_bank := 0.0
	if phase == Phase.APPROACH:
		position.z = minf(loop_z, position.z + flight_speed * cos(heading) * delta)
		var distance := maxf(1.0, loop_z - entry.z)
		var p := clampf((position.z - entry.z) / distance, 0.0, 1.0)
		# Quintic easing: zero lateral velocity AND acceleration at both ends.
		var blend := p * p * p * (10.0 + p * (-15.0 + 6.0 * p))
		position.x = lerpf(entry.x, approach_target_x, blend)
		var slope := (approach_target_x - entry.x) * 30.0 * p * p * (1.0 - p) * (1.0 - p) / distance
		var next_heading := atan(slope)
		var rate := (next_heading - heading) / maxf(delta, 0.001)
		target_bank = -clampf(atan(flight_speed * rate / 9.8), -0.65, 0.65)
		heading = next_heading
		shot_cooldown -= delta
		if position.z >= loop_z - flight_speed * 0.68 and shot_count < 3 and shot_cooldown <= 0:
			combat.fire_enemy(self)
			shot_count += 1
			shot_cooldown = 0.20
			flash_time = 0.065
		if position.z >= loop_z - 0.00001:
			anchor = position
			heading = 0.0
			phase = Phase.LOOP if maneuver == 0 else Phase.TURN
	elif phase == Phase.LOOP:
		loop_time = minf(loop_duration, loop_time + delta)
		var p := loop_time / loop_duration
		# Ease pitch rate into/out of the loop while maintaining flight speed.
		var angle := TAU * p - sin(TAU * p)
		position.z += flight_speed * cos(angle) * delta
		visual.position.y += flight_speed * sin(angle) * delta
		visual.rotation.x = -angle
		visual.scale = Vector3.ONE * (1.0 + 0.035 * (1.0 - cos(angle)))
		if loop_time >= loop_duration - 0.00001:
			phase = Phase.EXIT
			visual.position.y = 0
			visual.rotation.x = 0
			visual.scale = Vector3.ONE
	elif phase == Phase.TURN:
		loop_time = minf(turn_duration, loop_time + delta)
		var p := loop_time / turn_duration
		# A broad banked arc replaces the abrupt full horizontal circle.
		heading = turn_sign * turn_angle * pow(sin(PI * p), 2.0)
		var rate := turn_sign * turn_angle * PI * sin(TAU * p) / turn_duration
		position += Vector3(sin(heading), 0, cos(heading)) * flight_speed * delta
		target_bank = -clampf(atan(flight_speed * rate / 9.8), -0.65, 0.65)
		if loop_time >= turn_duration - 0.00001:
			phase = Phase.EXIT
			heading = 0.0
	else:
		position.z += flight_speed * delta
	bank = lerpf(bank, target_bank, 1.0 - exp(-delta * 5.0))
	rotation.y = heading
	visual.rotation.z = bank
	if position.z > combat.screen_bottom() + 2.0 or age > 35.0:
		retire()

func take_damage(amount: int) -> void:
	if not alive:
		return
	health -= amount
	if health <= 0:
		destroyed.emit(global_position + visual.position)
		retire()

func retire() -> void:
	alive = false
	collision_layer = 0
	hide()
	queue_free()
