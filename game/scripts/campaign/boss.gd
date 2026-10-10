extends Area3D
signal defeated
signal weak_points_neutralized
const PATTERNS := preload("res://scripts/campaign/boss_patterns.gd")
const MODELS := {"bomber":"res://assets/enemies/bomber.glb","destroyer":"res://assets/campaign/models/destroyer.glb","squadron":"res://assets/enemies/bomber.glb","fortress":"res://assets/campaign/models/fortress.glb","battleship":"res://assets/campaign/models/battleship.glb","ace":"res://assets/enemies/zero.glb","carrier":"res://assets/campaign/models/carrier.glb","citadel":"res://assets/campaign/models/fortress.glb"}
const NAMES := {"bomber":"KESTREL • bombardier de commandement","destroyer":"KUROGANE • croiseur lourd","squadron":"RAIDEN • escadre de choc","fortress":"TENRYU • forteresse volante","battleship":"ONYX • cuirassé d'assaut","ace":"AKAI • l'as écarlate","carrier":"SHIRO • porte-avions","citadel":"DAWNBREAKER • dernier rempart"}
var kind := "bomber"
var health := 260.0
var max_health := 260.0
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
var component_health: Array[float] = [24.0,24.0]
var component_visuals: Array[MeshInstance3D] = []
var component_fires: Array[MeshInstance3D] = []
var transition_time := 0.0
var previous_phase := 0
var attack_label := "APPROCHE"
var attack_hint := "REPÉREZ LES DEUX POINTS FAIBLES"
var attack_progress := 0.0
var attack_state := "arrival"
var attack_plan: Dictionary = {}
var pending_rounds: Array[Dictionary] = []
var burst_age := 0.0
var warning_duration := .75
var motion_age := 0.0

func presentation() -> Dictionary:
	return {"label":attack_label,"hint":attack_hint,"progress":attack_progress,"state":attack_state,"phase":phase}

func component_position(index: int) -> Vector3:
	return Vector3((-1.0 if index==0 else 1.0)*.65,-1.5,1.8) if naval else Vector3((-1.0 if index==0 else 1.0)*(.65 if kind=="ace" else 1.15),.15,0)

func take_hit_at(amount: float, at: Vector3) -> void:
	if not alive or dying or collision_layer==0 or transition_time>0 or amount<=0 or not is_finite(amount): return
	var local := to_local(at)
	for i in range(2):
		var target := component_position(i)
		if component_health[i]>0 and absf(local.x-target.x)<(.6 if naval or kind=="ace" else .85):
			component_health[i] = maxf(0.0,component_health[i]-amount)
			if component_health[i]==0:
				component_visuals[i].hide()
				component_fires[i].show()
				combat._explode(to_global(target),.8)
				if is_instance_valid(combat.campaign_driver):
					combat.campaign_driver.feedback = "POINT FAIBLE NEUTRALISÉ  /  DÉFENSE RÉDUITE"
					combat.campaign_driver.feedback_time = 2
				if component_health[0]==0 and component_health[1]==0:
					weak_points_neutralized.emit()
			take_damage(amount*2)
			return
	take_damage(amount)

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
	component_health = [float(maxi(12,int(max_health)/12)),float(maxi(12,int(max_health)/12))]
	for i in range(2):
		var part := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = .24
		mesh.bottom_radius = .32
		mesh.height = .18
		part.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(.28,.33,.35)
		mat.metallic = .6
		mat.emission_enabled = true
		mat.emission = Color(.25,.07,.01)
		part.material_override = mat
		part.position = component_position(i)
		add_child(part)
		if not naval: part.hide()
		component_visuals.append(part)
		var fire := preload("res://scripts/campaign/combat_detail.gd").make_card(1,Vector2(1.3,2.6))
		fire.position = part.position+Vector3(0,.7,.5)
		add_child(fire)
		fire.hide()
		component_fires.append(fire)

func _hide_warning() -> void:
	flare.hide()

func _cancel_attack() -> void:
	telegraph = 0.0
	attack_progress = 0.0
	attack_plan.clear()
	pending_rounds.clear()
	_hide_warning()

func _plan_attack(director: Node) -> Dictionary:
	return PATTERNS.build(kind,phase,volley+1,global_position+Vector3(0,.22,1),telegraph_target,int(director.mission.sector),director.balance,component_health)

func _begin_attack(director: Node) -> void:
	telegraph_target = director.player.global_position
	attack_plan = _plan_attack(director)
	attack_label = str(attack_plan.label)
	attack_hint = str(attack_plan.hint)
	warning_duration = float(attack_plan.warning)
	telegraph = warning_duration
	attack_progress = 0.0
	attack_state = "charging"
	# The HUD and this local glow announce the locked attack without drawing
	# projectile trajectories across the arena. Planning and timing stay intact.
	flare.show()
	flare.scale = Vector3.ONE*.4

func _release_rounds(director: Node) -> void:
	while not pending_rounds.is_empty() and float(pending_rounds[0].delay)<=burst_age+.00001:
		var round: Dictionary = pending_rounds.pop_front()
		var component := int(round.component)
		if component>=0 and component_health[component]<=0: continue
		var origin: Vector3 = round.origin
		director.combat._launch_enemy_round(origin,origin+Vector3(round.direction)*10,float(round.speed))
	if pending_rounds.is_empty(): attack_state = "recovery"

func advance(delta: float, director: Node) -> void:
	if not alive: return
	age += delta
	for fire in component_fires:
		if fire.visible: fire.material_override.set_shader_parameter("age",age)
	flash_time = maxf(0,flash_time-delta)
	hit_material.set_shader_parameter("strength",flash_time/0.07)
	for prop in props: prop.rotate_z(delta*55)
	if dying:
		if naval: combat.navigate_naval(self)
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
		if naval: combat.navigate_naval(self)
		return
	collision_layer = 2
	phase = mini(2,int((1-float(health)/max_health)*3))
	if phase!=previous_phase:
		previous_phase = phase
		transition_time = 1.2
		_cancel_attack()
		attack_state = "transition"
		attack_label = "RECONFIGURATION"
		attack_hint = "REPLACEZ-VOUS AVANT LA PROCHAINE OFFENSIVE"
		cooldown = maxf(cooldown,.7)
		combat.clear_enemy_bullets()
		director.feedback = "PHASE %d  /  %s" % [phase+1,["APPROCHE","DÉFENSE RENFORCÉE","DERNIÈRE OFFENSIVE"][phase]]
		director.feedback_time = 2
	if transition_time>0:
		transition_time = maxf(0,transition_time-delta)
		return
	if not director.player.alive:
		_cancel_attack()
		attack_state = "recovery"
		cooldown = maxf(cooldown,.7)
		return
	if telegraph>0:
		telegraph = maxf(0.0,telegraph-delta)
		attack_progress = clampf(1.0-telegraph/warning_duration,0.0,1.0)
		flare.scale = Vector3.ONE*(.4+.7*attack_progress)
		if telegraph<=0:
			_fire(director)
			_hide_warning()
		return
	if not pending_rounds.is_empty():
		burst_age += delta
		cooldown = maxf(0.0,cooldown-delta)
		_release_rounds(director)
		return
	attack_state = "recovery"
	attack_progress = 0.0
	motion_age += delta
	var frequency := 0.38 if naval else (0.72 if kind == "ace" else 0.48)
	var amplitude := 2.0 if naval else (5.0 if kind == "ace" else 3.3)
	var half_width := absf(combat.camera.project_position(Vector2.ZERO,1.0).x)
	amplitude = minf(half_width*(.16 if naval else .43),4.0 if naval else (12.0 if kind=="ace" else 10.0))
	position.x = sin(motion_age*frequency)*amplitude
	position.z = -6.3+sin(motion_age*0.33)*0.65
	if naval: combat.navigate_naval(self,sin(motion_age*frequency)*1.2)
	if not naval:
		visual.rotation.z = -cos(motion_age*frequency)*0.22
		if kind == "ace":
			visual.rotation.y = atan2(cos(motion_age*frequency)*amplitude*frequency,4.5)
			visual.rotation.z = sin(motion_age*frequency)*0.55
	cooldown -= delta
	if cooldown<=0: _begin_attack(director)

func _fire(director: Node) -> void:
	if not alive or dying or transition_time>0 or not director.player.alive: return
	if attack_plan.is_empty(): attack_plan = _plan_attack(director)
	volley += 1
	attack_label = str(attack_plan.label)
	attack_hint = str(attack_plan.hint)
	pending_rounds.assign(attack_plan.rounds)
	attack_plan = {}
	burst_age = 0.0
	attack_state = "firing"
	attack_progress = 1.0
	cooldown = (1.55-phase*.18)*director.combat.enemy_interval_scale
	_release_rounds(director)
	if kind in ["squadron","carrier"] and volley%5 == 0: director.spawn_reinforcement()

func take_damage(amount: float) -> void:
	if not alive or dying or collision_layer == 0 or amount<=0 or transition_time>0 or not is_finite(amount): return
	health = maxf(0.0,health-amount)
	flash_time = 0.07
	if health == 0:
		dying = true
		collision_layer = 0
		_cancel_attack()
		attack_state = "defeated"
		attack_label = "CIBLE NEUTRALISÉE"
		attack_hint = ""
		combat.clear_enemy_bullets()
