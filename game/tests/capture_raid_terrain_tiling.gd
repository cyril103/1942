extends SceneTree
## GPU-only inspection: continuous 3 x 3 repetitions through the real shader.
## Uses the gameplay lights/exposure; images are evidence for human inspection.
const TERRAIN := preload("res://scripts/campaign/assault_terrain.gd")
const LAYOUTS := preload("res://scripts/campaign/raid_layouts.gd")
var capture_dir := OS.get_user_data_dir().path_join("raid-terrain-tiling")
var stage: Node3D
var camera: Camera3D
var patch: MeshInstance3D
var records: Array[Dictionary] = []

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output-dir="): capture_dir = argument.trim_prefix("--output-dir=")
	_run.call_deferred()

func _make_stage() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(.025, .065, .09)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(.74, .83, .95)
	environment.ambient_light_energy = .65
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world := WorldEnvironment.new()
	world.environment = environment
	stage.add_child(world)
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(-.95, -.5, -.35)
	key.light_color = Color(1, .94, .82)
	key.light_energy = 1.4
	stage.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(-.5, 2.5, .4)
	fill.light_color = Color(.63, .78, 1)
	fill.light_energy = .45
	stage.add_child(fill)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.near = .1
	camera.far = 80.0
	camera.current = true
	stage.add_child(camera)
	patch = MeshInstance3D.new()
	patch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stage.add_child(patch)

func _patch_mesh(tile_metres: float) -> ArrayMesh:
	# One continuous 12/19m surface, not nine separate planes that reset local
	# p and would introduce artificial seams in the secondary texture sample.
	var half := tile_metres * 1.5
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(-half, 0, -half), Vector3(half, 0, -half),
		Vector3(-half, 0, half), Vector3(half, 0, half)
	])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(3, 0), Vector2(0, 3), Vector2(3, 3)])
	arrays[Mesh.ARRAY_COLOR] = PackedColorArray([Color(1, 0, 0), Color(1, 0, 0), Color(1, 0, 0), Color(1, 0, 0)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 1, 3, 2])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _capture(label: String, biome: String, tile_metres: float, secondary: float, oblique: bool) -> void:
	patch.mesh = _patch_mesh(tile_metres)
	var material := patch.material_override as ShaderMaterial
	material.set_shader_parameter("biome_tile_metres", tile_metres)
	material.set_shader_parameter("biome_secondary_strength", secondary)
	camera.size = tile_metres * 3.30
	camera.position = Vector3(0, tile_metres * 4.5, tile_metres * 2.0 if oblique else 0)
	camera.look_at(Vector3.ZERO, Vector3.UP if oblique else Vector3.FORWARD)
	for frame in range(5):
		await process_frame
	await RenderingServer.frame_post_draw
	var capture := root.get_texture().get_image()
	var path := ProjectSettings.globalize_path(capture_dir.path_join(label + ".png"))
	var error := capture.save_png(path)
	if error != OK:
		push_error("Cannot save tiling capture " + path)
	records.append({
		"file": path, "biome": biome, "tile_metres": tile_metres,
		"repetitions": "3x3 continuous local X/Z", "secondary_strength": secondary,
		"view": "oblique" if oblique else "vertical",
		"shader": "res://shaders/assault_terrain.gdshader",
		"lights": "main.tscn gameplay key/fill and ambient values",
		"inspection": "PENDING", "save_error": error
	})

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Tiling captures require the real renderer, not headless/dummy output")
		quit(2)
		return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 1280)
	var directory := ProjectSettings.globalize_path(capture_dir)
	DirAccess.make_dir_recursive_absolute(directory)
	_make_stage()
	for sector in [4, 6]:
		var authored := LAYOUTS.layout_for_sector(sector)
		var terrain: Node3D = TERRAIN.new()
		stage.add_child(terrain)
		terrain.hide()
		var mission := {"id": int(authored.mission), "sector": sector, "biome": str(authored.biome)}
		var length := (float(LAYOUTS.MIN_TARGET_HALF_LENGTH[sector]) + LAYOUTS.COAST_MARGIN + 8.0) * 2.0
		var layout := LAYOUTS.instantiate_layout(mission, 58.0, length, 15.0)
		terrain.configure(mission, 58.0, length, layout)
		var material := terrain.surface_material.duplicate() as ShaderMaterial
		material.set_shader_parameter("field_size", Vector2(512, 512))
		material.set_shader_parameter("use_shared_layout", true)
		material.set_shader_parameter("infrastructure_layer", 0)
		patch.material_override = material
		var biome := str(authored.biome)
		await _capture(biome + "-raw-3x3-4m", biome, 4.0, 0.0, false)
		await _capture(biome + "-gameplay-3x3-4m", biome, 4.0, .2, false)
		await _capture(biome + "-gameplay-oblique-3x3-4m", biome, 4.0, .2, true)
		await _capture(biome + "-raw-3x3-6m35", biome, 4.0 / .63, 0.0, false)
		stage.remove_child(terrain)
		terrain.free()
		await process_frame
	var file := FileAccess.open(directory.path_join("captures.json"), FileAccess.WRITE)
	if file==null:
		push_error("Cannot save tiling evidence")
		quit(1)
		return
	file.store_string(JSON.stringify({"records": records, "human_inspection": "PENDING", "seamless_verified": false, "performance": "NOT_MEASURED"}, "\t"))
	file.close()
	root.remove_child(stage)
	stage.free()
	await process_frame
	TERRAIN._coast_shader_cache = null
	await process_frame
	print("Terrain tiling: %d captures saved for inspection" % records.size())
	var failures := records.filter(func(record): return int(record.save_error) != OK).size()
	quit(0 if failures == 0 else 1)
