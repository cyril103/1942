extends Node3D
## A finite, prebuilt coastal battlefield. One shared scroll moves terrain,
## installations and wrecks; it must fully clear the carrier approach.
const TARGET := preload("res://scripts/campaign/ground_target.gd")
const TERRAIN := preload("res://scripts/campaign/assault_terrain.gd")
const LAYOUTS := preload("res://scripts/campaign/raid_layouts.gd")
const LABELS := {"fuel":"CARBURANT", "radar":"RADAR", "battery":"DCA", "bunker":"BUNKER", "runway":"HANGAR"}
signal network_disrupted(network_id: String, seconds: float, global_scope: bool)
signal mobile_route_announced(target_id: String, from: Vector3, to: Vector3, seconds: float)
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
var layout: Dictionary = {}
var destroyed_ids: Dictionary = {}
var escaped_ids: Dictionary = {}
var network_jams: Dictionary = {}
var secondary_destroyed_ids: Dictionary = {}
var _targets_by_id: Dictionary = {}
var _networks_for_target: Dictionary = {}
var _objective_announced := false
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
	var safe_x := minf(width*.33-2.3,sea._view_half.x*LOW_CAMERA_SIZE/cruise_camera_size-2.3)
	layout = LAYOUTS.instantiate_layout(director.mission,width,length,safe_x)
	position.z = -10000
	terrain = TERRAIN.new()
	add_child(terrain)
	terrain.configure(director.mission,width,length,layout)
	terrain.set_ground_detail(preload("res://assets/environment/raid-v2/coral-grass-detail.png"))
	terrain.set_ocean_parameter("ocean_texture",sea.OCEAN_TEXTURE)
	for parameter in ["ocean_tint","sea_desaturation","tile_size"]:
		terrain.set_ocean_parameter(parameter,sea.ocean_material.get_shader_parameter(parameter))
	_build_targets()
	sea.scrolled.connect(_on_scrolled)

func _build_targets() -> void:
	# Authored IDs, roads and priority lists are shared with terrain/briefing.
	# Count actual installations, rather than flooring a requested count / 5.
	var groups: Dictionary = layout.get("radar_groups",{})
	for network_id in groups:
		network_jams[str(network_id)] = 0.0
		for target_id in groups[network_id].get("target_ids",[]):
			if not _networks_for_target.has(str(target_id)): _networks_for_target[str(target_id)] = []
			_networks_for_target[str(target_id)].append(str(network_id))
	var routes: Dictionary = layout.get("routes",{})
	for spec in layout.get("targets",[]):
		var target := TARGET.new()
		target.variant = str(spec.variant)
		target.mobile = bool(spec.get("mobile",false))
		target.rapid_fire = bool(spec.get("rapid_fire",false))
		target.position = Vector3(spec.position.x,0.0,spec.position.z)
		# Priority/mobile status grants no extra armor. Preserve the established
		# sector bonus ceiling and fractional damage all the way to destruction.
		var bonus_cap := mini(4,int(director.mission.sector)/2)
		target.health = float(TARGET.HEALTH[target.variant])+clampi(int(spec.get("health_bonus",0)),0,bonus_cap)
		target.destroyed.connect(_on_destroyed.bind(target))
		target.movement_announced.connect(_on_mobile_route_announced)
		add_child(target)
		target.configure_defense(int(director.mission.sector),float(spec.get("defense_stagger",0.0)))
		target.configure_tactical(spec,routes.get(str(spec.get("mobile_route_id","")),{}))
		target.set_visual_altitude(TERRAIN.PLATEAU_Y)
		target.collision_layer = 0
		target.set_meta("spawn_x",target.position.x)
		target.set_meta("spawn_z",target.position.z)
		_targets_by_id[target.tactical_id] = target
		targets.append(target)

func advance(delta: float) -> void:
	if director.ending or director.paused or get_tree().paused: return
	if not deployed and director.elapsed>=12.0:
		deployed = true
		position.z = director.combat.screen_top()-length*.5-8
		deployment_distance = sea.scroll_distance
		for target in targets: target.collision_layer = 2
	if not deployed: return
	_advance_network_jams(delta)
	for target in targets:
		if not is_instance_valid(target) or not target.alive: continue
		if target.global_position.z>director.combat.screen_bottom()+4:
			escaped += 1
			escaped_ids[target.tactical_id] = true
			target.retire()
			continue
		target.set_jammed(_is_target_jammed(target.tactical_id))
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
		if director.has_signal("audio_event"):
			director.emit_signal("audio_event", "radio_important", "raid-entry:%d" % int(director.mission.id))
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

func target_by_id(target_id: String) -> Area3D:
	var target = _targets_by_id.get(target_id)
	return target if is_instance_valid(target) and not target.is_queued_for_deletion() else null

func main_objective_met() -> bool:
	if layout.is_empty(): return false
	if kills<int(layout.get("quota",director.mission.quota)): return false
	for target_id in layout.get("priority_ids",[]):
		if not destroyed_ids.has(str(target_id)): return false
	return true

func objective_status() -> Dictionary:
	# The director's victory and medal, briefing and HUD must all use this same
	# predicate. A priority is already one kill in the quota, never an extra kill.
	var missing: Array[String] = []
	var priority_escaped: Array[String] = []
	var priorities: Array = layout.get("priority_ids",[])
	for target_id in priorities:
		if not destroyed_ids.has(str(target_id)): missing.append(str(target_id))
		if escaped_ids.has(str(target_id)): priority_escaped.append(str(target_id))
	var secondary: Dictionary = layout.get("secondary_spec",{})
	var secondary_minimum := int(secondary.get("minimum",layout.get("secondary_target",0)))
	return {
		"layout_valid":bool(layout.get("valid",false)),"layout_warnings":layout.get("warnings",[]),
		"kills":kills,"quota":int(layout.get("quota",director.mission.quota)),
		"priority_total":priorities.size(),"priority_destroyed":priorities.size()-missing.size(),
		"missing_priority_ids":missing,"escaped_priority_ids":priority_escaped,
		"main_met":main_objective_met(),
		"secondary_kind":str(secondary.get("kind",layout.get("secondary_kind","ground_layout"))),
		"secondary_label":str(secondary.get("label","")),
		"secondary_progress":secondary_destroyed_ids.size(),"secondary_target":secondary_minimum,
		"secondary_met":secondary_minimum>0 and secondary_destroyed_ids.size()>=secondary_minimum
	}

func _advance_network_jams(delta: float) -> void:
	for network_id in network_jams:
		network_jams[network_id] = maxf(0.0,float(network_jams[network_id])-maxf(0.0,delta))
	_refresh_global_jam()

func _refresh_global_jam() -> void:
	# Legacy HUD's jam_remaining is reserved for a genuinely global shutdown.
	# Local networks are exposed separately, so it cannot claim all DCA is off.
	jam_remaining = 0.0
	var groups: Dictionary = layout.get("radar_groups",{})
	for network_id in network_jams:
		if bool(groups.get(network_id,{}).get("global",false)):
			jam_remaining = maxf(jam_remaining,float(network_jams[network_id]))

func _is_target_jammed(target_id: String) -> bool:
	if jam_remaining>0: return true
	if not _networks_for_target.has(target_id): return false
	for network_id in _networks_for_target[target_id]:
		if float(network_jams.get(network_id,0.0))>0: return true
	return false

func jam_status() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var groups: Dictionary = layout.get("radar_groups",{})
	for network_id in network_jams:
		var seconds := float(network_jams[network_id])
		if seconds<=0: continue
		var group: Dictionary = groups.get(network_id,{})
		var live_members := 0
		for target_id in group.get("target_ids",[]):
			var target := target_by_id(str(target_id))
			if is_instance_valid(target) and target.alive: live_members += 1
		result.append({"id":str(network_id),"seconds":seconds,"global":bool(group.get("global",false)),"alive_members":live_members})
	return result

func _disrupt_radar_networks(radar_id: String) -> void:
	var groups: Dictionary = layout.get("radar_groups",{})
	for network_id in groups:
		var group: Dictionary = groups[network_id]
		if not group.get("radar_ids",[]).has(radar_id): continue
		var seconds := maxf(0.0,float(group.get("jam_seconds",6.0)))
		network_jams[str(network_id)] = maxf(float(network_jams.get(str(network_id),0.0)),seconds)
		network_disrupted.emit(str(network_id),seconds,bool(group.get("global",false)))
	_refresh_global_jam()
	for target in targets:
		if is_instance_valid(target) and target.alive:
			target.set_jammed(_is_target_jammed(target.tactical_id))
	# The director owns the radio wording through network_disrupted, using the
	# authored readable label. Do not overwrite it with internal network IDs.

func _on_mobile_route_announced(target_id: String, from: Vector3, to: Vector3, seconds: float) -> void:
	mobile_route_announced.emit(target_id,from,to,seconds)
	if director.radio_time<=0:
		director.radio = "DCA mobile en déplacement. Exploitez son arrêt avant la rafale !"
		director.radio_time = 3.0

func _on_destroyed(at: Vector3, target: Area3D) -> void:
	var target_id: String = target.tactical_id
	if destroyed_ids.has(target_id): return
	destroyed_ids[target_id] = true
	kills += 1
	director.combat.kills += 1
	director.combat.score += 350
	director.on_kill(350,"ground")
	director.combat._explode(at+Vector3(0,TERRAIN.PLATEAU_Y+.55,0),1.15 if target.variant=="fuel" else .85,true,true,true)
	director.shake_time = maxf(director.shake_time,.16)
	if target.variant=="radar":
		radar_kills += 1
		_disrupt_radar_networks(target_id)
	elif target.variant=="fuel":
		for other in targets:
			if is_instance_valid(other) and other.alive and other.global_position.distance_to(at)<5.5: other.take_damage(9)
	var secondary: Dictionary = layout.get("secondary_spec",{})
	var secondary_ids: Array = secondary.get("target_ids",layout.get("secondary_ids",[]))
	if secondary_ids.has(target_id) and not secondary_destroyed_ids.has(target_id):
		secondary_destroyed_ids[target_id] = true
		director.complete_objective(str(secondary.get("kind",layout.get("secondary_kind","ground_layout"))))
	if not _objective_announced and main_objective_met():
		_objective_announced = true
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
	_targets_by_id.clear()
	network_jams.clear()
	jam_remaining = 0.0
