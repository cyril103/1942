extends SceneTree
var checks := 0
var failures: Array[String] = []
var capture := false
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok and failures.size()<20: failures.append(message); push_error(message)
func _initialize() -> void: _run.call_deferred()
func model_half_extent(ship: Node3D) -> Vector2:
	var half := Vector2.ZERO
	for mesh in ship.visual.find_children("*","MeshInstance3D",true,false):
		var box: AABB = mesh.get_aabb()
		for corner in range(8):
			var p: Vector3 = ship.to_local(mesh.to_global(box.get_endpoint(corner)))
			half.x = maxf(half.x,absf(p.x))
			half.y = maxf(half.y,absf(p.z))
	return half+Vector2(.1,.1)
func overlaps_island(sea: Node3D, ship: Node3D, half: Vector2) -> bool:
	var hull := PackedVector2Array()
	for corner in [Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(-1,1)]:
		var p: Vector3 = ship.to_global(Vector3(corner.x*half.x,0,corner.y*half.y))
		hull.append(Vector2(p.x,p.z))
	for island in sea.islands:
		var coast := PackedVector2Array()
		var size: Vector2 = island.mesh.size*0.5
		for corner in [Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(-1,1)]:
			var p: Vector3 = island.to_global(Vector3(corner.x*size.x,0,corner.y*size.y))
			coast.append(Vector2(p.x,p.z))
		if not Geometry2D.intersect_polygons(hull,coast).is_empty(): return true
	return false
func screenshot(name_text: String) -> void:
	if not capture: return
	for frame in range(3): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("C:/ChatGPT/1942/renders/archipelago-"+name_text+".png")
func _run() -> void:
	capture = "--capture" in OS.get_cmdline_user_args()
	root.size = Vector2i(1920,1080)
	var app = load("res://scenes/campaign.tscn").instantiate()
	app.testing = true
	root.add_child(app)
	current_scene = app
	await process_frame
	app.profile.reset()
	app.profile.data.unlocked = 32
	var coverage := []
	for number in range(1,33):
		app._launch(number)
		var d = app.director
		var sea = app.cockpit.flight.get_node("Seascape")
		var departure = app.cockpit.flight.get_node("Departure")
		for name_text in ["Seascape","Departure","Combat","Player","Weapons"]:
			app.cockpit.flight.get_node(name_text).set_physics_process(false)
		d.set_physics_process(false)
		for frame in range(600):
			sea._physics_process(1.0/60)
			departure._physics_process(1.0/60)
			if frame%30==0: check(not overlaps_island(sea,departure.carrier,Vector2(6,12)),"Carrier takeoff stays on water %d" % number)
		departure.finish_immediately()
		d._spawn_naval(1)
		d._spawn_boss("carrier")
		d.boss.health = d.boss.max_health
		d.boss.cooldown = 10000
		var boss_half := model_half_extent(d.boss)
		var escort_half := model_half_extent(d.navals[0])
		var variants := {}
		var central := 0
		var left := 0
		var right := 0
		var pool_count: int = sea.get_child_count()
		for step in range(int(d.mission.duration)*2+80):
			sea._physics_process(.5)
			d.boss.advance(.5,d)
			check(not overlaps_island(sea,d.boss,boss_half),"Naval boss stays on water %d" % number)
			for ship in d.navals:
				if not is_instance_valid(ship): continue
				if ship.position.z>8: ship.position.z = -18
				ship.cooldown = 10000
				ship.advance(.5,d.combat)
				check(not overlaps_island(sea,ship,escort_half),"Escort stays on water %d" % number)
			for island in sea.islands:
				if step>=int(d.mission.duration)*2: continue
				if absf(island.position.z)>sea._view_half.y: continue
				variants[int(island.get_meta("variant"))] = true
				if absf(island.position.x)<sea._view_half.x*.45: central += 1
				if island.position.x<0: left += 1
				else: right += 1
			if number in [1,13,17] and step==160:
				await screenshot("mission-%02d" % number)
		check(variants.size()>=4,"At least four distinct motifs within mission %d" % number)
		check(central>0 and left>0 and right>0,"Islands reach central, left and right areas %d" % number)
		check(sea.get_child_count()==pool_count,"Scenery pool stays bounded")
		coverage.append({"mission":number,"variants":variants.size(),"central_samples":central})
		d._clear_actors()
		departure.begin_landing()
		for frame in range(421):
			sea._physics_process(1.0/60)
			departure.advance_landing(1.0/60)
			check(not overlaps_island(sea,departure.carrier,Vector2(6,12)),"Whole carrier deck clears land during recovery %d" % number)
			if number==1 and frame==300: await screenshot("carrier-recovery")
		check(departure.landed and absf(departure.carrier.to_local(d.player.position).x)<.01,"Player lands on relocated runway")
		app._show_main()
		await process_frame
	app.music.stop()
	print("ARCHIPELAGO: ",checks," checks; failures: ",failures,"; coverage: ",coverage)
	quit(0 if failures.is_empty() else 1)
