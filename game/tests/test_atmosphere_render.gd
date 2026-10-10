extends SceneTree
## Run with a real renderer and --audio-driver Dummy. No actors or audio nodes.
## These comparisons exercise production geometry, textures, uniforms and GLSL.
const SEA := preload("res://scripts/seascape.gd")
const OUTPUT := "C:/ChatGPT/1942/renders/atmosphere-render-validation"
const RESOLUTION := Vector2i(640,360)
var checks := 0
var failures: Array[String] = []
var sea: Node3D
var island: MeshInstance3D
var camera: Camera3D
var scene: Node3D

func _initialize() -> void: _run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func capture() -> Image:
	# Render-server changes need a completed draw, not just a process tick.
	for frame in range(3): await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func render_sample(phase: float, scroll_a: float, scroll_b: float, height: float = 1.65) -> Image:
	for material in [sea.ocean_material,island.material_override]:
		material.set_shader_parameter("wave_phase",phase)
		material.set_shader_parameter("scroll_a",scroll_a)
		material.set_shader_parameter("scroll_b",scroll_b)
	island.material_override.set_shader_parameter("relief_height",height)
	return await capture()

func difference(a: Image, b: Image, region: Rect2i) -> Dictionary:
	var total := 0.0
	var peak := 0.0
	var outliers := 0
	for y in range(region.position.y,region.end.y):
		for x in range(region.position.x,region.end.x):
			var ca := a.get_pixel(x,y)
			var cb := b.get_pixel(x,y)
			var delta := Vector3(absf(ca.r-cb.r),absf(ca.g-cb.g),absf(ca.b-cb.b))
			var maximum := maxf(delta.x,maxf(delta.y,delta.z))
			total += (delta.x+delta.y+delta.z)/3.0
			peak = maxf(peak,maximum)
			if maximum>2.01/255.0: outliers += 1
	return {"mean":total/region.get_area(),"maximum":peak,"outliers":outliers}

func equivalent(a: Image, b: Image, label: String) -> void:
	var d := difference(a,b,Rect2i(Vector2i.ZERO,RESOLUTION))
	# 8-bit readback and float sin/fract rounding may alter a few quantization
	# boundaries. Allow <0.1 byte mean error and <=2 bytes for every pixel.
	check(d.mean<.1/255.0 and d.outliers==0,label)
	print(label,": ",d)

func coastal_pixels() -> Array[Vector2i]:
	# Read the actual mesh UV mapping, rather than assuming PlaneMesh orientation.
	var arrays := island.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var dx := Vector2.ZERO
	var dz := Vector2.ZERO
	for i in range(1,vertices.size()):
		if absf(vertices[i].x-vertices[0].x)>.01 and is_equal_approx(vertices[i].z,vertices[0].z): dx = (uvs[i]-uvs[0])/(vertices[i].x-vertices[0].x)
		if absf(vertices[i].z-vertices[0].z)>.01 and is_equal_approx(vertices[i].x,vertices[0].x): dz = (uvs[i]-uvs[0])/(vertices[i].z-vertices[0].z)
	var relief: Image = island.material_override.get_shader_parameter("relief_atlas").get_image()
	var cell: Vector2 = island.material_override.get_shader_parameter("atlas_cell")
	var result: Array[Vector2i] = []
	for y in range(RESOLUTION.y):
		for x in range(RESOLUTION.x):
			var local := island.to_local(camera.project_position(Vector2(x+.5,y+.5),1.0))
			var uv := uvs[0]+dx*(local.x-vertices[0].x)+dz*(local.z-vertices[0].z)
			if uv.x<.07 or uv.x>.93 or uv.y<.07 or uv.y>.93: continue
			var atlas_uv := (uv+cell)*.5
			var texel := relief.get_pixel(clampi(int(atlas_uv.x*relief.get_width()),0,relief.get_width()-1),clampi(int(atlas_uv.y*relief.get_height()),0,relief.get_height()-1))
			# The relief's documented alpha stores distance, green marks dry land.
			# Sample water just beyond beaches, excluding terrain lighting changes.
			if texel.g<.1 and texel.a>.505 and texel.a<.64: result.append(Vector2i(x,y))
	return result

func luminance(color: Color) -> float:
	return color.r*.2126+color.g*.7152+color.b*.0722

func _run() -> void:
	# The silent test launcher supplies --audio-driver Dummy. Godot consumes that
	# engine option before exposing script arguments; mute the empty scene too.
	AudioServer.set_bus_mute(0,true)
	if DisplayServer.get_name()=="headless":
		push_error("This test requires a real GPU renderer; do not run with --headless.")
		quit(2)
		return
	root.mode = Window.MODE_WINDOWED
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = RESOLUTION
	root.msaa_3d = Viewport.MSAA_DISABLED
	root.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	await process_frame
	scene = Node3D.new()
	root.add_child(scene)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 22
	camera.position.y = 35
	camera.rotation.x = -PI*.5
	scene.add_child(camera)
	camera.current = true
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color(.025,.065,.09)
	world.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	scene.add_child(world)
	sea = SEA.new()
	sea.camera = camera
	scene.add_child(sea)
	sea.set_physics_process(false)
	sea.set_process(false)
	sea.configure_sector({"seed":202119,"biome":"coral"})
	for other in sea.islands: other.hide()
	island = sea.islands[0]
	sea.naval_corridor = false
	sea._next_variant = 4
	sea._configure_island(island,0.0)
	island.position = Vector3(0,-3.0,0)
	island.rotation = Vector3.ZERO
	island.mesh.size = Vector2(18,18)
	island.material_override.set_shader_parameter("island_size",Vector2(18,18))
	island.show()
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var baseline := await render_sample(0,0,0)
	check(baseline.get_size()==RESOLUTION,"GPU returns the requested production frame")
	baseline.save_png(OUTPUT.path_join("phase-0.png"))
	equivalent(baseline,await render_sample(TAU,0,0),"Full sea and coast agree at phase 0 and TAU")
	equivalent(baseline,await render_sample(0,2,0),"First water layer wraps continuously from scroll 2 to 0")
	equivalent(baseline,await render_sample(0,0,2),"Second water layer wraps continuously from scroll 2 to 0")
	var phase_image := await render_sample(.73,.31,.77)
	var ocean_change := difference(baseline,phase_image,Rect2i(16,60,96,240))
	check(ocean_change.mean>.001,"Open water truly animates in the GPU output")
	await render_sample(0,0,0)
	sea._wave_phase = .73
	sea._scroll_a = .31
	sea._scroll_b = .77
	sea._physics_process(0)
	equivalent(phase_image,await capture(),"Production seascape binds the same phases to sea and coast")
	var pixels := coastal_pixels()
	check(pixels.size()>100,"Comparison includes a substantial wet shoreline region")
	var minimum := PackedFloat32Array()
	var maximum := PackedFloat32Array()
	minimum.resize(pixels.size())
	minimum.fill(INF)
	maximum.resize(pixels.size())
	# A/B renders retain the real shader. relief_height=0 disables its surf path.
	# Positive coastal excess isolates bright foam from moving open-sea ribbons,
	# lee shadows and static land; compare that excess over several wave phases.
	for phase in [0.0,.4,.9,1.45]:
		var with_surf := await render_sample(phase,0,0)
		var without_surf := await render_sample(phase,0,0,0)
		with_surf.save_png(OUTPUT.path_join("surf-%.2f.png" % phase))
		for i in range(pixels.size()):
			var excess := maxf(0,luminance(with_surf.get_pixelv(pixels[i]))-luminance(without_surf.get_pixelv(pixels[i])))
			minimum[i] = minf(minimum[i],excess)
			maximum[i] = maxf(maximum[i],excess)
	var moving_foam := 0
	var peak_foam := 0.0
	for i in range(pixels.size()):
		if maximum[i]-minimum[i]>4.0/255.0: moving_foam += 1
		peak_foam = maxf(peak_foam,maximum[i])
	check(peak_foam>.04,"Production shoreline renders visible foam above its water surface")
	check(moving_foam>=24,"At least 24 coastal pixels show real moving foam beyond quantization noise")
	print("ATMOSPHERE GPU: ",checks," checks; coastal pixels ",pixels.size(),"; animated foam pixels ",moving_foam,"; foam peak ",peak_foam,"; water delta ",ocean_change,"; failures ",failures)
	scene.queue_free()
	await process_frame
	await process_frame
	quit(0 if failures.is_empty() else 1)
