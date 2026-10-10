extends SceneTree
var failures: Array[String] = []
var checks := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	root.size = Vector2i(1920,1080)
	var app = load("res://scenes/campaign.tscn").instantiate()
	app.testing = true
	root.add_child(app)
	current_scene = app
	await process_frame
	app.profile.reset()
	app.profile.data.unlocked = 32
	app._launch(1)
	var flight = app.cockpit.flight
	var sea = flight.get_node("Seascape")
	var field = flight.get_node("Clouds")
	var departure = flight.get_node("Departure")
	for name_text in ["Seascape","Clouds","Combat","Player","Weapons","Departure"]:
		flight.get_node(name_text).set_physics_process(false)
	app.director.set_physics_process(false)
	check(field.ATLAS.get_image().has_mipmaps(),"Cloud and shadow mipmaps available")
	check(field.clouds.size()==field.POOL_SIZE and field.get_child_count()==field.POOL_SIZE*2,"Fixed pool of banks and shadow cards")
	field._physics_process(.2)
	check(field.clouds[0].material_override.get_shader_parameter("opacity")==field.strength*float(field.clouds[0].get_meta("density",1.0)),"Clouds remain visible during takeoff")
	check(field.VARIETY_ATLAS.get_image().has_mipmaps(),"New atlas has mipmaps")
	var variants := {}
	var widest := 0.0
	for cloud in field.clouds:
		variants[cloud.get_meta("variant")] = true
		widest = maxf(widest,cloud.mesh.size.x)
	check(variants.size()==8,"All eight silhouettes are available in each sector")
	check(widest>15,"Large banks complement small cumulus")
	departure.finish_immediately()
	var ids := []
	for cloud in field.clouds: ids.append(cloud.get_instance_id())
	var columns := [0,0,0]
	check(field.find_children("*","CollisionObject3D",true,false).is_empty(),"Clouds remain decorative and never own collisions")
	for frame in range(60*60*10):
		sea._physics_process(1.0/60)
		field._physics_process(1.0/60)
		if frame%600==0:
			check(field.get_child_count()==field.POOL_SIZE*2,"Ten-minute run keeps pool bounded")
			for i in range(field.POOL_SIZE):
				var cloud = field.clouds[i]
				var shadow = field.shadows[i]
				check(cloud.get_instance_id()==ids[i],"Cloud objects recycled")
				check(cloud.position.y<-.5 and cloud.position.y>sea.islands[0].position.y,"Cloud layer between terrain and aircraft")
				check(shadow.position.y>sea.islands[0].position.y and shadow.position.y<cloud.position.y,"Soft shadow above terrain, below clouds")
				check(is_equal_approx(shadow.position.x-cloud.position.x,.65),"Shadow follows bank without drift")
				check(absf(cloud.position.x)<field._half.x+1.6,"Weather spans the view with bounded independent drift")
				if absf(cloud.position.z)<field._half.y:
					columns[clampi(int((cloud.position.x/field._half.x+1.0)*1.5),0,2)] += 1
	check(field.recycle_count>100,"Endurance exercises recycling")
	check(columns.all(func(count): return count>5),"Clouds cross left, center and right instead of following a carrier route")
	check(field.clouds[0].material_override.get_shader_parameter("opacity")==field.strength*float(field.clouds[0].get_meta("density",1.0)),"Cruise preserves cloud opacity")
	for number in [1,9,17,21,25]:
		var mission: Dictionary = app.missions[number-1]
		sea.configure_sector(mission)
		field.configure_sector(mission)
		var positions := []
		for cloud in field.clouds: positions.append(cloud.position)
		field.configure_sector(mission)
		for i in range(field.POOL_SIZE): check(field.clouds[i].position==positions[i],"Weather is seeded reproducibly")
		for frame in range(60*37):
			sea._physics_process(1.0/60)
			field._physics_process(1.0/60)
		app.director.mission = mission
		app.director.feedback_time = 0
		if DisplayServer.get_name()!="headless":
			for frame in range(4): await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("C:/ChatGPT/1942/renders/clouds-%02d.png" % number)
	if DisplayServer.get_name()!="headless": await _check_aircraft_pixels(app,flight,field)
	departure.begin_landing()
	field._physics_process(2)
	check(field.clouds[0].material_override.get_shader_parameter("opacity")==field.strength*float(field.clouds[0].get_meta("density",1.0)),"Recovery preserves cloud opacity")
	app._show_main()
	app.music.stop()
	app.queue_free()
	await create_timer(.35).timeout
	print("CLOUDS: ",checks," checks; failures: ",failures)
	quit(0 if failures.is_empty() else 1)

func _check_aircraft_pixels(app: Node, flight: Node3D, field: Node3D) -> void:
	# Opaque player pixels must remain unchanged when a cloud sits beneath it.
	flight.get_node("Player").set_process(false)
	for cloud in field.clouds: cloud.position.z = -100
	field.clouds[0].position.x = app.cockpit.player.position.x
	field.clouds[0].position.z = app.cockpit.player.position.z
	field._sync_shadow(0)
	field.visible = false
	await process_frame
	await RenderingServer.frame_post_draw
	var without: Image = app.cockpit.viewport.get_texture().get_image()
	field.visible = true
	await process_frame
	await RenderingServer.frame_post_draw
	var with_cloud: Image = app.cockpit.viewport.get_texture().get_image()
	var screen: Vector2 = field.camera.unproject_position(app.cockpit.player.global_position)
	var center := Vector2i(screen)
	var difference := 0.0
	for x in range(-1,2):
		for y in range(-3,4):
			var a := without.get_pixelv(center+Vector2i(x,y))
			var b := with_cloud.get_pixelv(center+Vector2i(x,y))
			difference = maxf(difference,absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b))
	check(difference<.035,"Aircraft fuselage renders above the cloud layer")
