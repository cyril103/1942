extends Node3D
## Opening choreography. Ship and ocean share actual scrolled distance.
## A full positive X rotation pitches the -Z-facing aircraft through a loop.

signal flight_started

enum Phase { ON_DECK, TAKEOFF, CLIMB, LOOP, SETTLE, FLIGHT }
const HOLD_DURATION: float = 0.65
const RUN_DURATION: float = 3.1
const CLIMB_DURATION: float = 1.2
const LOOP_DURATION: float = 2.4
const SETTLE_DURATION: float = 1.6
const RUN_END: float = HOLD_DURATION + RUN_DURATION
const CLIMB_END: float = RUN_END + CLIMB_DURATION
const LOOP_END: float = CLIMB_END + LOOP_DURATION
const INTRO_DURATION: float = LOOP_END + SETTLE_DURATION
const DECK_ALTITUDE: float = -2.45
const LOOP_RADIUS: float = 2.0
const LIFT_FRACTION: float = 0.73
const LIFT_START: float = HOLD_DURATION + RUN_DURATION * LIFT_FRACTION
const PULLUP_DURATION: float = CLIMB_END - LIFT_START
const LOOP_ENTRY: float = PI * 65.0 / 180.0
const LOOP_RATE: float = (TAU - LOOP_ENTRY) / LOOP_DURATION

@export var player: Node3D
@export var seascape: Node3D
@export var camera: Camera3D

var carrier: Node3D
var contact_shadow: MeshInstance3D
var phase: Phase = Phase.ON_DECK
var elapsed: float = 0.0
var active: bool = true
var _cruise_speed: float
var _settle_start := Vector3.ZERO
var _wake_material: ShaderMaterial
var _shadow_material: ShaderMaterial
var engine_audio: Node3D
var landing_active := false
var landed := false
var landing_time := 0.0
var landing_start := Vector3.ZERO
const LANDING_DURATION := 7.0


func _ready() -> void:
	_cruise_speed = seascape.scroll_speed
	seascape.scroll_speed = 0.8
	seascape.scrolled.connect(_on_scrolled)
	_build_carrier()
	_build_shadow()
	player.controls_enabled = false
	player.bank.scale = Vector3.ONE * 0.68
	player.bank.rotation = Vector3.ZERO
	player.position = Vector3(0.0, DECK_ALTITUDE, 8.1)
	_update_shadow()
	engine_audio = preload("res://scripts/takeoff_audio.gd").new()
	engine_audio.departure = self
	engine_audio.player = player
	engine_audio.camera = camera
	add_child(engine_audio)


func _plane(name_text: String, size: Vector2, material: Material, parent_node: Node3D) -> MeshInstance3D:
	var result := MeshInstance3D.new()
	result.name = name_text
	var plane := PlaneMesh.new()
	plane.size = size
	result.mesh = plane
	result.material_override = material
	result.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent_node.add_child(result)
	return result


func _build_carrier() -> void:
	carrier = Node3D.new()
	carrier.name = "Carrier"
	add_child(carrier)
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/carrier.gdshader")
	material.set_shader_parameter("carrier_texture", preload("res://assets/environment/carrier.png"))
	var deck := _plane("FlightDeck", Vector2(12.0, 24.0), material, carrier)
	deck.position.y = -2.70
	_wake_material = ShaderMaterial.new()
	_wake_material.shader = preload("res://shaders/carrier_wake.gdshader")
	var wake := _plane("Wake", Vector2(7.0, 15.0), _wake_material, carrier)
	wake.position = Vector3(0.0, -3.08, 17.8)


func _build_shadow() -> void:
	_shadow_material = ShaderMaterial.new()
	_shadow_material.shader = preload("res://shaders/aircraft_shadow.gdshader")
	contact_shadow = _plane("TakeoffShadow", Vector2(2.08125, 1.6875), _shadow_material, self)
	_shadow_material.render_priority = 1


func _on_scrolled(distance: float) -> void:
	if carrier.visible and not landing_active:
		carrier.position.z += distance


func _physics_process(delta: float) -> void:
	elapsed += delta
	_wake_material.set_shader_parameter("wave_phase", fposmod(elapsed * 0.8, TAU))
	if not active:
		var bottom_world := camera.project_position(get_viewport().get_visible_rect().size, camera.position.y)
		if carrier.position.z - 12.0 > bottom_world.z + 1.0:
			carrier.hide()
			set_physics_process(false)
		return

	if elapsed < HOLD_DURATION:
		player.position = Vector3(0.0, DECK_ALTITUDE, carrier.position.z + 8.1)
	elif elapsed < CLIMB_END:
		phase = Phase.TAKEOFF if elapsed < RUN_END else Phase.CLIMB
		var run_u := clampf((elapsed - HOLD_DURATION) / RUN_DURATION, 0.0, 1.0)
		seascape.scroll_speed = lerpf(0.8, minf(_cruise_speed,2.4), smoothstep(0.0, 1.0, run_u))
		if elapsed < LIFT_START:
			player.position = Vector3(0.0, DECK_ALTITUDE, carrier.position.z + lerpf(8.1, -9.3, run_u * run_u))
		else:
			# One continuous pull-up: orientation comes from the path tangent,
			# measured relative to the scrolling ocean, not from a separate tween.
			var u := clampf((elapsed - LIFT_START) / PULLUP_DURATION, 0.0, 1.0)
			var p0 := Vector3(0.0, DECK_ALTITUDE, lerpf(8.1, -9.3, LIFT_FRACTION * LIFT_FRACTION))
			var runway_speed := 2.0 * 17.4 * LIFT_FRACTION / RUN_DURATION
			var p1 := p0 + Vector3(0.0, 0.0, -runway_speed * PULLUP_DURATION / 3.0)
			var p3 := _loop_entry_position()
			var entry_direction := Vector3(0.0, sin(LOOP_ENTRY), -cos(LOOP_ENTRY))
			var p2 := p3 - entry_direction * LOOP_RADIUS * LOOP_RATE * PULLUP_DURATION / 3.0
			player.position = p0.bezier_interpolate(p1, p2, p3, u) + Vector3(0.0, 0.0, carrier.position.z)
			var tangent := p0.bezier_derivative(p1, p2, p3, u)
			player.bank.rotation.x = atan2(tangent.y, -tangent.z)
		_update_altitude_scale()
	elif elapsed < LOOP_END:
		phase = Phase.LOOP
		var angle := LOOP_ENTRY + (elapsed - CLIMB_END) * LOOP_RATE
		var center_z := _loop_entry_position().z + LOOP_RADIUS * sin(LOOP_ENTRY)
		player.position = Vector3(0.0, LOOP_RADIUS * (1.0 - cos(angle)), carrier.position.z + center_z - LOOP_RADIUS * sin(angle))
		player.bank.rotation = Vector3(angle, 0.0, 0.0)
		_update_altitude_scale()
	elif elapsed < INTRO_DURATION:
		if phase != Phase.SETTLE:
			_settle_start = Vector3(0.0, 0.0, carrier.position.z + _loop_entry_position().z + LOOP_RADIUS * sin(LOOP_ENTRY))
		phase = Phase.SETTLE
		var u := (elapsed - LOOP_END) / SETTLE_DURATION
		seascape.scroll_speed = lerpf(minf(_cruise_speed,2.4),_cruise_speed,smoothstep(0,1,u))
		# Match the loop's outgoing screen velocity, then settle gently.
		var outgoing := Vector3(0.0, 0.0, minf(_cruise_speed,2.4) - LOOP_RADIUS * LOOP_RATE)
		player.position = _settle_start.bezier_interpolate(_settle_start + outgoing * SETTLE_DURATION / 3.0, Vector3(0.0, 0.0, 5.0), Vector3(0.0, 0.0, 5.0), u)
		player.bank.rotation = Vector3(TAU, 0.0, 0.0)
		player.bank.scale = Vector3.ONE
	else:
		_finish_flight()
	player._keep_inside_screen()
	_update_shadow()


func _loop_entry_position() -> Vector3:
	return Vector3(0.0, LOOP_RADIUS * (1.0 - cos(LOOP_ENTRY)), -12.0)


func _update_altitude_scale() -> void:
	# Orthographic depth cue, continuous through all airborne phases.
	var height := player.position.y
	var size := lerpf(0.68, 1.0, smoothstep(DECK_ALTITUDE, 0.0, height))
	size += 0.14 * smoothstep(0.0, 2.0 * LOOP_RADIUS, height)
	player.bank.scale = Vector3.ONE * size


func _update_shadow() -> void:
	var height := maxf(0.0, player.position.y - DECK_ALTITUDE)
	contact_shadow.position = Vector3(player.position.x + 0.04 + height * 0.15, -2.66, player.position.z + 0.06 + height * 0.22)
	contact_shadow.scale = Vector3.ONE * player.bank.scale.x
	var fade := 1.0 - smoothstep(LOOP_END, INTRO_DURATION, elapsed)
	_shadow_material.set_shader_parameter("opacity", (0.24 / (1.0 + height * 0.32)) * fade)
	_shadow_material.set_shader_parameter("softness", 0.035 + height * 0.032)


func _finish_flight() -> void:
	active = false
	phase = Phase.FLIGHT
	seascape.scroll_speed = _cruise_speed
	player.position = Vector3(0.0, 0.0, 5.0)
	player.bank.rotation = Vector3.ZERO
	player.bank.scale = Vector3.ONE
	player.controls_enabled = true
	contact_shadow.hide()
	flight_started.emit()


func finish_immediately() -> void:
	# Used by gameplay regression tests and scenery-only captures.
	engine_audio.stop()
	_finish_flight()
	carrier.hide()
	set_physics_process(false)

func begin_landing() -> void:
	active = false
	landing_active = true
	landed = false
	landing_time = 0
	landing_start = player.position
	player.set_physics_process(false)
	player.controls_enabled = false
	player.invulnerable_time = LANDING_DURATION+2
	player.bank.show()
	carrier.position = Vector3(0,0,-26)
	carrier.show()
	contact_shadow.show()
	set_physics_process(false)
	engine_audio.finished = false
	engine_audio.fade = 0
	engine_audio.set_physics_process(true)
	for voice in engine_audio.voices: voice.play()

func advance_landing(delta: float) -> void:
	if not landing_active or landed: return
	landing_time = minf(LANDING_DURATION,landing_time+delta)
	var t := landing_time
	carrier.position.z = lerpf(-26,-2,smoothstep(0,3.5,t))
	seascape.scroll_speed = lerpf(_cruise_speed,0.5,smoothstep(0,6,t))
	if t < 2:
		var u := smoothstep(0,2,t)
		player.position = landing_start.lerp(Vector3(0,0,8),u)
		player.bank.rotation = Vector3(0,0,clampf(landing_start.x*.06,-.38,.38)*sin(u*PI))
	elif t < 4.8:
		var u := (t-2)/2.8
		player.position = Vector3(0,lerpf(0,DECK_ALTITUDE,smoothstep(0,1,u)),lerpf(8,4,u))
		# Descent attitude followed by a gentle nose-up flare before touchdown.
		player.bank.rotation.x = -0.16*sin(u*PI)+0.08*smoothstep(.7,1,u)
		player.bank.rotation.z = 0
	else:
		var u := clampf((t-4.8)/2.2,0,1)
		player.position = Vector3(0,DECK_ALTITUDE,lerpf(4,-3,1-pow(1-u,3)))
		player.bank.rotation.x = lerpf(.08,0,smoothstep(0,.45,u))
	_update_altitude_scale()
	contact_shadow.position = Vector3(player.position.x+.04,-2.66,player.position.z+.06)
	contact_shadow.scale = player.bank.scale
	_shadow_material.set_shader_parameter("opacity",0.25)
	_shadow_material.set_shader_parameter("softness",.04+maxf(0,player.position.y-DECK_ALTITUDE)*.025)
	_wake_material.set_shader_parameter("wave_phase",t*.8)
	if t >= LANDING_DURATION:
		landed = true
		engine_audio.stop()
