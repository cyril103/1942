extends SceneTree
const SEA := preload("res://scripts/seascape.gd")
const RELIEF := preload("res://scripts/island_relief.gd")
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: _run.call_deferred()
func check(ok: bool,message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)
func channel_clear(sea: Node3D,at_z: float) -> bool:
	var center := Vector3(sea.channel_center(at_z),0,at_z)
	var heading := Basis(Vector3.UP,sea.channel_heading(at_z))
	var deck := PackedVector2Array()
	for corner in [Vector2(-6,-12),Vector2(6,-12),Vector2(6,12),Vector2(-6,12)]:
		var at: Vector3 = center+heading*Vector3(corner.x,0,corner.y)
		deck.append(Vector2(at.x,at.z))
	for island in sea.islands:
		if absf(island.position.z-at_z)>float(island.get_meta("radius"))+14: continue
		var coast := PackedVector2Array()
		var size: Vector2 = island.mesh.size*.5
		for corner in [Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(-1,1)]:
			var at: Vector3 = island.to_global(Vector3(corner.x*size.x,0,corner.y*size.y))
			coast.append(Vector2(at.x,at.z))
		if not Geometry2D.intersect_polygons(deck,coast).is_empty(): return false
	return true
func _run() -> void:
	root.size = Vector2i(1920,1080)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.position = Vector3(0,35,0)
	camera.rotation.x = -PI*.5
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 25
	var sea := SEA.new()
	sea.camera = camera
	root.add_child(sea)
	sea.set_physics_process(false)
	var ids: Array[int] = []
	for island in sea.islands: ids.append(island.get_instance_id())
	var started := Time.get_ticks_usec()
	for biome in ["coral","convoy","storm","jade","volcanic","dusk","arctic","final"]:
		sea.configure_sector({"seed":1942,"biome":biome})
		check(sea.get_child_count()==11 and sea.islands.size()==10,"Fixed ocean/ten-island pool: "+biome)
		for island in sea.islands:
			var material: ShaderMaterial = island.material_override
			var mesh: PlaneMesh = island.mesh
			var relief: Texture2D = material.get_shader_parameter("relief_atlas")
			check(mesh.subdivide_width==56 and mesh.subdivide_depth==56,"Bounded relief geometry")
			check(relief!=null and relief.get_width()==256 and relief.get_height()==256,"Compact cached heightfield")
			check(island.position.y+RELIEF.RELIEF_HEIGHT<-1.0,"All peaks remain below the flight plane")
			check(mesh.get_aabb().grow(island.extra_cull_margin).has_point(Vector3(0,RELIEF.RELIEF_HEIGHT,0)),"Expanded visibility bounds contain vertex-displaced peaks")
			check(material.get_shader_parameter("ocean_texture")==sea.OCEAN_TEXTURE,"Coast and open water share texture")
			check(material.get_shader_parameter("island_size")==mesh.size,"Relief normals use actual island proportions")
			check(material.get_shader_parameter("reflection_tint")==sea.ocean_material.get_shader_parameter("reflection_tint"),"Reflection has no coastal seams")
		for frame in range(1200): sea._physics_process(1.0/30.0)
		for i in range(sea.islands.size()): check(sea.islands[i].get_instance_id()==ids[i],"Relief never allocates replacement scenery")
	var builds_ms := (Time.get_ticks_usec()-started)/1000.0
	check(RELIEF._cache.size()==5,"Exactly one shared relief resource per existing atlas")
	for key in RELIEF._cache:
		var image: Image = RELIEF._cache[key].get_image()
		var raised := 0
		var water := 0
		var valid := true
		for y in range(image.get_height()):
			for x in range(image.get_width()):
				var pixel := image.get_pixel(x,y)
				if pixel.r>.03: raised += 1
				if pixel.g<.5:
					water += 1
					valid = valid and pixel.r==0
				valid = valid and pixel.r>=0 and pixel.r<=1
		check(valid,"Open water and lagoons remain flat: "+str(key))
		check(raised>150 and water>500,"Each atlas contains real raised coast-shaped terrain")
		check(image.has_mipmaps(),"Relief has filtered minification")
	# Exercise the complete carrier deck and turning bow in every authored sector.
	# This scenery-only fixture also covers ground missions, whose director correctly
	# refuses to spawn the naval boss used by the historical archipelago fixture.
	var missions: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/missions.json"))
	for mission in missions:
		sea.configure_sector(mission)
		sea.scroll_speed = float(mission.scroll)
		for second in range(180):
			sea._physics_process(1.0)
			check(channel_clear(sea,-16) and channel_clear(sea,0) and channel_clear(sea,14),"Raised scenery preserves full naval envelope: %d/%d" % [int(mission.id),second])
	# Reconfiguring sorties reuses all five maps without accumulating resources.
	var cache_count: int = RELIEF._cache.size()
	for biome in ["arctic","volcanic","jade"]: sea.configure_sector({"seed":300,"biome":biome})
	check(RELIEF._cache.size()==cache_count,"No accumulation when sectors are reconfigured")
	sea.queue_free()
	camera.queue_free()
	await process_frame
	print("OCEAN RELIEF: ",checks," checks; failures: ",failures,"; generation + 320s simulated: ",builds_ms," ms")
	quit(0 if failures.is_empty() else 1)
