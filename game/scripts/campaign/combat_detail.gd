extends Node3D
## Fixed GPU batch for opaque fragments and two wing trails; no rigid bodies.
const CAPACITY := 64
var batch: MultiMeshInstance3D
var lifetimes := PackedFloat32Array()
var positions := PackedVector3Array()
var velocities := PackedVector3Array()
var cursor := 0
var trails: Array[MeshInstance3D] = []
var player: Node3D
var enabled := true
var water_altitude := -2.9
var presentation_altitude := 0.0
var grounded := PackedByteArray()

func set_presentation_altitude(altitude: float) -> void:
	var change := altitude-presentation_altitude
	presentation_altitude = altitude
	if is_zero_approx(change): return
	for i in range(CAPACITY):
		if lifetimes[i]>0 and grounded[i]==0: positions[i].y += change

func _ready() -> void:
	batch = MultiMeshInstance3D.new()
	batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	batch.multimesh = MultiMesh.new()
	batch.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	batch.multimesh.use_colors = true
	var mesh := BoxMesh.new()
	mesh.size = Vector3(.10,.045,.18)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mesh.material = mat
	batch.multimesh.mesh = mesh
	batch.multimesh.instance_count = CAPACITY
	add_child(batch)
	lifetimes.resize(CAPACITY)
	positions.resize(CAPACITY)
	velocities.resize(CAPACITY)
	grounded.resize(CAPACITY)
	for i in range(CAPACITY): batch.multimesh.set_instance_transform(i,Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO),Vector3.ZERO))
	for side in [-1,1]:
		var trail := make_card(2,Vector2(.24,1.8))
		trail.set_meta("side",side)
		add_child(trail)
		trail.hide()
		trails.append(trail)

static func make_card(kind: int, size: Vector2) -> MeshInstance3D:
	var card := MeshInstance3D.new()
	card.mesh = PlaneMesh.new()
	card.mesh.size = size
	card.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/combat_detail.gdshader")
	mat.set_shader_parameter("kind",kind)
	card.material_override = mat
	return card

func burst(at: Vector3, naval := false, ground := false) -> void:
	if not enabled: return
	for i in range(8 if naval else 5):
		var slot := cursor%CAPACITY
		cursor += 1
		var angle := float(cursor)*2.39996
		positions[slot] = at
		grounded[slot] = 1 if ground else 0
		velocities[slot] = Vector3(cos(angle)*2.2,1.4+sin(angle)*.6,sin(angle)*2.2)
		lifetimes[slot] = 1.4
		batch.multimesh.set_instance_color(slot,Color(1,.49,.12) if i%3==0 else Color(.3,.35,.39))

func _physics_process(delta: float) -> void:
	visible = enabled
	if not enabled: return
	for i in range(CAPACITY):
		if lifetimes[i]<=0: continue
		lifetimes[i] = maxf(0,lifetimes[i]-delta)
		velocities[i].y -= delta*6.0
		positions[i] += velocities[i]*delta
		if positions[i].y<water_altitude+.05:
			lifetimes[i] = 0
		var basis := Basis(Vector3(1,.4,.2).normalized(),lifetimes[i]*9)
		if lifetimes[i]<=0: basis = basis.scaled(Vector3.ZERO)
		batch.multimesh.set_instance_transform(i,Transform3D(basis,positions[i]))
	if not is_instance_valid(player): return
	for trail in trails:
		trail.visible = player.alive and player.controls_enabled and absf(player.bank.rotation.z)>.18
		trail.position = player.bank.global_position+Vector3(float(trail.get_meta("side"))*.64,-.08,1.05)
		trail.material_override.set_shader_parameter("strength",clampf(absf(player.bank.rotation.z)*2,0,1))
