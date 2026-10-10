extends Node3D
## Compatibility compiles a material when it is first drawn, not when loaded.
## Draw representative geometry in the real flight viewport before simulation.
var _seen: Dictionary = {}
var _cards: Array[GeometryInstance3D] = []
var _sources: Node3D
var prepared_count := 0

func prepare(flight: Node3D, director: Node) -> void:
	process_mode = Node.PROCESS_MODE_DISABLED
	_sources = Node3D.new()
	_sources.hide()
	add_child(_sources)
	# These actors have no combat owner, signals or simulation. Only _ready runs
	# to produce the same meshes/material overlays that real enemies will use.
	for script in [preload("res://scripts/enemy_zero.gd"), preload("res://scripts/enemy_hayabusa.gd"), preload("res://scripts/enemy_red.gd"), preload("res://scripts/enemy_bomber.gd"), preload("res://scripts/campaign/enemy_naval.gd"), preload("res://scripts/campaign/convoy.gd")]:
		var actor: Node3D = script.new()
		if script==preload("res://scripts/enemy_red.gd"): actor.slot = 1
		_sources.add_child(actor)
		if actor is CollisionObject3D: actor.collision_layer = 0
	var kind := str(director.mission.get("boss",""))
	if not kind.is_empty():
		var boss := preload("res://scripts/campaign/boss.gd").new()
		boss.kind = kind
		_sources.add_child(boss)
	_collect(flight)
	var camera: Camera3D = director.combat.camera
	var viewport_size := camera.get_viewport().get_visible_rect().size
	for first in range(0,_cards.size(),24):
		for index in range(first,mini(first+24,_cards.size())):
			var card := _cards[index]
			var cell := index-first
			var pixel := viewport_size*Vector2(.12+float(cell%6)*.15,.17+float(cell/6)*.19)
			var origin := camera.project_ray_origin(pixel)
			var direction := camera.project_ray_normal(pixel)
			var center := origin+direction*((1.5-origin.y)/direction.y)
			card.position += center
			card.show()
		await RenderingServer.frame_post_draw
		if not is_instance_valid(flight): return
		for index in range(first,mini(first+24,_cards.size())): _cards[index].hide()
	# Flush the last submitted batch before restoring the first gameplay image.
	await RenderingServer.frame_post_draw
	prepared_count = _cards.size()

func _collect(node: Node) -> void:
	for child in node.get_children():
		# This node contains the temporary actors too; do not recurse into cards.
		if child==self:
			_collect(_sources)
			continue
		if child is MeshInstance3D and child.mesh!=null:
			_copy_mesh(child)
		elif child is MultiMeshInstance3D and child.multimesh!=null:
			_copy_batch(child)
		elif child is Label3D:
			var label := Label3D.new()
			label.font = child.font
			label.font_size = child.font_size
			label.pixel_size = .004
			label.outline_size = child.outline_size
			label.billboard = child.billboard
			label.rotation = child.rotation
			label.text = "VAGUE PARFAITE +0123456789 MULTI LASER VIE"
			label.cast_shadow = child.cast_shadow
			_add(label)
		_collect(child)

func _material_key(material: Material) -> String:
	if material==null: return "default"
	if not material is ShaderMaterial: return str(material.get_instance_id())
	var shader_material := material as ShaderMaterial
	var key := str(shader_material.shader.get_instance_id())
	for uniform in shader_material.shader.get_shader_uniform_list():
		var value = shader_material.get_shader_parameter(uniform.name)
		if value is Texture: key += ":"+str(value.get_instance_id())
	return key

func _copy_mesh(source: MeshInstance3D) -> void:
	var key := "mesh:%d:%s:%s" % [source.cast_shadow,_material_key(source.material_override),_material_key(source.material_overlay)]
	for i in range(source.mesh.get_surface_count()):
		var format_key: String = str(source.mesh.surface_get_format(i)) if source.mesh is ArrayMesh else source.mesh.get_class()
		key += ":%s:%s" % [format_key,_material_key(source.get_active_material(i))]
	if _seen.has(key): return
	_seen[key] = true
	var card := MeshInstance3D.new()
	card.mesh = source.mesh
	card.material_override = source.material_override
	card.material_overlay = source.material_overlay
	card.cast_shadow = source.cast_shadow
	for i in range(source.mesh.get_surface_count()): card.set_surface_override_material(i,source.get_surface_override_material(i))
	_fit(card,source.mesh.get_aabb())
	_add(card)

func _copy_batch(source: MultiMeshInstance3D) -> void:
	var original := source.multimesh
	if original.mesh==null: return
	var key := "batch:%s:%d:%s:%s" % [original.mesh.get_rid(),source.cast_shadow,original.use_colors,original.use_custom_data]
	if _seen.has(key): return
	_seen[key] = true
	var card := MultiMeshInstance3D.new()
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.use_colors = original.use_colors
	batch.use_custom_data = original.use_custom_data
	batch.mesh = original.mesh
	batch.instance_count = 1
	batch.set_instance_transform(0,Transform3D.IDENTITY)
	if batch.use_colors: batch.set_instance_color(0,Color.WHITE)
	if batch.use_custom_data: batch.set_instance_custom_data(0,Color(.8,.8,.8,.8))
	card.multimesh = batch
	card.material_override = source.material_override
	card.cast_shadow = source.cast_shadow
	_fit(card,original.mesh.get_aabb())
	_add(card)

func _fit(card: Node3D, bounds: AABB) -> void:
	var factor := 1.4/maxf(.01,maxf(bounds.size.x,maxf(bounds.size.y,bounds.size.z)))
	card.scale = Vector3.ONE*factor
	card.position = -bounds.get_center()*factor

func _add(card: GeometryInstance3D) -> void:
	card.hide()
	add_child(card)
	_cards.append(card)
