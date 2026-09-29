extends Node3D
## Fixed-capacity pool. Inactive slots have no processing or collision bodies.
## Enemy colliders occupy physics layer 2, cross Y=0 and expose take_damage(amount).

const CAPACITY := 96
const SHOT_INTERVAL := 0.125
const SPEED := 32.0
const MAX_LIFETIME := 3.0
const ENEMY_MASK := 2
const MUZZLES := [Vector3(-0.43875, 0.0225, -0.2925), Vector3(0.43875, 0.0225, -0.2925)]

@export var player: Node3D
@export var camera: Camera3D

var projectiles: Array[MeshInstance3D] = []
var lifetimes := PackedFloat32Array()
var flashes: Array[MeshInstance3D] = []
var impacts: Array[MeshInstance3D] = []
var impact_times := PackedFloat32Array()
var _impact_cursor := 0
var active_count := 0
var shots_fired := 0
var _cooldown := 0.0
var _flash_time := 0.0
var _query := PhysicsRayQueryParameters3D.new()
var audio: Node


func _ready() -> void:
	audio = preload("res://scripts/weapon_audio.gd").new()
	audio.name = "WeaponAudio"
	add_child(audio)
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/tracer.gdshader")
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(0.16, 0.85)
	mesh.material = material
	lifetimes.resize(CAPACITY)
	for index in range(CAPACITY):
		var shot := MeshInstance3D.new()
		shot.mesh = mesh
		shot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		shot.hide()
		add_child(shot)
		projectiles.append(shot)
	for muzzle: Vector3 in MUZZLES:
		var flash := MeshInstance3D.new()
		flash.mesh = mesh
		flash.position = muzzle + Vector3(0.0, 0.015, -0.0975)
		flash.scale = Vector3(1.125, 1.0, 0.225)
		flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		player.bank.add_child(flash)
		flash.hide()
		flashes.append(flash)
	_query.collision_mask = ENEMY_MASK
	_query.collide_with_areas = true
	impact_times.resize(8)
	var impact_mesh := PlaneMesh.new()
	impact_mesh.size = Vector2.ONE
	for index in range(8):
		var impact := MeshInstance3D.new()
		impact.mesh = impact_mesh
		var impact_material := ShaderMaterial.new()
		impact_material.shader = preload("res://shaders/bullet_impact.gdshader")
		impact.material_override = impact_material
		impact.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(impact)
		impact.hide()
		impacts.append(impact)


func _physics_process(delta: float) -> void:
	for index in range(impacts.size()):
		impact_times[index] = maxf(0.0, impact_times[index] - delta)
		var remaining := impact_times[index] / 0.16
		impacts[index].visible = remaining > 0.0
		impacts[index].scale = Vector3.ONE * lerpf(1.2, 0.25, remaining)
		impacts[index].material_override.set_shader_parameter("intensity", remaining)
	var viewport := get_viewport().get_visible_rect()
	var space := get_world_3d().direct_space_state
	for index in range(CAPACITY):
		if lifetimes[index] <= 0.0:
			continue
		var shot := projectiles[index]
		var previous := shot.global_position
		shot.position.z -= SPEED * delta
		lifetimes[index] -= delta
		# Sweep the entire segment, on the gameplay plane regardless of bank.
		_query.from = Vector3(previous.x, 0.0, previous.z)
		_query.to = Vector3(shot.global_position.x, 0.0, shot.global_position.z)
		var hit := space.intersect_ray(_query)
		if not hit.is_empty():
			_show_impact(hit.position)
			var target: Object = hit.collider
			if target.has_method("take_damage"):
				target.take_damage(1)
			_release(index)
			continue
		var screen_position := camera.unproject_position(shot.global_position)
		if lifetimes[index] <= 0.0 or not viewport.has_point(screen_position):
			_release(index)
	_flash_time = maxf(0.0, _flash_time - delta)
	for flash in flashes:
		flash.visible = _flash_time > 0.0 and player.controls_enabled
	if not player.controls_enabled or not Input.is_action_pressed("fire"):
		_cooldown = 0.0
		return
	_cooldown -= delta
	if _cooldown <= 0.0:
		_fire_salvo()
		# Preserve fractional cadence, without generating a burst after a stall.
		_cooldown = maxf(_cooldown + SHOT_INTERVAL, 0.0)


func _fire_salvo() -> void:
	if active_count > CAPACITY - 2:
		return
	audio.play_salvo()
	for muzzle: Vector3 in MUZZLES:
		for index in range(CAPACITY):
			if lifetimes[index] > 0.0:
				continue
			var shot := projectiles[index]
			shot.global_position = player.bank.to_global(muzzle)
			shot.show()
			lifetimes[index] = MAX_LIFETIME
			active_count += 1
			shots_fired += 1
			break
	_flash_time = 0.045
	for flash in flashes:
		flash.show()


func _release(index: int) -> void:
	projectiles[index].hide()
	lifetimes[index] = 0.0
	active_count -= 1


func _show_impact(point: Vector3) -> void:
	var impact := impacts[_impact_cursor]
	impact.global_position = point + Vector3(0.0, 0.2, 0.0)
	impact.scale = Vector3.ONE * 0.25
	impact.material_override.set_shader_parameter("intensity", 1.0)
	impact.show()
	impact_times[_impact_cursor] = 0.16
	_impact_cursor = (_impact_cursor + 1) % impacts.size()
