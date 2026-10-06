extends Area3D
signal destroyed(at: Vector3)
var alive := true
var health := 12
var age := 0.0
var variant := 0
var cooldown := 2.0
var warning_time := 0.0
var aim := Vector3.ZERO
var visual: Node3D
var flare: MeshInstance3D
var hit_material: ShaderMaterial
var hit_time := 0.0

func _ready() -> void:
	collision_layer = 2
	collision_mask = 0
	monitoring = false
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	# Include both wing-mounted tracers when the player centres the hull.
	shape.size = Vector3(1.2,1,4.3)
	collider.shape = shape
	add_child(collider)
	visual = Node3D.new()
	visual.position.y = -2.1
	visual.rotation.y = PI
	add_child(visual)
	var model = load("res://assets/campaign/models/destroyer.glb").instantiate()
	model.scale = Vector3.ONE*0.36
	visual.add_child(model)
	preload("res://scripts/campaign/materials.gd").apply(model)
	hit_material = ShaderMaterial.new()
	hit_material.shader = preload("res://shaders/bomber_hit.gdshader")
	for mesh in visual.find_children("*","MeshInstance3D",true,false): mesh.material_overlay = hit_material
	var wake := MeshInstance3D.new()
	var wake_mesh := PlaneMesh.new()
	wake_mesh.size = Vector2(3.2,8.5)
	wake.mesh = wake_mesh
	wake.position = Vector3(0,-2.85,2.7)
	var wake_material := ShaderMaterial.new()
	wake_material.shader = preload("res://shaders/naval_wake.gdshader")
	wake.material_override = wake_material
	add_child(wake)
	flare = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(0.8,0.8)
	flare.mesh = plane
	flare.position = Vector3(0,-1.6,-0.6)
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/bullet_impact.gdshader")
	flare.material_override = material
	add_child(flare)
	flare.hide()

func advance(delta: float, combat: Node) -> void:
	if not alive: return
	age += delta
	position.z += delta*1.7
	visual.rotation.z = sin(age*1.5)*0.02
	hit_time = maxf(0,hit_time-delta)
	hit_material.set_shader_parameter("strength",hit_time/0.08)
	if position.z > combat.screen_bottom()+3:
		retire()
		return
	if position.z < combat.screen_top()+1.5: return
	if warning_time > 0:
		warning_time -= delta
		flare.show()
		flare.scale = Vector3.ONE*(0.4+0.5*(1-warning_time/0.5))
		if warning_time <= 0:
			var origin := global_position+Vector3(0,0.2,0.5)
			var direction := (aim-origin).normalized()
			for angle in [-0.15,0.0,0.15]:
				combat._launch_enemy_round(origin,origin+direction.rotated(Vector3.UP,angle)*10,9.0)
			flare.hide()
	else:
		cooldown -= delta
		if cooldown <= 0 and combat.player.alive:
			aim = combat.player.global_position
			warning_time = 0.5
			cooldown = (3.1-variant*0.2)*combat.enemy_interval_scale

func take_damage(amount: int) -> void:
	if not alive or amount <= 0: return
	health -= amount
	hit_time = 0.08
	if health <= 0:
		destroyed.emit(global_position)
		retire()

func retire() -> void:
	if not alive: return
	alive = false
	collision_layer = 0
	hide()
	queue_free()
