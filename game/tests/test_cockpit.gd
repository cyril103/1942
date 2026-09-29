extends SceneTree
var failures: Array[String] = []
var checks := 0
const FIXTURE := "user://cockpit-test-record.cfg"

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func _initialize() -> void:
	_run.call_deferred()

func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _run() -> void:
	if FileAccess.file_exists(FIXTURE): DirAccess.remove_absolute(FIXTURE)
	var cockpit = load("res://scenes/cockpit.tscn").instantiate()
	cockpit.save_path = FIXTURE
	root.add_child(cockpit)
	current_scene = cockpit
	await process_frame
	var combat = cockpit.combat
	var player = cockpit.player
	var weapons = cockpit.flight.get_node("Weapons")
	for node_name in ["Combat","Weapons","Seascape","Player"]:
		cockpit.flight.get_node(node_name).set_physics_process(false)
	cockpit.flight.get_node("Departure").finish_immediately()
	check(combat.remaining_lives == 3,"Three actual lives at launch")
	check(not combat.hud.get_parent().visible,"Legacy HUD does not overlap gameplay")
	for dimensions in [Vector2i(1920,1080),Vector2i(1280,720),Vector2i(2560,1080),Vector2i(1280,1024),Vector2i(720,1280)]:
		root.size = dimensions
		await process_frame
		await process_frame
		check(cockpit.viewport.size.x*4 == cockpit.viewport.size.y*3,"Exact 3:4 viewport at %s" % dimensions)
		check(Rect2(Vector2.ZERO,cockpit.size).encloses(cockpit.play_rect),"Viewport stays within window")
		check(is_equal_approx(cockpit.left.position.x+555*cockpit.left.scale.x,cockpit.play_rect.position.x),"Left panel ends exactly at gameplay boundary")
		check(is_equal_approx(cockpit.right.position.x,cockpit.play_rect.end.x),"Right panel begins exactly at gameplay boundary")
		for direction in [KEY_LEFT,KEY_RIGHT,KEY_UP,KEY_DOWN]:
			key(direction,true)
			for frame in range(240): player._physics_process(1.0/60)
			key(direction,false)
			check(Rect2(Vector2.ONE*11,Vector2(cockpit.viewport.size)-Vector2.ONE*22).encloses(player.get_screen_bounds()),"Whole aircraft remains inside portrait playfield")
	root.size = Vector2i(1920,1080)
	await process_frame
	await process_frame
	player.position = Vector3(0,0,5)
	player.bank.rotation = Vector3.ZERO
	# Actual physics world, pooled rounds and shared target collider in SubViewport.
	combat.spawn_wave()
	var enemy = combat.enemies[0]
	enemy.position = Vector3.ZERO
	for index in range(1,4): combat.enemies[index].position = Vector3(20+index,0,-20)
	await physics_frame
	await physics_frame
	weapons._fire_salvo()
	weapons._physics_process(0.2)
	check(not enemy.alive and combat.score == 100,"Real projectile collision awards 100 points inside subviewport")
	cockpit._process(1.0)
	check(cockpit.left.displays[0].value == "000100","Score instrument displays live score")
	cockpit.save_record()
	var record := ConfigFile.new()
	check(record.load(FIXTURE) == OK and record.get_value("pilot","high_score",0) == 100,"High score saved to isolated fixture")
	var clone = load("res://scenes/cockpit.tscn").instantiate()
	clone.save_path = FIXTURE
	root.add_child(clone)
	check(clone.high_score == 100,"High score reloaded by a fresh cockpit")
	clone.queue_free()
	await process_frame
	var shooter = combat.enemies[1]
	shooter.position = Vector3(0,0,2)
	combat.fire_enemy(shooter)
	combat._update_bullets(0.4)
	check(not player.alive and combat.remaining_lives == 2 and not combat.game_over,"First death consumes one life")
	check(combat.lifetimes.count(0.0) == combat.BULLET_CAPACITY,"Hostile rounds cleared on death")
	combat._physics_process(2.3)
	check(player.alive and player.controls_enabled and player.invulnerable_time>0,"Respawn restores control with temporary protection")
	player.take_damage(1)
	check(player.alive and combat.remaining_lives == 2,"Respawn protection prevents immediate repeated death")
	player._physics_process(3.1)
	check(player.bank.visible and player.invulnerable_time == 0,"Protection expires and aircraft becomes fully visible")
	player.take_damage(1)
	combat._physics_process(2.3)
	player._physics_process(3.1)
	player.take_damage(1)
	cockpit._process(0.1)
	check(combat.game_over and combat.remaining_lives==0 and cockpit.message.visible,"Third death displays final mission overlay")
	var wave: int = combat.wave_count
	combat._physics_process(40)
	check(combat.wave_count == wave,"No waves after final defeat")
	# R must reload the cockpit root, not just the nested gameplay scene.
	var old_id: int = cockpit.get_instance_id()
	key(KEY_R,true)
	await process_frame
	await process_frame
	check(current_scene.get_instance_id()!=old_id and current_scene.has_node("FlightViewport"),"R restarts full cockpit")
	check(current_scene.combat.remaining_lives==3 and current_scene.combat.score==0,"Restart resets run and lives")
	current_scene.flight.get_node("Departure").finish_immediately()
	key(KEY_SPACE,true)
	current_scene.flight.get_node("Weapons")._physics_process(0.13)
	key(KEY_SPACE,false)
	check(current_scene.flight.get_node("Weapons").shots_fired>=2,"Space fires through the cockpit input boundary")
	current_scene.persistence_enabled = false
	key(KEY_R,false)
	DirAccess.remove_absolute(FIXTURE)
	var report := {"checks":checks,"failures":failures,"formats":["16:9","ultrawide","5:4","portrait"],"playfield":"3:4","lives":3}
	var file := FileAccess.open("res://tests/cockpit-results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("COCKPIT ","PASS" if failures.is_empty() else "FAIL",": ",JSON.stringify(report))
	if not failures.is_empty():
		quit(1)
		return
	key(KEY_ESCAPE,true)
	await create_timer(1).timeout
	push_error("Escape did not quit cockpit")
	quit(1)
