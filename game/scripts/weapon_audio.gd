extends Node
## Phase 5 candidate: original six PCM takes and the eight reusable gun voices.
## Spread changes timbre at -1dB; normal fire never requests music ducking.
const VOICE_COUNT := 8
const VARIANTS := [
	preload("res://assets/audio/weapons/salvo_01.wav"),
	preload("res://assets/audio/weapons/salvo_02.wav"),
	preload("res://assets/audio/weapons/salvo_03.wav"),
	preload("res://assets/audio/weapons/salvo_04.wav"),
	preload("res://assets/audio/weapons/salvo_05.wav"),
	preload("res://assets/audio/weapons/salvo_06.wav")
]
const SIGNATURES := {
	"standard": {"pitch": 1.0, "variation": .008, "gain": 0.0},
	"spread": {"pitch": .88, "variation": .012, "gain": -1.0}
}
const LASER_BASE_DB := -15.0
const LASER_ATTACK_SECONDS := .035
const LASER_RELEASE_SECONDS := .070
# Reserve headroom for simultaneous boss music, guns, engine and explosions.
# The all-sliders-at-100 stress mix clipped before this 3 dB gun reduction.
@export_range(-30.0, 0.0, 0.5) var volume_db := -8.0
var voices: Array[AudioStreamPlayer] = []
var salvos_played := 0
var voices_stolen := 0
var last_variant := -1
var last_signature := "standard"
var signature := "standard"
var alert_attenuation_db := 0.0
var laser_level := 0.0
var _cursor := 0
var _rng := RandomNumberGenerator.new()
var _voice_gains := PackedFloat32Array()
var _laser: AudioStreamPlayer
var _laser_active := false
var _laser_from := 0.0
var _laser_elapsed := 0.0

func _ready() -> void:
	_rng.randomize()
	_voice_gains.resize(VOICE_COUNT)
	_voice_gains.fill(0.0)
	for index in range(VOICE_COUNT):
		var voice := AudioStreamPlayer.new()
		voice.bus = "Effects"
		voice.max_polyphony = 1
		add_child(voice)
		voices.append(voice)

func set_signature(kind: String) -> void:
	signature = kind if SIGNATURES.has(kind) else "standard"

func set_alert_attenuation(attenuation_db: float) -> void:
	if not is_finite(attenuation_db):
		return
	alert_attenuation_db = clampf(attenuation_db, 0.0, 2.0)
	_update_voice_levels()

func play_salvo(kind: String = "") -> bool:
	if not kind.is_empty():
		set_signature(kind)
	var spec: Dictionary = SIGNATURES[signature]
	var variant := _rng.randi_range(0, VARIANTS.size() - 2)
	if variant >= last_variant:
		variant += 1
	var chosen := -1
	for offset in range(VOICE_COUNT):
		var index := (_cursor + offset) % VOICE_COUNT
		if not voices[index].playing:
			chosen = index
			break
	if chosen < 0:
		chosen = _cursor
		voices_stolen += 1
	var voice := voices[chosen]
	voice.stream = VARIANTS[variant]
	voice.pitch_scale = float(spec.pitch) + _rng.randf_range(-float(spec.variation), float(spec.variation))
	_voice_gains[chosen] = float(spec.gain) + _rng.randf_range(-.45, 0.0)
	voice.volume_db = volume_db + _voice_gains[chosen] - alert_attenuation_db
	voice.play()
	last_variant = variant
	last_signature = signature
	_cursor = (chosen + 1) % VOICE_COUNT
	salvos_played += 1
	return true

func bind_laser(voice: AudioStreamPlayer) -> void:
	_laser = voice
	_laser.bus = "Effects"
	_laser.max_polyphony = 1
	_laser.pitch_scale = 1.0 # Existing procedural loop, no sample/tempo replacement.
	_laser.volume_db = -75.0

func set_laser_active(active: bool) -> void:
	if active == _laser_active:
		return
	_laser_active = active
	_laser_from = laser_level
	_laser_elapsed = 0.0
	if active and is_instance_valid(_laser) and not _laser.playing:
		# Prime the envelope before play(): the audio thread may consume its
		# first buffer before the next _process frame updates this voice.
		_laser.volume_db = LASER_BASE_DB + linear_to_db(maxf(.001, laser_level)) - alert_attenuation_db
		_laser.play()

func _process(delta: float) -> void:
	advance(delta)

func advance(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0 or not is_instance_valid(_laser):
		return
	var target := 1.0 if _laser_active else 0.0
	var duration := LASER_ATTACK_SECONDS if _laser_active else LASER_RELEASE_SECONDS
	_laser_elapsed = minf(duration, _laser_elapsed + delta)
	laser_level = lerpf(_laser_from, target, smoothstep(0.0, 1.0, _laser_elapsed / duration))
	_laser.volume_db = LASER_BASE_DB + linear_to_db(maxf(.001, laser_level)) - alert_attenuation_db
	if not _laser_active and _laser_elapsed >= duration:
		_laser.stop()

func _update_voice_levels() -> void:
	for index in range(voices.size()):
		voices[index].volume_db = volume_db + _voice_gains[index] - alert_attenuation_db
	if is_instance_valid(_laser):
		_laser.volume_db = LASER_BASE_DB + linear_to_db(maxf(.001, laser_level)) - alert_attenuation_db

func stop_all() -> void:
	for voice in voices:
		voice.stop()
	if is_instance_valid(_laser):
		_laser.stop()
		_laser.volume_db = -75.0
	_laser_active = false
	_laser_from = 0.0
	_laser_elapsed = 0.0
	laser_level = 0.0

func voice_status() -> Dictionary:
	var active := 0
	for voice in voices:
		if voice.playing:
			active += 1
	return {"pool": voices.size(), "active": active, "salvos": salvos_played,
		"stolen": voices_stolen, "signature": signature, "guard_db": alert_attenuation_db,
		"laser_bound": is_instance_valid(_laser), "laser_level": laser_level}

func _notification(what: int) -> void:
	# AudioStreamPlayer normally pauses/resumes its existing playback with its
	# parent. A weapon must discard that tail instead of reviving it on resume.
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_PAUSED, NOTIFICATION_DISABLED]:
		stop_all()
