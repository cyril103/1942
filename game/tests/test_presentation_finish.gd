extends SceneTree
## Integration: actual actor signals, deferred retirement, score and reusable VFX.
var checks := 0
var failures: Array[String] = []
var app: Node
func _initialize() -> void: _run.call_deferred()
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message); push_error(message)
func freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children(): freeze(child)
func stop_audio(node: Node) -> void:
	if node is AudioStreamPlayer or node is AudioStreamPlayer3D: node.stop()
	for child in node.get_children(): stop_audio(child)
func _run() -> void:
	app = load("res://scenes/campaign.tscn").instantiate()
	app.testing = true
	app.profile.path = "user://presentation-fixture.json"
	root.add_child(app)
	app.profile.reset()
	app.profile.data.settings.fullscreen = false
	app._launch(1)
	var d: Node = app.director
	var c: Node = d.combat
	app.cockpit.flight.get_node("Departure").finish_immediately()
	freeze(app)
	d._clear_actors()
	c.enemies.clear()
	var awards: Array = []
	c.formations.cleared.connect(func(at,bonus,red): awards.append([at,bonus,red]))
	for pattern in [0,1]:
		c.wave_count = pattern
		c.spawn_wave()
		var previous: int = awards.size()
		var last_score := 0
		var last_bonus := 0
		for i in range(c.enemies.size()):
			last_score = c.score
			last_bonus = d.mastery.bonus_score
			c.enemies[i].take_damage(999)
			if i<c.enemies.size()-1: check(awards.size()==previous,"Partial wave cannot award points")
		check(awards.size()==previous+1,"All members killed awards once for each fighter type")
		check(c.score-last_score==100*d.mastery.multiplier+800,"Last kill plus exactly 800 bonus credited")
		check(d.mastery.bonus_score-last_bonus==100*(d.mastery.multiplier-1)+800,"Result bonus includes formation points")
		for enemy in c.enemies: enemy.take_damage(999)
		await process_frame
		check(awards.size()==previous+1,"Duplicate damage and tree exit cannot award twice")
		check(c.formations.members.is_empty() and c.formations.groups.is_empty(),"Resolved wave releases all bookkeeping")
		c.enemies.clear()
	c.spawn_wave()
	var count_before := awards.size()
	c.enemies[0].retire()
	for i in range(1,c.enemies.size()): c.enemies[i].take_damage(999)
	await process_frame
	check(awards.size()==count_before,"A single escape invalidates the perfect wave")
	check(c.formations.groups.is_empty(),"Failed wave releases bookkeeping")
	c.enemies.clear()
	# Two interleaved waves must retain independent identities and outcomes.
	c.spawn_wave()
	var first_wave: Array = c.enemies.duplicate()
	c.spawn_wave()
	var second_wave: Array = c.enemies.filter(func(enemy): return not first_wave.has(enemy))
	count_before = awards.size()
	for enemy in first_wave: enemy.take_damage(999)
	check(awards.size()==count_before+1,"Interleaved formation can complete independently")
	for enemy in second_wave: enemy.retire()
	await process_frame
	check(awards.size()==count_before+1 and c.formations.groups.is_empty(),"Escaped second formation cannot affect completed first")
	c.enemies.clear()
	c.spawn_wave()
	c.withdraw_aircraft()
	await process_frame
	count_before += 1
	check(awards.size()==count_before and c.formations.groups.is_empty(),"Low-flight withdrawal gives no reward")
	c.spawn_special()
	for red in c.red_enemies:
		red.distance = 1.0
		red.take_damage(999)
	check(awards.size()==count_before+1 and int(awards.back()[1])==1000,"Red squadron gets one 1000-point award")
	check(c.pow_spawn_count==1,"Original five-red POW reward remains intact")
	await process_frame
	c.red_enemies.clear()
	var pool: Node3D = d.score_bursts
	var nodes_before := pool.get_child_count()
	for i in range(200): pool.show_award(Vector3(-100+i,0,-100+i),800,false)
	check(pool.get_child_count()==nodes_before and pool.slots.size()==3,"Score display has a fixed capacity under overload")
	pool.advance(2)
	check(pool.slots.all(func(slot): return not slot.visible),"All award slots expire")
	d.details.impact(Vector3.ZERO,true)
	d.details._physics_process(.04)
	check(d.details.spark_lives.count(0.0)<d.details.SPARK_CAPACITY,"Impact emits visible sparks")
	d.details.enabled = false
	d.details._physics_process(2)
	check(d.details.spark_lives.count(0.0)==d.details.SPARK_CAPACITY,"Hidden particles expire when quality is reduced")
	d._clear_actors()
	stop_audio(app)
	await create_timer(.2).timeout
	app._show_main()
	app.music.stop()
	app.queue_free()
	await process_frame
	await process_frame
	print("PRESENTATION FINISH: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
