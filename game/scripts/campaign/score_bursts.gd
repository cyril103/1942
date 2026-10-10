extends Node3D
## Three reusable world-space awards. No per-kill text, timers or particle nodes.
const CAPACITY := 3
const DURATION := 1.65
const NUMBER_FONT := preload("res://assets/ui/fonts/BlackOpsOne-Regular.ttf")
const SMALL_FONT := preload("res://assets/ui/fonts/BarlowCondensed-Medium.ttf")
var camera: Camera3D
var slots: Array[Node3D] = []
var ages := PackedFloat64Array()
var origins := PackedVector3Array()
var cursor := 0
var reduced_flash := false

func _ready() -> void:
	ages.resize(CAPACITY)
	origins.resize(CAPACITY)
	ages.fill(DURATION)
	for i in range(CAPACITY):
		var slot := Node3D.new()
		add_child(slot)
		var title := _label(SMALL_FONT, 38, .011)
		title.name = "Title"
		title.position.z = -.36
		slot.add_child(title)
		var points := _label(NUMBER_FONT, 72, .014)
		points.name = "Points"
		points.position.z = .22
		slot.add_child(points)
		var accent := MeshInstance3D.new()
		accent.name = "Accent"
		var mesh := PlaneMesh.new()
		mesh.size = Vector2(5.2, 1.65)
		accent.mesh = mesh
		accent.position.y = -.06
		accent.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var material := ShaderMaterial.new()
		material.shader = preload("res://shaders/score_award.gdshader")
		accent.material_override = material
		slot.add_child(accent)
		slot.hide()
		slots.append(slot)

func _label(font: Font, size: int, pixel: float) -> Label3D:
	var label := Label3D.new()
	label.font = font
	label.font_size = size
	label.pixel_size = pixel
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.outline_size = 10
	label.outline_modulate = Color(.02,.035,.045,.95)
	label.modulate = Color(1,.83,.43)
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return label

func show_award(at: Vector3, bonus: int, red := false) -> void:
	if not is_instance_valid(camera): return
	var slot := slots[cursor]
	# Keep the whole award inside the playfield, above the player's usual lane.
	var size := get_viewport().get_visible_rect().size
	var projected := camera.unproject_position(at)
	projected.x = clampf(projected.x, size.x*.18, size.x*.82)
	projected.y = clampf(projected.y, size.y*.18, size.y*.57)
	for i in range(CAPACITY):
		if ages[i] >= DURATION or i == cursor: continue
		var other := camera.unproject_position(origins[i])
		if absf(other.x-projected.x)<size.x*.22 and absf(other.y-projected.y)<size.y*.14:
			projected.y = clampf(projected.y+size.y*.15,size.y*.18,size.y*.72)
	var ray := camera.project_ray_origin(projected)
	var direction := camera.project_ray_normal(projected)
	var altitude := at.y+.9
	origins[cursor] = ray+direction*((altitude-ray.y)/direction.y)
	ages[cursor] = 0
	slot.get_node("Title").text = "ESCADRILLE ROUGE" if red else "VAGUE PARFAITE"
	slot.get_node("Points").text = "+%d" % bonus
	slot.show()
	cursor = (cursor+1)%CAPACITY
	advance(0)

func _physics_process(delta: float) -> void:
	advance(delta)

func advance(delta: float) -> void:
	for i in range(CAPACITY):
		if ages[i] >= DURATION: continue
		ages[i] = minf(DURATION, ages[i]+delta)
		var t := ages[i]
		var slot := slots[i]
		slot.visible = t < DURATION
		var rise := 1.0-exp(-t*3.5)
		slot.position = origins[i]+Vector3(0,t*.15,-rise*.8)
		var pop := lerpf(.65,1.08,smoothstep(0,.17,t)) if t<.17 else lerpf(1.08,1.0,smoothstep(.17,.35,t))
		slot.scale = Vector3.ONE*pop
		var opacity := smoothstep(0,.07,t)*(1.0-smoothstep(1.0,DURATION,t))
		for name_text in ["Title","Points"]:
			var label: Label3D = slot.get_node(name_text)
			label.modulate.a = opacity
			label.outline_modulate.a = opacity*.95
		var material: ShaderMaterial = slot.get_node("Accent").material_override
		material.set_shader_parameter("age",t)
		material.set_shader_parameter("strength",opacity*(.35 if reduced_flash else 1.0))

func clear() -> void:
	ages.fill(DURATION)
	for slot in slots: slot.hide()
