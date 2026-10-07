extends Node3D
## A finite, prebuilt coastal battlefield. One shared scroll moves terrain,
## installations and wrecks; it must fully clear the carrier approach.
const TARGET := preload("res://scripts/campaign/ground_target.gd")
const TERRAIN := preload("res://scripts/campaign/assault_terrain.gd")
const LABELS := {"fuel":"CARBURANT", "radar":"RADAR", "battery":"DCA", "bunker":"BUNKER", "runway":"HANGAR"}
var director: Node
var sea: Node3D
var terrain: Node3D
var targets: Array[Area3D] = []
var deployed := false
var cleared := false
var kills := 0
var radar_kills := 0
var escaped := 0
var jam_remaining := 0.0
var low_flight := 0.0
var airspace_closed := false
var length := 120.0
var width := 52.0
var deployment_distance := 0.0
var quality := 1
var supply_drops := 0
var next_supply_kill := 3
var presentation_altitude := 0.0
var cruise_camera_height := 35.0
var cruise_camera_size := 25.0
const LOW_ALTITUDE := -5.8
const LOW_CAMERA_HEIGHT := -3.2
const LOW_CAMERA_SIZE := 21.0

func _ready() -> void:
	name = "GroundAssault"
	sea = director.cockpit.flight.get_node("Seascape")
	cruise_camera_height = director.combat.camera.position.y
	cruise_camera_size = director.combat.camera.size
	sea.ocean.position.y = -9.4
	director.details.water_altitude = -9.1
	# This sortie uses one authored landmass. Remove the separate island cards
	# before the first frame so they cannot intersect its incoming coastline.
	for island in sea.islands: island.hide()
	director.cockpit.flight.get_node("KeyLight").shadow_opacity = .60
	director.cockpit.flight.get_node("Clouds").shadow_altitude = TERRAIN.PLATEAU_Y+.025
	width = maxf(40,sea._view_half.x*2+14)
	length = (float(director.mission.duration)-43.0)*float(director.mission.scroll)*1.18
	position.z = -10000
	terrain = TERRAIN.new()
	add_child(terrain)
	terrain.configure(director.mission,width,length)
	terrain.set_ground_detail(preload("res://assets/environment/raid-v2/coral-grass-detail.png"))
	terrain.set_ocean_parameter("ocean_texture",sea.OCEAN_TEXTURE)
	for parameter in ["ocean_tint","sea_desaturation","tile_size"]:
		terrain.set_ocean_parameter(parameter,sea.ocean_material.get_shader_parameter(parameter))
	_build_targets()
	sea.scrolled.connect(_on_scrolled)

func _build_targets() -> void:
	var rows := int(director.mission.ground_count)/5
	var safe_x := minf(width*.33-2.3,sea._view_half.x*LOW_CAMERA_SIZE/cruise_camera_size-2.3)
	for row in range(rows):
		var z := lerpf(length*.5-16,-length*.5+16,float(row)/maxi(1,rows-1))
		var shift: float = [-.7,.6,-.2,.7,-.6,.2,-.5,.6,.0][row%9]
		for side in range(5):
			var target := TARGET.new()
			target.variant = "battery" if side!=2 else ["fuel","fuel","runway"][row%3]
			# The opening line can fight before the first radar's tactical shutdown.
			if side==2 and row in [1,rows-2]: target.variant = "radar"
			if side in [0,4] and (row+side)%3!=0: target.variant = "bunker"
			target.rapid_fire = side==1
			var x: float = [-safe_x*.85,-4.2,0.0,4.2,safe_x*.85][side]+shift
			# Keep five staggered positions across the clearing, with an open strip.
			if absf(z)<minf(30,length*.22)+6:
				var runway_x := width*.18
				var center := clampf(shift,-safe_x+4.2,minf(safe_x,runway_x-4.0)-4.2)
				x = center+(side-2)*4.2
				if side==0: x = -safe_x
				if side==4: x = runway_x+4.0 if runway_x+4.0<=safe_x else -safe_x
			target.position = Vector3(x,0,z+[3.6,-2.4,0.0,2.4,-5.4][side])
			target.health = int(TARGET.HEALTH[target.variant])+mini(4,int(director.mission.sector)/2)
			target.destroyed.connect(_on_destroyed.bind(target))
			add_child(target)
			target.configure_defense(int(director.mission.sector),float((row+side)%5)*.045)
			target.set_visual_altitude(TERRAIN.PLATEAU_Y)
			target.collision_layer = 0
			target.set_meta("spawn_x",target.position.x)
			target.set_meta("spawn_z",target.position.z)
			targets.append(target)

func advance(delta: float) -> void:
	if director.ending: return
	if not deployed and director.elapsed>=12.0:
		deployed = true
		position.z = director.combat.screen_top()-length*.5-8
		deployment_distance = sea.scroll_distance
		for target in targets: target.collision_layer = 2
	if not deployed: return
	jam_remaining = maxf(0,jam_remaining-delta)
	for target in targets:
		if not is_instance_valid(target) or not target.alive: continue
		if target.global_position.z>director.combat.screen_bottom()+4:
			escaped += 1
			target.retire()
			continue
		target.jammed = jam_remaining>0
		target.advance(delta,director.combat)
	targets = targets.filter(func(target): return is_instance_valid(target) and not target.is_queued_for_deletion())
	cleared = position.z-length*.5>director.combat.screen_bottom()+18.0
	var old_low := low_flight
	var local_z: float = director.player.position.z-position.z
	# Anticipate the coastline so the camera has crossed the cloud deck by the
	# time the aircraft reaches land; climb only after leaving the far shore.
	var above_plateau := 1.0-smoothstep(length*.5+1,length*.5+16,absf(local_z))
	low_flight = move_toward(low_flight,above_plateau,delta*.40)
	# The camera and every airborne visual descend below the physical cloud cards.
	# Zenith orthographic projection preserves exact X/Z alignment with gameplay
	# colliders at Y=0, including radar markers, laser sweeps and edge constraints.
	if director.player.controls_enabled:
		director.player.bank.rotation.x = lerpf(director.player.bank.rotation.x,-(low_flight-old_low)/maxf(.001,delta)*.36,1.0-exp(-delta*6))
	_apply_flight_view()
	sea.scroll_speed = float(director.mission.scroll)*lerpf(1.0,1.18,low_flight)

func _apply_flight_view() -> void:
	_update_airspace()
	var blend := smoothstep(0.0,1.0,low_flight)
	presentation_altitude = LOW_ALTITUDE*blend
	director.player.bank.position.y = presentation_altitude
	var camera: Camera3D = director.combat.camera
	camera.position.y = lerpf(cruise_camera_height,LOW_CAMERA_HEIGHT,blend)
	camera.size = lerpf(cruise_camera_size,LOW_CAMERA_SIZE,blend)
	director.combat.set_presentation_altitude(presentation_altitude)
	director.weapons.set_presentation_altitude(presentation_altitude)
	director.details.set_presentation_altitude(presentation_altitude)
	if is_instance_valid(director.special_ring):
		director.special_ring.position.y = presentation_altitude+.5
	# Keep the ocean large enough through zoom/viewport changes; cloud positions
	# remain fixed in the world and disappear solely by passing above the camera.
	var corner := camera.project_position(get_viewport().get_visible_rect().size,1.0)
	sea.ocean.mesh.size = Vector2(absf(corner.x),absf(corner.z))*2+Vector2(8,8)

func _update_airspace() -> void:
	if not airspace_closed and low_flight>0.02:
		airspace_closed = true
		director.combat.aircraft_enabled = false
		director.combat.withdraw_aircraft()
		director.radio = "Leader : on passe sous les chasseurs ! Canons au sol, restez mobiles !"
		director.radio_time = 4.0
	elif airspace_closed and extraction_ready():
		airspace_closed = false
		director.combat.aircraft_enabled = true

func extraction_ready() -> bool:
	# Air combat resumes over the far shore as soon as cruise altitude is back.
	# The stricter `cleared` margin remains reserved for the carrier itself.
	return deployed and low_flight<=.001 and position.z-length*.5>director.player.position.z+1.0

func _on_scrolled(distance: float) -> void:
	if deployed: position.z += distance
	for index in range(director.combat.effects.size()):
		var effect = director.combat.effects[index]
		if director.combat.effect_times[index]>0 and effect.get_meta("ground_scroll",false): effect.position.z += distance
	for parameter in ["scroll_a","scroll_b","wave_phase"]:
		terrain.set_ocean_parameter(parameter,sea.ocean_material.get_shader_parameter(parameter))

func is_over_land(at: Vector3) -> bool:
	return deployed and absf(at.x)<width*.5-3 and absf(at.z-position.z)<length*.5-6

func approach_clear() -> bool:
	return not deployed or cleared

func contacts() -> Array[Area3D]:
	var result: Array[Area3D] = []
	if not deployed: return result
	for target in targets:
		if is_instance_valid(target) and target.alive and target.global_position.z>=director.combat.screen_top()-3 and target.global_position.z<=director.combat.screen_bottom()+3:
			result.append(target)
	return result

func _on_destroyed(at: Vector3, target: Area3D) -> void:
	kills += 1
	director.combat.kills += 1
	director.combat.score += 350
	director.on_kill(350,"ground")
	director.combat._explode(at+Vector3(0,TERRAIN.PLATEAU_Y+.55,0),1.15 if target.variant=="fuel" else .85,true,true,true)
	director.shake_time = maxf(director.shake_time,.16)
	if target.variant=="radar":
		radar_kills += 1
		jam_remaining = 6.0
		director.complete_objective("radar")
		director.radio = "Radar neutralisé. Guidage de la DCA interrompu pendant 6 secondes !"
		director.radio_time = 4
	elif target.variant=="fuel":
		for other in targets:
			if is_instance_valid(other) and other.alive and other.global_position.distance_to(at)<5.5: other.take_damage(9)
	if kills==int(director.mission.quota):
		director.feedback = "FRAPPE CONFIRMÉE  /  OBJECTIF TERRESTRE ACCOMPLI"
		director.feedback_time = 4
	_drop_supplies(at)

func _drop_supplies(at: Vector3) -> void:
	# Preserve weapon progression without bringing red aircraft into the raid.
	# Two rewards at most, and never replace a pickup the player is collecting.
	if supply_drops>=2 or kills<next_supply_kill: return
	var combat: Node3D = director.combat
	if combat.pickup.active or combat.pickup.burst_time>0: return
	var half_width := absf(combat.camera.project_position(Vector2.ZERO,1.0).x)
	var drop := Vector3(clampf(at.x,-half_width+1.5,half_width-1.5),0,clampf(at.z,combat.screen_top()+1.5,combat.screen_bottom()-2.0))
	supply_drops += 1
	next_supply_kill += 6
	combat.pow_spawn_count += 1
	combat.pickup.activate(drop,director.player,combat.next_power_kind)
	combat.next_power_kind = {"spread":"laser","laser":"life","life":"spread"}[combat.next_power_kind]

func set_quality(level: int) -> void:
	quality = level
	if is_instance_valid(terrain): terrain.set_quality(level)

func finish() -> void:
	low_flight = 0
	_apply_flight_view()
	director.player.bank.rotation.x = 0
	sea.scroll_speed = float(director.mission.scroll)
	for target in targets:
		if is_instance_valid(target): target.retire()
	targets.clear()
