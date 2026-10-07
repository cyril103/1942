extends Node3D
signal scrolled(distance: float)
## Painted 2D scenery on flat unlit planes, below the 3D player.
## One shared speed scrolls water and islands from top (-Z) to bottom (+Z).

const OCEAN_TEXTURE: Texture2D = preload("res://assets/environment/ocean.png")
const ISLAND_ATLAS: Texture2D = preload("res://assets/environment/islands-atlas.png")
const MILITARY_ATLAS: Texture2D = preload("res://assets/environment/military-islands-atlas.png")
const ARCHIPELAGO_ATLAS: Texture2D = preload("res://assets/environment/archipelago-atlas.png")
const OCEAN_SHADER: Shader = preload("res://shaders/ocean.gdshader")
const ISLAND_SHADER: Shader = preload("res://shaders/island.gdshader")
const TILE_SIZE: float = 14.0
const POOL_SIZE: int = 10
# A swept navigation envelope includes the full carrier deck and turning bow.
const CHANNEL_MARGIN := 10.0
const CHANNEL_LOOKAHEAD := 15.0

@export var camera: Camera3D
@export_range(0.0, 10.0, 0.1) var scroll_speed: float = 2.4
@export var scenery_seed: int = 1942
@export var island_size_range: Vector2 = Vector2(7.5, 15.5)
@export var spacing_range: Vector2 = Vector2(11.0, 16.0)

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
var naval_corridor := false
var scroll_distance := 0.0
var _route_sign := 1.0
var _layout_index := 0
var _variant_bag: Array[int] = []
var _biome := "coral"
var _sector_atlas: Texture2D
var _polar_atlas: Texture2D
var _last_variant := -1


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
	var a := camera.project_position(Vector2.ZERO, 1.0)
	var b := camera.project_position(viewport_size, 1.0)
	_view_half = Vector2(absf(b.x - a.x), absf(b.z - a.z)) * 0.5
	(ocean.mesh as PlaneMesh).size = _view_half * 2.0 + Vector2(8.0, 8.0)
	for island in islands:
		_place_island(island)


func channel_center(at_z: float) -> float:
	# Coordinates attached to the scrolling seabed, not to elapsed gameplay time.
	# The opening anchorage stays straight for the complete takeoff.
	var travel := maxf(0.0,scroll_distance-at_z-24.0)
	var amplitude := clampf(_view_half.x-7.0,0.0,18.0)
	return _route_sign*amplitude*sin(travel/65.0)*smoothstep(0.0,28.0,travel)


func channel_heading(at_z: float) -> float:
	return atan2(channel_center(at_z+0.25)-channel_center(at_z-0.25),0.5)


func _place_island(island: MeshInstance3D) -> void:
	var extent: Vector2 = island.get_meta("extent",Vector2(8,8))
	var low := INF
	var high := -INF
	# Conservative bound between samples: route derivative stays below 0.6.
	var span := extent.y+CHANNEL_LOOKAHEAD
	for step in range(33):
		var x := channel_center(island.position.z+lerpf(-span,span,step/32.0))
		low = minf(low,x)
		high = maxf(high,x)
	var padding := span/32.0*0.6
	var left := low-CHANNEL_MARGIN-extent.x-padding
	var right := high+CHANNEL_MARGIN+extent.x+padding
	var left_space := left+_view_half.x
	var right_space := _view_half.x-right
	var side := -1.0 if left_space>right_space else 1.0
	if minf(left_space,right_space)>extent.x*0.35:
		side = float(island.get_meta("side",side))
	# Some islands hug the inner bank, others sit farther offshore. This brings
	# land through the middle when the channel bends toward either screen edge.
	var variation := float(island.get_meta("shore_offset",0.0))
	island.position.x = left-variation if side<0 else right+variation
	island.set_meta("lane",island.position.x/maxf(1.0,_view_half.x))


func _pick_variant() -> int:
	if _variant_bag.is_empty():
		if _biome=="arctic": _variant_bag.assign([12,13,14,15,9])
		elif _biome=="volcanic": _variant_bag.assign([8,5,7,5,8,6])
		elif _biome in ["jade","final"]: _variant_bag.assign([11,4,7,6,0,3])
		elif _biome=="convoy": _variant_bag.assign([10,4,6,7,1,2])
		else: _variant_bag.assign([0,1,2,3,4,5,6,7])
		if _biome!="arctic": _variant_bag.append_array([16,17,18,19])
		# Seeded shuffle keeps each mission reproducible and avoids a single motif.
		for i in range(_variant_bag.size()-1,0,-1):
			var j := _random.randi_range(0,i)
			var old := _variant_bag[i]
			_variant_bag[i] = _variant_bag[j]
			_variant_bag[j] = old
	if _variant_bag.size()>1 and _variant_bag.back()==_last_variant:
		for i in range(_variant_bag.size()-1):
			if _variant_bag[i]!=_last_variant:
				_variant_bag[-1] = _variant_bag[i]
				_variant_bag[i] = _last_variant
				break
	_last_variant = _variant_bag.pop_back()
	return _last_variant


func _configure_island(island: MeshInstance3D, at_z: float) -> void:
	var variant := _pick_variant() if naval_corridor else _next_variant
	var size := _random.randf_range(island_size_range.x, island_size_range.y)
	var shape := Vector2(size*_random.randf_range(.82,1.12),size*_random.randf_range(.85,1.16))
	(island.mesh as PlaneMesh).size = shape
	island.rotation.y = _random.randf_range(-0.4,0.4)
	var c := absf(cos(island.rotation.y))
	var s := absf(sin(island.rotation.y))
	var extent := Vector2(shape.x*c+shape.y*s,shape.x*s+shape.y*c)*0.5
	island.set_meta("extent",extent)
	island.set_meta("side",-1.0 if _layout_index%2==0 else 1.0)
	island.set_meta("shore_offset",_random.randf_range(0.0,2.5) if _layout_index%3 else 0.0)
	island.set_meta("radius",extent.y)
	island.set_meta("variant",variant)
	island.position = Vector3(0,-3.0,at_z)
	# Keep transparent sprites separated, including their broad coastal blend.
	for other in islands:
		if other==island or not other.has_meta("extent"): continue
		if absf(other.position.z-island.position.z)<float(other.get_meta("radius"))+extent.y+0.8:
			island.position.z = minf(island.position.z,other.position.z-float(other.get_meta("radius"))-extent.y-0.8)
	_place_island(island)
	var material := island.material_override as ShaderMaterial
	var atlas: Texture2D = ISLAND_ATLAS
	if variant>=16: atlas = MILITARY_ATLAS
	elif variant>=12: atlas = _polar_atlas
	elif variant>=8: atlas = _sector_atlas
	elif variant>=4: atlas = ARCHIPELAGO_ATLAS
	material.set_shader_parameter("island_atlas",atlas)
	material.set_shader_parameter("atlas_cell",Vector2(variant%2,(variant%4)/2))
	material.set_shader_parameter("phase_offset", _random.randf_range(0.0, TAU))
	material.set_shader_parameter("detail_tint",Color(_random.randf_range(.94,1.04),_random.randf_range(.97,1.03),_random.randf_range(.93,1.03)))
	_next_variant = (_next_variant + 1) % 4
	_layout_index += 1


func _physics_process(delta: float) -> void:
	var distance := scroll_speed * delta
	scroll_distance += distance
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

func configure_sector(mission: Dictionary) -> void:
	_random.seed = int(mission.seed)
	var biome: String = mission.biome
	_biome = biome
	_variant_bag.clear()
	_last_variant = -1
	_layout_index = 0
	_route_sign = -1.0 if int(mission.seed)%2==0 else 1.0
	scroll_distance = 0.0
	naval_corridor = true
	_sector_atlas = load("res://assets/campaign/sector-islands.png")
	_polar_atlas = load("res://assets/environment/polar-archipelago-atlas.png")
	var sea_tints := {"coral":Color(0.8,1.08,1.0),"convoy":Color(0.75,0.95,0.9),"storm":Color(0.58,0.7,0.8),"jade":Color(0.8,1.1,0.9),"volcanic":Color(0.75,0.72,0.68),"dusk":Color(1.15,0.68,0.57),"arctic":Color(0.77,0.94,1.07),"final":Color(1.1,0.94,0.75)}
	var tint: Color = sea_tints[biome]
	var desaturation := 0.4 if biome in ["storm","volcanic","arctic"] else 0.0
	ocean_material.set_shader_parameter("ocean_tint",tint)
	ocean_material.set_shader_parameter("sea_desaturation",desaturation)
	var next_z := -3.0
	for island in islands:
		island.remove_meta("extent")
	for island in islands:
		island.material_override.set_shader_parameter("ocean_tint",tint)
		island.material_override.set_shader_parameter("sea_desaturation",desaturation)
		island.material_override.set_shader_parameter("land_tint",Color(0.65,0.72,0.79) if biome == "storm" else (Color(1.0,0.83,0.65) if biome == "dusk" else Color.WHITE))
		_configure_island(island,next_z)
		next_z = island.position.z-_random.randf_range(spacing_range.x,spacing_range.y)
