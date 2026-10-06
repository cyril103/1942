extends Area3D
## Forward flight in a scrolling world; altitude is visual, combat is on the XZ plane.
signal destroyed(at: Vector3)
const MODEL := preload("res://assets/enemies/bomber.glb")
const ENTRY_DURATION := 6.5
const PATROL_DURATION := 16.0
const BLAST_TIMES := [0.0, 0.14, 0.32, 0.50, 0.67, 0.84, 1.06]
const BLAST_OFFSETS := [Vector3(-0.63,0,1.0), Vector3(0.63,0,1.0), Vector3(0,0,0.4), Vector3(-1.25,0,0), Vector3(1.25,0,0), Vector3(0,0,-1.2), Vector3.ZERO]
var alive := true
var dying := false
var health := 10
var age := 0.0
var death_age := 0.0
var blast_count := 0
var entry := Vector3.ZERO
var anchor := Vector3.ZERO
var amplitude := 5.0
var direction := 1.0
var visual: Node3D
var propellers: Array[Node3D] = []
var muzzles: Array[MeshInstance3D] = []
var hit_material: ShaderMaterial
var hit_time := 0.0
var muzzle_time := 0.0
var cooldown := 0.8
var heading := PI
var bank := 0.0
var pitch := 0.0
var exit_origin := Vector3.ZERO
var exit_velocity := Vector3.ZERO
var previous_velocity := Vector3.ZERO

func _ready() -> void:
	entry = position
	rotation.y = PI
	collision_layer = 0
	collision_mask = 0
	monitoring = false
	# Separate fuselage and wing shapes avoid a large rectangular empty hit region.
	for dimensions in [Vector3(0.52,1,3.5), Vector3(3.9,1,0.7)]:
		var collider := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = dimensions
		collider.shape = shape
		add_child(collider)
	visual = Node3D.new()
	add_child(visual)
	visual.position.y = -1.8
	visual.scale = Vector3.ONE * 0.78
	var model := MODEL.instantiate()
	model.scale = Vector3.ONE * 0.24
	visual.add_child(model)
	hit_material = ShaderMaterial.new()
	hit_material.shader = preload("res://shaders/bomber_hit.gdshader")
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		mesh.material_overlay = hit_material
	for prop_name in ["Bomber_Propeller_L", "Bomber_Propeller_R"]:
		var prop: Node3D = model.find_child(prop_name, true, false)
		if prop: propellers.append(prop)
	var gun_material := StandardMaterial3D.new()
	gun_material.albedo_color = Color(0.08,0.09,0.10)
	gun_material.metallic = 0.8
	gun_material.roughness = 0.3
	for side in [-1,1]:
		var gun := MeshInstance3D.new()
		var barrel := CylinderMesh.new()
		barrel.top_radius = 0.022
		barrel.bottom_radius = 0.028
		barrel.height = 0.32
		barrel.radial_segments = 8
		gun.mesh = barrel
		gun.material_override = gun_material
		gun.position = Vector3(side*0.07,0.06,-1.66)
		gun.rotation.x = PI/2
		visual.add_child(gun)
		var flash := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(0.22,0.34)
		flash.mesh = plane
		var material := ShaderMaterial.new()
		material.shader = preload("res://shaders/bullet_impact.gdshader")
		flash.material_override = material
		flash.position = Vector3(side*0.07,0.08,-1.86)
		visual.add_child(flash)
		flash.hide()
		muzzles.append(flash)

func smoothest(p: float) -> float:
	p = clampf(p,0,1)
	return p*p*p*(10.0+p*(-15.0+6.0*p))

func advance(delta: float, combat: Node) -> void:
	if not alive: return
	for prop in propellers: prop.rotate_z(delta*62.0)
	hit_time = maxf(0,hit_time-delta)
	hit_material.set_shader_parameter("strength",clampf(hit_time/0.055,0,1))
	muzzle_time = maxf(0,muzzle_time-delta)
	for muzzle in muzzles: muzzle.visible = muzzle_time > 0
	if dying:
		_advance_destruction(delta,combat)
		return
	age += delta
	var before := position
	var previous_height := visual.position.y
	if age < ENTRY_DURATION:
		var blend := smoothest(age/ENTRY_DURATION)
		position = entry.lerp(anchor,blend)
		visual.position.y = lerpf(-1.8,0,blend)
		visual.scale = Vector3.ONE*lerpf(0.78,1,blend)
		collision_layer = 2 if visual.position.y > -0.15 else 0
	elif age < ENTRY_DURATION+PATROL_DURATION:
		var t := age-ENTRY_DURATION
		var envelope := smoothest(t/2.0)
		position.x = anchor.x+direction*amplitude*sin(t*TAU/8.0)*envelope
		position.z = anchor.z+0.45*sin(t*TAU/8.0)*envelope
		visual.position.y = 0
		visual.scale = Vector3.ONE
		collision_layer = 2
	else:
		var t := age-ENTRY_DURATION-PATROL_DURATION
		if exit_origin == Vector3.ZERO:
			exit_origin = position
			exit_velocity = previous_velocity
		position = exit_origin+exit_velocity*(1-exp(-t*2.0))/2.0+Vector3(0,0,-1.8*t*t)
		if t > 4.0:
			retire()
			return
	var velocity := (position-before)/maxf(delta,0.0001)
	previous_velocity = velocity
	# Add the forward airspeed hidden by the scrolling camera to calculate attitude.
	var air_velocity := velocity+Vector3(0,0,-4.5)
	var desired_heading := atan2(air_velocity.x,air_velocity.z)
	var change := clampf(wrapf(desired_heading-heading,-PI,PI),-delta,delta)
	heading += change
	rotation.y = heading
	bank = lerpf(bank,-clampf(atan(change/maxf(delta,0.001)*air_velocity.length()/9.8),-0.50,0.50),1-exp(-delta*4))
	pitch = lerpf(pitch,-atan2((visual.position.y-previous_height)/maxf(delta,0.001),air_velocity.length()),1-exp(-delta*5))
	visual.rotation = Vector3(pitch,0,bank)
	cooldown -= delta
	if age >= ENTRY_DURATION and age < ENTRY_DURATION+PATROL_DURATION and cooldown <= 0:
		var to_player: Vector3 = combat.player.global_position-global_position
		if combat.player.alive and to_player.normalized().dot(-global_basis.z) > 0.3:
			combat.fire_bomber(self)
			muzzle_time = 0.085
			cooldown = 1.15*combat.enemy_interval_scale

func get_rear_muzzles() -> Array[Vector3]:
	var positions: Array[Vector3] = []
	for muzzle in muzzles: positions.append(muzzle.global_position)
	return positions

func take_damage(amount: int) -> void:
	if not alive or dying or collision_layer == 0 or amount <= 0: return
	health = maxi(0,health-amount)
	hit_time = 0.10
	hit_material.set_shader_parameter("strength",1.0)
	if health == 0:
		dying = true
		muzzle_time = 0
		collision_layer = 0
		for muzzle in muzzles: muzzle.hide()
		destroyed.emit(global_position)

func _advance_destruction(delta: float, combat: Node) -> void:
	death_age += delta
	position += Vector3(previous_velocity.x*0.18,0,0.65)*delta
	visual.position.y -= delta*0.45
	visual.rotation.z += delta*0.32*direction
	while blast_count < BLAST_TIMES.size() and death_age >= BLAST_TIMES[blast_count]:
		var final_blast := blast_count == BLAST_TIMES.size()-1
		combat._explode(visual.to_global(BLAST_OFFSETS[blast_count]),1.55 if final_blast else 0.72,blast_count == 0 or final_blast)
		blast_count += 1
	if death_age > 1.08: visual.hide()
	if death_age > 1.4: retire()

func retire() -> void:
	alive = false
	collision_layer = 0
	hide()
	queue_free()
