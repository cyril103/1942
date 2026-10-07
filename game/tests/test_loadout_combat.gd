extends SceneTree
## Actual production weapon sweeps and enemy colliders, not a duplicate DPS table.
## TTK fixtures are stationary targets: these measurements do not claim human viability.
const DT := 1.0/240.0
const LOADOUT := preload("res://scripts/campaign/loadout.gd")
const ZERO := preload("res://scripts/enemy_zero.gd")
const HAYABUSA := preload("res://scripts/enemy_hayabusa.gd")
const RED := preload("res://scripts/enemy_red.gd")
const BOMBER := preload("res://scripts/enemy_bomber.gd")
const NAVAL := preload("res://scripts/campaign/enemy_naval.gd")
const GROUND := preload("res://scripts/campaign/ground_target.gd")
const BOSS := preload("res://scripts/campaign/boss.gd")
const CONVOY := preload("res://scripts/campaign/convoy.gd")
var checks := 0
var failures: Array[String] = []
var app: Node
var director: Node
var timings: Array[Dictionary] = []
var pools: Array[Dictionary] = []
var cadence_samples: Array[Dictionary] = []

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
func _sync() -> void:
	await physics_frame
	await physics_frame

func _launch(aircraft: int, rank: int, modules: Array = []) -> void:
	app._dispose_run()
	await process_frame
	app.profile.data.aircraft = aircraft
	app.profile.data.upgrades = [rank,0,3]
	app.profile.data.owned_modules = modules.duplicate()
	app.profile.data.equipped_modules = modules.duplicate()
	app._launch(1)
	director = app.director
	app.cockpit.flight.get_node("Departure").finish_immediately()
	_freeze(app.cockpit.flight)
	_freeze(director)
	director.player.get_node("Hurtbox").collision_layer = 0
	director.player.position = Vector3(0,0,4)
	await _sync()

func _target(kind: String) -> Area3D:
	var target: Area3D
	match kind:
		"zero": target = ZERO.new(); target.health = 3
		"hayabusa": target = HAYABUSA.new(); target.health = 3
		"red":
			target = RED.new()
			target.health = 3
			target.route = Curve3D.new()
			target.route.add_point(Vector3.ZERO)
			target.route.add_point(Vector3(0,0,10))
		"bomber": target = BOMBER.new()
		"naval": target = NAVAL.new()
		"dca": target = GROUND.new(); target.variant = "battery"
		"boss": target = BOSS.new(); target.combat = director.combat
		"convoy": target = CONVOY.new()
	director.combat.add_child(target)
	target.position = Vector3.ZERO
	target.rotation = Vector3.ZERO
	target.collision_layer = 2
	if kind=="boss":
		# Hull measurement after both weak points have been neutralized. Components
		# are separately exercised below with their original HP and aimed weapons.
		target.component_health[0] = 0.0
		target.component_health[1] = 0.0
	return target

func _destruction_matrix() -> void:
	for aircraft in range(3):
		for rank in range(4):
			await _launch(aircraft,rank)
			var weapons: Node3D = director.weapons
			for kind in ["zero","hayabusa","red","bomber","naval","dca","boss"]:
				for power in ["none","laser"]:
					var target := _target(kind)
					await _sync()
					var initial_hp: float = target.health
					weapons.set_power(power)
					weapons._cooldown = 0
					weapons.laser_clock = 0
					var hits_before: int = weapons.hits_landed
					Input.action_press("fire")
					# First genuine collision demonstrates fractional damage survives all
					# target handlers. The opening P-38 shots have time to fan out.
					var elapsed := 0.0
					while is_instance_valid(target) and target.health==initial_hp and elapsed<.4:
						weapons._physics_process(DT)
						elapsed += DT
					var expected_damage: float = LOADOUT.DAMAGE_RANKS[rank]*(LOADOUT.BASE_LASER_DAMAGE if power=="laser" else 2.0)
					check(is_instance_valid(target) and is_equal_approx(target.health,maxf(0.0,initial_hp-expected_damage)),"%d/rank%d/%s/%s actual opening damage retains fractions" % [aircraft,rank,kind,power])
					while is_instance_valid(target) and target.health>0 and elapsed<30:
						weapons._physics_process(DT)
						elapsed += DT
					Input.action_release("fire")
					check(is_instance_valid(target) and target.health==0,"%d/rank%d/%s/%s actual weapon destroys target" % [aircraft,rank,kind,power])
					var hit_count: int = weapons.hits_landed-hits_before
					var per_hit: float = LOADOUT.DAMAGE_RANKS[rank]*(3.0 if power=="laser" else 1.0)
					check(hit_count==ceili(initial_hp/per_hit),"%d/rank%d/%s/%s destruction requires authentic damage threshold" % [aircraft,rank,kind,power])
					timings.append({"aircraft":aircraft,"rank":rank,"target":kind,"power":power,"target_hp":initial_hp,"hits":hit_count,"seconds":snappedf(elapsed,.0001)})
					weapons.cease_fire()
					if is_instance_valid(target): target.queue_free()
					await process_frame
					await _sync()
			# Cadence with no target measures the physics scheduler, including fractional
			# frame carry. Instantaneous bursts after a stall are not used as DPS proof.
			for power in ["none","laser"]:
				weapons.set_power(power)
				weapons._cooldown = 0
				weapons.laser_clock = 0
				var before: int = weapons.shots_fired
				Input.action_press("fire")
				for frame in range(480): weapons._physics_process(DT)
				Input.action_release("fire")
				var produced: int = weapons.shots_fired-before
				var interval: float = weapons.shot_interval if power=="none" else LOADOUT.BASE_LASER_INTERVAL*weapons.laser_interval_multiplier
				var expected: float = 2.0/interval*(2.0 if power=="none" else 1.0)
				check(absf(produced-expected)<=2.0,"%d/rank%d/%s actual two-second cadence" % [aircraft,rank,power])
				weapons.cease_fire()

func _components() -> void:
	await _launch(0,1)
	for kind in ["bomber","destroyer","ace"]:
		for rank in range(4):
			for power in ["none","laser"]:
				var boss: Area3D = BOSS.new()
				boss.kind = kind
				boss.combat = director.combat
				director.combat.add_child(boss)
				boss.collision_layer = 2
				var weapon: Node3D = director.weapons
				weapon.projectile_damage = LOADOUT.DAMAGE_RANKS[rank]
				weapon.set_power(power)
				weapon.laser_clock = 0
				var at: Vector3 = boss.component_position(0)
				director.player.position = Vector3(at.x,0,4.7)
				await _sync()
				var initial: float = boss.component_health[0]
				var body_hp: float = boss.health
				if power=="laser":
					Input.action_press("fire")
					weapon._update_laser(.001)
					Input.action_release("fire")
				else:
					weapon._fire_salvo()
					for frame in range(72): weapon._physics_process(DT)
				var damage: float = LOADOUT.DAMAGE_RANKS[rank]*(3.0 if power=="laser" else 2.0)
				check(is_equal_approx(boss.component_health[0],initial-damage),"%s/rank%d/%s weakpoint retains fractional damage" % [kind,rank,power])
				check(is_equal_approx(boss.health,body_hp-damage*2),"%s/rank%d/%s weakpoint multiplier applies to real hull damage" % [kind,rank,power])
				weapon.cease_fire()
				boss.queue_free()
				await process_frame
				await _sync()
	var convoy := _target("convoy")
	convoy.take_damage(1.25)
	check(is_equal_approx(convoy.health,4.75),"Friendly naval override retains fractional damage")
	convoy.take_damage(.5)
	check(is_equal_approx(convoy.health,4.75),"Friendly naval invulnerability still blocks repeated impacts")
	convoy.queue_free()
	await process_frame

func _modules_and_abilities() -> void:
	for aircraft in range(3):
		await _launch(aircraft,2,["precision","endurance"])
		var d: Node = director
		d.charge = 100
		check(d.use_strike(),"Aircraft %d ability can start" % aircraft)
		check(is_equal_approx(d.ability_time,[6.25,5.0,4.375][aircraft]),"Endurance changes real ability duration %d" % aircraft)
		var damage: float = d.weapons.projectile_damage
		check(is_equal_approx(damage,1.55*[1.0,1.35,1.2][aircraft]),"Ability proportional damage applies equally to POWs %d" % aircraft)
		check(is_equal_approx(d.weapons.shot_interval,d.base_interval/[1.5,1.0,1.0][aircraft]),"Ability cadence uses shared multiplicative rate %d" % aircraft)
		check(is_equal_approx(d.weapons.laser_interval_multiplier,d.base_laser_interval/[1.5,1.0,1.0][aircraft]),"Laser cadence follows aircraft ability %d" % aircraft)
		d.charge = 100
		check(not d.use_strike(),"Active ability cannot be restarted %d" % aircraft)
		d.charge = 0
		d.combat.kills += 13
		d._update_charge(2,true)
		check(d.charge==0 and d.previous_kills==d.combat.kills,"Strike kills cannot immediately refill its own capacitor %d" % aircraft)
		d._update_ability(100)
		d._update_charge(100,true)
		check(d.charge==0,"Long frame expiring ability cannot credit active seconds or kills %d" % aircraft)
		d._update_charge(1,false)
		check(is_equal_approx(d.charge,1.8),"Recharge resumes without catching up strike kills %d" % aircraft)
		check(d.weapons.projectile_damage==d.base_damage and d.weapons.laser_interval_multiplier==d.base_laser_interval and d.player.speed==d.base_speed,"Expiry restores real base weapon and motion %d" % aircraft)
		d.charge = 100
		d.use_strike()
		d.player.alive = false
		d._update_ability(.1)
		check(d.ability_time==0 and d.weapons.projectile_damage==d.base_damage,"Death cancels aircraft ability %d" % aircraft)
		d.player.alive = true
		d.ability_time = 0
		d.charge = 100
		d.paused = true
		check(not d.use_strike() and not d.use_bomb(),"Pause blocks combat actions %d" % aircraft)
		d.paused = false
		d.use_strike()
		d.ending = true
		d._update_ability(0)
		check(d.ability_time==0 and d.weapons.projectile_damage==d.base_damage,"Carrier landing cancels active ability %d" % aircraft)
		d.ending = false
		# Module modification reaches actual spread velocity and laser collision width.
	await _launch(2,0,["yield"])
	for i in range(13):
		var enemy := _target("zero")
		enemy.position = Vector3((i%5-2)*1.1,0,float(i/5)*1.1)
		enemy.destroyed.connect(director.combat._on_enemy_destroyed)
		director.combat.enemies.append(enemy)
	await _sync()
	director.charge = 100
	var before: int = director.combat.kills
	check(director.use_strike(),"Real 13-target strike starts")
	check(director.combat.kills-before==13,"Real area discharge produces thirteen authentic destruction callbacks")
	director._update_charge(.1,true)
	check(director.charge==0 and director.previous_kills==director.combat.kills,"Real thirteen-kill discharge cannot farm immediate recharge")
	director._update_ability(10)
	director._update_charge(10,true)
	director._update_charge(0,false)
	check(director.charge==0,"Real discharge kills never reappear as delayed charge after expiry")
	director.combat.enemies.clear()
	await process_frame
	for module in ["precision","coverage"]:
		await _launch(1,0,[module])
		var weapon: Node3D = director.weapons
		weapon.set_power("spread")
		weapon._fire_salvo()
		var angle := rad_to_deg(atan2(weapon.velocities[0].x,-weapon.velocities[0].z))
		check(is_equal_approx(angle,-12.0 if module=="precision" else -19.5),"%s changes actual spread trajectory" % module)
		weapon.cease_fire()
		weapon.set_power("none")
		weapon._fire_salvo()
		weapon._physics_process(.08)
		check(is_equal_approx(weapon.projectiles[1].position.x-weapon.projectiles[0].position.x,weapon.MUZZLES[1].x-weapon.MUZZLES[0].x),"%s preserves fair standard P-38 muzzle spacing" % module)
		weapon.cease_fire()
		var target := _target("naval")
		target.position.x = 1.2
		await _sync()
		weapon.set_power("laser")
		Input.action_press("fire")
		weapon._update_laser(.001)
		Input.action_release("fire")
		check((target.health<12)==(module=="coverage"),"%s laser width changes real edge collision" % module)
		check(is_equal_approx(weapon.laser.scale.x,.8 if module=="precision" else 1.3),"%s laser presentation matches real width" % module)
		weapon.cease_fire()
		target.queue_free()
		await process_frame
	await _launch(1,1)
	var snapshot := _target("naval")
	await _sync()
	director.charge = 100
	# Ability is activated before introducing a radar contact, so its initial
	# discharge does not consume this dedicated in-flight damage fixture.
	director.use_strike()
	director.weapons.set_power("none")
	director.weapons._fire_salvo()
	director._update_ability(100)
	for frame in range(40): director.weapons._physics_process(DT)
	check(is_equal_approx(snapshot.health,12-2*1.25*1.35),"In-flight projectiles retain launch damage when ability expires")
	director.weapons.cease_fire()
	check(director.weapons.round_damages.count(0.0)==director.weapons.CAPACITY,"Released projectile slots clear their damage snapshots")
	snapshot.queue_free()
	await process_frame
	await _launch(2,0,["plates","prepared"])
	check(director.bombs==2 and director.charge==25 and director.player.max_health==4 and is_equal_approx(director.player.speed,10.4*.92),"Preparation and plates change real bombs/initial charge/armor/motion")
	await _launch(1,0,["agile","payload"])
	check(director.bombs==3 and is_equal_approx(director.player.speed,14*1.08),"Agile and payload change real bomb capacity and motion")
	director.player.invulnerable_time = 0
	director.player.take_damage(1)
	check(is_equal_approx(director.player.invulnerable_time,.85*.75),"Agile shortens only real protection after a hit")
	director._update_charge(1,false)
	check(is_equal_approx(director.charge,1.8/.88),"Payload shortens real recharge time")
	for module in ["yield","reserve"]:
		await _launch(0,0,[module])
		director.combat.kills += 2
		director._update_charge(1,false)
		var expected: float = 2*8*(1.2 if module=="yield" else .8)+1.8*(.75 if module=="yield" else 1.4)
		check(is_equal_approx(director.charge,expected),"%s changes actual kill/passive charge with tradeoff" % module)

func _ability_damage() -> void:
	for aircraft in range(3):
		for power in ["none","spread","laser"]:
			await _launch(aircraft,1,["impact"])
			var d: Node = director
			var body := _target("boss")
			d.combat.campaign_contacts.append(body)
			d.charge = 100
			d.use_strike()
			check(is_equal_approx(body.health,260-[30.0,54.0,102.0][aircraft]),"%d real impact module changes initial discharge against original boss hull" % aircraft)
			body.queue_free()
			d.combat.campaign_contacts.clear()
			d.ability_time = 0
			d._update_ability(0)
			await process_frame
			var ship := _target("naval")
			# Preserve original ship HP. Triggering the ability strikes the ship first;
			# use a separate identical ship to measure active weapon damage afterwards.
			d.combat.campaign_contacts.append(ship)
			d.charge = 100
			var initial: float = ship.health
			d.use_strike()
			check(ship.health==0 and d.ability_time>0,"%d/%s real impact ability discharge destroys a visible ship" % [aircraft,power])
			check(is_equal_approx(d.ability_time,[3.75,3.0,2.625][aircraft]),"%d impact reduces active duration" % aircraft)
			ship.queue_free()
			d.combat.campaign_contacts.clear()
			await process_frame
			ship = _target("naval")
			await _sync()
			d.weapons.set_power(power)
			if power=="laser":
				Input.action_press("fire")
				d.weapons._update_laser(.001)
				Input.action_release("fire")
			else:
				d.weapons._fire_salvo()
				for frame in range(40): d.weapons._physics_process(DT)
			check(ship.health<12 and ship.health>0,"%d/%s real active weapon hits after discharge" % [aircraft,power])
			if power=="laser": check(is_equal_approx(ship.health,12-3*1.25*[1.0,1.35,1.2][aircraft]),"%d laser ability preserves proportional fractional damage" % aircraft)
			d.weapons.cease_fire()
			ship.queue_free()
			await process_frame

func _tap_cadence() -> void:
	# Use production 60 Hz input toggling: a turbo that releases for one frame
	# used to reset both weapon clocks and reach 30 salvos/laser ticks per second.
	var dt := 1.0/60.0
	for aircraft in range(3):
		for rank in range(4):
			for modules in [[],["precision"]]:
				await _launch(aircraft,rank,modules)
				var weapon: Node3D = director.weapons
				for active_ability in [false,true]:
					director.ability_time = 0
					director._update_ability(0)
					if active_ability:
						director.charge = 100
						director.use_strike()
					for power in ["none","laser"]:
						var amounts: Array[int] = []
						for tapped in [false,true]:
							weapon.set_power(power)
							Input.action_release("fire")
							# Time readies the weapon; changing POW or releasing does not.
							weapon._physics_process(1.0)
							var before: int = weapon.shots_fired
							for frame in range(240):
								if tapped and frame%2==1: Input.action_release("fire")
								else: Input.action_press("fire")
								weapon._physics_process(dt)
							Input.action_release("fire")
							var count: int = weapon.shots_fired-before
							amounts.append(count)
							var interval: float = weapon.shot_interval if power=="none" else LOADOUT.BASE_LASER_INTERVAL*weapon.laser_interval_multiplier
							var per_shot := 2 if power=="none" else 1
							# The measurement includes an initially ready shot plus elapsed
							# intervals. At exactly 72 intervals there can be 73 shots;
							# the first does not consume a preceding recharge interval.
							var ceiling := (floori(4.0/interval+.000001)+1)*per_shot
							check(count<=ceiling,"%d/rank%d/%s/%s/ability%s module%s cannot bypass the elapsed-time fire ceiling" % [aircraft,rank,power,"tap" if tapped else "hold",active_ability,str(modules)])
							if not tapped:
								check(absf(float(count)-4.0/interval*per_shot)<=per_shot,"Sustained firing keeps fractional cadence without an extra stall burst")
							weapon.cease_fire()
						check(amounts[1]<=amounts[0],"Tapping cannot out-fire holding for aircraft%d/rank%d/%s/ability%s module%s" % [aircraft,rank,power,active_ability,str(modules)])
						cadence_samples.append({"aircraft":aircraft,"rank":rank,"power":power,"ability":active_ability,"modules":modules,"held_shots":amounts[0],"tapped_shots":amounts[1],"seconds":4,"physics_hz":60,"shot_interval":weapon.shot_interval if power=="none" else LOADOUT.BASE_LASER_INTERVAL*weapon.laser_interval_multiplier})
	# Keep a positive cooldown through immediate release, POW switching, and a
	# short disabled-controls interval. A long inactive interval readies the next
	# shot naturally; an actual tree pause does not advance physics time at all.
	await _launch(2,0)
	var weapon: Node3D = director.weapons
	for power in ["none","laser"]:
		weapon.set_power(power)
		Input.action_release("fire")
		weapon._physics_process(1.0)
		var before: int = weapon.shots_fired
		Input.action_press("fire")
		weapon._physics_process(dt)
		check(weapon.shots_fired>before,"Ready %s weapon fires its first shot without a startup delay" % power)
		var after: int = weapon.shots_fired
		Input.action_release("fire")
		weapon._physics_process(dt)
		Input.action_press("fire")
		weapon._physics_process(dt)
		check(weapon.shots_fired==after,"A single released frame cannot reset %s cadence" % power)
		weapon.set_power("spread" if power=="laser" else "laser")
		weapon.set_power(power)
		weapon._physics_process(0)
		check(weapon.shots_fired==after,"Switching away and back cannot reset the %s weapon clock" % power)
		director.player.controls_enabled = false
		weapon._physics_process(dt)
		director.player.controls_enabled = true
		weapon._physics_process(0)
		check(weapon.shots_fired==after,"Brief controls disable cannot reset %s cadence" % power)
		Input.action_release("fire")
		weapon._physics_process(1.0)
		Input.action_press("fire")
		weapon._physics_process(0)
		check(weapon.shots_fired>after,"Inactive time naturally readies the %s weapon again" % power)
		Input.action_release("fire")
		weapon.cease_fire()

func _pool_stress() -> void:
	for screen in [Vector2i(1280,720),Vector2i(1920,1080),Vector2i(2560,1080)]:
		root.size = screen
		await _launch(0,3,["precision"])
		var weapon: Node3D = director.weapons
		# Longest on-screen projectile lifetime starts at the actual lower flight bound.
		director.player.position.z = 100
		director.player._keep_inside_screen()
		director.charge = 100
		director.use_strike()
		weapon.set_power("spread")
		weapon._cooldown = 0
		var peak := 0
		var before: int = weapon.shots_fired
		Input.action_press("fire")
		for frame in range(720):
			weapon._physics_process(DT)
			peak = maxi(peak,weapon.active_count)
		Input.action_release("fire")
		var expected: float = 3.0/weapon.shot_interval*4
		var emitted: int = weapon.shots_fired-before
		check(absf(expected-emitted)<=4,"%s worst cadence emits every expected salvo without pool starvation" % screen)
		check(peak<weapon.CAPACITY and weapon.projectiles.size()==weapon.CAPACITY,"%s worst firing pool stays bounded" % screen)
		for frame in range(800): weapon._physics_process(DT)
		check(weapon.active_count==0,"%s all missed spread rounds actually leave screen and release pool" % screen)
		pools.append({"resolution":str(screen),"peak":peak,"origin_z":director.player.position.z,"capacity":weapon.CAPACITY,"seconds":3,"shots":emitted})

func _run() -> void:
	root.size = Vector2i(1920,1080)
	app = load("res://scenes/campaign.tscn").instantiate()
	if app.get_script()==null:
		check(false,"Campaign scene must load its production script before any combat fixture")
		quit(1)
		return
	app.testing = true
	app.profile.path = "user://loadout-combat-isolated.json"
	root.add_child(app)
	current_scene = app
	await process_frame
	app.profile.reset()
	app.profile.data.unlocked = 32
	await _destruction_matrix()
	check(timings.size()==168,"All 168 aircraft/rank/weapon/production-target fixtures executed")
	await _components()
	await _modules_and_abilities()
	await _ability_damage()
	await _tap_cadence()
	check(cadence_samples.size()==96,"All 96 tap/hold aircraft/rank/POW/ability/module cadence fixtures executed")
	await _pool_stress()
	Input.action_release("fire")
	app.set_process(false)
	_stop_audio(app)
	app._dispose_run()
	await create_timer(.2).timeout
	app.queue_free()
	current_scene = null
	await process_frame
	await create_timer(.2).timeout
	var result := {"checks":checks,"failures":failures,"renderer":RenderingServer.get_current_rendering_method(),"stationary_target_timings":timings,"worst_case_projectile_pools":pools,"tap_hold_cadence":cadence_samples,"human_campaign_viability":"NOT_PERFORMED"}
	var path := "C:/ChatGPT/1942/game/tests/loadout-combat-results.json"
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file!=null: file.store_string(JSON.stringify(result,"\t")); file.close()
	print("LOADOUT COMBAT: ",checks," checks; failures: ",failures)
	quit(0 if failures.is_empty() else 1)
