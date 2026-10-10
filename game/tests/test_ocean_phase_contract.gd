extends SceneTree
## Static shader guard for the periodic phase supplied by Seascape. Non-integral
## harmonics or unwrapped noise translation cause visible jumps every 9.67 s.
var checks := 0
var failures: Array[String] = []
func check(ok: bool,message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)
func _initialize() -> void:
	var multiplier := RegEx.new()
	multiplier.compile("wave_phase\\s*\\*\\s*([0-9]*\\.?[0-9]+)|([0-9]*\\.?[0-9]+)\\s*\\*\\s*wave_phase")
	var linear_noise := RegEx.new()
	linear_noise.compile("noise\\([^;\\n]*wave_phase")
	for path in ["res://shaders/ocean_surface.gdshaderinc","res://shaders/island.gdshader","res://shaders/assault_terrain.gdshader"]:
		var code := FileAccess.get_file_as_string(path)
		for found in multiplier.search_all(code):
			var value := float(found.get_string(1) if not found.get_string(1).is_empty() else found.get_string(2))
			check(is_equal_approx(value,roundf(value)),"All bounded phase harmonics close at TAU: "+path)
		check(linear_noise.search(code)==null,"Noise cannot translate directly with the wrapping phase: "+path)
	var source := load("res://shaders/assault_terrain.gdshader") as Shader
	var terrain := preload("res://scripts/campaign/assault_terrain.gd")
	# The opaque plateau, authored infrastructure and coastal fringe must all
	# use this one source; only blend/depth and alpha differ for the fringe.
	check(terrain.SURFACE_SHADER==source,"Raid road, plateau and coast use one authored shader")
	var coast := Shader.new()
	coast.code = source.code.replace("render_mode diffuse_burley, specular_schlick_ggx;","render_mode blend_mix, depth_draw_never, diffuse_burley, specular_schlick_ggx;").replace("// COAST_ALPHA_HOOK","ALPHA = smoothstep(0.16, 0.34, coast_depth);")
	var expected: Array[String] = ["wave_phase","scroll_a","scroll_b","reflection_tint","ocean_tint","ocean_texture"]
	for shader in [source,coast]:
		var names: Array[String] = []
		for uniform in shader.get_shader_uniform_list(): names.append(str(uniform.name))
		for key in expected: check(names.has(key),"Both raid materials expose shared ocean uniform "+key)
	var body_start := source.code.find("void vertex()")
	check(source.code.substr(body_start).replace("// COAST_ALPHA_HOOK","")==coast.code.substr(coast.code.find("void vertex()")).replace("ALPHA = smoothstep(0.16, 0.34, coast_depth);",""),"Infrastructure and fringe preserve identical geometry, texture and surf calculations")
	print("OCEAN PHASE CONTRACT: ",checks," checks; failures: ",failures)
	quit(0 if failures.is_empty() else 1)
