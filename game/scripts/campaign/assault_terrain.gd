extends Node3D
## Sector-authored routes and targets share one local layout.
## Finite coastal battlefield. The campaign owns its scrolling transform.
## Only the outer third carries raised terrain and instanced scenery. The inner
## plateau stays at -8.0, below the physical cloud layer during the assault.

const SURFACE_SHADER := preload("res://shaders/assault_terrain.gdshader")
const LANDSCAPE_PATH := "res://assets/environment/raid-v2/tropical-battlefield.png"
const PLATEAU_Y := -8.0
const SEA_EDGE_Y := -9.48
const MAX_TRIANGLES := 29000
const MAX_PROP_INSTANCES := 340
const MAX_INFRASTRUCTURE_TRIANGLES := 2000
const MAX_ROUTE_SEGMENTS := 48
const MAX_RUNWAYS := 8
const INFRASTRUCTURE_Y := PLATEAU_Y + .040
# Strings, not preloads: only the active biome texture is referenced at runtime.
const BIOME_ALBEDO_PATHS := {
	"volcanic": "res://assets/environment/raid-v3/volcanic-basalt-albedo-native.png",
	"arctic": "res://assets/environment/raid-v3/arctic-packed-snow-albedo-native.png"
}
static var _coast_shader_cache: Shader

var triangle_count := 0
var coast_triangle_count := 0
var prop_count := 0
var surface: MeshInstance3D
var surface_material: ShaderMaterial
var coastal_fringe: MeshInstance3D
var coast_material: ShaderMaterial
var terrain_width := 48.0
var terrain_length := 120.0
var useful_half_width := 0.0
var useful_half_length := 0.0
var _biome := "coral"
var _seed_phase := 0.0
var _quality := 1
var _groups: Array[MultiMeshInstance3D] = []
var _random := RandomNumberGenerator.new()
var _ground_detail: Texture2D
var _scenery_clusters: Array[Vector2] = []
var shoreline: MeshInstance3D
var infrastructure_triangle_count := 0
var route_segment_count := 0
var runway_count := 0
var layout_id := ""
var _layout: Dictionary = {}
var _route_segments: Array[Dictionary] = []
var _runway_specs: Array[Dictionary] = []
var _layout_geometry_valid := true
var _layout_geometry_errors: Array[String] = []
var _shared_parameters: Dictionary = {}
var _infrastructure_materials: Array[ShaderMaterial] = []
var _biome_albedo: Texture2D
var _landscape: Texture2D


func configure(mission: Dictionary, width: float, length: float, layout: Dictionary = {}) -> void:
	# Construction happens once, before the coast reaches the screen. Reusing a
	# node is supported without retaining the old mesh or MultiMesh resources.
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_groups.clear()
	_infrastructure_materials.clear()
	_shared_parameters.clear()
	infrastructure_triangle_count = 0
	route_segment_count = 0
	runway_count = 0
	terrain_width = maxf(width, 24.0)
	terrain_length = maxf(length, 32.0)
	useful_half_width = terrain_width * .33
	useful_half_length = terrain_length * .5 - 9.0
	_biome = str(mission.get("biome", "coral"))
	_random.seed = int(mission.get("id", 1)) * 7919 + 1942
	_seed_phase = _random.randf_range(0.0, TAU)
	_layout = layout # The exact instance already used by GroundAssault targets.
	layout_id = str(layout.get("id", ""))
	_prepare_infrastructure()
	_load_active_biome_albedo()
	_build_surface()
	_build_shoreline()
	_build_infrastructure()
	_build_scenery()
	set_quality(_quality)


func set_ground_detail(texture: Texture2D) -> void:
	_ground_detail = texture
	set_ocean_parameter("ground_detail", texture)
	set_ocean_parameter("use_ground_detail", texture != null)


func set_ocean_parameter(parameter: StringName, value: Variant) -> void:
	## Keep the opaque shore and its transparent fringe in phase with the sea.
	## Also accepts shared pigment parameters when preview tools need them.
	_shared_parameters[parameter] = value
	for material in _all_surface_materials():
		material.set_shader_parameter(parameter, value)


func set_quality(level: int) -> void:
	_quality = clampi(level, 0, 2)
	for group in _groups:
		var total := group.multimesh.instance_count
		group.multimesh.visible_instance_count = int(ceil(total * [.55, .82, 1.0][_quality]))
		group.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if _quality == 0 else GeometryInstance3D.SHADOW_CASTING_SETTING_ON


func surface_height(at: Vector2) -> float:
	## Local X/Z query for scenery or future placed objects. All target lanes
	## |x| <= width*.33, |z| <= length/2-9 are exactly PLATEAU_Y.
	var edge_x := _half_width(at.y) - absf(at.x)
	var edge_z := _half_length(at.x) - absf(at.y)
	var coast := minf(edge_x / 3.0, edge_z / 6.0)
	var height := lerpf(SEA_EDGE_Y, PLATEAU_Y, smoothstep(0.0, 1.0, coast))
	var outer := smoothstep(terrain_width * .335, terrain_width * .40, absf(at.x))
	var inland := smoothstep(.65, 1.15, coast)
	var ridge := .25 + .75 * pow(.5 + .5 * sin(at.y * .075 + _seed_phase + at.x * .14), 2.0)
	return height + outer * inland * ridge * (1.15 if _biome == "volcanic" else .65)


func _half_width(z: float) -> float:
	return terrain_width * .5 - 1.05 - sin(z * .083 + _seed_phase) * .68 - sin(z * .21 - _seed_phase) * .32


func _half_length(x: float) -> float:
	return terrain_length * .5 - 1.0 - sin(x * .20 + _seed_phase) * .65 - sin(x * .41) * .35


func _build_surface() -> void:
	var spacing := maxf(1.0, sqrt(terrain_width * terrain_length / 13700.0))
	var columns := int(ceil(terrain_width / spacing))
	var rows := int(ceil(terrain_length / spacing))
	# Leave room under the global mesh budget for the thin shoreline ribbon.
	while columns * rows * 2 > MAX_TRIANGLES - 4000 - (MAX_INFRASTRUCTURE_TRIANGLES if not _layout.is_empty() else 0):
		spacing *= 1.025
		columns = int(ceil(terrain_width / spacing))
		rows = int(ceil(terrain_length / spacing))
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for row in range(rows + 1):
		var v := float(row) / rows
		for column in range(columns + 1):
			var u := float(column) / columns
			var nominal_z := (v - .5) * terrain_length
			var x := (u - .5) * 2.0 * _half_width(nominal_z)
			var z := (v - .5) * 2.0 * _half_length(x)
			var point := Vector2(x, z)
			var height := surface_height(point)
			vertices.append(Vector3(x, height, z))
			var normal := Vector3(surface_height(point - Vector2(.15, 0)) - surface_height(point + Vector2(.15, 0)), .3, surface_height(point - Vector2(0, .15)) - surface_height(point + Vector2(0, .15))).normalized()
			normals.append(normal)
			uvs.append(Vector2(u, v))
			var distance_to_coast := minf((_half_width(z) - absf(x)) / 3.0, (_half_length(x) - absf(z)) / 6.0)
			colors.append(Color(clampf(distance_to_coast, 0.0, 1.0), 0, 0, 1))
	for row in range(rows):
		for column in range(columns):
			var a := row * (columns + 1) + column
			var b := a + 1
			var c := a + columns + 1
			var d := c + 1
			# Clockwise when seen from above, matching Godot's front faces.
			indices.append_array(PackedInt32Array([a, b, c, b, d, c]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	var inland_indices := PackedInt32Array()
	var coastal_indices := PackedInt32Array()
	for triangle in range(0, indices.size(), 3):
		var a := indices[triangle]
		var b := indices[triangle + 1]
		var c := indices[triangle + 2]
		if minf(colors[a].r, minf(colors[b].r, colors[c].r)) < .40:
			coastal_indices.append_array(PackedInt32Array([a, b, c]))
		else:
			inland_indices.append_array(PackedInt32Array([a, b, c]))
	arrays[Mesh.ARRAY_INDEX] = inland_indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	triangle_count = indices.size() / 3
	coast_triangle_count = coastal_indices.size() / 3
	surface = MeshInstance3D.new()
	surface.name = "CoastalPlateau"
	surface.mesh = mesh
	# The coast receives prop shadows; terrain has no overhangs to cast them.
	surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	surface_material = ShaderMaterial.new()
	surface_material.shader = SURFACE_SHADER
	surface.material_override = surface_material
	add_child(surface)
	# Preserve all positions, normals and UVs. Only triangle ownership changes:
	# the central battlefield stays opaque, while the narrow coastal slopes fade
	# before they intersect the ocean instead of forming a hard normal-lit rim.
	arrays[Mesh.ARRAY_INDEX] = coastal_indices
	var coast_mesh := ArrayMesh.new()
	coast_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if _coast_shader_cache == null:
		_coast_shader_cache = Shader.new()
		_coast_shader_cache.code = SURFACE_SHADER.code.replace(
			"render_mode diffuse_burley, specular_schlick_ggx;",
			"render_mode blend_mix, depth_draw_never, diffuse_burley, specular_schlick_ggx;"
		).replace("// COAST_ALPHA_HOOK", "ALPHA = smoothstep(0.16, 0.34, coast_depth);")
	coast_material = ShaderMaterial.new()
	coast_material.shader = _coast_shader_cache
	coast_material.render_priority = -1
	coastal_fringe = MeshInstance3D.new()
	coastal_fringe.name = "CoastalFringeMesh"
	coastal_fringe.mesh = coast_mesh
	coastal_fringe.material_override = coast_material
	coastal_fringe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(coastal_fringe)
	set_ocean_parameter("field_size", Vector2(terrain_width, terrain_length))
	set_ocean_parameter("seed_phase", _seed_phase)
	set_ocean_parameter("landscape_texture", _landscape)
	set_ocean_parameter("pigment_exponent", 1.0)
	set_ocean_parameter("use_shared_layout", not _layout.is_empty())
	set_ocean_parameter("biome_material", 1 if _biome == "volcanic" else (2 if _biome == "arctic" else 0))
	set_ocean_parameter("biome_albedo", _biome_albedo)
	set_ocean_parameter("biome_tile_metres", 4.0)
	set_ocean_parameter("landscape_gain", .48 if _biome == "volcanic" else (.34 if _biome == "arctic" else .38))
	var palette := _palette()
	for parameter in palette:
		set_ocean_parameter(parameter, palette[parameter])
	set_ground_detail(_ground_detail)


func _palette() -> Dictionary:
	var grass := Color(.20, .37, .12)
	var meadow := Color(.40, .49, .22)
	var sand := Color(.80, .73, .52)
	var rock := Color(.43, .46, .41)
	match _biome:
		"convoy": grass = Color(.22, .37, .14); meadow = Color(.41, .48, .23)
		"storm": grass = Color(.18, .31, .19); meadow = Color(.34, .41, .24); sand = Color(.65, .69, .57)
		"jade": grass = Color(.17, .38, .18); meadow = Color(.32, .46, .22)
		"volcanic": grass = Color(.25, .33, .18); meadow = Color(.40, .39, .24); sand = Color(.52, .49, .42); rock = Color(.45, .46, .44)
		"dusk": grass = Color(.27, .37, .16); meadow = Color(.44, .46, .23)
		"arctic": grass = Color(.56, .62, .63); meadow = Color(.67, .69, .67); sand = Color(.65, .70, .71); rock = Color(.51, .57, .59)
		"final": grass = Color(.21, .35, .15); meadow = Color(.38, .43, .21)
	return {"grass_color": grass, "meadow_color": meadow, "sand_color": sand, "rock_color": rock, "snow_cover": 1.0 if _biome == "arctic" else 0.0}


func _build_shoreline() -> void:
	# Only this narrow perimeter is transparent. The battlefield itself remains
	# opaque and early-Z friendly; a full-screen transparent ground is avoided.
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var offsets := [-1.35, -.45, .35, 1.40]
	for edge in range(4):
		var horizontal := edge % 2 == 0
		var span := terrain_width if horizontal else terrain_length
		var count := clampi(int(ceil(span)), 4, 160)
		var first := vertices.size()
		for step in range(count + 1):
			var along := (float(step) / count - .5) * span
			var point: Vector2
			var inward: Vector2
			match edge:
				0: point = Vector2(along, -_half_length(along)); inward = Vector2(0, 1)
				1: point = Vector2(_half_width(along), along); inward = Vector2(-1, 0)
				2: point = Vector2(-along, _half_length(-along)); inward = Vector2(0, -1)
				_: point = Vector2(-_half_width(-along), -along); inward = Vector2(1, 0)
			for cross_step in range(4):
				var at := point + inward * float(offsets[cross_step])
				vertices.append(Vector3(at.x, maxf(SEA_EDGE_Y + .11, surface_height(at) + .035), at.y))
				uvs.append(Vector2(float(step) / count, float(cross_step) / 3.0))
		for step in range(count):
			for cross_step in range(3):
				var a := first + step * 4 + cross_step
				indices.append_array(PackedInt32Array([a, a + 1, a + 4, a + 1, a + 5, a + 4]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	triangle_count += indices.size() / 3
	var shader := Shader.new()
	shader.code = """shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
varying vec2 local_xz;
void vertex() { local_xz = VERTEX.xz; }
void fragment() {
 vec2 p = local_xz;
 float broken = .5 + .25*sin(p.x*2.4+p.y*1.3) + .25*sin(p.x*5.7-p.y*3.8);
 float ripple = sin(UV.y*18.0-TIME*1.5+sin(p.x*2.2+p.y*1.7)*.65);
 float foam = pow(max(0.0,ripple),7.0)*smoothstep(.31,.73,broken);
 float edge = smoothstep(.02,.31,UV.y)*(1.0-smoothstep(.60,1.0,UV.y));
 ALBEDO = vec3(.64,.74,.69);
 ALPHA = edge * foam * .35;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	shoreline = MeshInstance3D.new()
	shoreline.name = "NarrowShoreBlend"
	shoreline.mesh = mesh
	shoreline.material_override = material
	shoreline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shoreline)
	assert(triangle_count <= MAX_TRIANGLES)


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.vertex_color_use_as_albedo = true
	material.roughness = .95
	return material


func _build_scenery() -> void:
	if _biome in ["volcanic", "arctic"]:
		_build_geological_scenery()
		return
	var scale_count := clampf(terrain_width * terrain_length / 5500.0, .60, 1.0)
	var tree_count := int(52 * scale_count)
	var rock_count := int(64 * scale_count)
	var scrub_count := int(76 * scale_count)
	_scenery_clusters.clear()
	for index in range(clampi(int(terrain_length / 11.0), 6, 32)):
		var side := -1.0 if index % 2 == 0 else 1.0
		var z := _random.randf_range(-useful_half_length, useful_half_length)
		_scenery_clusters.append(Vector2(side * _random.randf_range(terrain_width * .365, terrain_width * .415), z))
	var trunk := _palm_trunk_mesh()
	trunk.surface_set_material(0, _material(Color(.43, .34, .20)))
	var leaves := _canopy_mesh(_biome == "arctic")
	var leaf_material := _material(Color(.29, .46, .12) if _biome != "arctic" else Color(.31, .43, .37))
	leaf_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	leaves.surface_set_material(0, leaf_material)
	var rock := SphereMesh.new()
	rock.radius = .55
	rock.height = .82
	rock.radial_segments = 11
	rock.rings = 5
	var irregular_rock := _weathered_rock(rock)
	irregular_rock.surface_set_material(0, _material(_palette().rock_color))
	var scrub := _scrub_mesh()
	var scrub_material := _material(_palette().grass_color.lightened(.018))
	scrub_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	scrub.surface_set_material(0, scrub_material)
	var trunks := _new_group("PalmTrunks" if _biome != "arctic" else "PineTrunks", trunk, tree_count)
	var crowns := _new_group("PalmCrowns" if _biome != "arctic" else "PineCrowns", leaves, tree_count)
	var rocks := _new_group("CoastalBoulders", irregular_rock, rock_count)
	var scrubland := _new_group("LowScrub", scrub, scrub_count)
	for index in range(tree_count):
		var anchor := _scenery_position()
		var size := _random.randf_range(.63, 1.10)
		var basis := Basis(Vector3.UP, _random.randf_range(0.0, TAU)).scaled(Vector3.ONE * size)
		var tint := Color.WHITE * _random.randf_range(.8, 1.15)
		trunks.multimesh.set_instance_transform(index, Transform3D(basis, anchor))
		crowns.multimesh.set_instance_transform(index, Transform3D(basis, anchor + basis * Vector3(.19, 1.62, .08)))
		trunks.multimesh.set_instance_color(index, tint)
		crowns.multimesh.set_instance_color(index, tint)
	for index in range(rock_count):
		var anchor := _scenery_position()
		var size := Vector3(_random.randf_range(.42, 1.25), _random.randf_range(.5, 1.15), _random.randf_range(.45, 1.15))
		var basis := Basis.from_euler(Vector3(_random.randf_range(-.3, .3), _random.randf_range(0.0, TAU), _random.randf_range(-.25, .25))).scaled(size)
		rocks.multimesh.set_instance_transform(index, Transform3D(basis, anchor + Vector3(0, size.y * .17, 0)))
		rocks.multimesh.set_instance_color(index, Color.WHITE * _random.randf_range(.8, 1.15))
	for index in range(scrub_count):
		var anchor := _scenery_position()
		var size := Vector3(_random.randf_range(.6, 1.6), _random.randf_range(.6, 1.1), _random.randf_range(.65, 1.4))
		scrubland.multimesh.set_instance_transform(index, Transform3D(Basis(Vector3.UP, _random.randf_range(0.0, TAU)).scaled(size), anchor + Vector3(0, .08 * size.y, 0)))
		scrubland.multimesh.set_instance_color(index, Color.WHITE * _random.randf_range(.8, 1.18))
	prop_count = tree_count * 2 + rock_count + scrub_count
	assert(prop_count <= MAX_PROP_INSTANCES)


func _new_group(group_name: String, mesh: Mesh, count: int) -> MultiMeshInstance3D:
	var group := MultiMeshInstance3D.new()
	group.name = group_name
	group.multimesh = MultiMesh.new()
	group.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	group.multimesh.use_colors = true
	group.multimesh.mesh = mesh
	group.multimesh.instance_count = count
	add_child(group)
	_groups.append(group)
	return group


func _scenery_position() -> Vector3:
	var center := _scenery_clusters[_random.randi_range(0, _scenery_clusters.size() - 1)]
	var z := clampf(center.y + _random.randfn(0.0, 2.6), -useful_half_length, useful_half_length)
	var side := signf(center.x)
	# A full canopy radius stays outside the destructible-object corridor.
	var minimum := terrain_width * .33 + .85
	var maximum := maxf(minimum, _half_width(z) - 3.35)
	var x := side * clampf(absf(center.x) + _random.randfn(0.0, 1.25), minimum, maximum)
	return Vector3(x, surface_height(Vector2(x, z)), z)


func _weathered_rock(source: SphereMesh) -> ArrayMesh:
	var arrays := source.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colors := PackedColorArray()
	for index in range(vertices.size()):
		var p := vertices[index]
		var wear := .81 + .11 * sin(p.x * 15.0 + p.z * 11.0) + .08 * cos(p.y * 17.0 - p.x * 5.0)
		vertices[index] *= wear
		colors.append(Color(.88, .91, .87) * (.78 + wear * .25))
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _palm_trunk_mesh() -> ArrayMesh:
	# A bent, tapered and ringed trunk gives the crown a believable attachment.
	var builder := SurfaceTool.new()
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ring in range(7):
		for side in range(7):
			var points: Array[Vector3] = []
			for corner in [Vector2(side,ring),Vector2(side+1,ring),Vector2(side+1,ring+1),Vector2(side,ring+1)]:
				var t: float = corner.y/7.0
				var angle: float = corner.x/7.0*TAU
				var radius := lerpf(.103,.048,t)
				points.append(Vector3(cos(angle)*radius+.19*t*t,1.62*t,sin(angle)*radius+.08*t*t))
			builder.set_color(Color.WHITE*(.84 if ring%2==0 else 1.05))
			_add_triangle(builder,points[0],points[2],points[1])
			_add_triangle(builder,points[0],points[3],points[2])
	builder.generate_normals()
	return builder.commit()


func _scrub_mesh() -> ArrayMesh:
	# Fern-like layered leaves, not intersecting spheres. All faces are opaque.
	var builder := SurfaceTool.new()
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	for frond in range(10):
		var angle := frond*2.4
		var direction := Vector3(sin(angle),0,cos(angle))
		var across := Vector3(cos(angle),0,-sin(angle))
		var leaf_length := .42+.20*sin(frond*1.87)
		var center := direction*leaf_length*.46+Vector3(0,.24+(frond%3)*.035,0)
		var root := Vector3(0,.04,0)
		var tip := direction*leaf_length+Vector3(0,.10,0)
		builder.set_color(Color(.86+.10*sin(angle),1.0,.83+.12*cos(angle)))
		_add_triangle(builder,root,center,center-across*.13)
		_add_triangle(builder,root,center+across*.13,center)
		_add_triangle(builder,center,tip,center-across*.13)
		_add_triangle(builder,center,center+across*.13,tip)
	builder.generate_normals()
	return builder.commit()


func _canopy_mesh(pine: bool) -> ArrayMesh:
	var builder := SurfaceTool.new()
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	if pine:
		for layer in range(3):
			var radius := .7 - layer * .15
			var base_y := -.4 + layer * .38
			for side in range(7):
				var angle := float(side) / 7.0 * TAU
				var next_angle := float(side + 1) / 7.0 * TAU
				_add_triangle(builder, Vector3(0, base_y + .85, 0), Vector3(sin(angle) * radius, base_y, cos(angle) * radius), Vector3(sin(next_angle) * radius, base_y, cos(next_angle) * radius))
	else:
		# Individual swept leaflets follow a bowed rachis; the old solid stars
		# are replaced by a finely cut palm silhouette at the lower camera.
		for frond in range(9):
			var angle := float(frond) / 9.0 * TAU + sin(frond * 2.17) * .14
			var direction := Vector3(sin(angle), 0, cos(angle))
			var across := Vector3(cos(angle), 0, -sin(angle))
			var length := 1.08 + .22 * sin(frond * 1.83)
			for segment in range(7):
				var t := float(segment + 1) / 8.0
				var next_t := float(segment + 2) / 8.0
				var p := direction * t * length + Vector3(0, sin(t * PI) * .29 - t * .39, 0)
				var tip := direction * next_t * length + Vector3(0, sin(next_t * PI) * .29 - next_t * .39, 0)
				var breadth := sin(t * PI) * .22
				builder.set_color(Color(.83+.14*t,.94+.06*t,.66+.24*t))
				_add_triangle(builder,p-across*.015,tip,p+across*.015)
				for side in [-1.0,1.0]:
					var leaf_tip: Vector3 = p+across*breadth*side+direction*.13-Vector3(0,.060,0)
					var root_tip := p+direction*.048
					var ridge: Vector3 = (p+leaf_tip)*.5+Vector3(0,.022,0)
					_add_triangle(builder,p,leaf_tip,ridge)
					_add_triangle(builder,ridge,leaf_tip,root_tip)
	builder.generate_normals()
	return builder.commit()



func _all_surface_materials() -> Array[ShaderMaterial]:
	var materials: Array[ShaderMaterial] = []
	for material in [surface_material, coast_material]:
		if is_instance_valid(material):
			materials.append(material)
	materials.append_array(_infrastructure_materials)
	return materials


func _load_active_biome_albedo() -> void:
	_biome_albedo = null
	_landscape = null
	if BIOME_ALBEDO_PATHS.has(_biome):
		# No asynchronous allocation during firing. GroundAssault constructs
		# this battlefield before deployment, then holds one active material.
		_biome_albedo = load(str(BIOME_ALBEDO_PATHS[_biome])) as Texture2D
		assert(_biome_albedo != null, "Missing native biome albedo: " + _biome)
	else:
		_landscape = load(LANDSCAPE_PATH) as Texture2D
		assert(_landscape != null, "Missing original tropical macro")


func infrastructure_status() -> Dictionary:
	## Construction observability; not a proof of runtime collider clearance.
	return {
		"layout_id": layout_id, "valid": _layout_geometry_valid,
		"errors": _layout_geometry_errors.duplicate(),
		"route_segments": route_segment_count, "runways": runway_count,
		"triangles": infrastructure_triangle_count,
		"opaque": true, "shared_layout": not _layout.is_empty(),
		"biome_material": _biome, "native_albedo_loaded": _biome_albedo != null
	}


func _prepare_infrastructure() -> void:
	_route_segments.clear()
	_runway_specs.clear()
	_layout_geometry_errors.clear()
	_layout_geometry_valid = true
	var routes: Dictionary = _layout.get("routes", {})
	for route_id in routes:
		var route: Dictionary = routes[route_id]
		var points: Array = route.get("world_points", [])
		var width := float(route.get("width", 0.0))
		if not is_finite(width) or width <= 0.0:
			_layout_geometry_errors.append("Invalid road width: " + str(route_id))
			continue
		for index in range(1, points.size()):
			var a: Vector3 = points[index - 1]
			var b: Vector3 = points[index]
			var from := Vector2(a.x, a.z)
			var to := Vector2(b.x, b.z)
			if not a.is_finite() or not b.is_finite() or from.distance_to(to) < .01:
				_layout_geometry_errors.append("Invalid road segment: " + str(route_id))
				continue
			var radius := width * .5 + .35
			if not _fits_plateau(from, Vector2.ONE * radius) or not _fits_plateau(to, Vector2.ONE * radius):
				_layout_geometry_errors.append("Road shoulders leave the flat plateau: " + str(route_id))
				continue
			_route_segments.append({"route_id": str(route_id), "from": from, "to": to, "half_width": width * .5})
	for authored in _layout.get("runways", []):
		var strip: Dictionary = authored
		var strip_position: Vector3 = strip.get("position", Vector3.ZERO)
		var extents: Vector2 = strip.get("world_half_extents", Vector2.ZERO)
		if not strip_position.is_finite() or not extents.is_finite() or extents.x <= 0.0 or extents.y <= 0.0:
			_layout_geometry_errors.append("Invalid airstrip: " + str(strip.get("id", "")))
			continue
		if not _fits_plateau(Vector2(strip_position.x, strip_position.z), extents + Vector2(.35, .66)):
			_layout_geometry_errors.append("Airstrip shoulders leave the flat plateau: " + str(strip.get("id", "")))
			continue
		_runway_specs.append({"id": str(strip.get("id", "")), "center": Vector2(strip_position.x, strip_position.z), "extents": extents})
	if _route_segments.size() > MAX_ROUTE_SEGMENTS or _runway_specs.size() > MAX_RUNWAYS:
		_layout_geometry_errors.append("Authored infrastructure exceeds the bounded geometry budget")
	_layout_geometry_valid = _layout_geometry_errors.is_empty()
	if not _layout_geometry_valid:
		# Reject the whole infrastructure set. Never silently truncate a shared
		# route and draw a road that disagrees with a moving battery's path.
		_route_segments.clear()
		_runway_specs.clear()


func _fits_plateau(center: Vector2, extent: Vector2) -> bool:
	return absf(center.x) + extent.x <= useful_half_width and absf(center.y) + extent.y <= useful_half_length


func _build_infrastructure() -> void:
	if _layout.is_empty() or not _layout_geometry_valid:
		return
	var road_arrays := _new_infrastructure_arrays()
	for segment_index in range(_route_segments.size()):
		var spec: Dictionary = _route_segments[segment_index]
		var a: Vector2 = spec.from
		var b: Vector2 = spec.to
		var half_width := float(spec.half_width)
		var across := Vector2((b - a).normalized().y, -(b - a).normalized().x)
		var offsets := [-half_width - .35, -half_width, half_width, half_width + .35]
		var extent := Vector2(half_width, 0.0)
		for band in range(3):
			var left := float(offsets[band])
			var right := float(offsets[band + 1])
			_append_infrastructure_quad(road_arrays,
				a + across * left, a + across * right, b + across * left, b + across * right,
				Vector2(left, 0), Vector2(right, 0), Vector2(left, a.distance_to(b)), Vector2(right, a.distance_to(b)),
				extent, INFRASTRUCTURE_Y)
		# Only the region outside a segment receives a radial cap. A full disk
		# painted terrain over the preceding road and exposed a circular seam.
		# Interior bends add one outer arc; the rectangular strips already fill
		# the inner corner. No overlapping elevated soil disks are generated.
		if segment_index == 0 or _route_segments[segment_index - 1].route_id != spec.route_id:
			_append_road_cap(road_arrays, a, half_width, a - b)
		else:
			var previous: Dictionary = _route_segments[segment_index - 1]
			_append_road_join(road_arrays, a, half_width, a - Vector2(previous.from), b - a)
		if segment_index == _route_segments.size() - 1 or _route_segments[segment_index + 1].route_id != spec.route_id:
			_append_road_cap(road_arrays, b, half_width, b - a)
	route_segment_count = _route_segments.size()
	_commit_infrastructure("AuthoredServiceRoads", road_arrays, 1)
	var runway_arrays := _new_infrastructure_arrays()
	for spec in _runway_specs:
		var center: Vector2 = spec.center
		var extent: Vector2 = spec.extents
		var margin := extent + Vector2(.35, .66)
		_append_infrastructure_quad(runway_arrays,
			center + Vector2(-margin.x, -margin.y), center + Vector2(margin.x, -margin.y),
			center + Vector2(-margin.x, margin.y), center + Vector2(margin.x, margin.y),
			Vector2(-margin.x, -margin.y), Vector2(margin.x, -margin.y),
			Vector2(-margin.x, margin.y), Vector2(margin.x, margin.y), extent, INFRASTRUCTURE_Y + .005)
	runway_count = _runway_specs.size()
	_commit_infrastructure("AuthoredAirstrips", runway_arrays, 2)
	assert(infrastructure_triangle_count <= MAX_INFRASTRUCTURE_TRIANGLES)
	assert(triangle_count <= MAX_TRIANGLES)


func _new_infrastructure_arrays() -> Dictionary:
	return {
		"vertices": PackedVector3Array(), "normals": PackedVector3Array(),
		"uvs": PackedVector2Array(), "paint_uvs": PackedVector2Array(),
		"colors": PackedColorArray(), "extents": PackedFloat32Array(), "indices": PackedInt32Array()
	}


func _ground_uv(point: Vector2) -> Vector2:
	# Invert the exact surface grid mapping so a painted shoulder samples
	# the same tropical macro texel as the opaque ground immediately below.
	var v := point.y / (2.0 * _half_length(point.x)) + .5
	var nominal_z := (v - .5) * terrain_length
	var u := point.x / (2.0 * _half_width(nominal_z)) + .5
	return Vector2(u, v)


func _append_infrastructure_vertex(arrays: Dictionary, point: Vector2, paint_uv: Vector2, extent: Vector2, height: float) -> void:
	arrays.vertices.append(Vector3(point.x, height, point.y))
	arrays.normals.append(Vector3.UP)
	arrays.uvs.append(_ground_uv(point))
	arrays.paint_uvs.append(paint_uv)
	# All shared routes/strips are on the exactly flat central plateau.
	arrays.colors.append(Color(1.0, 0.0, 0.0, 1.0))
	# COLOR is RGBA8/clamped by Godot. Preserve exact metre extents in the
	# float custom attribute instead of truncating a 10 m strip to 1 m.
	arrays.extents.append(extent.x)
	arrays.extents.append(extent.y)


func _append_infrastructure_quad(arrays: Dictionary, a: Vector2, b: Vector2, c: Vector2, d: Vector2,
		uv_a: Vector2, uv_b: Vector2, uv_c: Vector2, uv_d: Vector2, extent: Vector2, height: float) -> void:
	var first: int = arrays.vertices.size()
	_append_infrastructure_vertex(arrays, a, uv_a, extent, height)
	_append_infrastructure_vertex(arrays, b, uv_b, extent, height)
	_append_infrastructure_vertex(arrays, c, uv_c, extent, height)
	_append_infrastructure_vertex(arrays, d, uv_d, extent, height)
	arrays.indices.append_array(PackedInt32Array([first, first + 1, first + 2, first + 1, first + 3, first + 2]))


func _append_road_cap(arrays: Dictionary, center: Vector2, half_width: float, outward: Vector2) -> void:
	_append_road_arc(arrays, center, half_width, outward.angle() - PI * .5, PI)


func _append_road_join(arrays: Dictionary, center: Vector2, half_width: float, incoming: Vector2, outgoing: Vector2) -> void:
	var from := incoming.normalized()
	var to := outgoing.normalized()
	var turn := from.cross(to)
	if absf(turn) < .0001:
		return
	var side := 1.0 if turn > 0.0 else -1.0
	var normal_from := Vector2(from.y, -from.x) * side
	var normal_to := Vector2(to.y, -to.x) * side
	var sweep := wrapf(normal_to.angle() - normal_from.angle(), -PI, PI)
	_append_road_arc(arrays, center, half_width, normal_from.angle(), sweep)


func _append_road_arc(arrays: Dictionary, center: Vector2, half_width: float, start_angle: float, sweep: float) -> void:
	var extent := Vector2(half_width, 1.0)
	var radius := half_width + .35
	var first: int = arrays.vertices.size()
	var slices := maxi(1, int(ceil(absf(sweep) / PI * 8.0)))
	_append_infrastructure_vertex(arrays, center, Vector2.ZERO, extent, INFRASTRUCTURE_Y)
	for index in range(slices + 1):
		var angle := start_angle + float(index) / slices * sweep
		var relative := Vector2(cos(angle), sin(angle)) * radius
		_append_infrastructure_vertex(arrays, center + relative, relative, extent, INFRASTRUCTURE_Y)
	for index in range(slices):
		if sweep > 0.0:
			arrays.indices.append_array(PackedInt32Array([first, first + index + 1, first + index + 2]))
		else:
			arrays.indices.append_array(PackedInt32Array([first, first + index + 2, first + index + 1]))


func _commit_infrastructure(node_name: String, source: Dictionary, layer: int) -> void:
	if source.indices.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = source.vertices
	arrays[Mesh.ARRAY_NORMAL] = source.normals
	arrays[Mesh.ARRAY_TEX_UV] = source.uvs
	arrays[Mesh.ARRAY_TEX_UV2] = source.paint_uvs
	arrays[Mesh.ARRAY_COLOR] = source.colors
	arrays[Mesh.ARRAY_CUSTOM0] = source.extents
	arrays[Mesh.ARRAY_INDEX] = source.indices
	var mesh := ArrayMesh.new()
	var custom_format := Mesh.ARRAY_CUSTOM_RG_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, custom_format)
	var material := ShaderMaterial.new()
	material.shader = SURFACE_SHADER
	for parameter in _shared_parameters:
		material.set_shader_parameter(parameter, _shared_parameters[parameter])
	material.set_shader_parameter("infrastructure_layer", layer)
	_infrastructure_materials.append(material)
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	var added: int = source.indices.size() / 3
	infrastructure_triangle_count += added
	triangle_count += added


func _build_geological_scenery() -> void:
	# Material-specific geology replaces palm/fern groups entirely. The real
	# tropical scenery path above remains intact for Coral/Jade/Storm/etc.
	var scale_count := clampf(terrain_width * terrain_length / 5500.0, .60, 1.0)
	var boulder_count := int((92 if _biome == "volcanic" else 64) * scale_count)
	var scree_count := int((128 if _biome == "volcanic" else 120) * scale_count)
	_scenery_clusters.clear()
	for index in range(clampi(int(terrain_length / 11.0), 6, 32)):
		var side := -1.0 if index % 2 == 0 else 1.0
		_scenery_clusters.append(Vector2(side * _random.randf_range(terrain_width * .365, terrain_width * .415),
			_random.randf_range(-useful_half_length, useful_half_length)))
	var source := SphereMesh.new()
	source.radius = .55
	source.height = .82
	source.radial_segments = 11
	source.rings = 5
	var geology := _weathered_rock(source)
	var material := _material(Color.WHITE)
	material.albedo_texture = _biome_albedo
	material.uv1_triplanar = true
	material.uv1_scale = Vector3(.25, .25, .25)
	material.roughness = .98
	geology.surface_set_material(0, material)
	var boulders := _new_group("BasaltOutcrops" if _biome == "volcanic" else "FrostedOutcrops", geology, boulder_count)
	var scree := _new_group("BasaltScree" if _biome == "volcanic" else "ArcticScree", geology, scree_count)
	for index in range(boulder_count):
		var anchor := _scenery_position()
		var size := Vector3(_random.randf_range(.62, 1.55), _random.randf_range(.45, 1.08), _random.randf_range(.70, 1.55))
		var basis := Basis.from_euler(Vector3(_random.randf_range(-.3, .3), _random.randf_range(0.0, TAU), _random.randf_range(-.25, .25))).scaled(size)
		boulders.multimesh.set_instance_transform(index, Transform3D(basis, anchor + Vector3(0, size.y * .17, 0)))
		boulders.multimesh.set_instance_color(index, Color.WHITE * _random.randf_range(.91, 1.08))
	for index in range(scree_count):
		var anchor := _scenery_position()
		var size := Vector3(_random.randf_range(.22, .62), _random.randf_range(.08, .22), _random.randf_range(.27, .78))
		var basis := Basis(Vector3.UP, _random.randf_range(0.0, TAU)).scaled(size)
		scree.multimesh.set_instance_transform(index, Transform3D(basis, anchor + Vector3(0, size.y * .17, 0)))
		scree.multimesh.set_instance_color(index, Color.WHITE * _random.randf_range(.94, 1.08))
	prop_count = boulder_count + scree_count
	assert(prop_count <= MAX_PROP_INSTANCES)

func _add_triangle(builder: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	builder.add_vertex(a)
	builder.add_vertex(b)
	builder.add_vertex(c)
