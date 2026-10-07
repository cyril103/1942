extends "res://scripts/enemy_zero.gd"
## All five aircraft sample the same baked curve at a fixed distance offset.
signal escaped
var route: Curve3D
var slot := 0
var spacing := 3.2
var path_speed := 7.0
var distance := 0.0
var destroyed_by_player := false

func _ready() -> void:
	super._ready()
	distance = -slot*spacing
	for mesh in visual.find_children("*","MeshInstance3D",true,false):
		if mesh == flash: continue
		var original = mesh.get_active_material(0)
		if original is StandardMaterial3D and original.albedo_texture:
			var paint := ShaderMaterial.new()
			paint.shader = preload("res://shaders/red_squadron.gdshader")
			paint.set_shader_parameter("paint",original.albedo_texture)
			mesh.material_overlay = paint
	_update_pose(0.0)

func _update_pose(delta: float) -> void:
	visible = distance >= 0
	collision_layer = 2 if visible else 0
	if not visible: return
	var sample_distance := clampf(distance,0,route.get_baked_length())
	position = route.sample_baked(sample_distance,true)
	var ahead := route.sample_baked(minf(route.get_baked_length(),sample_distance+0.06),true)
	var behind := route.sample_baked(maxf(0,sample_distance-0.06),true)
	var tangent := ahead-behind
	var next_heading := atan2(tangent.x,tangent.z)
	if delta > 0:
		var rate := wrapf(next_heading-heading,-PI,PI)/delta
		bank = lerpf(bank,-clampf(atan(path_speed*rate/9.8),-0.72,0.72),1-exp(-5*delta))
	heading = next_heading
	rotation.y = heading
	visual.rotation.z = bank

func advance(delta: float, _combat: Node) -> void:
	if not alive: return
	age += delta
	var was_visible := distance >= 0
	distance += path_speed*delta
	if distance > route.get_baked_length():
		retire()
		return
	_update_pose(delta if was_visible else 0.0)
	if is_instance_valid(propeller): propeller.rotate_z(delta*65)

func take_damage(amount: float) -> void:
	if not alive or distance < 0 or amount <= 0 or not is_finite(amount): return
	if health-amount <= 0: destroyed_by_player = true
	super.take_damage(amount)

func retire() -> void:
	if not alive: return
	if not destroyed_by_player: escaped.emit()
	super.retire()
