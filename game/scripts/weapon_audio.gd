extends Node
## Eight reusable voices, preloaded PCM; no allocations or file reads per shot.

const VOICE_COUNT := 8
const VARIANTS := [
	preload("res://assets/audio/weapons/salvo_01.wav"),
	preload("res://assets/audio/weapons/salvo_02.wav"),
	preload("res://assets/audio/weapons/salvo_03.wav"),
	preload("res://assets/audio/weapons/salvo_04.wav"),
	preload("res://assets/audio/weapons/salvo_05.wav"),
	preload("res://assets/audio/weapons/salvo_06.wav"),
]

@export_range(-30.0, 0.0, 0.5) var volume_db := -5.0
var voices: Array[AudioStreamPlayer] = []
var salvos_played := 0
var last_variant := -1
var _cursor := 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	for index in range(VOICE_COUNT):
		var voice := AudioStreamPlayer.new()
		voice.max_polyphony = 1
		add_child(voice)
		voices.append(voice)


func play_salvo() -> void:
	# Pick among the other five takes, never repeat the previous one.
	var variant := _rng.randi_range(0, VARIANTS.size() - 2)
	if variant >= last_variant:
		variant += 1
	var voice := voices[_cursor]
	voice.stream = VARIANTS[variant]
	voice.pitch_scale = _rng.randf_range(0.992, 1.008)
	voice.volume_db = volume_db + _rng.randf_range(-0.45, 0.0)
	voice.play()
	last_variant = variant
	_cursor = (_cursor + 1) % VOICE_COUNT
	salvos_played += 1


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		for voice in voices:
			voice.stop()
