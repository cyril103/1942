extends SceneTree
## Decorative weather must work with a scroll source that has no navigation or
## actor API. Exercise real cards, independent recycling, resize and cloud deck.
const WEATHER := preload("res://scripts/cloudscape.gd")
var checks := 0
var failures: Array[String] = []
class ScrollSource extends Node3D:
	signal scrolled(distance: float)

func _initialize() -> void: _run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func snapshot(field: Node3D) -> Array:
	var values := []
	for cloud in field.clouds:
		values.append([cloud.position,cloud.mesh.size,cloud.get_meta("variant"),cloud.get_meta("density"),cloud.material_override.get_shader_parameter("phase")])
	return values

func _run() -> void:
	root.size = Vector2i(1920,1080)
	var scene := Node3D.new()
	root.add_child(scene)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.position.y = 35
	camera.rotation.x = -PI*.5
	camera.size = 25
	scene.add_child(camera)
	var source := ScrollSource.new()
	scene.add_child(source)
	var field := WEATHER.new()
	field.camera = camera
	field.seascape = source
	scene.add_child(field)
	field.set_physics_process(false)
	await process_frame
	var missions: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/missions.json"))
	var original_ids := []
	for cloud in field.clouds: original_ids.append(cloud.get_instance_id())
	check(field.find_children("*","CollisionObject3D",true,false).is_empty(),"Weather owns no collision or monitoring objects")
	check(field.get_child_count()==16,"Eight clouds and eight shadows retain the fixed render budget")
	var first_weather := []
	for mission in missions:
		field.configure_sector(mission)
		var before := snapshot(field)
		field._physics_process(31.0)
		field.configure_sector(mission)
		check(snapshot(field)==before,"Mission %d restarts identical weather, sizes, density and wind" % int(mission.id))
		var columns := [false,false,false]
		var silhouettes := {}
		for cloud in field.clouds:
			var lane := float(cloud.get_meta("lane"))
			columns[clampi(int((lane+1.0)*1.5),0,2)] = true
			silhouettes[cloud.get_meta("variant")] = true
		check(columns.all(func(used): return used),"Mission %d distributes weather across left, center and right" % int(mission.id))
		check(silhouettes.size()==8,"Mission %d preserves all eight authored silhouettes" % int(mission.id))
		if first_weather.is_empty(): first_weather = before
		else: check(before!=first_weather,"Different mission seeds produce different weather")
	# A neighbor can occupy the exact same space. The weather neither evades it
	# nor pushes the new bank behind it: no pairwise separation or hidden route.
	field.configure_sector(missions[7])
	var rng_state: int = field._bank_random[0].state
	field._spawn(0,-20.0)
	var expected: Array = snapshot(field)[0]
	for i in range(1,field.POOL_SIZE): field.clouds[i].position = field.clouds[0].position
	source.position = Vector3(100,70,-200)
	field._bank_random[0].state = rng_state
	field._spawn(0,-20.0)
	check(snapshot(field)[0]==expected,"Neighbor positions and scroll-source transform cannot affect bank placement")
	check(is_equal_approx(field.clouds[0].position.z,-20.0),"Spawning preserves independent depth even among overlapping cards")
	field.configure_sector(missions[7])
	var initial: Array = snapshot(field)
	field._physics_process(.5)
	var motions := {}
	for i in range(field.POOL_SIZE):
		var motion: float = field.clouds[i].position.x-initial[i][0].x
		motions[snappedf(motion,.001)] = true
		check(absf(motion)<.1,"Bank %d drifts gently with no lateral jump" % i)
	check(motions.size()>3,"Banks have independent drift phases and speeds")
	var before_scroll: Array = snapshot(field)
	source.scrolled.emit(2.5)
	for i in range(field.POOL_SIZE):
		check(is_equal_approx(field.clouds[i].position.z,before_scroll[i][0].z+2.5),"World scroll is the only longitudinal motion")
		check(is_equal_approx(field.shadows[i].position.z-field.clouds[i].position.z,.85),"Scrolling keeps the decorative shadow attached")
	# Force a single offscreen recycle while every other object is far away.
	field.clouds[0].position.z = field._half.y+20
	field._physics_process(0)
	check(field.clouds[0].position.z+float(field.clouds[0].get_meta("radius")) < -field._half.y-2,"Recycled banks settle fully beyond the upper view boundary")
	check(field.recycle_count==1 and field.clouds[0].get_instance_id()==original_ids[0],"Offscreen recycling reuses one bank and one shadow")
	# Resize proportionally without rerolling weather or compounding size caps.
	var before_resize: Array = snapshot(field)
	var world_depths := []
	for cloud in field.clouds: world_depths.append(cloud.position.z)
	root.size = Vector2i(900,1200)
	await process_frame
	field._update_view()
	for i in range(field.POOL_SIZE):
		check(field.clouds[i].mesh.size.x<field._half.x*1.3,"Portrait frame caps the cloud footprint")
		check(is_equal_approx(field.clouds[i].position.z,world_depths[i]),"Resize preserves the weather's independent depths")
	root.size = Vector2i(1920,1080)
	await process_frame
	field._update_view()
	check(snapshot(field)==before_resize,"Returning to the original viewport restores size and position exactly")
	field.shadow_altitude = -8.475
	camera.position.y = -3.2
	camera.size = 21
	field._physics_process(.1)
	check(field.clouds.all(func(cloud): return camera.is_position_behind(cloud.global_position)),"Coastal descent passes naturally beneath the cloud deck")
	check(field.shadows.all(func(shadow): return is_equal_approx(shadow.position.y,-8.475)),"Raid-specific shadow altitude is preserved")
	check(field.clouds.all(func(cloud): return cloud.visible and cloud.position.y<-.5),"Descent changes no bank altitude or visibility")
	camera.position.y = 35
	camera.size = 25
	field._physics_process(.1)
	check(field.clouds.all(func(cloud): return not camera.is_position_behind(cloud.global_position)),"Climbing restores the same clouds through camera geometry")
	var observed_columns := [0,0,0]
	var coverage := 0.0
	var samples := 0
	var has_clear_patch := false
	var has_depth_overlap := false
	for biome in range(8):
		field.configure_sector(missions[biome*4])
		for tick in range(30*90):
			source.scrolled.emit(2.4/30.0)
			field._physics_process(1.0/30.0)
			if tick%30: continue
			var footprint := 0.0
			for i in range(field.POOL_SIZE):
				var cloud: MeshInstance3D = field.clouds[i]
				var radius: Vector2 = cloud.mesh.size*.5
				var clipped := Vector2(maxf(0,minf(field._half.x,cloud.position.x+radius.x)-maxf(-field._half.x,cloud.position.x-radius.x)),maxf(0,minf(field._half.y,cloud.position.z+radius.y)-maxf(-field._half.y,cloud.position.z-radius.y)))
				footprint += clipped.x*clipped.y
				if absf(cloud.position.z)<field._half.y:
					observed_columns[clampi(int((cloud.position.x/field._half.x+1.0)*1.5),0,2)] += 1
				for j in range(i):
					if absf(cloud.position.z-field.clouds[j].position.z)<1.0: has_depth_overlap = true
			coverage += footprint/(field._half.x*field._half.y*4)
			samples += 1
			if footprint<field._half.x*field._half.y*.4: has_clear_patch = true
		check(field.recycle_count>12,"Biome %d exercises repeated independent recycling" % biome)
		check(field.get_child_count()==16,"Biome %d keeps weather cost fixed" % biome)
		for i in range(field.POOL_SIZE): check(field.clouds[i].get_instance_id()==original_ids[i],"Endurance preserves every pool object")
	check(observed_columns.all(func(count): return count>100),"Long flight shows clouds on both sides and through the middle")
	check(has_depth_overlap,"Independent depths naturally permit neighboring cloud groups")
	check(has_clear_patch,"Weather leaves generous clear patches during flight")
	check(coverage/samples<.6,"Average card footprints leave ample visible scenery before alpha masking")
	print("CLOUD DISTRIBUTION: ",checks," checks; mean rectangle coverage ",coverage/samples,"; columns ",observed_columns,"; failures: ",failures)
	scene.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
