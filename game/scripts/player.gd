extends Node3D
signal destroyed(at: Vector3)
signal damaged(remaining: int)
signal respawned
const RESPAWN_PROTECTION := 4.0
var max_health := 1
var health := 1
var focus_enabled := false
var hit_invulnerability_multiplier := 1.0
## Motion stays on the XZ plane; only the visual child banks.

@export var camera: Camera3D
@export_range(1.0, 30.0, 0.5) var speed: float = 9.0
@export_range(0.0, 60.0, 1.0) var max_bank_degrees: float = 28.0
@export_range(1.0, 30.0, 0.5) var bank_response: float = 10.0
@export var screen_margin_pixels: float = 12.0

@onready var bank: Node3D = $Bank
var _model_bounds: AABB
var _bounds_initialized: bool = false
var controls_enabled: bool = true
var alive: bool = true
var invulnerable_time := 0.0
var aircraft_index := 0
var propellers: Array[Node3D] = []

func configure_aircraft(index: int) -> void:
	aircraft_index = clampi(index,0,2)
	if aircraft_index == 0: return
	var old := bank.get_node("Aircraft") as Node3D
	var pose := old.transform
	bank.remove_child(old)
	old.queue_free()
	var resource := "res://assets/player-fleet/p38.glb" if aircraft_index == 1 else "res://assets/player-fleet/f4u.glb"
	var model := (load(resource) as PackedScene).instantiate() as Node3D
	model.name = "Aircraft"
	model.transform = pose
	bank.add_child(model)
	if aircraft_index == 1:
		for node in model.find_children("*","MeshInstance3D",true,false):
			for surface in range(node.mesh.get_surface_count()):
				var source = node.mesh.surface_get_material(surface)
				if source is StandardMaterial3D and source.resource_name == "Aircraft_skin":
					var tuned := source.duplicate() as StandardMaterial3D
					tuned.albedo_color = Color(.62,.66,.72)
					tuned.metallic = .35
					tuned.roughness = .58
					node.set_surface_override_material(surface,tuned)
	propellers.clear()
	for name_text in ["Propeller_L","Propeller_R","Propeller_Center"]:
		var prop := model.find_child(name_text,true,false) as Node3D
		if prop != null: propellers.append(prop)
	_bounds_initialized = false
	_collect_bounds(model)
	_keep_inside_screen()

func _process(delta: float) -> void:
	if not alive: return
	for i in range(propellers.size()):
		propellers[i].rotate_z(delta*65.0*(-1.0 if aircraft_index==1 and i==1 else 1.0))


func take_damage(amount: int) -> void:
	if not alive or not controls_enabled or amount <= 0 or invulnerable_time > 0:
		return
	health = maxi(0,health-amount)
	damaged.emit(health)
	if health > 0:
		invulnerable_time = 0.85*hit_invulnerability_multiplier
		return
	alive = false
	controls_enabled = false
	hide()
	destroyed.emit(global_position)


func respawn(at: Vector3) -> void:
	position = at
	bank.rotation = Vector3.ZERO
	bank.scale = Vector3.ONE
	bank.show()
	alive = true
	health = max_health
	controls_enabled = true
	invulnerable_time = RESPAWN_PROTECTION
	set_physics_process(true)
	show()
	_keep_inside_screen()
	respawned.emit()


func _ready() -> void:
	_collect_bounds(bank)
	get_viewport().size_changed.connect(_keep_inside_screen)
	_keep_inside_screen.call_deferred()


func _physics_process(delta: float) -> void:
	if invulnerable_time > 0:
		invulnerable_time = maxf(0,invulnerable_time-delta)
		bank.visible = invulnerable_time <= 0 or fmod(invulnerable_time,0.25)<0.14
	if not controls_enabled:
		return
	var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var motion_speed := speed
	if focus_enabled and Input.is_action_pressed("focus_flight"): motion_speed *= 0.48
	position += Vector3(direction.x, 0.0, direction.y) * motion_speed * delta
	# Negative Z rotation lowers the right wing when steering right.
	var target_bank := -direction.x * deg_to_rad(max_bank_degrees)
	bank.rotation.z = lerpf(bank.rotation.z, target_bank, 1.0 - exp(-bank_response * delta))
	_keep_inside_screen()


func _collect_bounds(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh != null:
			var relative := bank.global_transform.affine_inverse() * mesh_node.global_transform
			var bounds: AABB = relative * mesh_node.get_aabb()
			if _bounds_initialized:
				_model_bounds = _model_bounds.merge(bounds)
			else:
				_model_bounds = bounds
				_bounds_initialized = true
	for child in node.get_children():
		_collect_bounds(child)


func get_screen_bounds() -> Rect2:
	var first := camera.unproject_position(bank.global_transform * _model_bounds.get_endpoint(0))
	var result := Rect2(first, Vector2.ZERO)
	for corner in range(1, 8):
		var point := bank.global_transform * _model_bounds.get_endpoint(corner)
		result = result.expand(camera.unproject_position(point))
	return result


func _keep_inside_screen() -> void:
	if not is_instance_valid(camera) or not _bounds_initialized:
		return
	var viewport_size := get_viewport().get_visible_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	var bounds := get_screen_bounds()
	var offset := Vector2.ZERO
	var margin := screen_margin_pixels
	if bounds.position.x < margin:
		offset.x = margin - bounds.position.x
	elif bounds.end.x > viewport_size.x - margin:
		offset.x = viewport_size.x - margin - bounds.end.x
	if bounds.position.y < margin:
		offset.y = margin - bounds.position.y
	elif bounds.end.y > viewport_size.y - margin:
		offset.y = viewport_size.y - margin - bounds.end.y
	if not offset.is_zero_approx():
		var center := viewport_size * 0.5
		var depth := camera.global_position.distance_to(global_position)
		global_position += camera.project_position(center + offset, depth) - camera.project_position(center, depth)
