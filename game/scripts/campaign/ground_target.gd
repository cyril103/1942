extends Area3D
## Textured Blender ground installations: two shared meshes, one atlas, two VFX cards.
## The director scrolls every target, including its short-lived wreck, with the land.
signal destroyed(at: Vector3)

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

var variant := "fuel"
var health := 0
var max_health := 0
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
	var model: Node3D = MODELS[variant].instantiate()
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
	if not alive: return
	age += delta
	hit_time = maxf(0,hit_time-delta)
	material.set_shader_parameter("hit_flash",hit_time/0.09)
	fire.material_override.set_shader_parameter("age",age)
	if variant == "radar": assembly.rotation.y += delta*0.85
	if global_position.z > combat.screen_bottom()+4.0:
		retire()
		return
	if jammed:
		_cancel_salvo(0.24+defense_stagger)
		return
	if variant not in ["battery","bunker"]: return
	assembly.rotation.y = lerp_angle(assembly.rotation.y,turret_yaw,1.0-exp(-delta*7.0))
	if combat.game_over or not is_instance_valid(combat.player) or not combat.player.alive or not combat.player.controls_enabled:
		_cancel_salvo(0.24+defense_stagger)
		return
	# Begin the tell as soon as the gun enters the screen: the former two-unit
	# inset plus long delay let incoming player fire erase it before any shot.
	if global_position.z < combat.screen_top()+0.25 or global_position.z > combat.player.global_position.z-1.4:
		_cancel_salvo(0.03+defense_stagger)
		return
	if _outside_horizontal_view(combat):
		_cancel_salvo(0.03+defense_stagger)
		return
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
	if is_instance_valid(flare): flare.hide()

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

func take_damage(amount: int) -> void:
	if not alive or amount <= 0: return
	health = maxi(0,health-amount)
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
