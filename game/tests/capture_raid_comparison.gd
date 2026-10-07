extends SceneTree
## Accelerated visual inspection only: fixed camera/input states, not a playtest or FPS benchmark.
var output_dir := OS.get_user_data_dir().path_join("raid-visual-review")
var build_id := "unidentified"
var app: Control
var evidence: Array[Dictionary] = []
var failures: Array[String] = []
const FIXTURE := "user://raid-visual-comparison-isolated.json"

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output-dir="): output_dir = argument.trim_prefix("--output-dir=")
		if argument.begins_with("--build-id="): build_id = argument.trim_prefix("--build-id=")
	DirAccess.make_dir_recursive_absolute(output_dir)
	_run.call_deferred()

func _cleanup() -> void:
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(FIXTURE+suffix): DirAccess.remove_absolute(FIXTURE+suffix)

func _stop_audio(node: Node) -> void:
	if node is AudioStreamPlayer or node is AudioStreamPlayer3D: node.stop()
	for child in node.get_children(): _stop_audio(child)

func _capture(mission: int, size: Vector2i, phase: String, d: Node, flight: Node) -> void:
	app.cockpit.queue_redraw()
	app.cockpit.get_node("CampaignHUD").queue_redraw()
	for frame in range(5): await process_frame
	await RenderingServer.frame_post_draw
	var name := "m%02d-%dx%d-%s.png" % [mission,size.x,size.y,phase]
	var error := root.get_texture().get_image().save_png(output_dir.path_join(name))
	if error!=OK: failures.append("Cannot save "+name)
	var camera: Camera3D = d.combat.camera
	evidence.append({"file":name,"mission":mission,"phase":phase,"simulation_seconds":d.elapsed,"camera_position":str(camera.global_position),"camera_size":camera.size,"viewport":str(app.cockpit.viewport.size),"player_position":str(d.player.position),"presentation_altitude":d.combat.presentation_altitude,"terrain_position":str(d.assault.position),"terrain_width":d.assault.terrain.terrain_width,"terrain_length":d.assault.terrain.terrain_length,"triangles":d.assault.terrain.triangle_count,"props":d.assault.terrain.prop_count})

func _run() -> void:
	if DisplayServer.get_name()=="headless":
		push_error("Visual comparison requires the real renderer")
		quit(2)
		return
	_cleanup()
	for size in [Vector2i(1280,720),Vector2i(1920,1080)]:
		root.size = size
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(size)
		for number in [3,7,11,15,19,23,27,31]:
			seed(1942)
			app = load("res://scenes/campaign.tscn").instantiate()
			app.testing = true
			app.profile.path = FIXTURE
			root.add_child(app)
			current_scene = app
			await process_frame
			app.profile.reset()
			app.profile.data.unlocked = 32
			app.profile.data.settings.fullscreen = false
			app.profile.data.settings.quality = 1
			app._launch(number)
			var d: Node = app.director
			var flight: Node = app.cockpit.flight
			flight.get_node("Departure").finish_immediately()
			for name in ["Seascape","Clouds","Combat","Player","Weapons","Departure"]: flight.get_node(name).set_physics_process(false)
			d.set_physics_process(false)
			d.details.set_physics_process(false)
			d.weapons.audio._rng.seed = 1942
			d.player.get_node("Hurtbox").collision_layer = 0
			d.player.position = Vector3(-4,0,7)
			for tick in range(37*60+1):
				d.combat._physics_process(1.0/60)
				d.advance(1.0/60)
				flight.get_node("Seascape")._physics_process(1.0/60)
				flight.get_node("Clouds")._physics_process(1.0/60)
				d.details._physics_process(1.0/60)
				if tick%120==0: await process_frame
				if tick in [8*60,20*60,37*60]:
					var phase: String = {8*60:"approach",20*60:"descent",37*60:"combat"}[tick]
					if phase=="combat":
						d.weapons._fire_salvo()
						d.weapons._physics_process(.04)
					await _capture(number,size,phase,d,flight)
			_stop_audio(app)
			app._dispose_run()
			app.queue_free()
			current_scene = null
			await process_frame
			await process_frame
			await create_timer(.1).timeout
	_cleanup()
	if evidence.size()!=48: failures.append("Expected 48 captures, got %d" % evidence.size())
	var file := FileAccess.open(output_dir.path_join("capture-evidence.json"),FileAccess.WRITE)
	if file==null: failures.append("Cannot save capture report")
	else:
		file.store_string(JSON.stringify({"build":build_id,"quality":1,"seed":1942,"method":"Accelerated deterministic inspection; hurtbox disabled, no human play or FPS measurement","captures":evidence,"failures":failures},"\t"))
		file.close()
	print("RAID VISUAL COMPARISON ",evidence.size()," captures; failures=",failures)
	quit(0 if failures.is_empty() else 1)
