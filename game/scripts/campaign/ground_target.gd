extends Area3D
## Textured Blender ground installations: two shared meshes, one atlas, two VFX cards.
## The director scrolls every target, including its short-lived wreck, with the land.
signal destroyed(at: Vector3)
signal movement_announced(target_id: String, from: Vector3, to: Vector3, seconds: float)

const HEALTH := {"fuel":8, "radar":7, "battery":22, "bunker":32, "runway":14}
const FOOTPRINT := {"fuel":Vector2(3.3,2.8), "radar":Vector2(2.6,2.6), "battery":Vector2(2.8,2.8), "bunker":Vector2(3.2,2.5), "runway":Vector2(4.0,5.2)}
const MODELS := {
	"fuel":preload("res://assets/ground-forces/fuel.glb"),
	"radar":preload("res://assets/ground-forces/radar.glb"),
	"battery":preload("res://assets/ground-forces/battery.glb"),
	"bunker":preload("res://assets/ground-forces/bunker.glb"),
	"runway":preload("res://assets/ground-forces/runway.glb")
}
const FIELD_ATLAS := preload("res://assets/ground-forces/field-material-atlas.png")
const MOBILE_MODEL := preload("res://assets/ground-forces/battery_mobile.glb")

var variant := "fuel"
var health := 0.0
var max_health := 0.0
var alive := true
var jammed := false
var age := 0.0
var cooldown := 2.2
var warning_time := 0.0
var aim := Vector3.ZERO
var turret_yaw := 0.0
var hit_time := 0.0
var death_age := 0.0
var visual: Node3D
var assembly: MeshInstance3D
var hull: MeshInstance3D
var flare: MeshInstance3D
var fire: MeshInstance3D
var material: ShaderMaterial
var visual_altitude := -1.8
var defense_level := 0
var defense_stagger := 0.0
var rapid_fire := false
var salvo_remaining := 0
var salvo_total := 0
var salvo_time := 0.0
var muzzle_time := 0.0
var _salvo_direction := Vector3.FORWARD
var tactical_id := ""
var radar_group := ""
var priority_tag := ""
var mobile := false
enum MobilePhase { STATIONARY, ANNOUNCE, MOVE, SETTLE }
var mobile_phase: MobilePhase = MobilePhase.STATIONARY
var motion_intent := Vector3.ZERO
var motion_points := PackedVector3Array()
var motion_index := 0
var motion_clock := 0.0
var motion_wait := 0.0
var motion_origin := Vector3.ZERO
var motion_heading := 0.0
var motion_announcement_pending := false
const MOVE_WARNING_SECONDS := 0.60
const MOVE_SECONDS := 1.20
const MOVE_SETTLE_SECONDS := 0.25
const MOVE_STATION_SECONDS := 2.80

func configure_tactical(spec: Dictionary, route: Dictionary = {}) -> void:
	# Layout points use the raid's local X/Z frame; moving the Area3D therefore
	# moves its real collider and the scenery scroll remains shared with the land.
	tactical_id = str(spec.get("id",""))
	radar_group = str(spec.get("radar_group",""))
	priority_tag = str(spec.get("priority_tag",""))
	mobile = bool(spec.get("mobile",false)) and variant=="battery"
	motion_points.clear()
	for point in route.get("world_points",[]):
		if point is Vector3 and point.is_finite():
			motion_points.append(Vector3(point.x,0.0,point.z))
	mobile = mobile and motion_points.size()>=2
	mobile_phase = MobilePhase.STATIONARY
	motion_index = 0
	motion_clock = 0.0
	motion_announcement_pending = false
	motion_wait = 0.80+defense_stagger*6.0
	if mobile:
		position = motion_points[0]
		motion_origin = position
		motion_intent = motion_points[1]
	set_meta("target_id",tactical_id)
	set_meta("radar_group",radar_group)
	set_meta("priority_tag",priority_tag)
	set_meta("mobile",mobile)

func configure_defense(sector: int, stagger: float) -> void:
	# Each installation gets its own entry/recovery phase; radar recovery must
	# never restart every gun on the same frame.
	defense_level = clampi(sector,0,7)
	defense_stagger = clampf(stagger,0.0,0.28)
	cooldown = 0.03+defense_stagger
	warning_time = 0.0
	salvo_remaining = 0
	salvo_total = 0
	salvo_time = 0.0
	muzzle_time = 0.0
	if is_instance_valid(flare): flare.hide()

func set_jammed(value: bool) -> void:
	jammed = value
	if jammed: _cancel_salvo(0.24+defense_stagger)

func _ready() -> void:
	if not HEALTH.has(variant): variant = "fuel"
	if health <= 0: health = int(HEALTH[variant])
	max_health = health
	collision_layer = 2
	collision_mask = 0
	monitoring = false
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	var footprint: Vector2 = FOOTPRINT[variant]
	shape.size = Vector3(footprint.x,1.1,footprint.y)
	collider.shape = shape
	add_child(collider)
	visual = Node3D.new()
	add_child(visual)
	material = ShaderMaterial.new()
	material.shader = preload("res://shaders/ground_target.gdshader")
	material.set_shader_parameter("field_atlas",FIELD_ATLAS)
	var model: Node3D = (MOBILE_MODEL if mobile and variant=="battery" else MODELS[variant]).instantiate()
	visual.add_child(model)
	hull = model.find_child("Hull",true,false) as MeshInstance3D
	assembly = model.find_child("Radar" if variant=="radar" else "Turret",true,false) as MeshInstance3D
	for mesh in [hull,assembly]:
		mesh.material_override = material
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	flare = _card(Vector2(1.25,1.25),1)
	flare.position = Vector3(0,-0.53,0.32)
	add_child(flare)
	flare.hide()
	fire = _card(Vector2(3.1,3.7),0)
	fire.position = Vector3(0,-0.42,0.22)
	add_child(fire)
	fire.hide()
	set_visual_altitude(visual_altitude)
	set_process(false)

func set_visual_altitude(base_y: float) -> void:
	# Visual elevation is independent of Y=0 projectile sweeps and hit detection.
	visual_altitude = base_y
	if not is_instance_valid(visual) or not is_instance_valid(hull): return
	visual.position.y = base_y-hull.mesh.get_aabb().position.y
	if is_instance_valid(flare): flare.position.y = base_y+1.5
	if is_instance_valid(fire): fire.position.y = base_y+1.7

func _card(size: Vector2, kind: int) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = size
	node.mesh = plane
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/ground_target_fire.gdshader")
	mat.set_shader_parameter("kind",kind)
	node.material_override = mat
	return node

func advance(delta: float, combat: Node) -> void:
	if not alive or get_tree().paused: return
	age += delta
	hit_time = maxf(0,hit_time-delta)
	material.set_shader_parameter("hit_flash",hit_time/0.09)
	fire.material_override.set_shader_parameter("age",age)
	if variant == "radar": assembly.rotation.y += delta*0.85
	if global_position.z > combat.screen_bottom()+4.0:
		retire()
		return
	if variant not in ["battery","bunker"]: return
	var local_turret_yaw := turret_yaw-motion_heading if mobile else turret_yaw
	assembly.rotation.y = lerp_angle(assembly.rotation.y,local_turret_yaw,1.0-exp(-delta*7.0))
	if combat.game_over or not is_instance_valid(combat.player) or not combat.player.alive or not combat.player.controls_enabled:
		_cancel_salvo(0.24+defense_stagger)
		_suspend_mobile()
		return
	# Visible guns can turn back toward an aircraft that has passed them. A
	# player-relative Z cutoff created an empty firing range at the top edge.
	# Keep offscreen fire disabled and a small radial clearance around the pilot
	# so a gun directly underneath cannot release a point-blank volley.
	var pilot_distance := Vector2(global_position.x-combat.player.global_position.x,global_position.z-combat.player.global_position.z)
	if global_position.z < combat.screen_top()+0.25 or global_position.z > combat.screen_bottom()-0.25 or pilot_distance.length_squared() < 1.4*1.4:
		_cancel_salvo(0.03+defense_stagger)
		_suspend_mobile()
		return
	if _outside_horizontal_view(combat):
		_cancel_salvo(0.03+defense_stagger)
		_suspend_mobile()
		return
	# Radar disrupts firing, not a vehicle's engine. Motion remains continuous;
	# its busy phases never release a shot, even on the frame they finish.
	if jammed: _cancel_salvo(0.24+defense_stagger)
	var ready_to_fire := _advance_mobile(delta)
	if jammed or not ready_to_fire: return
	muzzle_time = maxf(0.0,muzzle_time-delta)
	if warning_time > 0:
		warning_time = maxf(0,warning_time-delta)
		flare.show()
		flare.material_override.set_shader_parameter("strength",1.0-warning_time/_warning_duration())
		if warning_time <= 0:
			if variant == "battery":
				salvo_total = 6+defense_level/2 if rapid_fire else 3+defense_level/3
			else:
				salvo_total = 2 if defense_level < 4 else 3
			salvo_remaining = salvo_total
			salvo_time = 0.0
			_fire_volley(combat)
	elif salvo_remaining > 0:
		salvo_time = maxf(0.0,salvo_time-delta)
		if salvo_time <= 0.0: _fire_volley(combat)
	else:
		cooldown -= delta
		if cooldown <= 0:
			aim = combat.player.global_position
			_salvo_direction = Vector3(aim.x-global_position.x,0,aim.z-global_position.z).normalized()
			turret_yaw = atan2(_salvo_direction.x,_salvo_direction.z)
			warning_time = _warning_duration()
			flare.material_override.set_shader_parameter("strength",0.0)
			flare.show()
	if warning_time <= 0.0:
		flare.visible = muzzle_time > 0.0
		if flare.visible: flare.material_override.set_shader_parameter("strength",muzzle_time/0.10)

func _advance_mobile(delta: float) -> bool:
	if not mobile: return true
	if mobile_phase==MobilePhase.STATIONARY:
		motion_wait = maxf(0.0,motion_wait-delta)
		# Complete the existing advertised burst before announcing a move. There
		# is no extra gun or attack budget: the vehicle reuses a normal battery.
		if motion_wait>0 or warning_time>0 or salvo_remaining>0: return true
		motion_origin = position
		motion_intent = motion_points[(motion_index+1)%motion_points.size()]
		motion_clock = 0.0
		mobile_phase = MobilePhase.ANNOUNCE
		_cancel_salvo(0.03+defense_stagger)
		_announce_mobile_move()
		return false
	_cancel_salvo(0.03+defense_stagger)
	motion_clock += maxf(0.0,delta)
	if mobile_phase==MobilePhase.ANNOUNCE:
		if motion_announcement_pending:
			_announce_mobile_move()
			motion_announcement_pending = false
		# Reuse the fixed muzzle card as a short ground corridor. Its far end is
		# the advertised destination; reset its pose before any gun warning.
		var corridor := motion_intent-position
		flare.position = Vector3(corridor.x*.5,visual_altitude+1.5,corridor.z*.5)
		flare.rotation.y = atan2(corridor.x,corridor.z)
		flare.scale = Vector3(0.55,1.0,maxf(1.0,corridor.length()/1.25))
		flare.show()
		flare.material_override.set_shader_parameter("strength",0.40+0.30*sin(motion_clock*TAU*3.0)*sin(motion_clock*TAU*3.0))
		if motion_clock>=MOVE_WARNING_SECONDS:
			mobile_phase = MobilePhase.MOVE
			motion_clock = 0.0
	elif mobile_phase==MobilePhase.MOVE:
		var progress := clampf(motion_clock/MOVE_SECONDS,0.0,1.0)
		position = motion_origin.lerp(motion_intent,smoothstep(0.0,1.0,progress))
		position.y = 0.0
		var direction := motion_intent-motion_origin
		if direction.length_squared()>0.001:
			motion_heading = lerp_angle(motion_heading,atan2(direction.x,direction.z),1.0-exp(-delta*5.0))
			visual.rotation.y = motion_heading
		if progress>=1.0:
			motion_index = (motion_index+1)%motion_points.size()
			mobile_phase = MobilePhase.SETTLE
			motion_clock = 0.0
	elif mobile_phase==MobilePhase.SETTLE:
		if motion_clock>=MOVE_SETTLE_SECONDS:
			mobile_phase = MobilePhase.STATIONARY
			motion_clock = 0.0
			motion_wait = MOVE_STATION_SECONDS+defense_stagger
	return false

func _announce_mobile_move() -> void:
	var raid := get_parent() as Node3D
	var goal := raid.to_global(motion_intent) if is_instance_valid(raid) else motion_intent
	movement_announced.emit(tactical_id,global_position,goal,MOVE_WARNING_SECONDS)

func _suspend_mobile() -> void:
	if not mobile: return
	# A respawn or offscreen interval must not resume an unannounced partial
	# move. Preserve the current point and the same seeded next destination.
	if mobile_phase in [MobilePhase.ANNOUNCE,MobilePhase.MOVE]:
		motion_origin = position
		mobile_phase = MobilePhase.ANNOUNCE
		motion_clock = 0.0
		motion_announcement_pending = true
	elif mobile_phase==MobilePhase.SETTLE:
		motion_clock = 0.0
	else:
		motion_wait = maxf(motion_wait,0.30+defense_stagger)

func _warning_duration() -> float:
	return lerpf(0.48,0.36,float(defense_level)/7.0)

func _outside_horizontal_view(combat: Node) -> bool:
	# Production uses the actual orthographic camera bounds, including the raid
	# zoom. Headless gameplay fixtures can omit the optional camera reference.
	var view_camera := combat.get("camera") as Camera3D
	if not is_instance_valid(view_camera): return false
	var viewport_size := view_camera.get_viewport().get_visible_rect().size
	var left := view_camera.project_position(Vector2.ZERO,1.0).x
	var right := view_camera.project_position(Vector2(viewport_size.x,0),1.0).x
	return global_position.x < minf(left,right)+0.6 or global_position.x > maxf(left,right)-0.6

func _cancel_salvo(recovery: float) -> void:
	warning_time = 0.0
	salvo_remaining = 0
	salvo_total = 0
	salvo_time = 0.0
	muzzle_time = 0.0
	cooldown = maxf(cooldown,recovery)
	if is_instance_valid(flare):
		flare.hide()
		if mobile:
			flare.position = Vector3(0.0,visual_altitude+1.5,0.32)
			flare.rotation = Vector3.ZERO
			flare.scale = Vector3.ONE

func _fire_volley(combat: Node) -> void:
	# Lock aim at the start of the warning, so an evasive move creates a reliable
	# escape lane. Twin barrels converge on that old aim instead of tracking.
	var progress := float(defense_level)/7.0
	var origin := global_position+Vector3(0,0.15,0)+_salvo_direction*0.55
	var fired := 0
	var volley_index := salvo_total-salvo_remaining
	if variant == "battery":
		var tangent := Vector3(_salvo_direction.z,0,-_salvo_direction.x)
		if rapid_fire:
			# Alternating barrels rake a narrow corridor around the locked aim.
			# Moving after the warning still escapes the complete burst.
			var side := -1.0 if volley_index%2==0 else 1.0
			var muzzle := origin+tangent*side*0.34
			var locked_lane := aim+tangent*side*0.70
			if combat._launch_enemy_round(muzzle,locked_lane,lerpf(14.0,17.0,progress)):
				fired += 1
		else:
			for side in [-1.0,1.0]:
				var muzzle: Vector3 = origin+tangent*side*0.34
				if combat._launch_enemy_round(muzzle,aim,lerpf(13.0,16.0,progress)):
					fired += 1
	else:
		var count := 5 if defense_level < 5 else 7
		var spread := deg_to_rad(15.0 if count==5 else 20.0)
		# Successive fans cross the first fan's gaps, but leave the outside lanes
		# open and use the same original aim throughout the attack.
		var sweep := lerpf(-1.0,1.0,float(volley_index)/float(salvo_total-1))*deg_to_rad(3.5)
		for index in range(count):
			var angle := lerpf(-spread,spread,float(index)/float(count-1))+sweep
			var direction := _salvo_direction.rotated(Vector3.UP,angle)
			if combat._launch_enemy_round(origin,origin+direction*32.0,lerpf(12.0,14.8,progress)):
				fired += 1
	# Exhaust a volley even if the bounded projectile pool is full: there is no
	# deferred backlog that could erupt when a projectile slot becomes free.
	salvo_remaining = maxi(0,salvo_remaining-1)
	if variant == "bunker": salvo_time = lerpf(0.28,0.22,progress)
	elif rapid_fire: salvo_time = lerpf(0.080,0.065,progress)
	else: salvo_time = lerpf(0.14,0.095,progress)
	if fired > 0:
		muzzle_time = 0.10
		if combat.has_method("play_ground_volley"): combat.play_ground_volley(variant,rapid_fire)
	if salvo_remaining == 0:
		var interval := lerpf(1.10,0.65,progress) if variant=="battery" else lerpf(1.45,0.90,progress)
		if variant=="battery" and rapid_fire: interval = lerpf(0.75,0.48,progress)
		cooldown = interval*combat.enemy_interval_scale

func take_damage(amount: float) -> void:
	if not alive or amount <= 0 or not is_finite(amount): return
	health = maxf(0.0,health-amount)
	hit_time = 0.09
	material.set_shader_parameter("hit_flash",1.0)
	material.set_shader_parameter("damage",1.0-float(health)/max_health)
	if health <= max_health/2:
		fire.show()
		fire.material_override.set_shader_parameter("strength",0.34)
	if health > 0: return
	alive = false
	collision_layer = 0
	_cancel_salvo(0.0)
	fire.show()
	fire.material_override.set_shader_parameter("strength",1.0)
	set_process(true)
	destroyed.emit(global_position)

func _process(delta: float) -> void:
	# Continue a bounded wreck animation even after the director stops alive actors.
	death_age += delta
	material.set_shader_parameter("hit_flash",maxf(0,1.0-death_age/0.09))
	assembly.rotation.z = lerpf(0.0,0.46,smoothstep(0.0,0.6,death_age))
	assembly.scale.y = lerpf(1.0,0.35,smoothstep(0.0,0.6,death_age))
	hull.scale.y = lerpf(1.0,0.72,smoothstep(0.0,0.5,death_age))
	fire.material_override.set_shader_parameter("age",age+death_age)
	fire.material_override.set_shader_parameter("strength",1.0-smoothstep(2.5,4.0,death_age))
	if death_age >= 4.0: retire()

func retire() -> void:
	alive = false
	collision_layer = 0
	_cancel_salvo(0.0)
	set_process(false)
	hide()
	queue_free()
