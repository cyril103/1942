extends RefCounted
static var sky_cache: Dictionary = {}

static func flight_lighting(flight: Node3D, biome: String) -> void:
	var world := flight.get_node("WorldEnvironment") as WorldEnvironment
	var environment := world.environment.duplicate() as Environment
	var key := biome if biome in ["dusk","storm"] else "day"
	if not sky_cache.has(key):
		var sky := Sky.new()
		sky.radiance_size = Sky.RADIANCE_SIZE_128
		sky.process_mode = Sky.PROCESS_MODE_QUALITY
		var atmosphere := ProceduralSkyMaterial.new()
		atmosphere.sky_top_color = Color(.12,.3,.56)
		atmosphere.sky_horizon_color = Color(.65,.79,.87)
		atmosphere.ground_bottom_color = Color(.025,.10,.14)
		atmosphere.ground_horizon_color = Color(.35,.56,.61)
		if key=="dusk":
			atmosphere.sky_top_color = Color(.20,.22,.42)
			atmosphere.sky_horizon_color = Color(.95,.57,.28)
		elif key=="storm":
			atmosphere.sky_top_color = Color(.18,.23,.3)
			atmosphere.sky_horizon_color = Color(.5,.59,.65)
		sky.sky_material = atmosphere
		sky_cache[key] = sky
	if key=="dusk": flight.get_node("KeyLight").light_color = Color(1,.78,.52)
	elif key=="storm": flight.get_node("KeyLight").light_color = Color(.82,.91,1)
	environment.sky = sky_cache[key]
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	world.environment = environment
	var bank := flight.get_node("Player/Bank")
	for mesh in bank.find_children("*","MeshInstance3D",true,false):
		for i in range(mesh.mesh.get_surface_count()):
			var source: Material = mesh.get_active_material(i)
			if source is StandardMaterial3D and "glass" in source.resource_name.to_lower():
				var glass := source.duplicate() as StandardMaterial3D
				glass.roughness = .18
				glass.metallic = .12
				mesh.set_surface_override_material(i,glass)

static func apply(model: Node3D) -> void:
	var cache := {}
	for mesh in model.find_children("*","MeshInstance3D",true,false):
		for surface in range(mesh.mesh.get_surface_count()):
			var original: Material = mesh.get_active_material(surface)
			if original == null: continue
			var name_text := original.resource_name
			var cell := Vector2.ZERO
			var metal := 0.2
			match name_text:
				"Weathered deck": cell=Vector2(0,0);metal=0.08
				"Blue gunmetal": cell=Vector2(1,0);metal=0.6
				"Olive enamel": cell=Vector2(0,1);metal=0.25
				"Rubber and soot": cell=Vector2(1,1);metal=0.45
				_: continue
			if not cache.has(name_text):
				var material := ShaderMaterial.new()
				material.shader = preload("res://shaders/campaign_surface.gdshader")
				material.set_shader_parameter("atlas",load("res://assets/campaign/material-atlas.png"))
				material.set_shader_parameter("cell",cell)
				material.set_shader_parameter("metalness",metal)
				cache[name_text] = material
			mesh.set_surface_override_material(surface,cache[name_text])
