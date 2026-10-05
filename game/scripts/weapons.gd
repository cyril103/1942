extends Node3D
## Fixed-capacity pool. Inactive slots have no processing or collision bodies.
## Enemy colliders occupy physics layer 2, cross Y=0 and expose take_damage(amount).

const CAPACITY := 96
const SHOT_INTERVAL := 0.125
const SPEED := 32.0
const MAX_LIFETIME := 3.0
const ENEMY_MASK := 2
const LASER_WIDTH := 0.96
const LASER_SAMPLES := 9
const MUZZLES := [Vector3(-0.43875, 0.0225, -0.2925), Vector3(0.43875, 0.0225, -0.2925)]

@export var player: Node3D
@export var camera: Camera3D

var projectiles: Array[MeshInstance3D] = []
var lifetimes := PackedFloat32Array()
var velocities := PackedVector3Array()
var spread_enabled := false
var power_type := "none"
var laser: MeshInstance3D
var laser_clock := 0.0
var laser_muzzle: MeshInstance3D
var laser_contact: MeshInstance3D
var laser_audio: AudioStreamPlayer
var shot_interval := SHOT_INTERVAL
var projectile_damage := 1
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
	player.destroyed.connect(_on_player_destroyed)
	audio = preload("res://scripts/weapon_audio.gd").new()
	audio.name = "WeaponAudio"
	add_child(audio)
	laser = MeshInstance3D.new()
	var beam := PlaneMesh.new()
	beam.size = Vector2(2.1,1)
	laser.mesh = beam
	var beam_material := ShaderMaterial.new()
	beam_material.shader = preload("res://shaders/player_laser.gdshader")
	laser.material_override = beam_material
	laser.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(laser)
	laser.hide()
	laser_muzzle = _make_laser_flare(1.35)
	laser_contact = _make_laser_flare(1.8)
	laser_audio = AudioStreamPlayer.new()
	var laser_loop: AudioStreamWAV = preload("res://assets/campaign/laser-loop.wav").duplicate()
	laser_loop.loop_mode = AudioStreamWAV.LOOP_FORWARD
	laser_loop.loop_end = roundi(laser_loop.get_length()*laser_loop.mix_rate)
	laser_audio.stream = laser_loop
	laser_audio.volume_db = -15
	add_child(laser_audio)
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/tracer.gdshader")
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(0.28, 1.05)
	mesh.material = material
	lifetimes.resize(CAPACITY)
	velocities.resize(CAPACITY)
	velocities.fill(Vector3(0,0,-SPEED))
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
	_update_laser(delta)
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
		shot.position += velocities[index] * delta
		lifetimes[index] -= delta
		# Sweep the entire segment, on the gameplay plane regardless of bank.
		_query.from = Vector3(previous.x, 0.0, previous.z)
		_query.to = Vector3(shot.global_position.x, 0.0, shot.global_position.z)
		var hit := space.intersect_ray(_query)
		if not hit.is_empty():
			_show_impact(hit.position)
			var target: Object = hit.collider
			if target.has_method("take_damage"):
				target.take_damage(projectile_damage)
			_release(index)
			continue
		var screen_position := camera.unproject_position(shot.global_position)
		if lifetimes[index] <= 0.0 or not viewport.has_point(screen_position):
			_release(index)
	_flash_time = maxf(0.0, _flash_time - delta)
	for flash in flashes:
		flash.visible = _flash_time > 0.0 and player.controls_enabled
	if not player.controls_enabled or not Input.is_action_pressed("fire") or power_type == "laser":
		_cooldown = 0.0
		return
	_cooldown -= delta
	if _cooldown <= 0.0:
		_fire_salvo()
		# Preserve fractional cadence, without generating a burst after a stall.
		_cooldown = maxf(_cooldown + shot_interval, 0.0)


func _fire_salvo() -> void:
	var count := 4 if spread_enabled else 2
	if active_count > CAPACITY - count:
		return
	audio.play_salvo()
	for barrel in range(count):
		var muzzle: Vector3 = MUZZLES[barrel / 2 if spread_enabled else barrel]
		var angle := deg_to_rad([-15.0,-5.0,5.0,15.0][barrel]) if spread_enabled else 0.0
		for index in range(CAPACITY):
			if lifetimes[index] > 0.0:
				continue
			var shot := projectiles[index]
			shot.global_position = player.bank.to_global(muzzle)
			velocities[index] = Vector3(sin(angle),0,-cos(angle))*SPEED
			shot.rotation.y = -angle
			shot.scale = Vector3(1.45,1,1.18) if spread_enabled else Vector3.ONE
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

func upgrade_spread() -> void:
	set_power("spread")

func set_power(kind: String) -> void:
	cease_fire()
	power_type = kind if kind in ["spread","laser","life"] else "none"
	spread_enabled = power_type == "spread"
	audio.volume_db = -6.0 if spread_enabled else -5.0
	for flash in flashes: flash.scale = Vector3(1.55,1,0.30) if spread_enabled else Vector3(1.125,1,0.225)

func cease_fire() -> void:
	for i in range(CAPACITY):
		if lifetimes[i] > 0: _release(i)
	if is_instance_valid(laser): laser.hide()
	if is_instance_valid(laser_muzzle): laser_muzzle.hide()
	if is_instance_valid(laser_contact): laser_contact.hide()
	if is_instance_valid(laser_audio): laser_audio.stop()
	for flash in flashes: flash.hide()

func _update_laser(delta: float) -> void:
	var firing: bool = power_type == "laser" and player.alive and player.controls_enabled and Input.is_action_pressed("fire")
	laser.visible = firing
	laser_muzzle.visible = firing
	laser_contact.hide()
	if not firing:
		laser_clock = 0
		laser_audio.stop()
		return
	if not laser_audio.playing: laser_audio.play()
	var origin := player.global_position+Vector3(0,0,-0.55)
	var end := Vector3(origin.x,0,camera.project_position(Vector2.ZERO,camera.position.y).z-1)
	# Parallel sweeps cover the luminous core, select the closest obstruction once.
	# A single target takes damage per tick, irrespective of how many rays touch it.
	var hit: Dictionary = {}
	var nearest_z := end.z
	var space := get_world_3d().direct_space_state
	for sample in range(LASER_SAMPLES):
		var offset := lerpf(-LASER_WIDTH*.5,LASER_WIDTH*.5,float(sample)/(LASER_SAMPLES-1))
		_query.from = Vector3(origin.x+offset,0,origin.z)
		_query.to = Vector3(end.x+offset,0,end.z)
		var candidate := space.intersect_ray(_query)
		if not candidate.is_empty() and candidate.position.z > nearest_z:
			nearest_z = candidate.position.z
			hit = candidate
	if not hit.is_empty(): end.z = nearest_z
	var length := maxf(.1,absf(end.z-origin.z))
	laser.global_position = (origin+end)*.5+Vector3(0,.25,0)
	laser.scale.z = length
	laser.material_override.set_shader_parameter("beam_length",length)
	laser_muzzle.global_position = origin+Vector3(0,.3,0)
	laser_contact.visible = not hit.is_empty()
	laser_contact.global_position = end+Vector3(0,.3,0)
	laser_clock -= delta
	if laser_clock <= 0:
		laser_clock += .1
		shots_fired += 1
		if not hit.is_empty() and hit.collider.has_method("take_damage"):
			hit.collider.take_damage(2+projectile_damage)
			_show_impact(end)

func _make_laser_flare(size: float) -> MeshInstance3D:
	var effect := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE*size
	effect.mesh = plane
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/laser_flare.gdshader")
	effect.material_override = material
	effect.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(effect)
	effect.hide()
	return effect

func _on_player_destroyed(_at: Vector3) -> void:
	set_power("none")
