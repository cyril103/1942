extends SceneTree
## Real aircraft/camera limits, real production guns, no artificial target damage.
const DT := 1.0/60.0
var checks := 0
var failures: Array[String] = []
var summaries: Array[Dictionary] = []
var app: Control

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func _freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	if node is AudioStreamPlayer or node is AudioStreamPlayer3D: node.stop()
	for child in node.get_children(): _freeze(child)

func _position_case(mission: int, aircraft: int, corner: Vector2) -> void:
	app.profile.data.aircraft = aircraft
	app._launch(mission)
	var d = app.director
	var raid = d.assault
	var combat = d.combat
	var pilot = d.player
	app.cockpit.flight.get_node("Departure").finish_immediately()
	_freeze(app.cockpit)
	raid.deployed = true
	raid.low_flight = 1
	raid.position.z = -raid.length*.5+10
	raid._apply_flight_view()
	pilot.position = Vector3(corner.x*100,0,corner.y*100)
	pilot._keep_inside_screen()
	var firing_guns := {}
	for frame in range(20*60):
		raid.position.z += float(d.mission.scroll)*1.18*DT
		# Record emissions without overflowing the fixed pool or harming the pilot.
		combat.clear_enemy_bullets()
		for gun in raid.targets:
			if not is_instance_valid(gun) or not gun.alive: continue
			var before: int = combat.enemy_shots
			gun.advance(DT,combat)
			if combat.enemy_shots>before: firing_guns[gun.get_instance_id()] = true
	check(combat.enemy_shots>0 and firing_guns.size()>0,"Mission %d aircraft %d corner %s cannot silence all visible DCA" % [mission,aircraft,corner])
	var before: int = combat.enemy_shots
	for gun in raid.targets:
		if not is_instance_valid(gun) or not gun.alive: continue
		gun.jammed = true
		for frame in range(60): gun.advance(DT,combat)
	check(combat.enemy_shots==before,"Mission %d aircraft %d corner %s respects radar disruption" % [mission,aircraft,corner])
	for gun in raid.targets:
		if not is_instance_valid(gun) or not gun.alive: continue
		gun.jammed = false
	pilot.controls_enabled = false
	for gun in raid.targets:
		if is_instance_valid(gun) and gun.alive:
			for frame in range(60): gun.advance(DT,combat)
	check(combat.enemy_shots==before,"Mission %d aircraft %d corner %s cannot shoot during carrier recovery" % [mission,aircraft,corner])
	summaries.append({"mission":mission,"aircraft":aircraft,"corner":str(corner),"player_z":pilot.position.z,"shots":before,"active_guns":firing_guns.size()})
	app._dispose_run()
	await process_frame

func _run() -> void:
	root.size = Vector2i(1920,1080)
	app = load("res://scenes/campaign.tscn").instantiate()
	app.testing = true
	app.profile.path = "user://ground-boundaries-isolated.json"
	root.add_child(app)
	current_scene = app
	await process_frame
	app.profile.reset()
	app.profile.data.unlocked = 32
	for mission in [3,31]:
		for aircraft in range(3):
			for corner in [Vector2(-1,-1),Vector2(1,-1),Vector2(-1,1),Vector2(1,1),Vector2(0,-1),Vector2(0,1)]:
				await _position_case(mission,aircraft,corner)
	app._show_main()
	app.music.stop()
	print("GROUND BOUNDARIES: ",JSON.stringify({"checks":checks,"failures":failures,"cases":summaries}))
	app.queue_free()
	await process_frame
	await create_timer(.2).timeout
	quit(0 if failures.is_empty() else 1)
