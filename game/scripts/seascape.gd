extends Node3D
signal scrolled(distance: float)
## Painted 2D scenery on flat unlit planes, below the 3D player.
## One shared speed scrolls water and islands from top (-Z) to bottom (+Z).

const OCEAN_TEXTURE: Texture2D = preload("res://assets/environment/ocean.png")
const ISLAND_ATLAS: Texture2D = preload("res://assets/environment/islands-atlas.png")
const OCEAN_SHADER: Shader = preload("res://shaders/ocean.gdshader")
const ISLAND_SHADER: Shader = preload("res://shaders/island.gdshader")
const TILE_SIZE: float = 14.0
const POOL_SIZE: int = 6

@export var camera: Camera3D
@export_range(0.0, 10.0, 0.1) var scroll_speed: float = 2.4
@export var scenery_seed: int = 1942
@export var island_size_range: Vector2 = Vector2(9.0, 14.0)
@export var spacing_range: Vector2 = Vector2(15.0, 23.0)

var islands: Array[MeshInstance3D] = []
var ocean: MeshInstance3D
var ocean_material: ShaderMaterial
var recycle_count: int = 0
var _random := RandomNumberGenerator.new()
var _view_half := Vector2(22.22, 12.5)
var _scroll_a: float = 0.0
var _scroll_b: float = 0.0
var _wave_phase: float = 0.0
var _next_variant: int = 0


func _ready() -> void:
	_random.seed = scenery_seed
	_build_ocean()
	_update_view()
	var next_z := -2.5
	for index in range(POOL_SIZE):
		var island := MeshInstance3D.new()
		island.name = "Island%02d" % index
		island.mesh = PlaneMesh.new()
		island.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var material := ShaderMaterial.new()
		material.shader = ISLAND_SHADER
		material.set_shader_parameter("island_atlas", ISLAND_ATLAS)
		material.set_shader_parameter("ocean_texture", OCEAN_TEXTURE)
		material.set_shader_parameter("tile_size", TILE_SIZE)
		island.material_override = material
		add_child(island)
		islands.append(island)
		_configure_island(island, next_z)
		# First island is off-center, so the opening view stays readable.
		if index == 0:
			island.set_meta("lane", -0.51)
			island.position.x = -_view_half.x * 0.51
		next_z -= _random.randf_range(spacing_range.x, spacing_range.y)
	get_viewport().size_changed.connect(_update_view)


func _build_ocean() -> void:
	ocean = MeshInstance3D.new()
	ocean.name = "Ocean"
	ocean.mesh = PlaneMesh.new()
	ocean.position.y = -3.2
	ocean.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ocean_material = ShaderMaterial.new()
	ocean_material.shader = OCEAN_SHADER
	ocean_material.set_shader_parameter("ocean_texture", OCEAN_TEXTURE)
	ocean_material.set_shader_parameter("tile_size", TILE_SIZE)
	ocean.material_override = ocean_material
	add_child(ocean)


func _update_view() -> void:
	if not is_instance_valid(camera) or not is_instance_valid(ocean):
		return
	var viewport_size := get_viewport().get_visible_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	var a := camera.project_position(Vector2.ZERO, camera.position.y)
	var b := camera.project_position(viewport_size, camera.position.y)
	_view_half = Vector2(absf(b.x - a.x), absf(b.z - a.z)) * 0.5
	(ocean.mesh as PlaneMesh).size = _view_half * 2.0 + Vector2(8.0, 8.0)
	for island in islands:
		island.position.x = float(island.get_meta("lane")) * _view_half.x


func _configure_island(island: MeshInstance3D, at_z: float) -> void:
	var size := _random.randf_range(island_size_range.x, island_size_range.y)
	(island.mesh as PlaneMesh).size = Vector2(size, size)
	island.rotation.y = _random.randf_range(-0.55, 0.55)
	var lane := _random.randf_range(-0.76, 0.76)
	island.set_meta("lane", lane)
	island.set_meta("radius", size * 0.72)
	island.set_meta("variant", _next_variant)
	island.position = Vector3(lane * _view_half.x, -3.0, at_z)
	var material := island.material_override as ShaderMaterial
	material.set_shader_parameter("atlas_cell", Vector2(_next_variant % 2, _next_variant / 2))
	material.set_shader_parameter("phase_offset", _random.randf_range(0.0, TAU))
	_next_variant = (_next_variant + 1) % 4


func _physics_process(delta: float) -> void:
	var distance := scroll_speed * delta
	# Bounded phases avoid float precision loss during long play sessions.
	_scroll_a = fposmod(_scroll_a + distance / TILE_SIZE, 2.0)
	_scroll_b = fposmod(_scroll_b + distance / (TILE_SIZE * 1.6), 2.0)
	_wave_phase = fposmod(_wave_phase + delta * 0.65, TAU)
	ocean_material.set_shader_parameter("scroll_a", _scroll_a)
	ocean_material.set_shader_parameter("scroll_b", _scroll_b)
	ocean_material.set_shader_parameter("wave_phase", _wave_phase)
	for island in islands:
		island.position.z += distance
		var coastal_material := island.material_override as ShaderMaterial
		coastal_material.set_shader_parameter("wave_phase", _wave_phase)
		coastal_material.set_shader_parameter("scroll_a", _scroll_a)
		coastal_material.set_shader_parameter("scroll_b", _scroll_b)
	for island in islands:
		var radius := float(island.get_meta("radius"))
		if island.position.z - radius > _view_half.y + 2.0:
			var first_z := -_view_half.y - island_size_range.y
			for other in islands:
				if other != island:
					first_z = minf(first_z, other.position.z)
			_configure_island(island, first_z - _random.randf_range(spacing_range.x, spacing_range.y))
			recycle_count += 1
	scrolled.emit(distance)
