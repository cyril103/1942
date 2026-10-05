extends SceneTree

var failures: Array[String] = []
var checks: int = 0


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)


func _run() -> void:
	var scene: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	scene.get_node("Departure").finish_immediately()
	await process_frame
	var sea = scene.get_node("Seascape")
	sea.set_physics_process(false)
	scene.get_node("Player").set_physics_process(false)
	var initial_count: int = sea.get_child_count()
	check(sea.islands.size() == 6 and initial_count == 7, "One ocean and a fixed pool of six islands")
	var ids: Array[int] = []
	for island in sea.islands:
		ids.append(island.get_instance_id())
		check(island.position.y < -2.0, "Scenery must remain below the aircraft")
	var before: float = sea.islands[0].position.z
	var phase_before: float = sea._scroll_a
	var screen_before: Vector2 = sea.camera.unproject_position(sea.islands[0].global_position)
	sea._physics_process(0.5)
	var screen_after: Vector2 = sea.camera.unproject_position(sea.islands[0].global_position)
	check(is_equal_approx(sea.islands[0].position.z - before, sea.scroll_speed * 0.5), "Island speed matches configured scroll")
	check(screen_after.y > screen_before.y, "Islands must scroll TOP TO BOTTOM on screen")
	check(absf(sea._scroll_a - phase_before - sea.scroll_speed * 0.5 / sea.TILE_SIZE) < 0.0001, "Ocean and islands use the same scroll distance")
	check(sea.ISLAND_ATLAS.get_image().has_mipmaps(), "Coastal blending requires imported atlas mipmaps")
	check(sea.OCEAN_TEXTURE.get_image().has_mipmaps(), "Ocean texture requires mipmaps for stable small waves")
	for coastal_island in sea.islands:
		var material: ShaderMaterial = coastal_island.material_override
		check(material.get_shader_parameter("ocean_texture") == sea.OCEAN_TEXTURE, "Coasts sample the same ocean texture")
		check(is_equal_approx(material.get_shader_parameter("scroll_a"), sea._scroll_a), "Coastal waves remain in phase with the ocean")

	# Simulate 30 minutes with the exact same physics stepping used at runtime.
	var variant_counts: Array[int] = [0, 0, 0, 0]
	for frame in range(30 * 60 * 60):
		sea._physics_process(1.0 / 60.0)
		if frame % 600 == 0:
			check(sea.get_child_count() == initial_count, "Scrolling must not allocate more scenery nodes")
			check(sea._scroll_a >= 0.0 and sea._scroll_a < 2.0, "Primary UV phase remains bounded")
			check(sea._scroll_b >= 0.0 and sea._scroll_b < 2.0, "Secondary UV phase remains bounded")
			check(sea._wave_phase >= 0.0 and sea._wave_phase < TAU, "Wave phase remains bounded")
			for index in range(sea.islands.size()):
				var island: MeshInstance3D = sea.islands[index]
				check(island.get_instance_id() == ids[index], "Existing islands are reused")
				check(island.position.z > -240.0 and island.position.z < 30.0, "Island coordinates stay bounded")
				variant_counts[int(island.get_meta("variant"))] += 1
	check(sea.recycle_count > 100, "Long simulation must exercise repeated recycling")
	for coastal_island in sea.islands:
		var material: ShaderMaterial = coastal_island.material_override
		check(is_equal_approx(material.get_shader_parameter("scroll_b"), sea._scroll_b), "Coastal waves remain synchronized after phase wrapping")
	for count in variant_counts:
		check(count > 0, "All four variants must appear")

	# A forced recycle occurs only after the entire rotated square has left view.
	var island: MeshInstance3D = sea.islands[0]
	var radius: float = island.get_meta("radius")
	island.position.z = sea._view_half.y + radius + 2.1
	sea._physics_process(0.0)
	check(island.position.z + float(island.get_meta("radius")) < -sea._view_half.y, "Recycled island must reappear wholly above screen")

	for size in [Vector2i(1920, 1080), Vector2i(2560, 1080), Vector2i(720, 1280)]:
		root.size = size
		await process_frame
		await process_frame
		var ocean_size: Vector2 = sea.ocean.mesh.size
		check(ocean_size.x > sea._view_half.x * 2.0 and ocean_size.y > sea._view_half.y * 2.0, "Ocean covers viewport after resize")

	var image := Image.load_from_file(ProjectSettings.globalize_path("res://assets/environment/islands-atlas.png"))
	check(image.has_mipmaps() == false and image.get_width() > 1000, "Original atlas retained at native resolution")
	check(image.get_pixel(0, 0).a < 0.02, "Atlas has real alpha transparency")
	var report := {"checks": checks, "failures": failures, "simulated_minutes": 30,
		"recycles": sea.recycle_count, "scenery_nodes": initial_count, "variants_sampled": variant_counts}
	var file := FileAccess.open("res://tests/seascape-results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("SEASCAPE: ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
