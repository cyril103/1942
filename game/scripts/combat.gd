extends Node3D
## Test encounter director. Enemy bodies are freed; bullets and VFX have fixed pools.
const EXPLOSION := preload("res://scripts/explosion_effect.gd")
const HAYABUSA := preload("res://scripts/enemy_hayabusa.gd")
const ENEMY := preload("res://scripts/enemy_zero.gd")
const BOMBER := preload("res://scripts/enemy_bomber.gd")
const RED := preload("res://scripts/enemy_red.gd")
const POW := preload("res://scripts/pow_pickup.gd")
const SPECIAL_INTERVAL := 40.0
const BOMBER_INTERVAL := 30.0
const WAVE_INTERVAL := 20.0
const BULLET_CAPACITY := 192
const BULLET_SPEED := 14.0
const EFFECT_CAPACITY := 18

@export var player: Node3D
@export var camera: Camera3D
var enemies: Array[Area3D] = []
var bombers: Array[Area3D] = []
var red_enemies: Array[Area3D] = []
var automatic_waves := true
var aircraft_enabled := true
var air_withdrawals: Array[Dictionary] = []
var dense_waves := false
var campaign_driver: Node
var max_fighters := 32
var next_power_kind := "spread"
var campaign_contacts: Array[Area3D] = []
var projectile_speed_scale := 1.0
var seascape: Node3D
var enemy_interval_scale := 1.0
var fighter_salvos := 3.0
var _salvo_fraction := 0.0
var special_enabled := true
var next_special := 12.0
var special_count := 0
var special_kills := 0
var special_resolved := 0
var special_failed := false
var pow_spawn_count := 0
var pickup: Node3D
var bombers_enabled := true
var next_bomber := BOMBER_INTERVAL
var bomber_count := 0
var bomber_shots := 0
var bomber_audio: AudioStreamPlayer
var bullets: Array[MeshInstance3D] = []
var velocities := PackedVector3Array()
var lifetimes := PackedFloat32Array()
var effects: Array[Node3D] = []
var effect_times := PackedFloat32Array()
var wave_count := 0
var kills := 0
var score := 0
# Standalone combat tests use one life; the cockpit configures a three-life run.
var remaining_lives := 1
var respawn_time := 0.0
var enemy_shots := 0
var combat_time := 0.0
var next_wave := 1.5
var started := false
var game_over := false
var hud: Label
var death_panel: Control
var _effect_cursor := 0
var _query := PhysicsRayQueryParameters3D.new()
var gun_audio: AudioStreamPlayer
var explosion_audio: AudioStreamPlayer
var ground_audio: AudioStreamPlayer
var ground_audio_cooldown := 0.0
var presentation_altitude := 0.0

func withdraw_aircraft() -> void:
	# The player dives beneath this airspace. Stop gameplay immediately, while
	# the detached models climb above the descending camera for a short exit.
	for group in [enemies,bombers,red_enemies]:
		for actor in group:
			if not is_instance_valid(actor): continue
			if actor.alive and actor.visual.is_visible_in_tree():
				var model: Node3D = actor.visual
				var side := -1.0 if actor.position.x<0 else 1.0
				model.reparent(self,true)
				air_withdrawals.append({"model":model,"side":side,"time":0.0})
			actor.retire()
		group.clear()
	clear_enemy_bullets()

func _update_withdrawals(delta: float) -> void:
	for exit_flight in air_withdrawals:
		exit_flight.time += delta
		var model: Node3D = exit_flight.model
		model.position += Vector3(float(exit_flight.side)*14.0,52.0,-9.0)*delta
		model.rotate_z(-float(exit_flight.side)*delta*.7)
		if exit_flight.time>=.75: model.queue_free()
	air_withdrawals = air_withdrawals.filter(func(item): return item.time<.75)

func play_ground_volley(kind: String, rapid_fire: bool) -> void:
	# One shared voice budget for a whole battery line: dense fire cannot stack
	# dozens of identical samples into a clipped transient.
	if ground_audio_cooldown>0: return
	ground_audio_cooldown = .075
	ground_audio.pitch_scale = .70 if kind=="bunker" else (1.12 if rapid_fire else .86)
	ground_audio.play()

func set_presentation_altitude(altitude: float) -> void:
	var change := altitude-presentation_altitude
	presentation_altitude = altitude
	if not is_zero_approx(change):
		for i in range(BULLET_CAPACITY):
			if lifetimes[i]>0: bullets[i].position.y += change
		for i in range(EFFECT_CAPACITY):
			if effect_times[i]>0 and not effects[i].get_meta("ground_scroll",false): effects[i].position.y += change
	pickup.presentation_altitude = altitude
	pickup.position.y = altitude+.35
	for group in [enemies,bombers,red_enemies]:
		for actor in group:
			if is_instance_valid(actor): _apply_aircraft_altitude(actor)

func _apply_aircraft_altitude(actor: Node3D) -> void:
	if is_zero_approx(presentation_altitude) and not actor.has_meta("altitude_pivot"): return
	var pivot: Node3D
	if actor.has_meta("altitude_pivot"):
		pivot = actor.get_meta("altitude_pivot")
	else:
		pivot = Node3D.new()
		pivot.name = "FlightAltitude"
		actor.add_child(pivot)
		actor.visual.reparent(pivot,false)
		actor.set_meta("altitude_pivot",pivot)
	pivot.position.y = presentation_altitude
	if actor is ENEMY:
		actor.loop_height_scale = lerpf(1.0,.18,clampf(-presentation_altitude/5.8,0,1))
		# Rescale the complete maneuver, including height gained before descent.
		if actor.phase==ENEMY.Phase.LOOP: actor.visual.position.y = actor.loop_elevation*actor.loop_height_scale

func _ready() -> void:
	seascape = get_parent().get_node_or_null("Seascape")
	player.destroyed.connect(_on_player_destroyed)
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(0.90, 0.90)
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/enemy_bullet.gdshader")
	mesh.material = material
	lifetimes.resize(BULLET_CAPACITY)
	velocities.resize(BULLET_CAPACITY)
	for index in range(BULLET_CAPACITY):
		var bullet := MeshInstance3D.new()
		bullet.mesh = mesh
		bullet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(bullet)
		bullet.hide()
		bullets.append(bullet)
	effect_times.resize(EFFECT_CAPACITY)
	for index in range(EFFECT_CAPACITY):
		var effect := EXPLOSION.new()
		add_child(effect)
		effects.append(effect)
	_query.collision_mask = 4
	_query.collide_with_areas = true
	gun_audio = AudioStreamPlayer.new()
	gun_audio.stream = preload("res://assets/audio/weapons/salvo_03.wav")
	gun_audio.volume_db = -15.0
	gun_audio.pitch_scale = 0.88
	gun_audio.max_polyphony = 8
	add_child(gun_audio)
	explosion_audio = AudioStreamPlayer.new()
	explosion_audio.stream = preload("res://assets/audio/weapons/explosion.wav")
	explosion_audio.volume_db = -9.0
	explosion_audio.max_polyphony = 4
	add_child(explosion_audio)
	bomber_audio = AudioStreamPlayer.new()
	bomber_audio.stream = gun_audio.stream
	bomber_audio.pitch_scale = 0.68
	bomber_audio.volume_db = -17
	bomber_audio.max_polyphony = 4
	add_child(bomber_audio)
	ground_audio = AudioStreamPlayer.new()
	ground_audio.stream = gun_audio.stream
	ground_audio.bus = "Effects"
	ground_audio.volume_db = -20.0
	ground_audio.max_polyphony = 4
	add_child(ground_audio)
	pickup = POW.new()
	add_child(pickup)
	_build_hud()

func navigate_naval(ship: Node3D, offset: float = 0.0) -> void:
	if not is_instance_valid(seascape): return
	ship.position.x = seascape.channel_center(ship.position.z)+offset
	ship.rotation.y = seascape.channel_heading(ship.position.z)

func screen_bottom() -> float:
	return camera.project_position(get_viewport().get_visible_rect().size, 1.0).z

func screen_top() -> float:
	return camera.project_position(Vector2.ZERO, 1.0).z

func _physics_process(delta: float) -> void:
	ground_audio_cooldown = maxf(0,ground_audio_cooldown-delta)
	_update_withdrawals(delta)
	if respawn_time > 0:
		respawn_time = maxf(0,respawn_time-delta)
		if respawn_time <= 0:
			clear_enemy_bullets()
			player.respawn(Vector3(0,0,screen_bottom()-3.0))
	_update_effects(delta)
	_update_bullets(delta)
	for enemy in enemies:
		if is_instance_valid(enemy) and enemy.alive:
			enemy.advance(delta, self)
			if enemy.has_meta("fire_warning"):
				var remaining: float = float(enemy.get_meta("fire_warning"))-delta
				enemy.set_meta("fire_warning",remaining)
				if remaining<=0:
					enemy.remove_meta("fire_warning")
					_fire_enemy_now(enemy)
	enemies = enemies.filter(func(enemy): return is_instance_valid(enemy) and enemy.alive)
	for bomber in bombers:
		if is_instance_valid(bomber) and bomber.alive: bomber.advance(delta,self)
	bombers = bombers.filter(func(bomber): return is_instance_valid(bomber) and bomber.alive)
	for red in red_enemies:
		if is_instance_valid(red) and red.alive: red.advance(delta,self)
	red_enemies = red_enemies.filter(func(red): return is_instance_valid(red) and red.alive)
	pickup.advance(delta,self)
	if not game_over and player.controls_enabled:
		started = true
		combat_time += delta
		if bombers_enabled:
			next_bomber -= delta
			if next_bomber <= 0:
				spawn_bomber()
				next_bomber += BOMBER_INTERVAL
		if special_enabled:
			next_special -= delta
			if next_special <= 0:
				spawn_special()
				next_special += SPECIAL_INTERVAL
		if automatic_waves: next_wave -= delta
		if automatic_waves and next_wave <= 0:
			spawn_wave()
			next_wave += WAVE_INTERVAL
	_update_hud()

func spawn_wave() -> void:
	if game_over or not aircraft_enabled:
		return
	# Safety cap for extremely tall windows; stale formations cannot accumulate.
	if dense_waves and enemies.size() >= max_fighters - 7: return
	if not dense_waves and enemies.size() >= 8:
		for enemy in enemies:
			if is_instance_valid(enemy): enemy.retire()
		enemies.clear()
	wave_count += 1
	var half_width := absf(camera.project_position(Vector2.ZERO, 1.0).x)
	if wave_count % 2 == 0:
		_spawn_hayabusa(half_width)
		return
	# Four independent lanes span the viewport, with space for each wingspan.
	var usable_width := maxf(2.0, half_width - 1.8)
	var lanes := [-0.95, -0.32, 0.32, 0.95]
	var delays := [0.0, 0.75, 0.30, 1.15]
	var speeds := [10.0, 11.4, 10.7, 11.0]
	for index in range(8 if dense_waves else 4):
		var profile := (index + wave_count - 1) % 4
		var side := -1.0 if index < 2 else 1.0
		var enemy := ENEMY.new()
		enemy.shot_limit = next_fighter_shot_limit()
		enemy.flight_speed = speeds[profile]
		var lane: float = lerpf(-0.93,0.93,float(index)/7.0) if dense_waves else lanes[index]
		if dense_waves: side = signf(lane)
		enemy.position = Vector3(lane * usable_width, 0, screen_top() - 2.5 - delays[profile] * enemy.flight_speed)
		if dense_waves: enemy.health = 3
		enemy.loop_z = [-2.8, 1.2, -0.8, 2.6][profile]
		enemy.loop_duration = [2.4, 2.7, 2.6, 2.8][profile]
		enemy.maneuver = profile % 2
		enemy.turn_sign = -side
		# Aim once per pass so a moving player cannot cause sudden course changes.
		var aim_x := player.global_position.x * (0.65 if profile % 2 == 0 else 0.25)
		enemy.approach_target_x = clampf(lerpf(enemy.position.x, aim_x, 0.65) + side * 0.8, -usable_width * 0.55, usable_width * 0.55)
		if dense_waves:
			enemy.approach_target_x = clampf(lerpf(enemy.position.x,player.position.x,.24+profile*.04),-usable_width*.9,usable_width*.9)
		enemy.turn_duration = 2.5 + profile * 0.15
		enemy.turn_angle = 0.42 + profile * 0.035
		enemy.destroyed.connect(_on_enemy_destroyed)
		add_child(enemy)
		_apply_aircraft_altitude(enemy)
		enemies.append(enemy)

func _spawn_hayabusa(half_width: float) -> void:
	for slot in range(8 if dense_waves else 4):
		var index := slot % 4
		var enemy := HAYABUSA.new()
		enemy.shot_limit = next_fighter_shot_limit()
		enemy.side = -1.0 if index % 2 == 0 else 1.0
		enemy.flight_speed = [11.0, 12.0, 11.5, 12.5][index]
		enemy.roll_duration = [1.25, 1.40, 1.30, 1.45][index]
		enemy.roll_radius = [0.42, 0.52, 0.46, 0.58][index]
		enemy.entry_heading = [1.26, 1.22, 1.30, 1.24][index]
		enemy.attack_heading = [0.24, 0.18, 0.28, 0.20][index]
		enemy.target_offset = [-2.4, 2.4, -0.8, 0.8][index]
		enemy.position = Vector3(enemy.side * (half_width + 2.2 + index * 2.0 + (slot/4)*6.0), 0, screen_top() + [1.8, 3.0, 0.8, 2.2][index] + (slot/4)*3.0)
		if dense_waves:
			enemy.health = 3
			enemy.position = Vector3(enemy.side*(half_width+2.2),0,screen_top()-.4+index*.55)
			enemy.entry_delay = (slot/4)*1.1+index*.16
		enemy.destroyed.connect(_on_enemy_destroyed)
		add_child(enemy)
		_apply_aircraft_altitude(enemy)
		enemies.append(enemy)

func next_fighter_shot_limit() -> int:
	# Distribute extra rounds across the formation rather than upgrading every
	# aircraft at once at an arbitrary mission boundary.
	var count := int(floor(fighter_salvos))
	_salvo_fraction += fighter_salvos-count
	if _salvo_fraction >= 0.99999:
		count += 1
		_salvo_fraction = maxf(0.0,_salvo_fraction-1.0)
	return clampi(count,1,3)

func fire_enemy(enemy: Area3D) -> void:
	if not aircraft_enabled: return
	if is_instance_valid(campaign_driver):
		if game_over or not player.alive or enemy.has_meta("fire_warning"): return
		var aim := player.global_position
		var role: String = enemy.get_meta("role","escort")
		if role=="interceptor":
			var motion := Input.get_vector("move_left","move_right","move_up","move_down")
			aim += Vector3(motion.x,0,motion.y)*player.speed*.18
		elif role=="gunner": aim.x += sin(enemy.age*2)*2.4
		enemy.set_meta("locked_aim",aim)
		enemy.set_meta("fire_warning",.22)
		return
	_fire_enemy_now(enemy)

func _fire_enemy_now(enemy: Area3D) -> void:
	if game_over or not aircraft_enabled or not player.alive:
		return
	var target: Vector3 = enemy.get_meta("locked_aim",player.global_position)
	if enemy.has_meta("locked_aim"): enemy.remove_meta("locked_aim")
	gun_audio.play()
	for side in ([0] if dense_waves else [-1, 1]):
		var origin := enemy.global_position + enemy.global_basis * Vector3(side * 0.241875, 0.1875, 0.478125)
		_launch_enemy_round(origin,target,BULLET_SPEED)

func _launch_enemy_round(origin: Vector3, target: Vector3, speed: float, visual_origin := false) -> bool:
	if not visual_origin: origin.y += presentation_altitude
	for index in range(BULLET_CAPACITY):
		if lifetimes[index] > 0: continue
		var direction := Vector3(target.x-origin.x,0,target.z-origin.z).normalized()
		if direction.length_squared() < 0.1: direction = Vector3(0,0,1)
		bullets[index].global_position = origin
		bullets[index].show()
		velocities[index] = direction*speed*projectile_speed_scale
		lifetimes[index] = 6.0
		enemy_shots += 1
		return true
	return false

func fire_bomber(bomber: Area3D) -> void:
	if game_over or not aircraft_enabled or not player.alive: return
	bomber_audio.play()
	var target := player.global_position
	if is_instance_valid(campaign_driver) and is_instance_valid(campaign_driver.convoy) and campaign_driver.convoy.alive:
		target = campaign_driver.convoy.global_position
	for origin in bomber.get_rear_muzzles():
		if _launch_enemy_round(origin,target,14.0,true): bomber_shots += 1

func spawn_bomber() -> void:
	if game_over or not aircraft_enabled or not bombers.is_empty(): return
	bomber_count += 1
	var bomber := BOMBER.new()
	var half_width := absf(camera.project_position(Vector2.ZERO,1.0).x)
	bomber.direction = -1.0 if bomber_count % 2 == 0 else 1.0
	bomber.position = Vector3(bomber.direction*1.4,0,screen_bottom()+2.7)
	bomber.anchor = Vector3(0,0,screen_top()+4.2)
	bomber.amplitude = minf(5.0,maxf(0.5,half_width-2.7))
	bomber.destroyed.connect(_on_bomber_destroyed)
	add_child(bomber)
	_apply_aircraft_altitude(bomber)
	bombers.append(bomber)

func _on_bomber_destroyed(_at: Vector3) -> void:
	kills += 1
	score += 500
	if is_instance_valid(campaign_driver): campaign_driver.on_kill(500,"bomber")

func get_radar_contacts() -> Array[Area3D]:
	var contacts: Array[Area3D] = []
	contacts.append_array(enemies)
	for actor in campaign_contacts:
		if is_instance_valid(actor) and actor.alive: contacts.append(actor)
	for red in red_enemies:
		if is_instance_valid(red) and red.alive and red.visible: contacts.append(red)
	for bomber in bombers:
		if is_instance_valid(bomber) and bomber.alive and not bomber.dying: contacts.append(bomber)
	return contacts

func _update_bullets(delta: float) -> void:
	var viewport := get_viewport().get_visible_rect()
	var space := get_world_3d().direct_space_state
	for index in range(BULLET_CAPACITY):
		if lifetimes[index] <= 0: continue
		var before := bullets[index].global_position
		bullets[index].position += velocities[index] * delta
		lifetimes[index] -= delta
		_query.from = Vector3(before.x, 0, before.z)
		_query.to = Vector3(bullets[index].global_position.x, 0, bullets[index].global_position.z)
		var hit := space.intersect_ray(_query)
		if not hit.is_empty() and player.alive:
			lifetimes[index] = 0
			bullets[index].hide()
			hit.collider.take_damage(1)
			continue
		if lifetimes[index] <= 0 or not viewport.has_point(camera.unproject_position(bullets[index].global_position)):
			lifetimes[index] = 0
			bullets[index].hide()

func _on_enemy_destroyed(at: Vector3) -> void:
	kills += 1
	score += 100
	if is_instance_valid(campaign_driver): campaign_driver.on_kill(100,"fighter")
	_explode(at)

func _on_player_destroyed(at: Vector3) -> void:
	remaining_lives = maxi(0,remaining_lives-1)
	game_over = remaining_lives == 0
	_explode(at)
	if game_over:
		respawn_time = 0
		if not is_instance_valid(campaign_driver): death_panel.show()
	else: respawn_time = 1.5
	for index in range(BULLET_CAPACITY):
		lifetimes[index] = 0
		bullets[index].hide()

func _explode(at: Vector3, effect_scale: float = 1.0, sound: bool = true, ground_scroll: bool = false, visual_origin := false) -> void:
	if not visual_origin: at.y += presentation_altitude
	if is_instance_valid(campaign_driver) and is_instance_valid(campaign_driver.details): campaign_driver.details.burst(at,effect_scale>1.1,ground_scroll)
	if sound: explosion_audio.play()
	effects[_effect_cursor].scale = Vector3.ONE*EXPLOSION.AIRCRAFT_EFFECT_SCALE*effect_scale
	effects[_effect_cursor].set_meta("ground_scroll",ground_scroll)
	effects[_effect_cursor].trigger(at, float(kills + _effect_cursor) * 1.713)
	effect_times[_effect_cursor] = EXPLOSION.DURATION
	_effect_cursor = (_effect_cursor + 1) % EFFECT_CAPACITY

func _update_effects(delta: float) -> void:
	for index in range(EFFECT_CAPACITY):
		if effect_times[index] <= 0: continue
		effect_times[index] = maxf(0, effect_times[index] - delta)
		effects[index].advance(delta)

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Label.new()
	hud.position = Vector2(24, 18)
	hud.add_theme_font_size_override("font_size", 20)
	hud.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	hud.add_theme_constant_override("shadow_offset_x", 2)
	hud.add_theme_constant_override("shadow_offset_y", 2)
	layer.add_child(hud)
	death_panel = CenterContainer.new()
	layer.add_child(death_panel)
	death_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	death_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.04, 0.06, 0.92)
	style.content_margin_left = 48
	style.content_margin_right = 48
	style.content_margin_top = 28
	style.content_margin_bottom = 28
	panel.add_theme_stylebox_override("panel", style)
	death_panel.add_child(panel)
	var label := Label.new()
	label.text = "AVION DÉTRUIT\n\nR — Recommencer le test\nÉchap — Quitter"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 28)
	panel.add_child(label)
	death_panel.hide()
	_update_hud()

func _update_hud() -> void:
	if not started:
		hud.text = "TEST COMBAT  •  Décollage\nFlèches : piloter   Espace : tirer   R : recommencer"
	else:
		hud.text = "VAGUE %d  •  %d ABATTUS  •  %s\nEspace : tirer   R : recommencer" % [wave_count, kills, "TEST TERMINÉ" if game_over else "PROCHAINE : %ds" % ceili(maxf(0, next_wave))]

func spawn_special() -> void:
	if not aircraft_enabled: return
	if game_over or not red_enemies.is_empty(): return
	special_count += 1
	special_kills = 0
	special_resolved = 0
	special_failed = false
	var side := 1.0 if special_count % 2 == 1 else -1.0
	var w := absf(camera.project_position(Vector2.ZERO,1.0).x)
	var top := screen_top()
	var route := Curve3D.new()
	route.bake_interval = 0.04
	# Circular Bezier quarters (radius >= aircraft span) prevent tight curvature spikes.
	var radius := minf(4.0,w-1.5)
	var handle := radius*0.55228475
	var z := top+4.0
	var points := [Vector3(-w-3,0,z),Vector3(0,0,z),Vector3(radius,0,z+radius),Vector3(0,0,z+2*radius),Vector3(-radius,0,z+3*radius),Vector3(-radius,0,screen_bottom()+5)]
	var tangents := [Vector3(4,0,0),Vector3(handle,0,0),Vector3(0,0,handle),Vector3(-handle,0,0),Vector3(0,0,handle),Vector3(0,0,4)]
	for index in range(points.size()):
		var point: Vector3 = points[index]
		var tangent: Vector3 = tangents[index]
		point.x *= side
		tangent.x *= side
		route.add_point(point,-tangent,tangent)
	for index in range(5):
		var red := RED.new()
		red.route = route
		red.slot = index
		red.destroyed.connect(_on_red_destroyed)
		red.escaped.connect(_on_red_escaped)
		add_child(red)
		_apply_aircraft_altitude(red)
		red_enemies.append(red)

func _on_red_destroyed(at: Vector3) -> void:
	special_kills += 1
	special_resolved += 1
	kills += 1
	score += 150
	if is_instance_valid(campaign_driver): campaign_driver.on_kill(150,"red")
	_explode(at)
	if special_kills == 5 and special_resolved == 5 and not special_failed:
		var half_width := absf(camera.project_position(Vector2.ZERO,1.0).x)
		var drop := Vector3(clampf(at.x,-half_width+1,half_width-1),0,clampf(at.z,screen_top()+1.5,screen_bottom()-3))
		pickup.activate(drop,player,next_power_kind)
		if dense_waves: next_power_kind = {"spread":"laser","laser":"life","life":"spread"}[next_power_kind]
		pow_spawn_count += 1
		if is_instance_valid(campaign_driver): campaign_driver.complete_objective("formation")

func _on_red_escaped() -> void:
	special_failed = true
	special_resolved += 1

func clear_enemy_bullets() -> void:
	for index in range(BULLET_CAPACITY):
		lifetimes[index] = 0
		bullets[index].hide()
