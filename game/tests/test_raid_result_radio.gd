extends SceneTree
## Controlled real weapon/death/Director paths and actual result UI.
## Targets are isolated for the arena; this is not a sortie or human playtest.
const FIXTURE := "user://raid-result-radio-isolated.json"
const DT := 1.0/120.0
var app: Control
var director: Node
var checks := 0
var failures: Array[String] = []
var observations: Array[Dictionary] = []
var death_cases := 0
var retreat_cases := 0
var victory_cases := 0
var radio_cases := 0
var output_dir := "user://raid-result-radio-review"
var report_box := {"reports":[]}

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output-dir="): output_dir = argument.trim_prefix("--output-dir=")
	DirAccess.make_dir_recursive_absolute(output_dir)
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func _cleanup_profile() -> void:
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(FIXTURE+suffix): DirAccess.remove_absolute(FIXTURE+suffix)

func _freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children(): _freeze(child)

func _stop_audio(node: Node) -> void:
	if node is AudioStreamPlayer or node is AudioStreamPlayer3D: node.stop()
	for child in node.get_children(): _stop_audio(child)

func _sync() -> void:
	await physics_frame
	await physics_frame

func _launch(number: int) -> void:
	Input.action_release("fire")
	app._dispose_run()
	await _sync()
	app.profile.reset()
	app.profile.data.unlocked = 32
	app.profile.data.run_lives = 1
	app.profile.data.settings.fullscreen = false
	app._launch(number)
	director = app.director
	report_box.reports = []
	director.finished.connect(func(report): report_box.reports.append(report.duplicate(true)))
	app.cockpit.flight.get_node("Departure").finish_immediately()
	_freeze(app.cockpit.flight)
	_stop_audio(app)
	director.player.position = Vector3(0,0,7)
	director.player.get_node("Hurtbox").collision_layer = 0
	director.elapsed = 12.0
	director.assault.advance(DT)
	check(director.assault.deployed,"Real raid deploys its prepared colliders")
	director.assault.position = Vector3.ZERO
	director.assault.low_flight = 1.0
	director.assault._apply_flight_view()
	await _sync()

func _kill_with_weapon(target: Area3D, kept: Array = []) -> bool:
	check(is_instance_valid(target) and target.alive,"Weapon case executes on a living physical target")
	if not is_instance_valid(target) or not target.alive: return false
	var index := 0
	for other in director.assault.targets:
		if not is_instance_valid(other) or other==target or kept.has(other): continue
		other.collision_layer = 0
		other.position = Vector3(80+index*8,0,-80)
		index += 1
	target.position = Vector3(0,0,-2)
	target.collision_layer = 2
	director.player.position = Vector3(0,0,7)
	await _sync()
	var weapons: Node3D = director.weapons
	weapons.cease_fire()
	weapons.set_power("laser")
	Input.action_release("fire")
	weapons._physics_process(1.0)
	var initial_kills: int = director.assault.kills
	var initial_hits: int = weapons.hits_landed
	Input.action_press("fire")
	for tick in range(120*8):
		if not target.alive: break
		weapons._physics_process(DT)
	Input.action_release("fire")
	weapons.cease_fire()
	check(weapons.hits_landed>initial_hits and not target.alive,"Production laser really destroys "+target.tactical_id)
	check(director.assault.kills==initial_kills+1 and director.assault.destroyed_ids.has(target.tactical_id),"Physical destruction records exactly one authored ID")
	return not target.alive

func _meet_main_objective() -> void:
	var raid: Node3D = director.assault
	for target_id in raid.layout.priority_ids:
		await _kill_with_weapon(raid.target_by_id(str(target_id)))
	for target in raid.targets.duplicate():
		if raid.kills>=int(raid.layout.quota): break
		if is_instance_valid(target) and target.alive and target.variant!="fuel":
			await _kill_with_weapon(target)
	check(raid.kills>=int(raid.layout.quota) and raid.main_objective_met(),"Real weapons meet quota AND all mandatory hangar IDs")

func _find_label(text: String) -> Label:
	for child in app.design.get_children():
		if child is Label and child.text==text: return child
	return null

func _ui_result(title: String, outcome: String, context: String) -> void:
	check(app.page=="result","Actual deferred result screen opens: "+context)
	check(_find_label(title)!=null,"Result title is "+title+": "+context)
	check(_find_label(outcome)!=null,"Result outcome is "+outcome+": "+context)
	check(_find_label("MISSION INACCOMPLIE")==null if title=="GAME OVER" else true,"Game Over cannot retain an incomplete-mission title: "+context)
	# canvas_items keeps a logical canvas while the Window/PNG has pixel dimensions.
	# Compare like coordinates, then use the real canvas/stretch transforms to
	# independently check every rendered rectangle against the physical window.
	var logical_bounds: Rect2 = root.get_visible_rect()
	var pixel_bounds := Rect2(Vector2.ZERO,Vector2(root.size))
	var final_transform: Transform2D = root.get_final_transform()
	# Read the completed framebuffer, as the real PNG capture does. The texture's
	# declared size is not a measurement of the pixels returned by GPU readback.
	await RenderingServer.frame_post_draw
	var texture: ViewportTexture = root.get_texture()
	var declared_texture_size: Vector2 = texture.get_size()
	var rendered_image: Image = texture.get_image()
	var render_size: Vector2i = rendered_image.get_size() if rendered_image!=null else Vector2i.ZERO
	var control_bounds: Array[Dictionary] = []
	check(rendered_image!=null and render_size==root.size,"Result render output matches the physical window: "+context)
	for child in app.design.get_children():
		if child is not Control: continue
		var local_rect := Rect2(Vector2.ZERO,child.size)
		var canvas_transform: Transform2D = child.get_global_transform_with_canvas()
		var logical_rect: Rect2 = canvas_transform*local_rect
		var pixel_rect: Rect2 = (final_transform*canvas_transform)*local_rect
		check(logical_bounds.encloses(logical_rect),"Visible logical result contains "+str(child.name)+": "+context)
		check(pixel_bounds.encloses(pixel_rect),"Visible physical result contains "+str(child.name)+": "+context)
		control_bounds.append({"name":str(child.name),"logical_rect":str(logical_rect),"physical_rect":str(pixel_rect)})
		if child is Label:
			check(child.get_minimum_size().y<=child.size.y+.2,"Result fits all lines in "+str(child.name)+": "+context)
	observations.append({"kind":"ui_geometry","context":context,"logical_visible_rect":str(logical_bounds),"logical_size":[logical_bounds.size.x,logical_bounds.size.y],"physical_window_size":[root.size.x,root.size.y],"physical_render_size":[render_size.x,render_size.y],"viewport_texture_declared_size":[declared_texture_size.x,declared_texture_size.y],"final_transform":str(final_transform),"controls":control_bounds})
	var ground: Label = app.design.get_node("ResultGroundObjective")
	var status: Dictionary = app.result.ground_status
	check(ground.text.contains("%d / %d" % [int(status.kills),int(status.quota)]),"Result preserves actual quota counts: "+context)
	check(ground.text.contains("PRIORITÉS  %d / %d" % [int(status.priority_destroyed),int(status.priority_total)]),"Result preserves mandatory-target counts: "+context)

func _await_result() -> void:
	for frame in range(3): await process_frame
	check(report_box.reports.size()==1,"The real Director emits exactly one terminal report")
	check(not director.active and director.paused and paused,"Actual result deactivates and pauses the flight")

func _capture(name: String) -> void:
	if "--capture-ui" not in OS.get_cmdline_user_args(): return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output_dir.path_join(name+".png"))==OK,"Save regression screenshot "+name)

func _last_life(objective_met: bool, cached_completion: bool) -> void:
	await _launch(15)
	if objective_met: await _meet_main_objective()
	check(director.assault.main_objective_met()==objective_met,"Death fixture starts with its real requested objective state")
	# Exercise both historical cached landing decisions; neither determines
	# whether the last-life path is Game Over or what was truly destroyed.
	director.mission_completed = cached_completion
	var objective_before: Dictionary = director.assault.objective_status()
	director.player.invulnerable_time = 0
	director.player.take_damage(director.player.health)
	check(not director.player.alive and director.combat.game_over and director.combat.remaining_lives==0,"Actual lethal damage exhausts the last life through Combat")
	check(director.deaths==1 and director.damage_taken==1,"The lethal hit runs actual damage/death callbacks")
	director.advance(2.39)
	check(report_box.reports.is_empty() and director.active,"Game Over retains its real death presentation delay")
	director.advance(.02)
	await _await_result()
	if report_box.reports.is_empty(): return
	var report: Dictionary = report_box.reports[0]
	check(not report.won and bool(report.game_over) and not bool(report.objective_failed),"Last-life loss is Game Over, never a living objective retreat")
	check(int(report.lives)==0 and int(report.grade)==0 and int(report.bonus)==0,"Game Over retains zero lives and no victory award")
	check(bool(report.objective_met)==objective_met and report.ground_status==director.assault.objective_status(),"Report retains real objectives even when the pilot dies after completing them")
	check(int(report.ground_status.kills)==int(objective_before.kills) and int(report.ground_status.priority_destroyed)==int(objective_before.priority_destroyed),"The death delay invents no quota or priority destruction")
	var context := "%dp main=%s cached=%s" % [root.size.y,str(objective_met),str(cached_completion)]
	await _ui_result("GAME OVER","AUCUNE VIE RESTANTE",context)
	await _capture("game-over-%d-main-%s-cache-%s" % [root.size.y,str(objective_met),str(cached_completion)])
	# A historical report may carry the obsolete objective flag and no terminal
	# cause. Its actual zero-life count still takes precedence in presentation.
	var legacy := report.duplicate(true)
	legacy.erase("game_over")
	legacy.objective_failed = true
	app._draw_result(legacy)
	check(_find_label("GAME OVER")!=null and _find_label("AUCUNE VIE RESTANTE")!=null,"Historical zero-life report also renders Game Over")
	observations.append({"kind":"last_life","window":str(root.size),"objective_before":objective_before,"cached_completion":cached_completion,"report":report})
	death_cases += 1

func _carrier_result(won: bool) -> void:
	await _launch(15)
	if won: await _meet_main_objective()
	var raid: Node3D = director.assault
	var departure: Node3D = app.cockpit.flight.get_node("Departure")
	raid.position.z = raid.length*.5+director.combat.screen_bottom()+40.0
	raid.low_flight = 0.0
	raid._apply_flight_view()
	director.elapsed = float(director.mission.duration)
	director.event_index = director.mission.events.size()
	director.act_index = director.mission.get("acts",[]).size()-1
	# Advance the real return window, ending decision and landing choreography.
	for tick in range(120):
		if not director.active: break
		director.advance(.25)
	check(departure.landed,"Living outcome goes through a real carrier landing")
	await _await_result()
	if report_box.reports.is_empty(): return
	var report: Dictionary = report_box.reports[0]
	check(bool(report.won)==won and bool(report.objective_met)==won,"Living outcome retains the actual shared objective decision")
	check(not bool(report.game_over) and bool(report.objective_failed)==not won and int(report.lives)==1,"Living retreat keeps its historical incomplete-objective semantics")
	var title := "MISSION ACCOMPLIE" if won else "MISSION INACCOMPLIE"
	var outcome: String = ["—","BRONZE","ARGENT","OR"][int(report.grade)] if won else "OBJECTIF NON ATTEINT"
	await _ui_result(title,outcome,"living %dp won=%s" % [root.size.y,str(won)])
	var legacy := report.duplicate(true)
	legacy.erase("game_over")
	app._draw_result(legacy)
	check(_find_label(title)!=null and _find_label(outcome)!=null,"Historical living result keeps the same title and outcome")
	observations.append({"kind":"carrier_result","window":str(root.size),"report":report})
	if won: victory_cases += 1
	else: retreat_cases += 1

func _radar_radio(number: int, radar_id: String, network_id: String, expected_label: String) -> void:
	await _launch(number)
	var raid: Node3D = director.assault
	var group: Dictionary = raid.layout.radar_groups[network_id]
	var radar: Area3D = raid.target_by_id(radar_id)
	var linked: Area3D = raid.target_by_id(str(group.target_ids[0]))
	var outsider: Area3D
	for other_id in raid.layout.radar_groups:
		if other_id!=network_id:
			outsider = raid.target_by_id(str(raid.layout.radar_groups[other_id].target_ids[0]))
			break
	check(is_instance_valid(radar) and is_instance_valid(linked) and is_instance_valid(outsider),"Radio fixture contains real radar and independent guns")
	if not is_instance_valid(radar) or not is_instance_valid(linked) or not is_instance_valid(outsider): return
	for target in raid.targets:
		if not [radar,linked,outsider].has(target): target.retire()
	linked.position = Vector3(-7,0,-5)
	outsider.position = Vector3(7,0,-5)
	var emissions: Array[Dictionary] = []
	raid.network_disrupted.connect(func(id,seconds,global_scope): emissions.append({"id":id,"seconds":seconds,"global":global_scope}))
	await _kill_with_weapon(radar,[linked,outsider])
	check(emissions.size()==1 and emissions[0].id==network_id and is_equal_approx(float(emissions[0].seconds),6.0) and not bool(emissions[0].global),"Actual radar emits one local six-second disruption")
	check(str(group.label)==expected_label and director.radio.contains(expected_label),"Radio retains the readable authored label "+expected_label)
	check(not director.radio.contains("Réseau "+network_id) and director.radio.contains("Les autres défenses restent actives."),"Radio does not overwrite the readable label with an internal scope")
	check(is_equal_approx(director.radio_time,4.0),"The single radio message preserves its presentation duration")
	check(linked.jammed and not outsider.jammed and raid.jam_remaining==0.0,"Local disruption leaves independent real guns armed")
	var outsider_rounds := 0
	var linked_rounds := 0
	for tick in range(120*3):
		director.combat._physics_process(DT)
		raid.advance(DT)
		for index in range(director.combat.BULLET_CAPACITY):
			if director.combat.lifetimes[index]!=6.0: continue
			var x: float = director.combat.bullets[index].global_position.x
			if absf(x-7)<1.0: outsider_rounds += 1
			if absf(x+7)<1.0: linked_rounds += 1
	check(outsider_rounds>0 and linked_rounds==0,"Independent network emits actual pooled rounds while the linked guns stay silent")
	check(float(raid.network_jams[network_id])>2.9 and float(raid.network_jams[network_id])<3.1,"Removing duplicate wording does not change the disruption clock")
	check(director.radio.contains(expected_label),"No later assault update replaces the radar label with a technical ID")
	observations.append({"kind":"radar_radio","mission":number,"radar":radar_id,"network":network_id,"radio":director.radio,"emissions":emissions,"outsider_rounds":outsider_rounds,"linked_rounds":linked_rounds})
	radio_cases += 1

func _run() -> void:
	if DisplayServer.get_name()=="headless":
		push_error("Actual result UI needs the renderer")
		quit(2)
		return
	_cleanup_profile()
	app = load("res://scenes/campaign.tscn").instantiate()
	app.testing = true
	app.profile.path = FIXTURE
	root.add_child(app)
	current_scene = app
	await process_frame
	app.set_process(false)
	root.mode = Window.MODE_WINDOWED
	for dimensions in [Vector2i(1280,720),Vector2i(1920,1080)]:
		root.size = dimensions
		await process_frame
		await process_frame
		for objective_met in [false,true]:
			for cached_completion in [false,true]:
				await _last_life(objective_met,cached_completion)
		await _carrier_result(false)
		await _carrier_result(true)
	await _radar_radio(11,"storm/r01","west","Réseau Ouest")
	await _radar_radio(31,"final/r02","middle","Ceinture intermédiaire")
	check(death_cases==8 and retreat_cases==2 and victory_cases==2 and radio_cases==2,"All eight deaths, four actual landings and two radar cases executed")
	Input.action_release("fire")
	paused = false
	_stop_audio(app)
	app._dispose_run()
	await create_timer(.25).timeout
	app.queue_free()
	current_scene = null
	await process_frame
	await process_frame
	await create_timer(.10).timeout
	_cleanup_profile()
	var file := FileAccess.open("res://tests/raid-result-radio-results.json",FileAccess.WRITE)
	check(file!=null,"Save actual result/radio regression report")
	if file!=null:
		file.store_string(JSON.stringify({"checks":checks,"failures":failures,"fixtures":{"deaths":death_cases,"retreats":retreat_cases,"victories":victory_cases,"radars":radio_cases},"observations":observations,"method":"controlled actual weapons, lethal damage, Director.advance and deferred App UI","human_play":"NOT_PERFORMED","performance":"NOT_MEASURED"},"\t"))
		file.close()
	print("RAID RESULT RADIO: ",checks," checks; failures: ",failures)
	quit(0 if failures.is_empty() else 1)
