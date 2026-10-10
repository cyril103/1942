extends RefCounted
## Aircraft and naval finishes preserve authored UVs and imported resources.
const PAINT := preload("res://shaders/fleet_paint.gdshader")
const GLASS := preload("res://shaders/fleet_glass.gdshader")
const HULL := preload("res://shaders/campaign_surface.gdshader")
const ATLAS := preload("res://assets/campaign/material-atlas.png")
static var sky_cache: Dictionary = {}
# Sun, fill, high sky, horizon, reflected sea, key / fill / ambient energy.
const PALETTES := {
	"coral": [Color("fff0cf"),Color("81bad5"),Color("1d6090"),Color("bce1e3"),Color("184b54"),1.85,.30,.34],
	"convoy": [Color("ffe1b0"),Color("88afcf"),Color("36577a"),Color("b9cfd5"),Color("1b3a4c"),1.80,.32,.34],
	"storm": [Color("d4e9ff"),Color("789aaa"),Color("1c3047"),Color("839daa"),Color("1a303c"),1.45,.38,.40],
	"jade": [Color("ffe9bd"),Color("84c3b9"),Color("215366"),Color("b6d4c1"),Color("1b4c42"),1.88,.29,.32],
	"dusk": [Color("ffb875"),Color("8d9ad7"),Color("252c59"),Color("f0a878"),Color("24374e"),1.75,.42,.35],
	"arctic": [Color("f1f6ff"),Color("82b8da"),Color("355f91"),Color("c6e1eb"),Color("355773"),1.72,.33,.38],
	"volcanic": [Color("ffb980"),Color("8a99b6"),Color("433c50"),Color("cfa184"),Color("292d40"),1.75,.36,.34],
	"final": [Color("ffe1a8"),Color("80b9d3"),Color("224661"),Color("dbbea0"),Color("243d4c"),1.95,.32,.34]
}

static func flight_lighting(flight: Node3D, biome: String) -> void:
	var world := flight.get_node("WorldEnvironment") as WorldEnvironment
	var environment := world.environment.duplicate() as Environment
	var key := biome if PALETTES.has(biome) else "coral"
	var palette: Array = PALETTES[key]
	if not sky_cache.has(key):
		var sky := Sky.new()
		sky.radiance_size = Sky.RADIANCE_SIZE_128
		sky.process_mode = Sky.PROCESS_MODE_QUALITY
		var atmosphere := ProceduralSkyMaterial.new()
		atmosphere.sky_top_color = palette[2]
		atmosphere.sky_horizon_color = palette[3]
		atmosphere.ground_bottom_color = palette[4]
		atmosphere.ground_horizon_color = palette[3].lerp(palette[4],.55)
		atmosphere.sky_curve = .22
		atmosphere.ground_curve = .18
		atmosphere.sun_angle_max = 3.0
		sky.sky_material = atmosphere
		sky_cache[key] = sky
	var sunlight := flight.get_node("KeyLight") as DirectionalLight3D
	sunlight.light_color = palette[0]
	sunlight.light_energy = palette[5]
	sunlight.rotation = Vector3(-.79,-.58,-.27)
	var fill := flight.get_node("FillLight") as DirectionalLight3D
	fill.light_color = palette[1]
	fill.light_energy = palette[6]
	fill.rotation = Vector3(-.40,2.35,.20)
	fill.shadow_enabled = false
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = palette[1].lerp(Color.WHITE,.3)
	environment.ambient_light_energy = palette[7]
	environment.sky = sky_cache[key]
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	world.environment = environment
	enhance_aircraft(flight.get_node("Player/Bank"))
	if not flight.has_node("FleetFinish"):
		var finish := preload("res://scripts/campaign/fleet_finish.gd").new()
		finish.name = "FleetFinish"
		finish.enhance = enhance_aircraft
		flight.add_child(finish)

static func enhance_aircraft(model: Node3D) -> void:
	# Public showroom API; idempotent and no additional geometry/draw pass.
	var cache: Dictionary = {}
	for node in model.find_children("*","MeshInstance3D",true,false):
		var mesh := node as MeshInstance3D
		if mesh.mesh==null or mesh.material_override!=null: continue
		for surface in range(mesh.mesh.get_surface_count()):
			var source := mesh.get_active_material(surface) as StandardMaterial3D
			if source==null or source.resource_name.ends_with(" / Cinematic"): continue
			var label := source.resource_name.to_lower()
			var identity := source.get_instance_id()
			if cache.has(identity):
				mesh.set_surface_override_material(surface,cache[identity])
				continue
			var material: Material
			if "glass" in label or "glazing" in label:
				material = _glass(source)
			elif "aircraft_skin" in label or "aircraft atlas" in label or "portable pbr" in label or "enamel" in label or "machined" in label or "warm metal" in label:
				material = _paint(source)
			elif "recess" in label or "insignia" in label or "identification" in label or "safety" in label or "navigation" in label or "frame" in label:
				var detail := source.duplicate() as StandardMaterial3D
				detail.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
				detail.roughness = .52 if "recess" in label else .38
				if "navigation" in label:
					detail.emission_enabled = true
					detail.emission = source.albedo_color
					detail.emission_energy_multiplier = .45
				material = detail
			if material==null: continue
			material.resource_name = source.resource_name+" / Cinematic"
			cache[identity] = material
			mesh.set_surface_override_material(surface,material)

static func _glass(source: StandardMaterial3D) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = GLASS
	material.set_shader_parameter("glass_tint",source.albedo_color.lerp(Color(.04,.16,.24),.65))
	return material

static func _paint(source: StandardMaterial3D) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = PAINT
	var tint := source.albedo_color
	if source.albedo_texture!=null and "p38" in source.albedo_texture.resource_path: tint = Color(.80,.85,.89)
	material.set_shader_parameter("tint",tint)
	material.set_shader_parameter("has_albedo",source.albedo_texture!=null)
	if source.albedo_texture!=null: material.set_shader_parameter("paint",source.albedo_texture)
	material.set_shader_parameter("has_normal",source.normal_enabled and source.normal_texture!=null)
	if source.normal_texture!=null: material.set_shader_parameter("normal_texture",source.normal_texture)
	material.set_shader_parameter("normal_strength",source.normal_scale*.85)
	material.set_shader_parameter("has_orm",source.roughness_texture!=null)
	if source.roughness_texture!=null: material.set_shader_parameter("orm_texture",source.roughness_texture)
	var metal := clampf(source.metallic,.16,.88)
	if source.albedo_texture!=null and "p38" in source.albedo_texture.resource_path: metal = .66
	material.set_shader_parameter("metalness",metal)
	material.set_shader_parameter("surface_roughness",clampf(source.roughness*.82,.26,.49))
	material.set_shader_parameter("relief",.010 if source.albedo_texture!=null else 0.0)
	return material

static func apply(model: Node3D) -> void:
	var cache: Dictionary = {}
	for mesh in model.find_children("*","MeshInstance3D",true,false):
		for surface in range(mesh.mesh.get_surface_count()):
			var source := mesh.get_active_material(surface) as StandardMaterial3D
			if source==null: continue
			var name_text := source.resource_name
			var cell := Vector2.ZERO
			var metal := .2
			var roughness := .55
			match name_text:
				"Weathered deck": cell=Vector2(0,0); metal=.06; roughness=.78
				"Blue gunmetal": cell=Vector2(1,0); metal=.72; roughness=.36
				"Olive enamel": cell=Vector2(0,1); metal=.28; roughness=.44
				"Rubber and soot": cell=Vector2(1,1); metal=.15; roughness=.64
				"Brass trim":
					var brass := source.duplicate() as StandardMaterial3D
					brass.metallic = .82
					brass.roughness = .29
					mesh.set_surface_override_material(surface,brass)
					continue
				_: continue
			if not cache.has(name_text):
				var material := ShaderMaterial.new()
				material.shader = HULL
				material.set_shader_parameter("atlas",ATLAS)
				material.set_shader_parameter("cell",cell)
				material.set_shader_parameter("metalness",metal)
				material.set_shader_parameter("surface_roughness",roughness)
				material.set_shader_parameter("relief",.014 if metal>.2 else .005)
				cache[name_text] = material
			mesh.set_surface_override_material(surface,cache[name_text])
	enhance_aircraft(model)
