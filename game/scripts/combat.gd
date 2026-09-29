extends Node3D
## Test encounter director. Enemy bodies are freed; bullets and VFX have fixed pools.
const EXPLOSION := preload("res://scripts/explosion_effect.gd")
const ENEMY := preload("res://scripts/enemy_zero.gd")
const WAVE_INTERVAL := 20.0
const BULLET_CAPACITY := 64
const BULLET_SPEED := 14.0
const EFFECT_CAPACITY := 8

@export var player: Node3D
@export var camera: Camera3D
var enemies: Array[Area3D] = []
var bullets: Array[MeshInstance3D] = []
var velocities := PackedVector3Array()
var lifetimes := PackedFloat32Array()
var effects: Array[Node3D] = []
var effect_times := PackedFloat32Array()
var wave_count := 0
var kills := 0
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

func _ready() -> void:
	player.destroyed.connect(_on_player_destroyed)
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(0.44, 0.44)
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
	_build_hud()

func screen_bottom() -> float:
	return camera.project_position(get_viewport().get_visible_rect().size, camera.position.y).z

func screen_top() -> float:
	return camera.project_position(Vector2.ZERO, camera.position.y).z

func _physics_process(delta: float) -> void:
	_update_effects(delta)
	_update_bullets(delta)
	for enemy in enemies:
		if is_instance_valid(enemy) and enemy.alive:
			enemy.advance(delta, self)
	enemies = enemies.filter(func(enemy): return is_instance_valid(enemy) and enemy.alive)
	if not game_over and player.controls_enabled:
		started = true
		combat_time += delta
		next_wave -= delta
		if next_wave <= 0:
			spawn_wave()
			next_wave += WAVE_INTERVAL
	_update_hud()

func spawn_wave() -> void:
	if game_over:
		return
	# Safety cap for extremely tall windows; stale formations cannot accumulate.
	if enemies.size() >= 8:
		for enemy in enemies:
			if is_instance_valid(enemy): enemy.retire()
		enemies.clear()
	wave_count += 1
	var half_width := absf(camera.project_position(Vector2.ZERO, camera.position.y).x)
	# Four independent lanes span the viewport, with space for each wingspan.
	var usable_width := maxf(2.0, half_width - 1.8)
	var lanes := [-0.95, -0.32, 0.32, 0.95]
	var delays := [0.0, 0.75, 0.30, 1.15]
	var speeds := [10.0, 11.4, 10.7, 11.0]
	for index in range(4):
		var profile := (index + wave_count - 1) % 4
		var side := -1.0 if index < 2 else 1.0
		var enemy := ENEMY.new()
		enemy.flight_speed = speeds[profile]
		enemy.position = Vector3(lanes[index] * usable_width, 0, screen_top() - 4.5 - delays[profile] * enemy.flight_speed)
		enemy.loop_z = [-2.8, 1.2, -0.8, 2.6][profile]
		enemy.loop_duration = [2.4, 2.7, 2.6, 2.8][profile]
		enemy.maneuver = profile % 2
		enemy.turn_sign = -side
		# Aim once per pass so a moving player cannot cause sudden course changes.
		var aim_x := player.global_position.x * (0.65 if profile % 2 == 0 else 0.25)
		enemy.approach_target_x = clampf(lerpf(enemy.position.x, aim_x, 0.65) + side * 0.8, -usable_width * 0.55, usable_width * 0.55)
		enemy.turn_duration = 2.5 + profile * 0.15
		enemy.turn_angle = 0.42 + profile * 0.035
		enemy.destroyed.connect(_on_enemy_destroyed)
		add_child(enemy)
		enemies.append(enemy)

func fire_enemy(enemy: Area3D) -> void:
	if game_over or not player.alive:
		return
	var target: Vector3 = player.global_position
	gun_audio.play()
	for side in [-1, 1]:
		for index in range(BULLET_CAPACITY):
			if lifetimes[index] > 0: continue
			var origin := enemy.global_position + enemy.global_basis * Vector3(side * 0.43, 0.25, 0.85)
			var direction := Vector3(target.x - origin.x, 0, target.z - origin.z).normalized()
			if direction.length_squared() < 0.1: direction = Vector3(0, 0, 1)
			bullets[index].global_position = origin
			bullets[index].show()
			velocities[index] = direction * BULLET_SPEED
			lifetimes[index] = 6.0
			enemy_shots += 1
			break

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
	_explode(at)

func _on_player_destroyed(at: Vector3) -> void:
	game_over = true
	_explode(at)
	death_panel.show()
	for index in range(BULLET_CAPACITY):
		lifetimes[index] = 0
		bullets[index].hide()

func _explode(at: Vector3) -> void:
	explosion_audio.play()
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
