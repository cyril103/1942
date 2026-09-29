extends Node3D
## Fixed reusable multi-layer VFX. No node allocation when triggered.
const DURATION := 3.5
# Match the two 25% aircraft reductions, including particle travel distances.
const AIRCRAFT_EFFECT_SCALE := 0.5625
const ATLAS := preload("res://assets/effects/explosion-atlas.png")
var clouds: Array[MeshInstance3D] = []
var sparks: Array[MeshInstance3D] = []
var debris: Array[MeshInstance3D] = []
var flash: MeshInstance3D
var age := DURATION
var variant := 0.0

func _ready() -> void:
	scale = Vector3.ONE * AIRCRAFT_EFFECT_SCALE
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE
	for index in range(5):
		var cloud := MeshInstance3D.new()
		cloud.mesh = plane
		var material := ShaderMaterial.new()
		material.shader = preload("res://shaders/explosion_cloud.gdshader")
		material.set_shader_parameter("atlas", ATLAS)
		cloud.material_override = material
		cloud.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(cloud)
		clouds.append(cloud)
	flash = MeshInstance3D.new()
	flash.mesh = plane
	var flash_material := ShaderMaterial.new()
	flash_material.shader = preload("res://shaders/blast_flash.gdshader")
	flash.material_override = flash_material
	flash.position.y = 0.42
	flash.scale = Vector3.ONE * 7.0
	add_child(flash)
	var spark_mesh := PlaneMesh.new()
	spark_mesh.size = Vector2(0.10, 0.5)
	var spark_material := ShaderMaterial.new()
	spark_material.shader = preload("res://shaders/tracer.gdshader")
	spark_mesh.material = spark_material
	for index in range(16):
		var spark := MeshInstance3D.new()
		spark.mesh = spark_mesh
		spark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(spark)
		sparks.append(spark)
	var chunk_mesh := BoxMesh.new()
	chunk_mesh.size = Vector3(0.10, 0.045, 0.19)
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.10, 0.12, 0.09)
	metal.metallic = 0.55
	metal.roughness = 0.65
	chunk_mesh.material = metal
	for index in range(6):
		var chunk := MeshInstance3D.new()
		chunk.mesh = chunk_mesh
		chunk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(chunk)
		debris.append(chunk)
	hide()

func trigger(at: Vector3, seed_value: float) -> void:
	global_position = at + Vector3(0, 0.3, 0)
	age = 0.0
	variant = seed_value
	show()
	advance(0.0)

func advance(delta: float) -> void:
	age += delta
	if age >= DURATION:
		hide()
		return
	# Follow scenery gently as smoke disperses; individual lobes rise and drift.
	position.z += delta * 0.7
	for index in range(clouds.size()):
		var cloud := clouds[index]
		var delay := index * 0.035
		var t := maxf(0, age - delay)
		cloud.visible = age >= delay
		var angle := variant + index * 2.39996
		var spread := (1.0 - exp(-t * 3.0)) * (0.0 if index == 0 else 1.0 + index * 0.06)
		cloud.position = Vector3(cos(angle) * spread + t * 0.12, 0.05 * index + t * 0.11, sin(angle) * spread)
		cloud.rotation.y = angle + t * (0.07 if index % 2 == 0 else -0.06)
		var size := (0.7 + 2.7 * (1.0 - exp(-t * 5.5)) + t * 0.45) * (1.0 if index == 0 else 0.72)
		cloud.scale = Vector3.ONE * size
		cloud.material_override.set_shader_parameter("age", t * (0.93 + index * 0.04))
		cloud.material_override.set_shader_parameter("variation", angle)
		cloud.material_override.set_shader_parameter("opacity", 1.0 if index == 0 else 0.82)
	flash.visible = age < 0.34
	flash.material_override.set_shader_parameter("age", age)
	for index in range(sparks.size()):
		var spark := sparks[index]
		var a := variant + index * 2.39996
		var life := 0.48 + float(index % 5) * 0.12
		spark.visible = age < life
		var distance := (2.3 + float(index % 4) * 0.7) * (1.0 - exp(-age * 3.0))
		spark.position = Vector3(cos(a) * distance, 0.32 + age * 0.3, sin(a) * distance)
		spark.rotation.y = -a + PI * 0.5
		spark.scale = Vector3.ONE * maxf(0.01, 1.0 - age / life)
	for index in range(debris.size()):
		var chunk := debris[index]
		var a := variant + index * 2.39996 + 0.6
		chunk.visible = age < 1.35
		chunk.position = Vector3(cos(a) * age * 2.2, age * 1.4 - age * age * 1.7, sin(a) * age * 2.2)
		chunk.rotation = Vector3(age * 8, a + age * 5, age * 9)
		chunk.scale = Vector3.ONE * (1.0 - smoothstep(0.9, 1.35, age))
