extends SceneTree
## External rendered art-cost fixture, compatible with the 1.7 and 1.8 packs.
## No campaign scene, aircraft, DCA, projectiles, collisions, HUD or input replay.
## Run one GPU process at a time; its figures are NOT whole-game frame rates.

class ScrollRig extends Node3D:
	var terrain: Node3D
	var ocean_material: ShaderMaterial
	var scroll_speed := 1.0
	var origin_z := 0.0
	var ticks := 0
	var limit := 0
	var running := false
	var state_signature := 0
	var samples: Array[Dictionary] = []
	func begin(total_ticks: int) -> void:
		ticks = 0
		limit = total_ticks
		running = true
		state_signature = 0
		samples.clear()
		_pose()
	func _pose() -> void:
		var seconds := float(ticks)/60.0
		var distance := seconds*scroll_speed
		terrain.position.z = origin_z+distance
		var phases := {"scroll_a":fposmod(distance/14.0,2.0),"scroll_b":fposmod(distance/(14.0*1.6),2.0),"wave_phase":fposmod(seconds*.65,TAU)}
		for parameter in phases:
			ocean_material.set_shader_parameter(parameter,phases[parameter])
			terrain.set_ocean_parameter(parameter,phases[parameter])
	func _physics_process(_delta: float) -> void:
		if not running: return
		ticks += 1
		_pose()
		if ticks%60==0:
			var state := "%d|%d" % [ticks,roundi(terrain.position.z*100000)]
			state_signature = (state_signature*31+state.hash())%2147483647
			samples.append({"tick":ticks,"terrain_z":terrain.position.z,"state":state})
		if ticks>=limit: running = false

const MISSIONS := [3,7,11,15,19,23,27,31]
const BIOMES := ["coral","convoy","storm","jade","volcanic","dusk","arctic","final"]
const FRAME_BUDGET := 1000.0/60.0
const WARMUP_TICKS := 60
const LOW_CAMERA_HEIGHT := -3.2
const LOW_CAMERA_SIZE := 21.0
const FIELD_WIDTH := 65.0
const FIELD_LENGTH := 220.0
const MEASURED_SCROLL_DISTANCE := 18.0
const SEA_TINTS := {"coral":Color(.8,1.08,1.0),"convoy":Color(.75,.95,.9),"storm":Color(.58,.7,.8),"jade":Color(.8,1.1,.9),"volcanic":Color(.75,.72,.68),"dusk":Color(1.15,.68,.57),"arctic":Color(.77,.94,1.07),"final":Color(1.1,.94,.75)}
var output_dir := OS.get_user_data_dir().path_join("raid-terrain-performance")
var build_id := "unidentified"
var quality := 1
var duration_seconds := 6
var dimensions := Vector2i(1920,1080)
var viewport: SubViewport
var screen: TextureRect
var terrain_script
var operations_script
var materials_script
var layouts_script
var ocean_shader: Shader
var ocean_texture: Texture2D
var ground_detail: Texture2D
var light_templates: Dictionary = {}
var reports: Array[Dictionary] = []
var failures: Array[String] = []

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output-dir="): output_dir = argument.trim_prefix("--output-dir=")
		if argument.begins_with("--build-id="): build_id = argument.trim_prefix("--build-id=")
		if argument.begins_with("--quality="): quality = clampi(argument.trim_prefix("--quality=").to_int(),0,2)
		if argument.begins_with("--duration="): duration_seconds = clampi(argument.trim_prefix("--duration=").to_int(),6,60)
		if argument.begins_with("--size="):
			var parts := argument.trim_prefix("--size=").split("x")
			if parts.size()==2: dimensions = Vector2i(maxi(640,parts[0].to_int()),maxi(360,parts[1].to_int()))
	output_dir = ProjectSettings.globalize_path(output_dir)
	var error := DirAccess.make_dir_recursive_absolute(output_dir)
	if error!=OK: failures.append("Cannot create output directory: "+error_string(error))
	_run.call_deferred()

func _memory() -> Dictionary:
	return {"engine_static_bytes":int(Performance.get_monitor(Performance.MEMORY_STATIC)),"render_estimated_bytes":int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)),"nodes":int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),"resources":int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),"orphan_nodes":int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))}

func _summary(values: Array[float]) -> Dictionary:
	if values.is_empty(): return {"samples":0}
	var ordered := values.duplicate()
	ordered.sort()
	var total := 0.0
	var over_60 := 0
	var over_30 := 0
	for value in ordered:
		total += value
		if value>FRAME_BUDGET: over_60 += 1
		if value>1000.0/30.0: over_30 += 1
	return {"samples":ordered.size(),"mean_ms":total/ordered.size(),"p95_ms":ordered[mini(ordered.size()-1,int(ordered.size()*.95))],"p99_ms":ordered[mini(ordered.size()-1,int(ordered.size()*.99))],"max_ms":ordered.back(),"over_16_67ms":over_60,"over_33_33ms":over_30}

func _write(path: String, data: Dictionary) -> bool:
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file==null:
		failures.append("Cannot write evidence: "+path)
		return false
	file.store_string(JSON.stringify(data,"\t"))
	file.close()
	return true

func _load_assets() -> bool:
	terrain_script = load("res://scripts/campaign/assault_terrain.gd")
	operations_script = load("res://scripts/campaign/operations.gd")
	materials_script = load("res://scripts/campaign/materials.gd")
	if ResourceLoader.exists("res://scripts/campaign/raid_layouts.gd"):
		layouts_script = load("res://scripts/campaign/raid_layouts.gd")
	ocean_shader = load("res://shaders/ocean.gdshader")
	ocean_texture = load("res://assets/environment/ocean.png")
	ground_detail = load("res://assets/environment/raid-v2/coral-grass-detail.png")
	var scene := load("res://scenes/main.tscn") as PackedScene
	if terrain_script==null or operations_script==null or materials_script==null or ocean_shader==null or ocean_texture==null or ground_detail==null or scene==null:
		failures.append("Required art/lighting resources could not be loaded from this pack")
		return false
	# Read main.tscn properties without instantiating its gameplay actors.
	var state := scene.get_state()
	for index in range(state.get_node_count()):
		var name_text := str(state.get_node_name(index))
		if name_text not in ["WorldEnvironment","KeyLight","FillLight","Camera"]: continue
		var properties := {}
		for property_index in range(state.get_node_property_count(index)):
			var property_name := str(state.get_node_property_name(index,property_index))
			if property_name=="script": continue
			properties[property_name] = state.get_node_property_value(index,property_index)
		light_templates[name_text] = properties
	if light_templates.size()!=4:
		failures.append("main.tscn lighting/camera template is incomplete")
		return false
	return true

func _template(node: Node, name_text: String) -> void:
	node.name = name_text
	for key in light_templates[name_text]:
		var value: Variant = light_templates[name_text][key]
		if value is Environment: value = value.duplicate()
		node.set(key,value)

func _node_counts(node: Node) -> Dictionary:
	var result := {"nodes":1,"mesh_instances":1 if node is MeshInstance3D else 0,"multimesh_groups":1 if node is MultiMeshInstance3D else 0,"collision_objects":1 if node is CollisionObject3D else 0}
	for child in node.get_children():
		var child_counts := _node_counts(child)
		for key in result: result[key] = int(result[key])+int(child_counts[key])
	return result

func _rig(mission: Dictionary, view: String) -> Dictionary:
	var started := Time.get_ticks_usec()
	var rig := ScrollRig.new()
	rig.name = "TerrainArtRig"
	var world := WorldEnvironment.new()
	_template(world,"WorldEnvironment")
	rig.add_child(world)
	var key := DirectionalLight3D.new()
	_template(key,"KeyLight")
	key.shadow_opacity = .60
	key.shadow_enabled = quality>0
	rig.add_child(key)
	var fill := DirectionalLight3D.new()
	_template(fill,"FillLight")
	rig.add_child(fill)
	var camera := Camera3D.new()
	_template(camera,"Camera")
	camera.position = Vector3(0,LOW_CAMERA_HEIGHT,0)
	camera.size = LOW_CAMERA_SIZE
	rig.add_child(camera)
	# Production lighting helper expects Player/Bank, but these two empty
	# transforms contain no mesh, collider, script, controller or input logic.
	var lighting_stub := Node3D.new()
	lighting_stub.name = "Player"
	var bank_stub := Node3D.new()
	bank_stub.name = "Bank"
	lighting_stub.add_child(bank_stub)
	rig.add_child(lighting_stub)
	materials_script.flight_lighting(rig,str(mission.biome))
	var half_x := LOW_CAMERA_SIZE*.5*float(viewport.size.x)/float(viewport.size.y)
	var width := FIELD_WIDTH
	var length := FIELD_LENGTH
	var safe_x := minf(width*.33-2.3,half_x-2.3)
	if safe_x<7.0:
		failures.append("Requested aspect ratio is narrower than the terrain layout's authored minimum")
		rig.free()
		return {}
	var layout: Dictionary = {}
	var terrain: Node3D = terrain_script.new()
	rig.terrain = terrain
	rig.add_child(terrain)
	var configure_arguments := 0
	for method in terrain.get_method_list():
		if str(method.name)=="configure": configure_arguments=method.args.size()
	if configure_arguments>=4 and layouts_script!=null:
		layout = layouts_script.instantiate_layout(mission,width,length,safe_x)
		if not bool(layout.get("valid",false)):
			failures.append("Invalid shared terrain layout: "+str(layout.get("warnings",[])))
			rig.free()
			return {}
		terrain.configure(mission,width,length,layout)
	elif configure_arguments==3:
		terrain.configure(mission,width,length)
	else:
		failures.append("Unsupported terrain configure API (%d arguments)" % configure_arguments)
		rig.free()
		return {}
	terrain.set_ground_detail(ground_detail)
	terrain.set_quality(quality)
	var ocean := MeshInstance3D.new()
	ocean.name = "OceanOnly"
	var plane := PlaneMesh.new()
	plane.size = Vector2(half_x*2.0+8.0,LOW_CAMERA_SIZE+8.0)
	ocean.mesh = plane
	ocean.position.y = -9.4
	ocean.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	material.shader = ocean_shader
	material.set_shader_parameter("ocean_texture",ocean_texture)
	material.set_shader_parameter("ocean_tint",SEA_TINTS[str(mission.biome)])
	material.set_shader_parameter("sea_desaturation",.4 if mission.biome in ["storm","volcanic","arctic"] else 0.0)
	material.set_shader_parameter("tile_size",14.0)
	ocean.material_override = material
	rig.ocean_material = material
	rig.add_child(ocean)
	for parameter in ["ocean_texture","ocean_tint","sea_desaturation","tile_size"]:
		terrain.set_ocean_parameter(parameter,material.get_shader_parameter(parameter))
	rig.scroll_speed = MEASURED_SCROLL_DISTANCE/float(duration_seconds)
	# Incoming coastline remains in view for the whole short coastal traversal.
	# The independent plateau view measures inland detail/infrastructure only.
	rig.origin_z = -length*.5-MEASURED_SCROLL_DISTANCE*.5 if view=="coast" else -length*.18
	rig._pose()
	viewport.add_child(rig)
	var construction_ms := (Time.get_ticks_usec()-started)/1000.0
	return {"rig":rig,"camera":camera,"construction_ms":construction_ms,"width":width,"length":length,"safe_x":safe_x,"configure_arguments":configure_arguments,"layout_id":str(layout.get("id","legacy-embedded-layout")),"triangles":int(terrain.get("triangle_count")),"props":int(terrain.get("prop_count"))}

func _wait_ticks(rig: ScrollRig, total_ticks: int, measured: bool) -> Dictionary:
	var frame_times: Array[float] = []
	var gpu_times: Array[float] = []
	var cpu_times: Array[float] = []
	var zero_gpu_samples := 0
	var started := Time.get_ticks_usec()
	var previous := started
	rig.begin(total_ticks)
	while rig.running:
		await process_frame
		var now := Time.get_ticks_usec()
		if measured:
			frame_times.append((now-previous)/1000.0)
			var gpu := RenderingServer.viewport_get_measured_render_time_gpu(viewport.get_viewport_rid())+RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid())
			gpu_times.append(gpu)
			if gpu<=0.0: zero_gpu_samples+=1
			cpu_times.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000.0)
		previous = now
		if (now-started)/1000000.0>float(total_ticks)/60.0*3.0+5.0:
			failures.append("Art fixture exceeded wall-clock limit")
			rig.running = false
			break
	return {"wall_seconds":(Time.get_ticks_usec()-started)/1000000.0,"physics_ticks":rig.ticks,"frame_intervals":_summary(frame_times),"gpu_completed_ms":_summary(gpu_times),"cpu_process_ms":_summary(cpu_times),"gpu_zero_samples":zero_gpu_samples,"state_signature":rig.state_signature,"state_samples":rig.samples.duplicate(true)}

func _scenario(mission: Dictionary, view: String, pass_index: int) -> void:
	seed(1942)
	var before := _memory()
	var setup := _rig(mission,view)
	if setup.is_empty(): return
	var rig: ScrollRig = setup.rig
	var node_counts := _node_counts(rig)
	if int(node_counts.collision_objects)!=0: failures.append("Art rig unexpectedly contains collision objects")
	var warmup := await _wait_ticks(rig,WARMUP_TICKS,false)
	var active_memory := _memory()
	var measured := await _wait_ticks(rig,duration_seconds*60,true)
	var record := {"mission":int(mission.id),"biome":str(mission.biome),"view":view,"pass":pass_index,"cache_note":"First or repeat construction of this biome/view in one process; driver/disk caches were not erased","construction_ms":setup.construction_ms,"warmup_seconds":warmup.wall_seconds,"warmup_ticks":warmup.physics_ticks,"viewport":[viewport.size.x,viewport.size.y],"camera_position":str(setup.camera.position),"camera_size":setup.camera.size,"width":setup.width,"length":setup.length,"safe_x":setup.safe_x,"scroll_speed":rig.scroll_speed,"origin_z":rig.origin_z,"configure_arguments":setup.configure_arguments,"layout_id":setup.layout_id,"triangles":setup.triangles,"props":setup.props,"node_counts":node_counts,"before_memory":before,"active_memory":active_memory,"measurement":measured}
	if int(measured.physics_ticks)!=duration_seconds*60: failures.append("Incomplete terrain scenario M%02d %s pass%d" % [int(mission.id),view,pass_index])
	if int(measured.frame_intervals.get("samples",0))==0: failures.append("No rendered samples for terrain scenario")
	viewport.remove_child(rig)
	rig.free()
	setup.clear()
	# Raw frame arrays lived only in _wait_ticks and have already been released.
	await process_frame
	await process_frame
	record.after_dispose_memory = _memory()
	if int(record.after_dispose_memory.nodes)!=int(before.nodes): failures.append("Terrain cleanup node count did not return to baseline")
	if int(record.after_dispose_memory.orphan_nodes)>int(before.orphan_nodes): failures.append("Terrain cleanup introduced orphan nodes")
	if pass_index==1:
		if reports.is_empty() or int(reports.back().mission)!=int(mission.id) or str(reports.back().view)!=view or int(reports.back().get("pass",-1))!=0:
			failures.append("Terrain replay is missing its matching first pass")
		else:
			var previous: Dictionary = reports.back()
			for field in ["physics_ticks","state_signature","state_samples"]:
				if previous.measurement[field]!=measured[field]: failures.append("Terrain replay mismatch %s for M%02d %s" % [field,int(mission.id),view])
	_write(output_dir.path_join("terrain-m%02d-%s-q%d-pass%d.json" % [int(mission.id),view,quality,pass_index]),record)
	reports.append(record)
	print("TERRAIN ART M%02d %s pass%d construction=%.3fms frames=%s" % [int(mission.id),view,pass_index,float(record.construction_ms),JSON.stringify(measured.frame_intervals)])

func _run() -> void:
	if DisplayServer.get_name()=="headless":
		push_error("Terrain art benchmark requires a real GPU renderer")
		quit(2)
		return
	if not failures.is_empty():
		push_error(failures[0])
		quit(1)
		return
	Engine.physics_ticks_per_second = 60
	Engine.max_fps = 0
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(dimensions)
	root.size = dimensions
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var entry_memory := _memory()
	var load_started := Time.get_ticks_usec()
	if not _load_assets():
		push_error(failures[0])
		quit(1)
		return
	var startup_asset_load_ms := (Time.get_ticks_usec()-load_started)/1000.0
	viewport = SubViewport.new()
	viewport.name = "ArtOnlyViewport"
	viewport.size = Vector2i(dimensions.x,roundi(float(dimensions.y)*.9))
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = [Viewport.MSAA_DISABLED,Viewport.MSAA_2X,Viewport.MSAA_4X][quality]
	root.add_child(viewport)
	screen = TextureRect.new()
	screen.texture = viewport.get_texture()
	screen.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(screen)
	RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(),true)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	await process_frame
	await process_frame
	var initial_memory := _memory()
	var sources: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/missions.json"))
	if not sources is Array or sources.size()!=32:
		failures.append("Expected the 32-mission source catalogue")
	else:
		for index in range(MISSIONS.size()):
			var mission: Dictionary = operations_script.prepare(sources[int(MISSIONS[index])-1])
			if str(mission.biome)!=BIOMES[index]:
				failures.append("Unexpected biome for M%02d" % int(mission.id))
				continue
			for view in ["coast","plateau"]:
				for pass_index in range(2): await _scenario(mission,view,pass_index)
	if reports.size()!=32: failures.append("Expected 32 terrain scenarios; received %d" % reports.size())
	var report := {"schema":1,"build_id":build_id,"engine":Engine.get_version_info(),"gpu":RenderingServer.get_video_adapter_name(),"cpu":OS.get_processor_name(),"os":OS.get_name(),"requested_window":[dimensions.x,dimensions.y],"actual_window":str(DisplayServer.window_get_size()),"root_visible_rect":str(root.get_visible_rect()),"viewport":[viewport.size.x,viewport.size.y],"quality":quality,"duration_ticks_per_scenario":duration_seconds*60,"warmup_ticks_per_scenario":WARMUP_TICKS,"physics_hz":60,"vsync":false,"max_fps":0,"seed":1942,"terrain_rng_note":"Production terrain derives its local seed from the preserved mission ID: id*7919+1942","field_width":FIELD_WIDTH,"field_length":FIELD_LENGTH,"measured_scroll_distance":MEASURED_SCROLL_DISTANCE,"startup_asset_load_ms":startup_asset_load_ms,"entry_memory":entry_memory,"initial_memory":initial_memory,"after_rigs_memory":_memory(),"method":"32 art-only scenarios: eight prepared raid biomes x coast/plateau x two passes. Production terrain/ocean shaders and main.tscn lighting; no gameplay actors or collisions.","comparison_contract":"Use the identical external script, size, duration and quality on both immutable packs. Geometry/roads/props/albedos intentionally differ between versions; cameras and scroll paths do not.","timing_limits":"Frame intervals are CPU-observed render cadence, not isolated shader time. GPU completed measurements may lag and zero may mean unavailable. TIME_PROCESS is process callbacks, not whole CPU time. Construction/startup/warmup are separate.","memory_limits":"Engine static and estimated render allocations are not process private bytes or physical VRAM. Cached scripts, source lighting resources, textures and sky shaders can remain resident; this fixture does not establish absence of memory leaks.","human_visual_inspection":"NOT_PERFORMED","whole_game_fps":"NOT_MEASURED","other_gpu_processes":"operator_must_verify_none","scenarios":reports,"failures":failures}
	screen.texture = null
	screen.queue_free()
	viewport.queue_free()
	await process_frame
	await process_frame
	report.after_fixture_dispose_memory = _memory()
	if int(report.after_fixture_dispose_memory.nodes)!=int(entry_memory.nodes): failures.append("Art fixture cleanup did not return to its entry node count")
	if int(report.after_fixture_dispose_memory.orphan_nodes)>int(entry_memory.orphan_nodes): failures.append("Art fixture cleanup introduced orphan nodes")
	report.failures = failures
	_write(output_dir.path_join("raid-terrain-q%d-%dx%d.json" % [quality,dimensions.x,dimensions.y]),report)
	print("TERRAIN ART BENCHMARK scenarios=",reports.size()," failures=",failures)
	quit(0 if failures.is_empty() else 1)
