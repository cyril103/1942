extends Node
signal finished(report: Dictionary)
const NAVAL := preload("res://scripts/campaign/enemy_naval.gd")
const BOSS := preload("res://scripts/campaign/boss.gd")
var cockpit: Control
var mission: Dictionary
var profile: RefCounted
var combat: Node3D
var player: Node3D
var weapons: Node3D
var elapsed := 0.0
var event_index := 0
var active := true
var ending := false
var ending_time := 0.0
var navals: Array[Area3D] = []
var boss: Area3D
var boss_won := false
var boss_spawned := false
var bombs := 2
var charge := 0.0
var attacks_used := 0
var deaths := 0
var damage_taken := 0
var naval_kills := 0
var previous_kills := 0
var feedback := ""
var feedback_time := 0.0
var shake_time := 0.0
var special_ring: MeshInstance3D
var ring_time := 0.0
var paused := false
var start_score := 0
var first_takeoff := true
var reinforcement_time := 7.5
var defeat_time := 0.0

func _ready() -> void:
	combat = cockpit.combat
	player = cockpit.player
	weapons = cockpit.flight.get_node("Weapons")
	cockpit.campaign = self
	combat.automatic_waves = false
	combat.dense_waves = true
	combat.campaign_driver = self
	combat.score = int(profile.data.run_score)
	combat.next_power_kind = ["spread","laser","life"][int(mission.sector)%3]
	combat.bombers_enabled = false
	combat.special_enabled = false
	combat.remaining_lives = int(profile.data.run_lives)
	combat.projectile_speed_scale = [0.88,1.0,1.15][profile.data.difficulty]*float(mission.pressure)
	var aircraft: int = profile.data.aircraft
	player.speed = [12.0,14.0,10.4][aircraft]
	player.max_health = [2,2,3][aircraft]+int(profile.data.upgrades[1])
	player.health = player.max_health
	player.focus_enabled = true
	player.damaged.connect(_on_damage)
	player.destroyed.connect(_on_death)
	player.respawned.connect(_on_respawn)
	bombs = 3 if aircraft == 2 else 2
	weapons.shot_interval = [0.105,0.09,0.12][aircraft]*(1.0-0.06*int(profile.data.upgrades[0]))
	weapons.projectile_damage = 2 if int(profile.data.upgrades[0]) == 3 else 1
	start_score = combat.score
	cockpit.high_score = profile.data.high_score
	if not first_takeoff: cockpit.flight.get_node("Departure").finish_immediately()
	var sea = cockpit.flight.get_node("Seascape")
	var departure = cockpit.flight.get_node("Departure")
	departure._cruise_speed = float(mission.scroll)
	sea.scroll_speed = .8 if departure.active else float(mission.scroll)
	sea.scenery_seed = mission.seed
	sea.configure_sector(mission)
	cockpit.flight.get_node("KeyLight").shadow_enabled = true
	_build_ring()
	feedback = "MISSION %02d  /  %s" % [mission.id,mission.title.to_upper()]
	feedback_time = 5

func _build_ring() -> void:
	special_ring = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(3,3)
	special_ring.mesh = plane
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/pow_halo.gdshader")
	material.set_shader_parameter("burst",1.0)
	special_ring.material_override = material
	cockpit.flight.add_child(special_ring)
	special_ring.hide()

func _physics_process(delta: float) -> void:
	advance(delta)

func advance(delta: float) -> void:
	if not active or paused: return
	feedback_time = maxf(0,feedback_time-delta)
	if ring_time > 0:
		ring_time = maxf(0,ring_time-delta)
		special_ring.scale = Vector3.ONE*lerpf(1,13,1-ring_time/0.7)
		special_ring.material_override.set_shader_parameter("strength",ring_time/0.7*(1.0 if profile.data.settings.flashes else 0.25))
		special_ring.visible = ring_time > 0
	if shake_time > 0:
		shake_time = maxf(0,shake_time-delta)
		var strength := shake_time*9 if profile.data.settings.shake else 0.0
		cockpit.screen.position = cockpit.play_rect.position+Vector2(sin(elapsed*79),cos(elapsed*91))*strength
	else: cockpit.screen.position = cockpit.play_rect.position
	if combat.kills > previous_kills:
		charge = minf(100,charge+(combat.kills-previous_kills)*(5.0+float(profile.data.upgrades[2])))
		previous_kills = combat.kills
	for ship in navals:
		if is_instance_valid(ship) and ship.alive: ship.advance(delta,combat)
	navals = navals.filter(func(ship): return is_instance_valid(ship) and ship.alive)
	if is_instance_valid(boss) and boss.alive:
		boss.advance(delta,self)
		if not boss.dying and boss.age > 4:
			reinforcement_time -= delta
			if reinforcement_time <= 0:
				spawn_reinforcement()
				reinforcement_time = 8.5-float(mission.sector)*.3
	combat.campaign_contacts = navals.duplicate()
	if is_instance_valid(boss) and boss.alive: combat.campaign_contacts.append(boss)
	if combat.game_over:
		defeat_time += delta
		if defeat_time >= 2.4: _end(false)
		return
	if ending:
		ending_time += delta
		var departure = cockpit.flight.get_node("Departure")
		departure.advance_landing(delta)
		if departure.landed: _end(true)
		return
	if not player.controls_enabled: return
	elapsed += delta
	while event_index < mission.events.size() and elapsed >= float(mission.events[event_index].time):
		_dispatch(mission.events[event_index])
		event_index += 1
	combat.next_wave = maxf(0,float(mission.duration)-elapsed)
	if Input.is_action_just_pressed("bomb"): use_bomb()
	if Input.is_action_just_pressed("strike"): use_strike()
	if elapsed >= float(mission.duration) and (mission.boss == "" or boss_won):
		ending = true
		feedback = "SECTEUR SÉCURISÉ  /  APPROCHE DU PORTE-AVIONS"
		feedback_time = 6
		combat.clear_enemy_bullets()
		player.invulnerable_time = 6
		_clear_actors()
		weapons.cease_fire()
		cockpit.flight.get_node("Departure").begin_landing()

func _dispatch(event: Dictionary) -> void:
	match event.kind:
		"zero", "hayabusa":
			combat.wave_count = int(event.get("pattern",0))*2+(0 if event.kind == "zero" else 1)
			combat.spawn_wave()
			for enemy in combat.enemies:
				if enemy.age == 0: enemy.flight_speed *= clampf(float(mission.pressure),1.0,1.2)
		"red":
			combat.spawn_special()
			feedback = "ESCADRILLE ROUGE  •  5 AVIONS = POW"
			feedback_time = 3
		"bomber": combat.spawn_bomber()
		"naval": _spawn_naval(int(event.get("pattern",0)))
		"boss": _spawn_boss(event.variant)

func _spawn_naval(pattern: int) -> void:
	if navals.size() >= 4: return
	for i in range(1 if pattern == 0 else 2):
		var ship := NAVAL.new()
		ship.variant = pattern
		ship.health = 10+int(mission.sector)*2
		var half_width := absf(combat.camera.project_position(Vector2.ZERO,combat.camera.position.y).x)
		ship.position = Vector3((-1.0 if i == 0 else 1.0)*minf(half_width*.38,9.0),0,combat.screen_top()-3-i*4)
		ship.destroyed.connect(_on_naval_destroyed)
		combat.add_child(ship)
		navals.append(ship)

func _spawn_boss(kind: String) -> void:
	if boss_spawned: return
	boss_spawned = true
	boss = BOSS.new()
	boss.kind = kind
	boss.combat = combat
	boss.max_health = int([260,310,350,390,440,360,520,650][int(mission.sector)]*[1.0,1.25,1.5][profile.data.difficulty])
	boss.health = boss.max_health
	boss.position = Vector3(0,0,-17)
	boss.defeated.connect(_on_boss_defeated)
	combat.add_child(boss)
	combat.clear_enemy_bullets()
	feedback = "ALERTE  /  " + BOSS.NAMES[kind].to_upper()
	feedback_time = 4.5

func spawn_reinforcement() -> void:
	if combat.enemies.size() > 20: return
	combat.wave_count = 0
	combat.spawn_wave()

func _on_boss_defeated() -> void:
	boss_won = true
	combat.score += 5000+int(mission.sector)*1000
	combat.kills += 1
	combat.clear_enemy_bullets()
	shake_time = 0.6

func _on_naval_destroyed(at: Vector3) -> void:
	naval_kills += 1
	combat.kills += 1
	combat.score += 300
	combat._explode(at,1.2)

func _on_damage(_health: int) -> void:
	damage_taken += 1
	shake_time = 0.28
	feedback = "IMPACT  /  BLINDAGE %d" % player.health
	feedback_time = 1.2

func _on_death(_at: Vector3) -> void:
	deaths += 1
	charge = maxf(0,charge-20)
	feedback = ""
	feedback_time = 0

func _on_respawn() -> void:
	feedback = "RETOUR EN VOL  /  PROTECTION 4 SECONDES"
	feedback_time = 2.5

func use_bomb() -> bool:
	if not active or ending or not player.controls_enabled or bombs <= 0: return false
	bombs -= 1
	attacks_used += 1
	_discharge(35,false)
	feedback = "BOMBE  /  ESPACE AÉRIEN DÉGAGÉ"
	feedback_time = 2.0
	return true

func use_strike() -> bool:
	if not active or ending or not player.controls_enabled or charge < 100: return false
	charge = 0
	attacks_used += 1
	_discharge(65,true)
	feedback = "FRAPPE SPÉCIALE"
	feedback_time = 2.0
	return true

func _discharge(damage: int, focused: bool) -> void:
	combat.clear_enemy_bullets()
	player.invulnerable_time = maxf(player.invulnerable_time,1.5)
	special_ring.global_position = player.global_position+Vector3(0,0.5,0)
	ring_time = 0.7
	special_ring.show()
	shake_time = 0.35
	combat.explosion_audio.play()
	var targets: Array[Area3D] = combat.get_radar_contacts()
	for target in targets:
		if not is_instance_valid(target) or not target.alive: continue
		var on_screen: bool = cockpit.viewport.get_visible_rect().has_point(combat.camera.unproject_position(target.global_position))
		if on_screen and (not focused or absf(target.global_position.x-player.global_position.x)<4.0): target.take_damage(damage)

func _clear_actors() -> void:
	for group in [combat.enemies,combat.bombers,combat.red_enemies,navals]:
		for actor in group:
			if is_instance_valid(actor) and actor.alive: actor.retire()
	combat.clear_enemy_bullets()

func _end(won: bool) -> void:
	if not active: return
	active = false
	player.controls_enabled = false
	var grade := 0
	if won:
		grade = 1
		if deaths == 0: grade = 2
		var objective_met: bool = combat.kills >= int(mission.quota)
		if mission.objective == "strike": objective_met = naval_kills >= int(mission.quota)
		if mission.objective == "boss": objective_met = boss_won
		if deaths == 0 and damage_taken <= 2 and objective_met: grade = 3
	var bonus := maxi(0,player.health*100+combat.remaining_lives*250+bombs*150) if won else 0
	combat.score += bonus
	finished.emit({"won":won,"mission":mission.id,"score":combat.score,"mission_score":combat.score-start_score,"lives":combat.remaining_lives,"power":weapons.power_type,"kills":combat.kills,"naval_kills":naval_kills,"deaths":deaths,"damage":damage_taken,"grade":grade,"bonus":bonus,"seconds":elapsed,"spread":weapons.spread_enabled})
