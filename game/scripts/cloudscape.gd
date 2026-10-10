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
var shadow_altitude := SHADOW_ALTITUDE
var strength := .72
var evolution := 0.0
var recycle_count := 0
var wind := .13
var wind_phase := 0.0
var _random := RandomNumberGenerator.new()
var _bank_random: Array[RandomNumberGenerator] = []
var _half := Vector2(24,12.5)
var _tint := Color.WHITE

func _ready() -> void:
	for i in range(POOL_SIZE):
		_bank_random.append(RandomNumberGenerator.new())
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
	var a := camera.project_position(Vector2.ZERO,1.0)
	var b := camera.project_position(size,1.0)
	_half = Vector2(absf(b.x-a.x),absf(b.z-a.z))*.5
	for i in range(clouds.size()):
		if clouds[i].has_meta("base_size"):
			_size_bank(i)
			_place_bank(clouds[i])
		_sync_shadow(i)

func configure_sector(mission: Dictionary) -> void:
	_random.seed = int(mission.seed)+9017
	evolution = 0
	wind_phase = 0
	recycle_count = 0
	var biome: String = mission.biome
	wind = -.13 if int(mission.seed)%2 else .13
	strength = .70 if biome=="storm" else .76
	_tint = {"storm":Color(.70,.78,.87),"dusk":Color(1.0,.85,.72),"volcanic":Color(.89,.88,.86),"arctic":Color(.91,.97,1.0)}.get(biome,Color(1.0,.985,.96))
	# Scramble the opening across the entire width, including its center. Depth
	# is sampled independently: small groups and open patches have no route.
	var opening_offset := _random.randf()
	for i in range(POOL_SIZE):
		var rng := _bank_random[i]
		rng.seed = int(mission.seed)+9017+i*7919
		clouds[i].set_meta("variant",posmod(int(mission.seed)+i,8))
		var lane := fposmod(opening_offset+i*.618033989+rng.randf_range(-.055,.055),1.0)*1.9-.95
		var at_z := _half.y-rng.randf_range(2.0,maxf(82.0,_half.y*6.5))
		_spawn(i,at_z,lane)

func _spawn(index: int, at_z: float, opening_lane: float = INF) -> void:
	var cloud := clouds[index]
	var rng := _bank_random[index]
	var silhouette := int(cloud.get_meta("variant",index))
	var size := Vector2(rng.randf_range(7.0,10.5),rng.randf_range(5.5,8.5))
	if silhouette>=4:
		size = [Vector2(16,13),Vector2(18,9),Vector2(13,11),Vector2(15,10)][silhouette-4]
		size *= rng.randf_range(.90,1.06)
	cloud.set_meta("base_size",size)
	_size_bank(index)
	var lane := rng.randf_range(-.98,.98) if is_inf(opening_lane) else opening_lane
	cloud.set_meta("lane",lane)
	cloud.set_meta("wind_offset",rng.randf_range(0.0,TAU))
	cloud.set_meta("wind_amplitude",rng.randf_range(.25,.75))
	cloud.set_meta("wind_rate",rng.randf_range(.7,1.3))
	cloud.set_meta("wind_origin",wind_phase)
	cloud.position = Vector3(lane*_half.x,ALTITUDE-index*.035,at_z)
	_place_bank(cloud)
	# Opacity is atmospheric, never conditional on an actor, island or flight path.
	cloud.set_meta("density",rng.randf_range(.76,1.0)*(.72 if silhouette==7 else 1.0))
	var atlas := VARIETY_ATLAS if silhouette>=4 else ATLAS
	var variant := silhouette%4
	var cell := Vector2(variant%2,variant/2)
	cloud.material_override.set_shader_parameter("cloud_atlas",atlas)
	shadows[index].material_override.set_shader_parameter("cloud_atlas",atlas)
	cloud.material_override.set_shader_parameter("atlas_cell",cell)
	cloud.material_override.set_shader_parameter("cloud_tint",_tint)
	cloud.material_override.set_shader_parameter("phase",rng.randf_range(0,TAU))
	cloud.material_override.set_shader_parameter("evolution",evolution)
	shadows[index].material_override.set_shader_parameter("atlas_cell",cell)
	_sync_shadow(index)
	_update_opacity(index)

func _sync_shadow(index: int) -> void:
	shadows[index].position = Vector3(clouds[index].position.x+.65,shadow_altitude,clouds[index].position.z+.85)

func _place_bank(cloud: MeshInstance3D) -> void:
	var offset := float(cloud.get_meta("wind_offset"))
	var phase := (wind_phase-float(cloud.get_meta("wind_origin")))*float(cloud.get_meta("wind_rate"))
	cloud.position.x = float(cloud.get_meta("lane"))*_half.x+float(cloud.get_meta("wind_amplitude"))*(sin(phase+offset)-sin(offset))

func _size_bank(index: int) -> void:
	# Reapply the original size on viewport changes; repeated resizes cannot shrink it.
	var size: Vector2 = clouds[index].get_meta("base_size")
	size *= minf(1.0,_half.x/16.0)
	(clouds[index].mesh as PlaneMesh).size = size
	(shadows[index].mesh as PlaneMesh).size = size*1.07
	clouds[index].set_meta("radius",size.y*.5)

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
	wind_phase += delta*wind
	for i in range(POOL_SIZE):
		var cloud := clouds[i]
		_place_bank(cloud)
		cloud.material_override.set_shader_parameter("evolution",evolution)
		_sync_shadow(i)
		if cloud.position.z-float(cloud.get_meta("radius"))>_half.y+2:
			# Each bank has its own weather stream. Nothing is pushed behind another
			# object; independent offscreen delays create both clusters and clear sky.
			var next_z := -_half.y-10.0-_bank_random[i].randf_range(5.0,60.0)
			cloud.set_meta("variant",(int(cloud.get_meta("variant"))+3)%8)
			_spawn(i,next_z)
			recycle_count += 1
