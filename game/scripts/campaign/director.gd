extends Node
signal finished(report: Dictionary)
const NAVAL := preload("res://scripts/campaign/enemy_naval.gd")
const BOSS := preload("res://scripts/campaign/boss.gd")
const LOADOUT := preload("res://scripts/campaign/loadout.gd")
const SCORING := preload("res://scripts/campaign/scoring_rules.gd")
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
var balance: Dictionary
var mastery = preload("res://scripts/campaign/mastery.gd").new()
var details: Node3D
var act_index := -1
var act_title := ""
var radio := ""
var radio_time := 0.0
var ability_time := 0.0
var base_speed := 12.0
var base_interval := .105
var base_damage := 1.0
var equipment: Dictionary
var base_laser_interval := 1.0
var practice := false
var last_boss_phase := -1
var convoy: Area3D
var assault: Node3D
var mission_completed := true
var extraction_started_at := -1.0
var extraction_end_at := 0.0
var extraction_next_wave := 0.0
var extraction_wave_count := 0

func _ready() -> void:
	combat = cockpit.combat
	player = cockpit.player
	weapons = cockpit.flight.get_node("Weapons")
	cockpit.campaign = self
	combat.automatic_waves = false
	combat.aircraft_enabled = true
	combat.dense_waves = true
	combat.campaign_driver = self
	combat.score = int(profile.data.run_score)
	combat.next_power_kind = ["spread","laser","life"][int(mission.sector)%3]
	combat.bombers_enabled = false
	combat.special_enabled = false
	combat.remaining_lives = int(profile.data.run_lives)
	balance = preload("res://scripts/campaign/balance.gd").settings(int(mission.id),int(profile.data.difficulty))
	combat.projectile_speed_scale = [0.88,1.0,1.15][profile.data.difficulty]*float(mission.pressure)*float(balance.speed)
	combat.enemy_interval_scale = float(balance.interval)
	combat.fighter_salvos = float(balance.salvos)
	var aircraft: int = profile.data.aircraft
	player.configure_aircraft(aircraft)
	weapons.configure_aircraft(aircraft)
	equipment = LOADOUT.stats(profile.data,aircraft)
	player.speed = float(equipment.speed)
	player.max_health = int(equipment.max_health)
	player.hit_invulnerability_multiplier = float(equipment.hit_invulnerability_multiplier)
	player.health = player.max_health
	player.focus_enabled = true
	player.damaged.connect(_on_damage)
	player.destroyed.connect(_on_death)
	player.respawned.connect(_on_respawn)
	bombs = int(equipment.bombs)
	charge = float(equipment.initial_charge)
	previous_kills = combat.kills
	weapons.shot_interval = float(equipment.shot_interval)
	weapons.projectile_damage = float(equipment.projectile_damage)
	weapons.laser_interval_multiplier = float(equipment.laser_interval_multiplier)
	weapons.spread_multiplier = float(equipment.spread_multiplier)
	weapons.laser_width_multiplier = float(equipment.laser_width_multiplier)
	start_score = combat.score
	cockpit.high_score = profile.data.high_score
	if not first_takeoff: cockpit.flight.get_node("Departure").finish_immediately()
	var sea = cockpit.flight.get_node("Seascape")
	var departure = cockpit.flight.get_node("Departure")
	departure._cruise_speed = float(mission.scroll)
	sea.scroll_speed = .8 if departure.active else float(mission.scroll)
	sea.scenery_seed = mission.seed
	sea.configure_sector(mission)
	cockpit.flight.get_node("Clouds").configure_sector(mission)
	cockpit.flight.get_node("KeyLight").shadow_enabled = true
	preload("res://scripts/campaign/materials.gd").flight_lighting(cockpit.flight,mission.biome)
	mastery.secondary_kind = mission.get("secondary","formation")
	mastery.secondary_target = int(mission.get("secondary_target",1))
	base_speed = player.speed
	base_interval = weapons.shot_interval
	base_damage = weapons.projectile_damage
	base_laser_interval = weapons.laser_interval_multiplier
	details = preload("res://scripts/campaign/combat_detail.gd").new()
	details.player = player
	cockpit.flight.add_child(details)
	if mission.get("ground_assault",false):
		assault = preload("res://scripts/campaign/ground_assault.gd").new()
		assault.director = self
		cockpit.flight.add_child(assault)
		assault.network_disrupted.connect(_on_network_disrupted)
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

func on_kill(base: int, kind: String) -> void:
	combat.score += mastery.kill(base)
	complete_objective(kind)

func complete_objective(kind: String) -> void:
	combat.score += mastery.objective(kind)

func _on_network_disrupted(network_id: String, seconds: float, global_scope: bool) -> void:
	var group: Dictionary = assault.layout.get("radar_groups",{}).get(network_id,{})
	var label: String = str(group.get("label","Réseau radar"))
	radio = "Contrôle : toute la DCA est brouillée pendant %.0f secondes." % seconds if global_scope else "Contrôle : %s brouillé %.0f secondes. Les autres défenses restent actives." % [label,seconds]
	radio_time = 4.0

func _update_acts() -> void:
	var acts: Array = mission.get("acts",[])
	while act_index+1<acts.size() and elapsed>=float(acts[act_index+1].time):
		act_index += 1
		act_title = acts[act_index].title
		radio = acts[act_index].radio
		radio_time = 5
		if act_index==1 and mastery.secondary_kind=="convoy" and not practice:
			convoy = preload("res://scripts/campaign/convoy.gd").new()
			convoy.position = Vector3(0,0,4)
			convoy.rescued.connect(func(): complete_objective("convoy"); radio="Convoi : route sécurisée. Merci pour la couverture."; radio_time=5)
			convoy.lost.connect(func(): combat._explode(convoy.position,1.6); radio="Contrôle : convoi perdu. Poursuivez la mission."; radio_time=5)
			combat.add_child(convoy)
			combat.navigate_naval(convoy)
			radio = "Convoi allié en approche. Interceptez les bombardiers !"
			combat.spawn_bomber()
		if feedback_time<=0:
			feedback = act_title
			feedback_time = 3

func _update_ability(delta: float) -> void:
	ability_time = maxf(0,ability_time-delta)
	player.speed = base_speed
	weapons.shot_interval = base_interval
	weapons.projectile_damage = base_damage
	weapons.laser_interval_multiplier = base_laser_interval
	if not player.alive or ending or not active: ability_time = 0
	if ability_time<=0: return
	player.speed *= float(equipment.ability_speed_multiplier)
	weapons.projectile_damage *= float(equipment.ability_damage_multiplier)
	var rate := float(equipment.ability_rate_multiplier)
	weapons.shot_interval /= rate
	weapons.laser_interval_multiplier /= rate
	if int(profile.data.aircraft)==2:
		player.invulnerable_time = maxf(player.invulnerable_time,.2)

func _update_charge(delta: float, ability_was_active: bool) -> void:
	# Observe every kill exactly once, including kills produced by the strike.
	# A frame that expires an ability remains blocked, so a long frame cannot
	# turn those kills into a delayed recharge or credit active-time seconds.
	var new_kills: int = maxi(0,combat.kills-previous_kills)
	previous_kills = combat.kills
	if not active or ability_was_active or ability_time>0 or ending or not player.alive or not player.controls_enabled: return
	charge = minf(100,charge+delta*float(equipment.charge_passive)+new_kills*float(equipment.charge_kill))

func _physics_process(delta: float) -> void:
	advance(delta)

func advance(delta: float) -> void:
	if not active or paused: return
	feedback_time = maxf(0,feedback_time-delta)
	radio_time = maxf(0,radio_time-delta)
	if player.alive and player.controls_enabled and not ending:
		mastery.advance(delta)
	var ability_was_active := ability_time>0
	_update_ability(delta)
	_update_charge(delta,ability_was_active)
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
	for ship in navals:
		if is_instance_valid(ship) and ship.alive: ship.advance(delta,combat)
	navals = navals.filter(func(ship): return is_instance_valid(ship) and ship.alive)
	if is_instance_valid(convoy) and convoy.alive: convoy.advance(delta,combat)
	if is_instance_valid(assault): assault.advance(delta)
	if is_instance_valid(boss) and boss.alive:
		boss.advance(delta,self)
		if not boss.dying and boss.age > 4:
			reinforcement_time -= delta
			if reinforcement_time <= 0:
				spawn_reinforcement()
				reinforcement_time = 8.5-float(mission.sector)*.3
	combat.campaign_contacts = navals.duplicate()
	if is_instance_valid(assault): combat.campaign_contacts.append_array(assault.contacts())
	if is_instance_valid(boss) and boss.alive: combat.campaign_contacts.append(boss)
	if combat.game_over:
		defeat_time += delta
		if defeat_time >= 2.4: _end(false)
		return
	if ending:
		ending_time += delta
		var departure = cockpit.flight.get_node("Departure")
		departure.advance_landing(delta)
		if departure.landed: _end(mission_completed)
		return
	if not player.controls_enabled: return
	elapsed += delta
	_update_acts()
	_update_extraction()
	while event_index < mission.events.size() and elapsed >= float(mission.events[event_index].time):
		_dispatch(mission.events[event_index])
		event_index += 1
	var combat_deadline := maxf(float(mission.duration),extraction_end_at)
	combat.next_wave = maxf(0,combat_deadline-elapsed)
	if Input.is_action_just_pressed("bomb"): use_bomb()
	if Input.is_action_just_pressed("strike"): use_strike()
	if (elapsed >= combat_deadline or practice) and (mission.boss == "" or boss_won):
		if is_instance_valid(assault) and (not assault.approach_clear() or extraction_started_at<0): return
		mission_completed = not is_instance_valid(assault) or assault.main_objective_met()
		ending = true
		_update_ability(0)
		feedback = "SECTEUR SÉCURISÉ  /  APPROCHE DU PORTE-AVIONS" if mission_completed else "OBJECTIF INCOMPLET  /  REPLI VERS LE PORTE-AVIONS"
		feedback_time = 6
		combat.clear_enemy_bullets()
		player.invulnerable_time = 6
		_clear_actors()
		weapons.cease_fire()
		cockpit.flight.get_node("Departure").begin_landing()

func _update_extraction() -> void:
	if not is_instance_valid(assault) or ending or not active or paused: return
	if not player.alive or not player.controls_enabled or combat.game_over: return
	if not combat.aircraft_enabled or not assault.extraction_ready():
		# Never collect overdue salvos while below the cloud deck.
		extraction_next_wave = maxf(extraction_next_wave,elapsed+.35)
		return
	if extraction_started_at<0:
		extraction_started_at = elapsed
		extraction_end_at = maxf(float(mission.duration),elapsed+12.0)
		extraction_next_wave = elapsed
		act_title = "INTERCEPTION AU RETOUR"
		radio = "Contrôle : chasseurs sur votre route de retour ! Dégagez l'approche du porte-avions."
		radio_time = 5.0
		feedback = "REMONTÉE  /  CONTACTS AÉRIENS"
		feedback_time = 3.0
	# Leave five seconds for the last formation to pass before automatic landing.
	if elapsed>=extraction_end_at-5.0 or elapsed<extraction_next_wave: return
	var before: int = combat.enemies.size()
	var kind := "zero" if extraction_wave_count%2==0 else "hayabusa"
	_dispatch({"kind":kind,"pattern":int(mission.sector)+extraction_wave_count,"role":"interceptor" if kind=="hayabusa" else "escort"})
	if combat.enemies.size()>before: extraction_wave_count += 1
	# One formation at most per update, including after a long pause or respawn.
	var interval := lerpf(4.8,3.4,float(mission.sector)/7.0)
	extraction_next_wave = elapsed+interval

func _dispatch(event: Dictionary) -> void:
	if mission.get("ground_assault",false) and not combat.aircraft_enabled: return
	match event.kind:
		"zero", "hayabusa":
			combat.wave_count = int(event.get("pattern",0))*2+(0 if event.kind == "zero" else 1)
			combat.spawn_wave()
			for enemy in combat.enemies:
				if enemy.age == 0:
					enemy.flight_speed *= clampf(float(mission.pressure),1.0,1.2)
					enemy.set_meta("role",event.get("role","escort"))
					if event.get("role","")=="interceptor": enemy.flight_speed *= 1.08
					if event.get("role","")=="gunner": enemy.flight_speed *= .88
		"red":
			combat.spawn_special()
			feedback = "ESCADRILLE ROUGE  •  5 AVIONS = POW"
			feedback_time = 3
		"bomber": combat.spawn_bomber()
		"naval": _spawn_naval(int(event.get("pattern",0)))
		"boss": _spawn_boss(event.variant)

func _spawn_naval(pattern: int) -> void:
	if mission.get("ground_assault",false): return
	if navals.size() >= 4: return
	for i in range(1 if pattern == 0 else 2):
		var ship := NAVAL.new()
		ship.variant = pattern
		ship.health = 10+int(mission.sector)*2
		ship.route_offset = (-1.0 if i == 0 else 1.0)*1.7
		ship.position = Vector3(0,0,combat.screen_top()-3-i*6)
		combat.navigate_naval(ship,ship.route_offset)
		ship.destroyed.connect(_on_naval_destroyed)
		combat.add_child(ship)
		navals.append(ship)

func _spawn_boss(kind: String) -> void:
	if mission.get("ground_assault",false): return
	if boss_spawned: return
	boss_spawned = true
	if practice: event_index = mission.events.size()
	boss = BOSS.new()
	boss.kind = kind
	boss.combat = combat
	boss.max_health = int([260,310,350,390,440,360,520,650][int(mission.sector)]*[1.0,1.25,1.5][profile.data.difficulty])
	boss.max_health = int(boss.max_health*float(mission.get("boss_health_scale",1.0)))
	boss.health = boss.max_health
	boss.position = Vector3(0,0,-17)
	boss.defeated.connect(_on_boss_defeated)
	boss.weak_points_neutralized.connect(func(): complete_objective("boss"))
	combat.add_child(boss)
	if boss.naval: combat.navigate_naval(boss)
	combat.clear_enemy_bullets()
	feedback = "ALERTE  /  " + BOSS.NAMES[kind].to_upper()
	feedback_time = 4.5

func spawn_reinforcement() -> void:
	if combat.enemies.size() > 20: return
	combat.wave_count = 0
	combat.spawn_wave()

func _on_boss_defeated() -> void:
	if boss_won: return
	boss_won = true
	combat.score += 5000+int(mission.sector)*1000
	# Killing the hull advances the chain, while only the component signal can
	# complete the distinct challenge to neutralize both weak points.
	on_kill(5000,"boss_destroyed")
	combat.kills += 1
	combat.clear_enemy_bullets()
	shake_time = 0.6

func _on_naval_destroyed(at: Vector3) -> void:
	naval_kills += 1
	combat.kills += 1
	combat.score += 300
	on_kill(300,"naval")
	combat._explode(at,1.2)

func _on_damage(_health: int) -> void:
	damage_taken += 1
	mastery.hit()
	shake_time = 0.28
	feedback = "IMPACT  /  BLINDAGE %d" % player.health
	feedback_time = 1.2

func _on_death(_at: Vector3) -> void:
	deaths += 1
	ability_time = 0
	_update_ability(0)
	charge = maxf(0,charge-20)
	feedback = ""
	feedback_time = 0

func _on_respawn() -> void:
	feedback = "RETOUR EN VOL  /  PROTECTION 4 SECONDES"
	feedback_time = 2.5

func use_bomb() -> bool:
	if not active or paused or ending or not player.alive or not player.controls_enabled or bombs <= 0: return false
	bombs -= 1
	attacks_used += 1
	_discharge(35,false)
	feedback = "BOMBE  /  ESPACE AÉRIEN DÉGAGÉ"
	feedback_time = 2.0
	return true

func use_strike() -> bool:
	if not active or paused or ending or not player.alive or not player.controls_enabled or ability_time>0 or charge < 100: return false
	charge = 0
	attacks_used += 1
	ability_time = float(equipment.ability_duration)
	_update_ability(0)
	_discharge(float(equipment.strike_damage),bool(equipment.strike_focused))
	feedback = "%s  /  %s %.1f S" % [LOADOUT.aircraft(int(profile.data.aircraft)).name,str(equipment.ability_label),ability_time]
	feedback_time = 2.0
	return true

func _discharge(damage: float, focused: bool) -> void:
	combat.clear_enemy_bullets()
	player.invulnerable_time = maxf(player.invulnerable_time,1.5)
	special_ring.global_position = player.global_position+Vector3(0,combat.presentation_altitude+0.5,0)
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
	if is_instance_valid(assault): assault.finish()
	if is_instance_valid(convoy): convoy.retire()
	for group in [combat.enemies,combat.bombers,combat.red_enemies,navals]:
		for actor in group:
			if is_instance_valid(actor) and actor.alive: actor.retire()
	combat.clear_enemy_bullets()

func _end(won: bool) -> void:
	if not active: return
	active = false
	_update_ability(0)
	weapons.cease_fire()
	previous_kills = combat.kills
	player.controls_enabled = false
	var objective_met: bool = combat.kills >= int(mission.quota)
	if mission.objective == "strike": objective_met = naval_kills >= int(mission.quota)
	if mission.objective == "ground": objective_met = is_instance_valid(assault) and assault.main_objective_met()
	if mission.objective == "boss": objective_met = boss_won
	# The landing decision is cached separately from the actual objective. Losing
	# the last life is always Game Over, even during an incomplete retreat.
	var game_over: bool = not won and combat.game_over
	var objective_failed: bool = not won and not game_over and not mission_completed
	var grade := SCORING.medal(won,deaths,damage_taken,objective_met)
	var bonus := maxi(0,player.health*100+combat.remaining_lives*250+bombs*150) if won else 0
	combat.score += bonus
	finished.emit({"game_over":game_over,"objective_met":objective_met,"ground_status":assault.objective_status() if is_instance_valid(assault) else {},"ground_kills":assault.kills if is_instance_valid(assault) else 0,"objective_failed":objective_failed,"rank":mastery.rank(won,deaths,damage_taken),"best_chain":mastery.best_chain,"secondary":mastery.secondary_complete,"chain_bonus":mastery.bonus_score,"accuracy":float(weapons.hits_landed)/maxi(1,weapons.shots_fired),"won":won,"mission":mission.id,"score":combat.score,"mission_score":combat.score-start_score,"lives":combat.remaining_lives,"power":weapons.power_type,"kills":combat.kills,"naval_kills":naval_kills,"deaths":deaths,"damage":damage_taken,"grade":grade,"bonus":bonus,"seconds":elapsed,"spread":weapons.spread_enabled})
