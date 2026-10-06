extends Area3D
signal defeated
const MODELS := {"bomber":"res://assets/enemies/bomber.glb","destroyer":"res://assets/campaign/models/destroyer.glb","squadron":"res://assets/enemies/bomber.glb","fortress":"res://assets/campaign/models/fortress.glb","battleship":"res://assets/campaign/models/battleship.glb","ace":"res://assets/enemies/zero.glb","carrier":"res://assets/campaign/models/carrier.glb","citadel":"res://assets/campaign/models/fortress.glb"}
const NAMES := {"bomber":"KESTREL • bombardier de commandement","destroyer":"KUROGANE • croiseur lourd","squadron":"RAIDEN • escadre de choc","fortress":"TENRYU • forteresse volante","battleship":"ONYX • cuirassé d'assaut","ace":"AKAI • l'as écarlate","carrier":"SHIRO • porte-avions","citadel":"DAWNBREAKER • dernier rempart"}
var kind := "bomber"
var health := 260
var max_health := 260
var alive := true
var dying := false
var age := 0.0
var death_age := 0.0
var cooldown := 1.0
var phase := 0
var volley := 0
var flash_time := 0.0
var telegraph := 0.0
var telegraph_target := Vector3.ZERO
var visual: Node3D
var flare: MeshInstance3D
var hit_material: ShaderMaterial
var props: Array[Node3D] = []
var combat: Node
var blast_cursor := 0
var naval := false

func _ready() -> void:
	collision_layer = 0
	collision_mask = 0
	monitoring = false
	naval = kind in ["destroyer","battleship","carrier"]
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.3,1,6.8) if naval else Vector3(6.2,1,2.4)
	if kind == "ace": shape.size = Vector3(2.3,1,1.6)
	collider.shape = shape
	add_child(collider)
	visual = Node3D.new()
	visual.rotation.y = PI if naval else 0.0
	visual.position.y = -2.0 if naval else 0.0
	add_child(visual)
	var model = load(MODELS[kind]).instantiate()
	var model_scale := 0.43
	if naval: model_scale = 0.64
	if kind in ["fortress","citadel"]: model_scale = 0.34
	if kind == "ace": model_scale = 0.24
	model.scale = Vector3.ONE*model_scale
	visual.add_child(model)
	preload("res://scripts/campaign/materials.gd").apply(model)
	hit_material = ShaderMaterial.new()
	hit_material.shader = preload("res://shaders/bomber_hit.gdshader")
	for mesh in model.find_children("*","MeshInstance3D",true,false):
		mesh.material_overlay = hit_material
		if "Propeller" in mesh.name: props.append(mesh)
	if naval:
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
	plane.size = Vector2(1.6,1.6)
	flare.mesh = plane
	flare.position.y = 0.3
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/bullet_impact.gdshader")
	flare.material_override = material
	add_child(flare)
	flare.hide()

func advance(delta: float, director: Node) -> void:
	if not alive: return
	age += delta
	flash_time = maxf(0,flash_time-delta)
	hit_material.set_shader_parameter("strength",flash_time/0.07)
	for prop in props: prop.rotate_z(delta*55)
	if dying:
		death_age += delta
		visual.rotation.z += delta*0.13
		while blast_cursor < 10 and death_age >= blast_cursor*0.18:
			var offset := Vector3(sin(blast_cursor*2.4)*2.0,0,cos(blast_cursor*1.7)*1.7)
			director.combat._explode(global_position+offset,1.1 if blast_cursor<9 else 2.0,blast_cursor in [0,4,9])
			blast_cursor += 1
		if death_age > 1.85: visual.hide()
		if death_age > 2.6:
			alive = false
			defeated.emit()
			queue_free()
		return
	if age < 4:
		position.z = lerpf(-17.0,-6.3,smoothstep(0,4,age))
		return
	collision_layer = 2
	phase = mini(2,int((1-float(health)/max_health)*3))
	var frequency := 0.38 if naval else (0.72 if kind == "ace" else 0.48)
	var amplitude := 2.0 if naval else (5.0 if kind == "ace" else 3.3)
	var half_width := absf(combat.camera.project_position(Vector2.ZERO,combat.camera.position.y).x)
	amplitude = minf(half_width*(.16 if naval else .43),4.0 if naval else (12.0 if kind=="ace" else 10.0))
	position.x = sin((age-4)*frequency)*amplitude
	position.z = -6.3+sin((age-4)*0.33)*0.65
	if not naval:
		visual.rotation.z = -cos((age-4)*frequency)*0.22
		if kind == "ace":
			visual.rotation.y = atan2(cos((age-4)*frequency)*amplitude*frequency,4.5)
			visual.rotation.z = sin((age-4)*frequency)*0.55
	if telegraph > 0:
		telegraph -= delta
		flare.show()
		flare.scale = Vector3.ONE*(0.4+0.7*(1-telegraph/0.6))
		if telegraph <= 0:
			_fire(director)
			flare.hide()
	else:
		cooldown -= delta
		if cooldown <= 0 and director.player.alive:
			telegraph = 0.6
			telegraph_target = director.player.global_position
			cooldown = (1.55-phase*0.18)*director.combat.enemy_interval_scale

func _fire(director: Node) -> void:
	volley += 1
	var origin := global_position+Vector3(0,0.22,1.0)
	var aim := Vector3(telegraph_target.x-origin.x,0,telegraph_target.z-origin.z).normalized()
	var sector: int = director.mission.sector
	var count := mini(3+phase*2,int(director.balance.boss_fan))
	var speed := 6.2+sector*0.25
	if phase == 2 and volley%3 == 0 and director.balance.boss_ring:
		# The rotating ring always retains a wide safe gap toward the bottom.
		for i in range(12):
			if i in [2,3]: continue
			var angle := i*TAU/12+sin(volley*0.6)*0.35
			var direction := Vector3(sin(angle),0,cos(angle))
			director.combat._launch_enemy_round(origin,origin+direction*10,speed*0.82)
	else:
		var sweep := sin(volley*0.8)*0.45 if kind in ["fortress","citadel","carrier"] else 0.0
		for i in range(count):
			var angle := (i-(count-1)*0.5)*0.16+sweep
			director.combat._launch_enemy_round(origin,origin+aim.rotated(Vector3.UP,angle)*10,speed)
	if kind in ["destroyer","battleship"] and phase >= 1:
		for side in [-1,1]:
			var gun_origin := origin+Vector3(side*0.75,0,2.0)
			for i in range(mini(2+phase,int(director.balance.boss_flank))):
				var angle: float = side*(0.22+i*0.23)+sin(volley*0.7)*0.2
				var direction := Vector3(sin(angle),0,cos(angle))
				director.combat._launch_enemy_round(gun_origin,gun_origin+direction*10,speed*0.8)
	if kind == "ace" and phase >= 1:
		for side in [-1,1]:
			var gun_origin := origin+Vector3(side*0.7,0,0)
			director.combat._launch_enemy_round(gun_origin,gun_origin+aim*10,speed*1.25)
	if kind in ["squadron","carrier"] and volley%5 == 0: director.spawn_reinforcement()

func take_damage(amount: int) -> void:
	if not alive or dying or collision_layer == 0 or amount<=0: return
	health = maxi(0,health-amount)
	flash_time = 0.07
	if health == 0:
		dying = true
		collision_layer = 0
		telegraph = 0
		flare.hide()
		combat.clear_enemy_bullets()
