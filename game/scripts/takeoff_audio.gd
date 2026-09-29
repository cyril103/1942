extends Node3D
## P-51 sample layers. Exaggerated world-to-acoustic scale for a cinematic pass.
## Doppler still follows signed radial velocity relative to the camera.
const METERS_PER_UNIT := 14.0
const SOUND_SPEED := 343.0
var departure: Node3D
var player: Node3D
var camera: Camera3D
var voices: Array[AudioStreamPlayer3D] = []
var last_distance := 0.0
var radial_speed := 0.0
var doppler := 1.0
var finished := false
var fade := 0.0

func _ready() -> void:
	process_physics_priority = 1
	last_distance = player.global_position.distance_to(camera.global_position)
	for file in ["res://assets/audio/engine/merlin-exhaust.wav", "res://assets/audio/engine/merlin-body.wav"]:
		var voice := AudioStreamPlayer3D.new()
		var sample: AudioStreamWAV = load(file).duplicate()
		sample.loop_mode = AudioStreamWAV.LOOP_FORWARD
		sample.loop_begin = 0
		sample.loop_end = sample.data.size() / (4 if sample.stereo else 2)
		voice.stream = sample
		voice.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
		voice.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		voice.max_db = 0.0
		voice.volume_db = -60.0
		add_child(voice)
		voices.append(voice)
		voice.play()

func _physics_process(delta: float) -> void:
	if finished: return
	global_position = player.global_position
	var distance := global_position.distance_to(camera.global_position)
	var measured := (distance - last_distance) / maxf(delta, 0.001)
	last_distance = distance
	radial_speed = lerpf(radial_speed, clampf(measured * METERS_PER_UNIT, -75.0, 75.0), 1.0 - exp(-delta * 9.0))
	doppler = clampf(SOUND_SPEED / (SOUND_SPEED + radial_speed), 0.82, 1.26)
	var throttle := smoothstep(departure.HOLD_DURATION, departure.RUN_END, departure.elapsed)
	var rpm := lerpf(0.78, 1.0, throttle)
	if not departure.active:
		fade += delta / 1.5
	if not player.alive:
		fade += delta * 4.0
	if fade >= 1.0:
		stop()
		return
	var entry_fade := smoothstep(0.0, 0.35, departure.elapsed)
	var distance_gain := clampf(pow(35.0 / maxf(distance, 1.0), 2.0), 0.55, 1.4)
	var envelope := entry_fade * (1.0 - smoothstep(0.0, 1.0, fade)) * distance_gain
	for index in range(voices.size()):
		var voice := voices[index]
		voice.pitch_scale = rpm * doppler
		voice.volume_db = (-12.0 if index == 0 else -5.0) + linear_to_db(maxf(0.001, envelope * lerpf(0.38, 1.0, throttle)))

func stop() -> void:
	finished = true
	for voice in voices: voice.stop()
	set_physics_process(false)
