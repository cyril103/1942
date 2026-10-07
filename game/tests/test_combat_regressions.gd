extends SceneTree
## Real production collisions: contact sweeps, bounded pools, and boss objectives.
const DT := 1.0/60.0
const BOSS := preload("res://scripts/campaign/boss.gd")
const NAVAL := preload("res://scripts/campaign/enemy_naval.gd")
const GROUND := preload("res://scripts/campaign/ground_target.gd")
const MASTERY := preload("res://scripts/campaign/mastery.gd")
var checks := 0
var failures: Array[String] = []
var app: Node
var director: Node
var report: Dictionary = {}

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func _initialize() -> void: _run.call_deferred()

func _freeze(node: Node) -> void:
	node.set_physics_process(false)
	node.set_process(false)
	for child in node.get_children(): _freeze(child)

func _stop_audio(node: Node) -> void:
	if node is AudioStreamPlayer or node is AudioStreamPlayer3D: node.stop()
	for child in node.get_children(): _stop_audio(child)

func _sync_physics() -> void:
	await physics_frame
	await physics_frame

func _make_target(kind: String) -> Area3D:
	var target: Area3D
	if kind.begins_with("boss:"):
		target = BOSS.new()
		target.kind = kind.trim_prefix("boss:")
		target.combat = director.combat
		target.health = 1000
		target.max_health = 1000
	else:
		target = NAVAL.new() if kind=="naval" else GROUND.new()
		if kind=="ground": target.variant = "battery"
		target.health = 1000
	director.combat.add_child(target)
	target.position = Vector3.ZERO
	target.collision_layer = 2
	return target

func _contact_target(kind: String) -> void:
	var target := _make_target(kind)
	var weapons: Node3D = director.weapons
	var collider: CollisionShape3D = target.get_child(0)
	var half_depth: float = collider.shape.size.z*.5
	for place in ["outside","boundary","inside"]:
		var origin_z: float = half_depth+2.0 if place=="outside" else (half_depth if place=="boundary" else 0.0)
		weapons.set_power("none")
		director.player.position = Vector3(0,0,origin_z-weapons.muzzle_positions[0].z)
		await _sync_physics()
		var hp: int = target.health
		var hits: int = weapons.hits_landed
		weapons._fire_salvo()
		weapons._physics_process(.15)
		check(target.health<hp and hp-target.health<=4,"%s canons hit once per round from %s" % [kind,place])
		check(weapons.hits_landed-hits==2 and weapons.active_count==0,"%s two contact rounds are consumed once from %s" % [kind,place])
		weapons._physics_process(DT)
		check(weapons.hits_landed-hits==2,"%s released rounds cannot damage again from %s" % [kind,place])
		weapons.set_power("laser")
		director.player.position = Vector3(0,0,origin_z-weapons.laser_nose)
		await _sync_physics()
		hp = target.health
		hits = weapons.hits_landed
		Input.action_press("fire")
		weapons._update_laser(.001)
		check(target.health<hp and hp-target.health<=6 and weapons.hits_landed-hits==1,"%s nine laser rays yield one damage tick from %s" % [kind,place])
		check(weapons.laser_contact.visible and is_finite(weapons.laser.scale.z) and weapons.laser.scale.z>0,"%s finite contact presentation from %s" % [kind,place])
		check(weapons.laser_contact.global_position.z<=origin_z+.001,"%s laser contact never appears behind its origin from %s" % [kind,place])
		if place=="inside":
			check(not weapons.laser.visible and is_equal_approx(weapons.laser_contact.global_position.z,origin_z),"%s interior impact uses muzzle flare without inverted beam" % kind)
		hp = target.health
		weapons._update_laser(.001)
		check(target.health==hp and weapons.hits_landed-hits==1,"%s laser respects its cadence from %s" % [kind,place])
		Input.action_release("fire")
	weapons.set_power("none")
	target.queue_free()
	await process_frame
	await _sync_physics()

func _overlap_and_shield() -> void:
	var first := _make_target("naval")
	var second := _make_target("naval")
	var weapons: Node3D = director.weapons
	director.player.position = Vector3(0,0,-weapons.laser_nose)
	weapons.set_power("laser")
	await _sync_physics()
	var combined: int = first.health+second.health
	weapons._update_laser(0)
	Input.action_press("fire")
	weapons._update_laser(.001)
	check(combined-first.health-second.health==3,"Overlapping production ships receive exactly one laser damage tick in total")
	Input.action_release("fire")
	weapons.set_power("none")
	first.queue_free()
	second.queue_free()
	await process_frame
	var boss := _make_target("boss:bomber")
	boss.transition_time = 1.2
	await _sync_physics()
	var hp: int = boss.health
	weapons._fire_salvo()
	weapons._physics_process(.15)
	check(boss.health==hp and weapons.active_count==0,"Invulnerable boss consumes contact rounds without losing health")
	weapons.set_power("laser")
	Input.action_press("fire")
	weapons._update_laser(.001)
	check(boss.health==hp,"Interior laser preserves boss phase invulnerability")
	Input.action_release("fire")
	weapons.set_power("none")
	boss.queue_free()
	await process_frame
	await _sync_physics()
	director.player.position = Vector3(20,0,0)
	weapons._fire_salvo()
	weapons._physics_process(weapons.MAX_LIFETIME+.1)
	check(weapons.active_count==0 and weapons.lifetimes.count(0.0)==weapons.CAPACITY,"Missed rounds expire and release every pool slot")

func _reset_objective() -> void:
	director.mastery = MASTERY.new()
	director.mastery.secondary_kind = "boss"
	director.mastery.secondary_target = 1
	director.mastery.best_chain = 16
	director.combat.score = 0
	director.combat.kills = 0
	director.boss_won = false
	director.boss_spawned = false
	director.active = true
	director.player.controls_enabled = true
	report = {}

func _body_and_components(kind: String, components: int) -> void:
	_reset_objective()
	director._spawn_boss(kind)
	var boss: Area3D = director.boss
	boss.position = Vector3.ZERO
	boss.age = 5
	boss.collision_layer = 2
	for i in range(components):
		boss.take_hit_at(boss.component_health[i],boss.to_global(boss.component_position(i)))
		check(director.mastery.secondary_complete==(i==1),"%s objective follows actual component %d destruction" % [kind,i+1])
	check(director.combat.score==(2500 if components==2 else 0),"%s %d components reward exactly one bonus or none" % [kind,components])
	if components==2:
		boss.take_hit_at(1,boss.to_global(boss.component_position(1)))
		check(director.combat.score==2500,"%s re-hitting an already destroyed component grants no extra bonus" % kind)
	# The production area-damage path deliberately hits only the body. A bomb
	# must never manufacture neutralized components, even on a lethal discharge.
	director.combat.campaign_contacts.clear()
	director.combat.campaign_contacts.append(boss)
	await _sync_physics()
	if components<2:
		director._discharge(boss.health,false)
	else:
		boss.take_damage(boss.health)
	check(boss.dying,"%s body dies with %d components neutralized" % [kind,components])
	boss.advance(2.7,director)
	var expected: int = 5000+int(director.mission.sector)*1000+(2500 if components==2 else 0)
	check(director.boss_won and director.combat.score==expected,"%s body victory and component bonus remain separate" % kind)
	check(director.mastery.secondary_complete==(components==2),"%s hull death preserves the true component objective" % kind)
	director._on_boss_defeated()
	check(director.combat.score==expected and director.combat.kills==1,"%s repeated death callback cannot award a second victory or bonus" % kind)
	director._end(true)
	check(report.get("secondary",false)==(components==2) and report.get("rank","")==("S" if components==2 else "B"),"%s result rank and secondary reflect real component destruction" % kind)
	await process_frame

func _weapon_components(kind: String, power: String) -> void:
	_reset_objective()
	director._spawn_boss(kind)
	var boss: Area3D = director.boss
	boss.position = Vector3.ZERO
	boss.age = 5
	boss.collision_layer = 2
	var weapons: Node3D = director.weapons
	weapons.set_power(power)
	weapons._update_laser(0)
	for side in range(2):
		# Aim authentic player weapons at one component lane. Stay behind the
		# production box so the regression also keeps normal exterior hits valid.
		var at: Vector3 = boss.component_position(side)
		director.player.position = Vector3(at.x,0,4.7)
		await _sync_physics()
		var rounds := 0
		while boss.component_health[side]>0 and not boss.dying and rounds<40:
			if power=="laser":
				Input.action_press("fire")
				weapons._update_laser(.1)
				Input.action_release("fire")
			else:
				weapons._fire_salvo()
				for frame in range(20): weapons._physics_process(DT)
			rounds += 1
		check(boss.component_health[side]==0,"%s real %s weapon destroys component %d" % [kind,power,side+1])
	check(director.mastery.secondary_complete and director.combat.score==2500,"%s real %s earns component bonus once" % [kind,power])
	weapons.set_power("none")
	boss.queue_free()
	await process_frame
	director.boss = null

func _lethal_component(kind: String) -> void:
	_reset_objective()
	director._spawn_boss(kind)
	var boss: Area3D = director.boss
	boss.age = 5
	boss.collision_layer = 2
	boss.take_hit_at(boss.component_health[0],boss.to_global(boss.component_position(0)))
	var final_damage: int = boss.component_health[1]
	boss.health = final_damage*2
	boss.take_hit_at(final_damage,boss.to_global(boss.component_position(1)))
	check(boss.dying and director.mastery.secondary_complete and director.combat.score==2500,"%s a single lethal component hit still earns the objective exactly once" % kind)
	boss.advance(2.7,director)
	check(director.combat.score==7500+int(director.mission.sector)*1000,"%s lethal component and hull callbacks cannot duplicate the reward" % kind)
	await process_frame

func _run() -> void:
	root.size = Vector2i(1920,1080)
	app = load("res://scenes/campaign.tscn").instantiate()
	app.testing = true
	app.profile.path = "user://combat-regressions-isolated.json"
	root.add_child(app)
	current_scene = app
	await process_frame
	app.profile.reset()
	app.profile.data.unlocked = 32
	app._launch(4)
	director = app.director
	app.cockpit.flight.get_node("Departure").finish_immediately()
	_freeze(app.cockpit.flight)
	_freeze(director)
	director.player.get_node("Hurtbox").collision_layer = 0
	for connection in director.finished.get_connections(): director.finished.disconnect(connection.callable)
	director.finished.connect(func(value): report=value)
	for kind in ["boss:bomber","boss:destroyer","boss:ace","naval","ground"]:
		await _contact_target(kind)
	await _overlap_and_shield()
	for kind in BOSS.MODELS:
		for components in range(3): await _body_and_components(kind,components)
		await _lethal_component(kind)
	for kind in ["bomber","destroyer","ace"]:
		for power in ["none","laser"]: await _weapon_components(kind,power)
	Input.action_release("fire")
	app.set_process(false)
	_stop_audio(app)
	await create_timer(.25).timeout
	app.queue_free()
	current_scene = null
	await process_frame
	await process_frame
	await create_timer(.10).timeout
	print("COMBAT REGRESSIONS: ",checks," checks; failures: ",failures)
	quit(0 if failures.is_empty() else 1)
