extends Node3D
## Prelit volume impostors: fixed pool, one cloud card + one soft shadow per bank.
const ATLAS := preload("res://assets/environment/clouds/cumulus-refined-atlas.png")
const VARIETY_ATLAS := preload("res://assets/environment/clouds/cumulus-variety-atlas.png")
const CLOUD_SHADER := preload("res://shaders/cumulus.gdshader")
const SHADOW_SHADER := preload("res://shaders/cloud_shadow.gdshader")
const POOL_SIZE := 8
const ALTITUDE := -1.25
const SHADOW_ALTITUDE := -2.94
@export var seascape: Node3D
@export var camera: Camera3D
var clouds: Array[MeshInstance3D] = []
var shadows: Array[MeshInstance3D] = []
var enabled := true
var strength := .72
var evolution := 0.0
var recycle_count := 0
var wind := .13
var wind_phase := 0.0
var _random := RandomNumberGenerator.new()
var _next_variant := 0
var _half := Vector2(24,12.5)
var _tint := Color.WHITE

func _ready() -> void:
	for i in range(POOL_SIZE):
		for shadow in [false,true]:
			var card := MeshInstance3D.new()
			card.name = ("Shadow" if shadow else "Cumulus")+str(i)
			card.mesh = PlaneMesh.new()
			card.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var material := ShaderMaterial.new()
			material.shader = SHADOW_SHADER if shadow else CLOUD_SHADER
			material.set_shader_parameter("cloud_atlas",ATLAS)
			card.material_override = material
			add_child(card)
			if shadow: shadows.append(card)
			else: clouds.append(card)
	get_viewport().size_changed.connect(_update_view)
	_update_view()
	configure_sector({"seed":1942,"biome":"coral"})
	seascape.scrolled.connect(_on_scrolled)

func _update_view() -> void:
	var size := get_viewport().get_visible_rect().size
	if size.x<=0 or size.y<=0: return
	var a := camera.project_position(Vector2.ZERO,camera.position.y)
	var b := camera.project_position(size,camera.position.y)
	_half = Vector2(absf(b.x-a.x),absf(b.z-a.z))*.5
	for i in range(clouds.size()):
		clouds[i].position.x = float(clouds[i].get_meta("lane",0.0))*_half.x
		if clouds[i].has_meta("radius"): _place_bank(clouds[i])
		_sync_shadow(i)

func configure_sector(mission: Dictionary) -> void:
	_random.seed = int(mission.seed)+9017
	_next_variant = int(mission.seed)%8
	evolution = 0
	wind_phase = 0
	var biome: String = mission.biome
	wind = -.13 if int(mission.seed)%2 else .13
	strength = .70 if biome=="storm" else .76
	_tint = {"storm":Color(.70,.78,.87),"dusk":Color(1.0,.85,.72),"volcanic":Color(.89,.88,.86),"arctic":Color(.91,.97,1.0)}.get(biome,Color(1.0,.985,.96))
	for cloud in clouds: cloud.set_meta("placed",false)
	for i in range(POOL_SIZE):
		_spawn(i,7.0-i*9.0)

func _spawn(index: int, at_z: float) -> void:
	var cloud := clouds[index]
	var size := Vector2(_random.randf_range(8.0,11.0),_random.randf_range(6.5,9.0))
	if _next_variant>=4:
		size = [Vector2(16,13),Vector2(18,9),Vector2(13,11),Vector2(15,10)][_next_variant-4]
		size *= _random.randf_range(.92,1.08)
	# Proportional cap avoids covering the whole playfield on narrow displays.
	size *= minf(1.0,_half.x/16.0)
	(cloud.mesh as PlaneMesh).size = size
	(shadows[index].mesh as PlaneMesh).size = size*1.07
	var lane := _random.randf_range(-.72,.72)
	cloud.set_meta("lane",lane)
	cloud.set_meta("radius",size.y*.5)
	cloud.position = Vector3(lane*_half.x,ALTITUDE-index*.035,at_z)
	_place_bank(cloud)
	# Separate complete card footprints, including shadow and wind margins.
	# Placement is settled offscreen; opacity never responds to the camera.
	for attempt in range(POOL_SIZE*2):
		var next_z := cloud.position.z
		for other in clouds:
			if other==cloud or not other.get_meta("placed",false): continue
			var other_size := (other.mesh as PlaneMesh).size
			if absf(cloud.position.x-other.position.x)<(size.x+other_size.x)*.535+1.6:
				if absf(next_z-other.position.z)<(size.y+other_size.y)*.535+1.0:
					next_z = minf(next_z,other.position.z-(size.y+other_size.y)*.535-1.0)
		if is_equal_approx(next_z,cloud.position.z): break
		cloud.position.z = next_z
		_place_bank(cloud)
	cloud.set_meta("placed",true)
	cloud.set_meta("variant",_next_variant)
	cloud.set_meta("density",.72 if _next_variant==7 else 1.0)
	var atlas := VARIETY_ATLAS if _next_variant>=4 else ATLAS
	var variant := _next_variant%4
	var cell := Vector2(variant%2,variant/2)
	cloud.material_override.set_shader_parameter("cloud_atlas",atlas)
	shadows[index].material_override.set_shader_parameter("cloud_atlas",atlas)
	cloud.material_override.set_shader_parameter("atlas_cell",cell)
	cloud.material_override.set_shader_parameter("cloud_tint",_tint)
	cloud.material_override.set_shader_parameter("phase",_random.randf_range(0,TAU))
	shadows[index].material_override.set_shader_parameter("atlas_cell",cell)
	_next_variant = (_next_variant+1)%8
	_sync_shadow(index)
	_update_opacity(index)

func _sync_shadow(index: int) -> void:
	shadows[index].position = Vector3(clouds[index].position.x+.65,SHADOW_ALTITUDE,clouds[index].position.z+.85)

func _place_bank(cloud: MeshInstance3D) -> void:
	# Reserve the complete curved carrier approach before a bank enters the view.
	# Scroll distance and bank Z advance together, keeping this envelope stationary.
	var size := (cloud.mesh as PlaneMesh).size
	var span := size.y*.5+15.0
	var low := INF
	var high := -INF
	for step in range(33):
		var x: float = seascape.channel_center(cloud.position.z+lerpf(-span,span,step/32.0))
		low = minf(low,x)
		high = maxf(high,x)
	var clearance := 10.0+size.x*.5+1.0+span/32.0*.6
	var left := low-clearance
	var right := high+clearance
	var side := -1.0 if left+_half.x>_half.x-right else 1.0
	if minf(left+_half.x,_half.x-right)>0:
		side = -1.0 if float(cloud.get_meta("lane",0.0))<0 else 1.0
	cloud.position.x = (left if side<0 else right)+side*absf(float(cloud.get_meta("lane",0.0)))*2.0
	cloud.set_meta("anchor_x",cloud.position.x)
	cloud.set_meta("wind_origin",sin(wind_phase))

func _update_opacity(index: int) -> void:
	var density: float = clouds[index].get_meta("density",1.0)
	clouds[index].material_override.set_shader_parameter("opacity",strength*density)
	shadows[index].material_override.set_shader_parameter("opacity",.17*density)

func _on_scrolled(distance: float) -> void:
	for i in range(POOL_SIZE):
		clouds[i].position.z += distance
		_sync_shadow(i)

func _physics_process(delta: float) -> void:
	visible = enabled
	if not enabled: return
	evolution = fposmod(evolution+delta*.14,TAU*10.0)
	wind_phase = fposmod(wind_phase+delta*wind,TAU)
	for i in range(POOL_SIZE):
		var cloud := clouds[i]
		cloud.position.x = float(cloud.get_meta("anchor_x"))+.4*(sin(wind_phase)-float(cloud.get_meta("wind_origin")))
		cloud.material_override.set_shader_parameter("evolution",evolution)
		_sync_shadow(i)
		if cloud.position.z-float(cloud.get_meta("radius"))>_half.y+2:
			var next_z := -_half.y-12.0
			for other in clouds: next_z = minf(next_z,other.position.z-9.0)
			_spawn(i,next_z)
			recycle_count += 1
