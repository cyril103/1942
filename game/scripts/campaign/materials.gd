extends RefCounted
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
