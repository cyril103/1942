extends SceneTree
## External, rendered presentation fixtures for the same 1.8/1.9 packs.
## Posed images and manual mobile-controller snapshots, never gameplay/FPS proof.
const DT := 1.0 / 60.0
const SEED := 1942
const CAPTURE_CLOCK_SCALE := 0.000001
const DIMENSIONS := [Vector2i(1280, 720), Vector2i(1920, 1080)]
const BACKGROUNDS := [
	{"id": "dark-ocean", "mission": 11, "kind": "ocean", "coast_depth": -1.0},
	{"id": "foam", "mission": 3, "kind": "coast", "coast_depth": .32},
	{"id": "sand", "mission": 3, "kind": "coast", "coast_depth": .60},
	{"id": "vegetation", "mission": 15, "kind": "plateau", "coast_depth": 1.0},
	{"id": "snow", "mission": 27, "kind": "plateau", "coast_depth": 1.0}
]
const LABEL_CASES := ["hierarchy", "feedback-ability", "reinforcement", "game-over", "mobile-announce", "mobile-move", "mobile-settle", "mobile-fire"]
const FONT_PATH := "res://assets/ui/fonts/BarlowCondensed-Medium.ttf"
var output_dir := OS.get_user_data_dir().path_join("raid-readability-captures")
var build_id := "unidentified"
var quality := 1
var app: Control
var captures: Array[Dictionary] = []
var failures: Array[String] = []
var fixture_path := ""
var original_time_scale := 1.0
var original_mouse_mode := Input.MOUSE_MODE_VISIBLE

func _initialize() -> void:
	original_time_scale = Engine.time_scale
	original_mouse_mode = Input.mouse_mode
	# Keep a positive engine clock (Godot advises against zero). All scene
	# callbacks are disabled; manual controller steps still receive exact DT.
	Engine.time_scale = CAPTURE_CLOCK_SCALE
	Engine.physics_ticks_per_second = 60
	fixture_path = "user://readability-capture-%d.json" % Time.get_ticks_usec()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output-dir="): output_dir = argument.trim_prefix("--output-dir=")
		elif argument.begins_with("--build-id="): build_id = argument.trim_prefix("--build-id=")
		elif argument.begins_with("--quality="): quality = clampi(argument.trim_prefix("--quality=").to_int(), 0, 2)
		elif argument == "--measure": failures.append("This harness captures posed images only. Use the separate full-mission replay for frame timing.")
	_run.call_deferred()

func _fail(message: String) -> void:
	failures.append(message)
	push_error(message)

func _v2(value: Vector2) -> Array:
	return [value.x, value.y]

func _v3(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

func _release_inputs() -> void:
	for action in InputMap.get_actions():
		Input.action_release(action)
		InputMap.action_erase_events(action)

func _freeze_and_silence(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	node.set_process_input(false)
	node.set_process_unhandled_input(false)
	node.set_process_unhandled_key_input(false)
	if node is AudioStreamPlayer or node is AudioStreamPlayer3D:
		node.stop()
	for child in node.get_children(): _freeze_and_silence(child)

func _cleanup_fixture() -> void:
	if fixture_path.is_empty(): return
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(fixture_path + suffix):
			var error: int = DirAccess.remove_absolute(fixture_path + suffix)
			if error != OK: _fail("Cannot remove this harness's isolated profile: " + fixture_path + suffix)

func _prepare_output() -> bool:
	if output_dir.is_empty():
		_fail("An empty output directory is not allowed")
		return false
	output_dir = ProjectSettings.globalize_path(output_dir)
	if FileAccess.file_exists(output_dir.path_join("captures.json")):
		_fail("Refusing to overwrite an existing capture report; choose a fresh output directory")
		return false
	var error: int = DirAccess.make_dir_recursive_absolute(output_dir)
	if error != OK:
		_fail("Cannot create output directory: " + output_dir)
		return false
	var directory: DirAccess = DirAccess.open(output_dir)
	if directory == null or not directory.get_files().is_empty() or not directory.get_directories().is_empty():
		_fail("Capture output must be an empty directory; partial or unrelated evidence will not be mixed")
		return false
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(fixture_path + suffix):
			_fail("Isolated profile path already exists; no existing profile will be removed")
			fixture_path = ""
			return false
	return true

func _memory() -> Dictionary:
	return {"engine_static_bytes": int(Performance.get_monitor(Performance.MEMORY_STATIC)),
		"render_memory_estimate_bytes": int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"orphan_nodes": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"resources": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))}

func _active(values: PackedFloat32Array) -> int:
	var count: int = 0
	for value in values:
		if value > 0: count += 1
	return count

func _world_at(uv: Vector2) -> Vector3:
	var d: Node = app.director
	var camera: Camera3D = d.combat.camera
	var p: Vector3 = camera.project_position(Vector2(app.cockpit.viewport.size) * uv, 1.0)
	return Vector3(p.x, 0.0, p.z)

func _surface_sample(point: Vector3) -> Dictionary:
	var raid: Node3D = app.director.assault
	var terrain: Node3D = raid.terrain
	if not terrain.visible: return {"surface": "production ocean", "terrain_drawn": false}
	var local: Vector3 = raid.to_local(point)
	var coast: float = minf((terrain._half_width(local.z) - absf(local.x)) / 3.0, (terrain._half_length(local.x) - absf(local.z)) / 6.0)
	return {"surface": "production raid terrain/coast", "terrain_drawn": true, "local_xz": [local.x, local.z],
		"analytic_coast_depth": coast, "production_surface_height": terrain.surface_height(Vector2(local.x, local.z)),
		"limitation": "analytical terrain location; not a sampled GPU material mask or contrast measurement"}

func _new_scene(number: int, dimensions: Vector2i) -> bool:
	seed(SEED)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(dimensions)
	root.size = dimensions
	for path in ["res://scripts/campaign/app.gd", "res://scripts/campaign/hud.gd"]:
		var script: Script = load(path) as Script
		if not is_instance_valid(script) or not script.can_instantiate():
			_fail("Production App/HUD script cannot instantiate: " + path)
			return false
	var scene: PackedScene = load("res://scenes/campaign.tscn") as PackedScene
	if scene == null or not scene.can_instantiate():
		_fail("Production campaign scene is unavailable")
		return false
	var constructed: Variant = scene.instantiate()
	if not is_instance_valid(constructed) or constructed is not Control:
		_fail("Production campaign did not construct its Control root")
		if is_instance_valid(constructed): constructed.free()
		return false
	app = constructed
	if not app.has_method("_launch") or not app.has_method("_dispose_run"):
		_fail("Production campaign root has no usable App script methods")
		return false
	app.testing = true
	app.profile.path = fixture_path
	root.add_child(app)
	current_scene = app
	await process_frame
	app.profile.reset()
	app.profile.data.unlocked = 32
	app.profile.data.settings.fullscreen = false
	app.profile.data.settings.quality = quality
	app.profile.data.settings.vsync = false
	app.profile.data.settings.fps = false
	app.profile.data.settings.music = 0.0
	app.profile.data.settings.effects = 0.0
	app._launch(number)
	if not is_instance_valid(app.director) or not is_instance_valid(app.director.assault):
		_fail("Production ground sortie is unavailable: M%02d" % number)
		return false
	var d: Node = app.director
	var flight: Node = app.cockpit.flight
	flight.get_node("Departure").finish_immediately()
	# Remove only the prototype wrapper after _ready. Refuse to suppress any
	# gameplay callback if a later build adds one to this wrapper.
	var prototype: Script = flight.get_script()
	if prototype != null:
		for method in prototype.get_script_method_list():
			if str(method.name) in ["_process", "_physics_process"]:
				_fail("Prototype input wrapper acquired a gameplay callback")
				return false
		flight.set_script(null)
	_freeze_and_silence(app)
	_release_inputs()
	d.weapons.audio._rng.seed = SEED
	d.player.get_node("Hurtbox").collision_layer = 0
	d.player.invulnerable_time = 0.0
	d.player.alive = true
	d.player.controls_enabled = true
	d.player.show()
	d.player.bank.show()
	d.player.bank.rotation = Vector3.ZERO
	d.player.position = Vector3(0.0, 0.0, 6.5)
	d.elapsed = 37.0
	d.feedback_time = 0.0
	d.ability_time = 0.0
	d.radio_time = 0.0
	d.mastery.cue_time = 0.0
	d.combat.respawn_time = 0.0
	d.combat.game_over = false
	d.combat.clear_enemy_bullets()
	d.weapons.cease_fire()
	for target in d.assault.targets:
		# Posed visual laboratory: no damage, contacts, score, or raycast proof.
		target.collision_layer = 0
		target.warning_time = 0.0
		target.salvo_remaining = 0
		target.flare.hide()
		target.hide()
	var sea: Node = flight.get_node("Seascape")
	for tick in range(60): sea._physics_process(DT)
	# The real mobile and projectile methods may emit sound while posing.
	# Dummy audio is required by the repro command; also stop all live voices.
	_freeze_and_silence(app)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(dimensions)
	root.size = dimensions
	await process_frame
	await process_frame
	return true

func _pose_background(spec: Dictionary) -> Dictionary:
	var d: Node = app.director
	var raid: Node3D = d.assault
	var terrain: Node3D = raid.terrain
	# Deployed=false deliberately suppresses contact labels in material plates.
	# Terrain transforms below are laboratory poses, not natural mission timing.
	raid.deployed = false
	if str(spec.kind) == "ocean":
		raid.position.z = -10000.0
		raid.low_flight = 0.0
		terrain.hide()
		# A material plate isolates water contrast; cloud occlusion is covered by
		# live gameplay review elsewhere, not by this controlled plate.
		app.cockpit.flight.get_node("Clouds").hide()
	else:
		terrain.show()
		raid.low_flight = 1.0
		raid.position.z = 0.0
		if str(spec.kind) == "coast":
			raid.position.z = -(terrain._half_length(0.0) - float(spec.coast_depth) * 6.0)
	raid._apply_flight_view()
	return {"kind": spec.kind, "center_coast_depth_requested": spec.coast_depth,
		"terrain_position": _v3(raid.position), "contact_labels_suppressed": true,
		"clouds_hidden_for_ocean_material_plate": str(spec.kind) == "ocean",
		"low_flight": raid.low_flight, "natural_mission_progression": false}

func _pose_projectiles(explosions: bool) -> Dictionary:
	var d: Node = app.director
	var player: Node3D = d.player
	var saved_position: Vector3 = player.position
	var friendly: Array[Dictionary] = []
	var hostile: Array[Dictionary] = []
	# Four side-by-side samples from the production firing APIs. Rounds remain
	# at their real launch positions, unscaled and unadvanced, for GPU capture.
	for column in range(4):
		var origin: Vector3 = _world_at(Vector2(.23 + float(column) * .18, .50))
		player.position = origin + Vector3(-.65, 0.0, .2925)
		var first_slot: int = d.weapons.active_count
		d.weapons._fire_salvo()
		for index in range(first_slot, d.weapons.active_count):
			friendly.append({"slot": index, "world": _v3(d.weapons.projectiles[index].global_position),
				"screen": _v2(d.combat.camera.unproject_position(d.weapons.projectiles[index].global_position)),
				"surface": _surface_sample(d.weapons.projectiles[index].global_position)})
		var enemy_origin: Vector3 = origin + Vector3(.75, .20, 0.0)
		if not d.combat._launch_enemy_round(enemy_origin, enemy_origin + Vector3(0, 0, 10), 14.0):
			_fail("Hostile production pool refused a material-plate sample")
		else:
			var slot: int = hostile.size()
			hostile.append({"slot": slot, "world": _v3(d.combat.bullets[slot].global_position),
				"screen": _v2(d.combat.camera.unproject_position(d.combat.bullets[slot].global_position)),
				"surface": _surface_sample(d.combat.bullets[slot].global_position)})
		if explosions:
			# Alternating depths put real flash/smoke both behind and in front of
			# sample quads. This intentionally challenges transparency/occlusion.
			var effect_at: Vector3 = origin + Vector3(0, .25 if column % 2 == 0 else -.25, -.15)
			d.combat._explode(effect_at, 1.0, false, false, false)
	player.position = saved_position
	if explosions:
		for tick in range(9):
			d.combat._update_effects(DT)
			d.details._physics_process(DT)
	_freeze_and_silence(app)
	return {"friendly": friendly, "hostile": hostile, "explosions": explosions,
		"explosion_advance_ticks": 9 if explosions else 0,
		"explosion_age_seconds": .15 if explosions else 0.0,
		"projectile_motion": "frozen at production launch pose; no raycast or cadence claim"}

func _pose_contacts() -> Dictionary:
	var d: Node = app.director
	var raid: Node3D = d.assault
	raid.position.z = 0.0
	raid.deployed = true
	raid.low_flight = 1.0
	raid.terrain.show()
	raid._apply_flight_view()
	var required: Array[Area3D] = []
	var others: Array[Area3D] = []
	for target in raid.targets:
		if target.variant == "radar" or str(target.tactical_id) in raid.layout.get("priority_ids", []): required.append(target)
		else: others.append(target)
	var ordered: Array[Area3D] = []
	ordered.append_array(required)
	ordered.append_array(others)
	var corners: Array[Vector2] = [Vector2(.005, .005), Vector2(.995, .005), Vector2(.995, .995), Vector2(.005, .995)]
	if required.size() > corners.size():
		_fail("The authored persistent contact budget changed; review the corner fixture before continuing")
		return {}
	var contacts: Array[Dictionary] = []
	for index in range(ordered.size()):
		var target: Area3D = ordered[index]
		var uv: Vector2 = corners[index] if index < required.size() else Vector2(.12 + float((index - required.size()) % 6) * .15, .21 + float(floori(float(index - required.size()) / 6.0)) * .115)
		if uv.y > .88: uv.y = .88
		target.position = raid.to_local(_world_at(uv))
		target.position.y = 0.0
		target.show()
		target.alive = true
		target.health = target.max_health
		target.warning_time = .25 if index % 4 == 0 else 0.0
		target.salvo_remaining = 2 if index % 4 == 1 else 0
		if index % 4 == 2: target.health = target.max_health * .60
		if target.warning_time > 0:
			target.flare.show()
			target.flare.material_override.set_shader_parameter("strength", .65)
		contacts.append({"id": target.tactical_id, "variant": target.variant, "priority": str(target.tactical_id) in raid.layout.get("priority_ids", []),
			"priority_tag": target.priority_tag, "world": _v3(target.global_position), "uv_requested": _v2(uv),
			"health": target.health, "max_health": target.max_health, "warning_time": target.warning_time, "salvo_remaining": target.salvo_remaining})
	d.player.position = _world_at(Vector2(.5, .82))
	Input.action_press("focus_flight")
	return {"contacts": contacts, "required_contacts": required.size(), "contact_count": ordered.size(),
		"poses": "authored production actors relocated for HUD edge/crowd inspection; colliders disabled"}

func _pose_mobile(case_id: String) -> Dictionary:
	var d: Node = app.director
	var selected: Area3D
	for target in d.assault.targets:
		if target.mobile:
			selected = target
			break
	if not is_instance_valid(selected):
		_fail("The chosen production sector has no mobile battery")
		return {}
	var start: Vector3 = _world_at(Vector2(.34, .60))
	var goal: Vector3 = _world_at(Vector2(.61, .60))
	selected.motion_points = PackedVector3Array([d.assault.to_local(start), d.assault.to_local(goal)])
	selected.position = selected.motion_points[0]
	selected.motion_origin = selected.position
	selected.motion_intent = selected.motion_points[1]
	selected.motion_index = 0
	selected.motion_clock = 0.0
	selected.motion_wait = 0.0
	selected.motion_announcement_pending = false
	selected.mobile_phase = selected.MobilePhase.STATIONARY
	selected.warning_time = 0.0
	selected.salvo_remaining = 0
	selected.flare.hide()
	selected._advance_mobile(DT)
	var steps: int = {"mobile-announce": 12, "mobile-move": 60, "mobile-settle": 115, "mobile-fire": 140}[case_id]
	for tick in range(steps): selected._advance_mobile(DT)
	if case_id == "mobile-fire":
		selected.cooldown = 0.0
		# Actual firing controller creates the warning. No projectile/raycast is
		# used as gameplay evidence, and no cadence or warning timer is changed.
		for tick in range(18): selected.advance(DT, d.combat)
	_freeze_and_silence(app)
	var expected: int = {"mobile-announce": selected.MobilePhase.ANNOUNCE, "mobile-move": selected.MobilePhase.MOVE,
		"mobile-settle": selected.MobilePhase.SETTLE, "mobile-fire": selected.MobilePhase.STATIONARY}[case_id]
	if selected.mobile_phase != expected: _fail("Mobile snapshot did not reach its requested phase: " + case_id)
	return {"id": selected.tactical_id, "phase": int(selected.mobile_phase), "expected_phase": expected,
		"controller_steps": steps + 1 + (18 if case_id == "mobile-fire" else 0), "step_seconds": DT,
		"world": _v3(selected.global_position), "from": _v3(start), "to": _v3(goal),
		"warning_time": selected.warning_time, "salvo_remaining": selected.salvo_remaining,
		"flare_visible": selected.flare.visible, "flare_kind": selected.flare.material_override.get_shader_parameter("kind"),
		"limitation": "snapshots of real mobile controller on a posed laboratory route; no continuous-motion human test"}

func _pose_overlays(case_id: String) -> Dictionary:
	var d: Node = app.director
	d.feedback_time = 2.0 if case_id == "feedback-ability" else 0.0
	d.feedback = "FRAPPE CONFIRMÉE  /  OBJECTIF TERRESTRE ACCOMPLI"
	d.ability_time = 3.5 if case_id == "feedback-ability" else 0.0
	d.combat.respawn_time = 1.0 if case_id == "reinforcement" else 0.0
	d.combat.game_over = case_id == "game-over"
	d.radio_time = 3.0
	d.radio = "Contrôle : repérez les radars, les priorités et l'annonce de déplacement."
	if not d.assault.network_jams.is_empty():
		var network: String = str(d.assault.network_jams.keys()[0])
		d.assault.network_jams[network] = 3.6
	var hud: Control = app.cockpit.get_node("CampaignHUD")
	hud.elapsed = 1.25
	hud._update_jam_status()
	return {"feedback_time": d.feedback_time, "feedback": d.feedback, "ability_time": d.ability_time,
		"respawn_time": d.combat.respawn_time, "game_over": d.combat.game_over, "radio": d.radio,
		"hud_elapsed": hud.elapsed, "laboratory_overlay_flags": true}

func _resource_source_evidence(path: String) -> Dictionary:
	# Load the runtime resource first. In a --main-pack launch, FileAccess can
	# still resolve accessible .gd text from --path while Script loads compiled
	# bytecode from the pack. That text is not embedded/runtime identity proof.
	var resource: Resource = ResourceLoader.load(path)
	var text: String = ""
	var api: String = ""
	var kind: String = "unknown"
	if resource is Shader:
		var shader: Shader = resource as Shader
		text = shader.code
		api = "ResourceLoader.load().Shader.code"
		kind = "Shader"
	elif resource is Script:
		var script: Script = resource as Script
		text = script.get_source_code()
		api = "ResourceLoader.load().Script.get_source_code()"
		kind = "Script"
	var normalized: String = text.replace("\r\n", "\n").strip_edges()
	var status: String = "available" if not normalized.is_empty() else "unavailable_in_compiled_pack"
	if not is_instance_valid(resource): status = "resource_unavailable"
	return {"sha256": normalized.sha256_text() if not normalized.is_empty() else "",
		"status": status,
		"origin": "resource_representation_not_exact_source_or_bytecode", "api": api, "kind": kind,
		"resource_path": resource.resource_path if is_instance_valid(resource) else "",
		"normalization": "CRLF to LF; strip_edges; SHA256 UTF8",
		"identity_limit": "Representation of a loaded resource; never an exact source/bytecode or complete pack identity"}

func _filesystem_text_evidence(path: String) -> Dictionary:
	# Diagnostic only, deliberately separate from loaded resource evidence.
	var exists: bool = FileAccess.file_exists(path)
	var text: String = FileAccess.get_file_as_string(path) if exists else ""
	var normalized: String = text.replace("\r\n", "\n").strip_edges()
	return {"sha256": normalized.sha256_text() if not normalized.is_empty() else "", "exists": exists,
		"origin": "accessible_filesystem_text_not_runtime_identity",
		"normalization": "CRLF to LF; strip_edges; SHA256 UTF8"}

func _actual_runtime_provenance(hud: Control, contacts: Array[Dictionary]) -> Dictionary:
	# Observe the actual HUD instance and actual material uniform snapshots.
	# Do not assume that accessible .gd text describes the compiled instance.
	var methods: Dictionary = {}
	for method in ["_draw_ground_contacts", "_ground_label_reservations", "_draw_mobile_motion_hint"]:
		methods[method] = hud.has_method(method)
	var actual_script: Script = hud.get_script() as Script
	var uniforms: Array[Dictionary] = []
	for contact in contacts:
		uniforms.append({"id": contact.id, "mobile_phase": contact.mobile_phase,
			"flare_kind": contact.flare_kind, "flare_visible": contact.flare_visible})
	return {"hud_methods": methods,
		"hud_script_resource_path": actual_script.resource_path if is_instance_valid(actual_script) else "",
		"actual_ground_material_uniforms": uniforms,
		"identity_limit": "Observed methods/material uniforms of real posed production instances; not bytecode or whole-pack identity"}

func _capture(name: String, dimensions: Vector2i, fixture: Dictionary) -> void:
	var path: String = output_dir.path_join(name + ".png")
	if FileAccess.file_exists(path):
		_fail("Refusing to overwrite an existing image: " + path)
		return
	_freeze_and_silence(app)
	var hud: Control = app.cockpit.get_node("CampaignHUD")
	hud._process(0.0)
	app.cockpit.queue_redraw()
	hud.queue_redraw()
	for frame in range(5): await process_frame
	await RenderingServer.frame_post_draw
	var pixels: Image = root.get_texture().get_image()
	if pixels == null or pixels.is_empty():
		_fail("The real GPU viewport returned no pixels: " + name)
		return
	var actual_size: Vector2i = pixels.get_size()
	if actual_size != dimensions: _fail("Extracted GPU pixels have a different physical size: " + name + " got " + str(actual_size))
	var error: int = pixels.save_png(path)
	if error != OK:
		_fail("Cannot save GPU capture: " + path)
		return
	var d: Node = app.director
	var camera: Camera3D = d.combat.camera
	var final_contacts: Array[Dictionary] = []
	for target in d.assault.contacts():
		final_contacts.append({"id": target.tactical_id, "world": _v3(target.global_position),
			"screen": _v2(camera.unproject_position(target.global_position)), "visible": target.visible,
			"variant": target.variant, "health": target.health, "max_health": target.max_health,
			"warning_time": target.warning_time, "salvo_remaining": target.salvo_remaining,
			"mobile": target.mobile, "mobile_phase": int(target.mobile_phase),
			"flare_visible": target.flare.visible, "flare_kind": target.flare.material_override.get_shader_parameter("kind")})
	var pools: Dictionary = {"player_active": _active(d.weapons.lifetimes), "player_capacity": d.weapons.CAPACITY,
		"enemy_active": _active(d.combat.lifetimes), "enemy_capacity": d.combat.BULLET_CAPACITY,
		"explosions_active": _active(d.combat.effect_times), "explosions_capacity": d.combat.EFFECT_CAPACITY}
	if int(pools.player_active) > int(pools.player_capacity) or int(pools.enemy_active) > int(pools.enemy_capacity) or int(pools.explosions_active) > int(pools.explosions_capacity):
		_fail("A fixed production pool exceeded its capacity: " + name)
	var source_hashes: Dictionary = {}
	var filesystem_text_diagnostics: Dictionary = {}
	for source in ["res://shaders/enemy_bullet.gdshader", "res://shaders/tracer.gdshader", "res://shaders/ground_target_fire.gdshader", "res://scripts/campaign/hud.gd", "res://scripts/campaign/ground_target.gd"]:
		source_hashes[source] = _resource_source_evidence(source)
		filesystem_text_diagnostics[source] = _filesystem_text_evidence(source)
	var entry: Dictionary = {"file": name + ".png", "build": build_id, "quality": quality, "seed": SEED, "mission": int(d.mission.id), "biome": str(d.mission.biome),
		"physical_png_pixels": [actual_size.x, actual_size.y], "requested_window_pixels": [dimensions.x, dimensions.y],
		"window_pixels_reported": _v2(Vector2(DisplayServer.window_get_size())), "root_viewport_pixels_reported": _v2(root.get_visible_rect().size),
		"gameplay_internal_pixels": _v2(Vector2(app.cockpit.viewport.size)), "cockpit_canvas_size": _v2(app.cockpit.size),
		"play_rect": {"position": _v2(app.cockpit.play_rect.position), "size": _v2(app.cockpit.play_rect.size)},
		"camera_position": _v3(camera.global_position), "camera_rotation": _v3(camera.global_rotation), "camera_size": camera.size,
		"player_position": _v3(d.player.position), "player_visual_altitude": d.player.bank.position.y,
		"mission_elapsed_fixture": d.elapsed, "sea_manual_ticks": 60, "sea_scroll_distance": d.assault.sea.scroll_distance,
		"terrain_position": _v3(d.assault.position), "terrain_size": [d.assault.width, d.assault.length],
		"terrain_triangles": d.assault.terrain.triangle_count, "terrain_props": d.assault.terrain.prop_count,
		"engine_time_scale": Engine.time_scale, "extraction": "GPU pixels read after frame_post_draw; no assumed ViewportTexture dimensions",
		"pools": pools, "memory": _memory(), "source_hashes": source_hashes,
		"filesystem_text_diagnostics": filesystem_text_diagnostics, "runtime_provenance": _actual_runtime_provenance(hud, final_contacts),
		"final_contacts": final_contacts, "fixture": fixture}
	captures.append(entry)
	print("READABILITY GPU CAPTURE ", name, " ", actual_size, " pools=", JSON.stringify(pools))

func _dispose() -> void:
	_release_inputs()
	if is_instance_valid(app):
		_freeze_and_silence(app)
		if app.has_method("_dispose_run"): app._dispose_run()
		app.queue_free()
	app = null
	current_scene = null
	for frame in range(3): await process_frame

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		_fail("Rendered readability captures require the real renderer, not headless")
		Engine.time_scale = original_time_scale
		quit(2)
		return
	if not failures.is_empty() or not _prepare_output():
		Engine.time_scale = original_time_scale
		quit(2)
		return
	var initial_memory: Dictionary = _memory()
	for dimensions in DIMENSIONS:
		for spec in BACKGROUNDS:
			for explosion in [false, true]:
				var launched: Variant = await _new_scene(int(spec.mission), dimensions)
				if launched != true:
					_fail("Material fixture did not finish scene construction: " + str(spec.id))
					await _dispose()
					continue
				var fixture: Dictionary = {"scope": "material and projectile plate", "background": _pose_background(spec)}
				fixture.projectiles = _pose_projectiles(explosion)
				await _capture("background-%s-%s-%d" % [str(spec.id), "explosion" if explosion else "clear", dimensions.y], dimensions, fixture)
				await _dispose()
		for case_id in LABEL_CASES:
			var number: int = 19 if str(case_id).begins_with("mobile-") else 31
			var launched: Variant = await _new_scene(number, dimensions)
			if launched != true:
				_fail("Contact fixture did not finish scene construction: " + str(case_id))
				await _dispose()
				continue
			var fixture: Dictionary = {"scope": "ground contact HUD and edge stress", "contacts": _pose_contacts(), "overlays": _pose_overlays(case_id)}
			if str(case_id).begins_with("mobile-"): fixture.mobile = _pose_mobile(case_id)
			fixture.projectiles = _pose_projectiles(case_id == "feedback-ability")
			await _capture("contacts-%s-%d" % [case_id, dimensions.y], dimensions, fixture)
			await _dispose()
	_cleanup_fixture()
	if captures.size() != 36: _fail("Expected 36 rendered captures; got %d" % captures.size())
	var report: Dictionary = {"schema": 2, "build": build_id, "engine": Engine.get_version_info(), "gpu": RenderingServer.get_video_adapter_name(),
		"cpu": OS.get_processor_name(), "os": OS.get_name(), "quality": quality, "seed": SEED,
		"method": "Controlled posed production scenes and manually advanced mobile-controller snapshots, DT=1/60 s",
		"font": FONT_PATH,
		"input_isolation": "All hardware action events erased; prototype input wrapper removed after verifying no gameplay callbacks; automatic simulation disabled",
		"audio": "Silent visual harness; use --audio-driver Dummy. No PCM recording, listening, or mix proof.",
		"shader_time": "Positive Engine.time_scale=0.000001 minimizes further builtin TIME advancement; initial builtin TIME is unavailable and not asserted equal across processes",
		"resolution_note": "Physical PNG pixels and internal gameplay viewport pixels are recorded separately; canvas stretch can keep the same internal resolution at both window sizes",
		"limits": ["Not a natural mission or human playtest", "No damage, raycast, target viability, cadence or FPS proof", "No continuous-motion or human recognition proof", "Memory monitors are engine/static and graphics estimates, not Windows private bytes or physical VRAM", "No automatic contrast or artistic acceptance assertion"],
		"human_review": "NOT_PERFORMED", "captures": captures, "initial_memory": initial_memory, "after_dispose_memory": _memory(), "failures": failures}
	var file: FileAccess = FileAccess.open(output_dir.path_join("captures.json"), FileAccess.WRITE)
	if file == null: _fail("Cannot save capture evidence report")
	else:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	Engine.time_scale = original_time_scale
	Input.mouse_mode = original_mouse_mode
	print("READABILITY CAPTURES ", captures.size(), " failures=", failures)
	quit(0 if failures.is_empty() else 1)
