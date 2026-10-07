extends Node3D
## One reusable pickup and collection burst; no per-frame allocation.
var power_kind := "spread"
var icon: MeshInstance3D
const ICONS := {"spread":preload("res://assets/campaign/icons/spread.svg"),"laser":preload("res://assets/campaign/icons/laser.svg"),"life":preload("res://assets/campaign/icons/life.svg")}
var active := false
var age := 0.0
var burst_time := 0.0
var collected_count := 0
var visual: Node3D
var halo: MeshInstance3D
var label: Label3D
var previous_relative := Vector3.ZERO
var audio: AudioStreamPlayer
var spawn_sound: AudioStreamWAV
var collect_sound: AudioStreamWAV
var presentation_altitude := 0.0

func _ready() -> void:
	visual = Node3D.new()
	add_child(visual)
	icon = MeshInstance3D.new()
	var tile := PlaneMesh.new()
	tile.size = Vector2(1.3,1.3)
	icon.mesh = tile
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_texture = ICONS.spread
	icon.material_override = material
	icon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visual.add_child(icon)
	label = Label3D.new()
	label.text = "MULTI"
	label.font = preload("res://assets/ui/fonts/BarlowCondensed-Medium.ttf")
	label.font_size = 48
	label.pixel_size = .005
	label.outline_size = 8
	label.rotation.x = -PI/2
	label.position = Vector3(0,.05,.95)
	visual.add_child(label)
	halo = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(2.2,2.2)
	halo.mesh = plane
	var glow := ShaderMaterial.new()
	glow.shader = preload("res://shaders/pow_halo.gdshader")
	halo.material_override = glow
	halo.position.y = -0.02
	add_child(halo)
	audio = AudioStreamPlayer.new()
	audio.volume_db = -12
	add_child(audio)
	spawn_sound = _make_chime(false)
	collect_sound = _make_chime(true)
	hide()

func _make_chime(ascending: bool) -> AudioStreamWAV:
	var sample_rate := 32000
	var length := 0.78
	var data := PackedByteArray()
	data.resize(int(sample_rate*length)*2)
	var notes := [523.25,659.25,783.99,1046.50] if ascending else [783.99,659.25]
	for index in range(data.size()/2):
		var t := float(index)/sample_rate
		var sample := 0.0
		for note in range(notes.size()):
			var local_t := t-note*0.095
			if local_t < 0: continue
			var envelope := minf(1,local_t/0.006)*exp(-local_t*9.0)
			sample += (sin(TAU*notes[note]*local_t)+0.18*sin(TAU*notes[note]*2.003*local_t))*envelope*0.20
		data.encode_s16(index*2,int(clampf(sample,-0.95,0.95)*32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.data = data
	return stream

func activate(at: Vector3, player: Node3D, kind: String = "spread") -> void:
	power_kind = kind if ICONS.has(kind) else "spread"
	icon.material_override.albedo_texture = ICONS[power_kind]
	label.text = {"spread":"MULTI","laser":"LASER","life":"1 UP"}[power_kind]
	halo.material_override.set_shader_parameter("tint",{"spread":Color("54efff"),"laser":Color("f883ff"),"life":Color("75ffad")}[power_kind])
	global_position = Vector3(at.x,presentation_altitude+0.35,at.z)
	age = 0
	burst_time = 0
	active = true
	previous_relative = player.global_position-global_position
	previous_relative.y = 0
	visual.show()
	halo.scale = Vector3.ONE
	halo.material_override.set_shader_parameter("burst",0.0)
	halo.material_override.set_shader_parameter("strength",1.0)
	audio.stream = spawn_sound
	audio.play()
	show()

func advance(delta: float, combat: Node) -> void:
	if burst_time > 0:
		burst_time = maxf(0,burst_time-delta)
		var p := 1.0-burst_time/0.65
		halo.scale = Vector3.ONE*lerpf(0.8,3.3,p)
		halo.material_override.set_shader_parameter("strength",(1-p)*(1-p))
		if burst_time <= 0: hide()
		return
	if not active: return
	age += delta
	position.z += delta*1.35
	visual.position.y = sin(age*4.0)*0.07
	visual.rotation.y = sin(age*2.0)*0.12
	halo.scale = Vector3.ONE*(1.0+0.07*sin(age*5.0))
	halo.material_override.set_shader_parameter("strength",0.82+0.18*sin(age*5.0))
	var relative: Vector3 = combat.player.global_position-global_position
	relative.y = 0
	if combat.player.alive and combat.player.controls_enabled:
		var closest := Geometry3D.get_closest_point_to_segment(Vector3.ZERO,previous_relative,relative)
		if closest.length() < 0.8:
			collect(combat)
	previous_relative = relative
	if active and (age > 14 or position.z > combat.screen_bottom()+1):
		active = false
		hide()

func collect(combat: Node) -> void:
	if not active: return
	active = false
	collected_count += 1
	combat.get_parent().get_node("Weapons").set_power(power_kind)
	if power_kind == "life": combat.remaining_lives = mini(9,combat.remaining_lives+1)
	var campaign = combat.campaign_driver
	if is_instance_valid(campaign):
		campaign.feedback = {"spread":"MULTI-TIR ÉQUIPÉ","laser":"LASER ÉQUIPÉ","life":"VIE SUPPLÉMENTAIRE  /  TIR STANDARD"}[power_kind]
		campaign.feedback_time = 1.6
	visual.hide()
	burst_time = 0.65
	halo.material_override.set_shader_parameter("burst",1.0)
	audio.stream = collect_sound
	audio.play()
