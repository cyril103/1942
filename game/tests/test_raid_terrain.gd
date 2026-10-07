extends SceneTree
## Terrain contract: inspect actual meshes/materials for all authored sectors.
## No campaign quota, real collider, human-play or FPS claim is made by this test.
const TERRAIN := preload("res://scripts/campaign/assault_terrain.gd")
const LAYOUTS := preload("res://scripts/campaign/raid_layouts.gd")
const WIDTH := 58.0
const SAFE_X := 15.0
const EPS := .003
var checks := 0
var failures: Array[String] = []
var sectors: Array[Dictionary] = []

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func _mission(sector: int) -> Dictionary:
	var data := LAYOUTS.layout_for_sector(sector)
	return {"id": int(data.mission), "sector": sector, "biome": str(data.biome)}

func _length(sector: int) -> float:
	return maxf(120.0, (float(LAYOUTS.MIN_TARGET_HALF_LENGTH[sector]) + LAYOUTS.COAST_MARGIN + 8.0) * 2.0)

func _near(a: Vector2, b: Vector2) -> bool:
	return a.distance_to(b) <= EPS

func _xz(point: Vector3) -> Vector2:
	return Vector2(point.x, point.z)

func _has_vertex(vertices: PackedVector3Array, at: Vector2) -> bool:
	for vertex in vertices:
		if _near(_xz(vertex), at):
			return true
	return false

func _cross(a: Vector2, b: Vector2) -> float:
	return a.x * b.y - a.y * b.x

func _in_triangle(point: Vector2, a: Vector2, b: Vector2, c: Vector2) -> bool:
	var ab := _cross(b - a, point - a)
	var bc := _cross(c - b, point - b)
	var ca := _cross(a - c, point - c)
	return (ab >= -EPS and bc >= -EPS and ca >= -EPS) or (ab <= EPS and bc <= EPS and ca <= EPS)

func _covered(arrays: Array, point: Vector2) -> bool:
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for first in range(0, indices.size(), 3):
		if _in_triangle(point, _xz(vertices[indices[first]]), _xz(vertices[indices[first + 1]]), _xz(vertices[indices[first + 2]])):
			return true
	return false

func _segment_distance(point: Vector2, a: Vector2, b: Vector2) -> float:
	var axis := b - a
	var t := clampf((point - a).dot(axis) / axis.length_squared(), 0.0, 1.0)
	return point.distance_to(a + axis * t)

func _core_distance(point: Vector2, points: Array) -> float:
	var minimum := INF
	for index in range(1, points.size()):
		minimum = minf(minimum, _segment_distance(point, _xz(points[index - 1]), _xz(points[index])))
	return minimum

func _mesh_checks(node: MeshInstance3D, terrain: Node3D, label: String, layer: int) -> Array:
	var material := node.material_override as ShaderMaterial
	check(material != null and material.shader == terrain.surface_material.shader, label + " shares the real ground shader")
	check(int(material.get_shader_parameter("infrastructure_layer")) == layer, label + " selects the real paint layer")
	check(bool(material.get_shader_parameter("use_shared_layout")), label + " has no invented legacy route")
	check(not material.shader.code.contains("ALPHA ="), label + " is opaque and writes depth")
	check(not material.shader.code.contains("depth_draw_never"), label + " stays out of transparent fringe")
	var mesh := node.mesh as ArrayMesh
	var format := mesh.surface_get_format(0)
	check((format & Mesh.ARRAY_FORMAT_CUSTOM0) != 0, label + " stores custom extents")
	check(((format >> Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) & Mesh.ARRAY_FORMAT_CUSTOM_MASK) == Mesh.ARRAY_CUSTOM_RG_FLOAT, label + " preserves metre extents as RG float")
	var arrays := mesh.surface_get_arrays(0)
	check(typeof(arrays[Mesh.ARRAY_CUSTOM0]) == TYPE_PACKED_FLOAT32_ARRAY, label + " returns full float custom data")
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var custom: PackedFloat32Array = arrays[Mesh.ARRAY_CUSTOM0]
	var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	check(custom.size() == vertices.size() * 2 and uv2.size() == vertices.size(), label + " has complete per-vertex paint attributes")
	var bounds_ok := true
	var winding_ok := true
	for vertex in vertices:
		bounds_ok = bounds_ok and vertex.is_finite() and absf(vertex.x) <= terrain.useful_half_width + EPS and absf(vertex.z) <= terrain.useful_half_length + EPS
		bounds_ok = bounds_ok and absf(terrain.surface_height(_xz(vertex)) - TERRAIN.PLATEAU_Y) < EPS
		bounds_ok = bounds_ok and vertex.y >= TERRAIN.INFRASTRUCTURE_Y - EPS and vertex.y <= TERRAIN.INFRASTRUCTURE_Y + .01
	for first in range(0, indices.size(), 3):
		var a := vertices[indices[first]]
		var b := vertices[indices[first + 1]]
		var c := vertices[indices[first + 2]]
		winding_ok = winding_ok and (b - a).cross(c - a).y < 0.0
	check(bounds_ok, label + " complete geometry rests on the finite flat plateau")
	check(winding_ok, label + " real triangles face upward with Godot winding")
	return arrays

func _sector_checks(terrain: Node3D, sector: int, layout: Dictionary) -> void:
	var label := "M%02d" % int(layout.mission)
	var status: Dictionary = terrain.infrastructure_status()
	check(status.valid, label + " passes visual input guards: " + str(status.errors))
	check(status.layout_id == str(layout.id), label + " consumes the authored identity")
	check(is_same(terrain._layout, layout), label + " preserves the shared instance")
	check(status.shared_layout and status.opaque, label + " uses shared opaque infrastructure")
	check(terrain.triangle_count <= TERRAIN.MAX_TRIANGLES, label + " complete triangle budget")
	check(terrain.prop_count <= TERRAIN.MAX_PROP_INSTANCES, label + " scenery instance budget")
	check(terrain.infrastructure_triangle_count <= TERRAIN.MAX_INFRASTRUCTURE_TRIANGLES, label + " infrastructure budget")
	check(terrain.coast_triangle_count > 0 and terrain.coast_triangle_count < terrain.triangle_count, label + " retains a narrow coast")
	check(not terrain.surface_material.shader.code.contains("ALPHA ="), label + " central ground is opaque")
	check(terrain.coast_material.shader.code.contains("ALPHA = smoothstep(0.16, 0.34, coast_depth);"), label + " original narrow alpha hook remains")
	check(terrain.coast_material.shader.code.contains("ocean_surface(world_xz)"), label + " coast still uses the shared ocean")
	check(terrain.shoreline.visible, label + " original shoreline ribbon remains")
	var road_node := terrain.get_node_or_null("AuthoredServiceRoads") as MeshInstance3D
	var strip_node := terrain.get_node_or_null("AuthoredAirstrips") as MeshInstance3D
	check(road_node != null and strip_node != null, label + " creates actual authored meshes")
	if road_node == null or strip_node == null:
		return
	var roads := _mesh_checks(road_node, terrain, label + " roads", 1)
	var strips := _mesh_checks(strip_node, terrain, label + " strips", 2)
	var road_vertices: PackedVector3Array = roads[Mesh.ARRAY_VERTEX]
	var strip_custom: PackedFloat32Array = strips[Mesh.ARRAY_CUSTOM0]
	var segment_total := 0
	var route_data: Dictionary = layout.routes
	for route_id in route_data:
		var route: Dictionary = route_data[route_id]
		var points: Array = route.world_points
		segment_total += points.size() - 1
		var route_matches := true
		for point in points:
			route_matches = route_matches and _has_vertex(road_vertices, _xz(point))
		for index in range(1, points.size()):
			for weight in [.0, .25, .5, .75, 1.0]:
				route_matches = route_matches and _covered(roads, _xz(points[index - 1]).lerp(_xz(points[index]), weight))
		check(route_matches, label + " renders the exact centreline " + str(route_id))
	check(status.route_segments == segment_total, label + " consumes every segment without truncation")
	check(status.runways == layout.runways.size(), label + " consumes every airstrip")
	var strip_index := 0
	for strip in layout.runways:
		var center := _xz(strip.position)
		var extent: Vector2 = strip.world_half_extents
		var strip_matches := _covered(strips, center)
		for side in [-1.0, 1.0]:
			strip_matches = strip_matches and _covered(strips, center + Vector2(side * extent.x, 0))
			strip_matches = strip_matches and _covered(strips, center + Vector2(0, side * extent.y))
		# Each actual strip quad stores its unrounded X/Z extents four times.
		for corner in range(4):
			var first := strip_index * 8 + corner * 2
			strip_matches = strip_matches and absf(strip_custom[first] - extent.x) < EPS and absf(strip_custom[first + 1] - extent.y) < EPS
		check(strip_matches, label + " preserves actual strip geometry/extents " + str(strip.id))
		strip_index += 1
	var mobile_total := 0
	for target in layout.targets:
		var footprint: Vector2 = target.footprint
		var center := _xz(target.position)
		var foundation_ok := true
		for x in [-.5, .5]:
			for z in [-.5, .5]:
				foundation_ok = foundation_ok and absf(terrain.surface_height(center + Vector2(x * footprint.x, z * footprint.y)) - TERRAIN.PLATEAU_Y) < EPS
		check(foundation_ok, label + " target foundation shares the plateau " + str(target.id))
		if not target.mobile:
			continue
		mobile_total += 1
		var route: Dictionary = route_data[target.mobile_route_id]
		var points: Array = route.world_points
		var on_core := true
		for index in range(1, points.size()):
			for weight in [.0, .25, .5, .75, 1.0]:
				var station := _xz(points[index - 1]).lerp(_xz(points[index]), weight)
				for x in [-.5, .5]:
					for z in [-.5, .5]:
						var corner := station + Vector2(x * footprint.x, z * footprint.y)
						on_core = on_core and _core_distance(corner, points) + LAYOUTS.CLEARANCE <= float(route.width) * .5 + EPS and _covered(roads, corner)
		check(on_core, label + " full mobile footprint stays on its rendered road " + str(target.id))
	check(mobile_total == (6 if sector == 4 else 0), label + " mobile routes remain sector specific")
	var groups: Array = terrain._groups
	var group_names: Array[String] = []
	for group in groups:
		group_names.append(str(group.name))
	if sector in [4, 6]:
		check(status.native_albedo_loaded and terrain._landscape == null, label + " uses its native albedo without a tropical macro")
		var texture_image: Image = terrain._biome_albedo.get_image()
		check(texture_image != null and texture_image.has_mipmaps(), label + " native material imports mipmaps for distant/oblique filtering")
		check(groups.size() == 2 and not group_names.has("PalmTrunks") and not group_names.has("PalmCrowns"), label + " geology replaces tropical foliage")
		check(terrain.prop_count <= (220 if sector == 4 else 184), label + " geological scenery stays bounded")
	else:
		check(not status.native_albedo_loaded and terrain._landscape != null, label + " preserves the original tropical macro")
		check(group_names.has("PalmTrunks") and group_names.has("PalmCrowns") and group_names.has("LowScrub"), label + " preserves living tropical scenery")
	for quality in range(3):
		terrain.set_quality(quality)
		var visibility_ok := true
		var shadows_ok := true
		for group in groups:
			visibility_ok = visibility_ok and group.multimesh.visible_instance_count == int(ceil(group.multimesh.instance_count * [.55, .82, 1.0][quality]))
			shadows_ok = shadows_ok and group.cast_shadow == (GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if quality == 0 else GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
		check(visibility_ok and shadows_ok, label + " quality %d preserves bounded instances and shadows" % quality)
	sectors.append({"mission": int(layout.mission), "triangles": terrain.triangle_count, "infrastructure_triangles": terrain.infrastructure_triangle_count, "props": terrain.prop_count, "segments": status.route_segments, "strips": status.runways, "biome": str(layout.biome)})

func _run() -> void:
	for sector in range(8):
		var terrain: Node3D = TERRAIN.new()
		root.add_child(terrain)
		var mission := _mission(sector)
		var length := _length(sector)
		var layout := LAYOUTS.instantiate_layout(mission, WIDTH, length, SAFE_X)
		check(bool(layout.valid), "Sector%d test dimensions satisfy the real layout" % sector)
		terrain.configure(mission, WIDTH, length, layout)
		if not (sector in [4, 6]):
			terrain.set_ground_detail(load("res://assets/environment/raid-v2/coral-grass-detail.png"))
		_sector_checks(terrain, sector, layout)
		root.remove_child(terrain)
		terrain.free()
		await process_frame
	var reused: Node3D = TERRAIN.new()
	root.add_child(reused)
	for sector in [0, 4, 6, 0]:
		var mission := _mission(sector)
		var layout := LAYOUTS.instantiate_layout(mission, WIDTH, _length(sector), SAFE_X)
		reused.configure(mission, WIDTH, _length(sector), layout)
		check(reused.get_child_count() == (7 if sector in [4, 6] else 9), "Reconfigure sector%d retains only current terrain groups" % sector)
		check(reused.infrastructure_status().valid, "Reconfigure sector%d uses the current authored route set" % sector)
		await process_frame
	var malformed := LAYOUTS.instantiate_layout(_mission(0), WIDTH, _length(0), SAFE_X)
	malformed.routes["invalid"] = {"width": 1.0, "world_points": [Vector3.ZERO, Vector3(WIDTH, 0, 0)]}
	reused.configure(_mission(0), WIDTH, _length(0), malformed)
	check(not reused.infrastructure_status().valid and reused.infrastructure_triangle_count == 0, "Out-of-plateau authored routes reject the entire set without truncation")
	check(reused.get_node_or_null("AuthoredServiceRoads") == null, "Invalid set cannot draw a partial route under a mobile battery")
	root.remove_child(reused)
	reused.free()
	await process_frame
	TERRAIN._coast_shader_cache = null
	await process_frame
	var result := {"checks": checks, "failures": failures, "sectors": sectors, "human_validation": "NOT_PERFORMED", "tiling_capture": "SEPARATE_CAPTURE_REQUIRED", "runtime_colliders": "SEPARATE_COMBAT_SUITE_REQUIRED", "performance": "NOT_MEASURED"}
	var file := FileAccess.open("res://tests/raid-terrain-results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	print("Terrain contract: %d checks / %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
