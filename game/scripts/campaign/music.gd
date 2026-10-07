extends Node
## Original jeu-final action soundtrack, with two voices for seamless crossfades.
var players: Array[AudioStreamPlayer] = []
var current_mode := ""
var current := 0
var fade := 1.0
var tracks := {}
var radio_player: AudioStreamPlayer
var previous_radio := ""
func _ready() -> void:
	for key in ["menu","flight","flight2","boss","victory"]:
		var stream = load("res://assets/campaign/music/"+key+".wav")
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_end = roundi(stream.get_length()*stream.mix_rate)
		tracks[key] = stream
	for i in range(2):
		var player := AudioStreamPlayer.new()
		player.bus = "Music"
		add_child(player)
		players.append(player)
	radio_player = AudioStreamPlayer.new()
	radio_player.stream = preload("res://assets/campaign/music/radio-cue.wav")
	radio_player.bus = "Effects"
	radio_player.volume_db = -12
	add_child(radio_player)

func update_combat(director: Node) -> void:
	if director.radio_time>0 and director.radio!=previous_radio:
		previous_radio = director.radio
		radio_player.play()
func set_mode(mode: String) -> void:
	if mode == current_mode or not tracks.has(mode): return
	current_mode = mode
	current = 1-current
	players[current].stream = tracks[mode]
	players[current].volume_db = -50
	players[current].play()
	fade = 0
func _process(delta: float) -> void:
	if fade >= 1: return
	fade = minf(1,fade+delta/1.5)
	players[current].volume_db = linear_to_db(maxf(0.003,fade)) - 6
	players[1-current].volume_db = linear_to_db(maxf(0.003,1-fade)) - 6
	if fade >= 1: players[1-current].stop()
func stop() -> void:
	for player in players: player.stop()
	if is_instance_valid(radio_player): radio_player.stop()
	fade = 1.0
	current_mode = ""
	previous_radio = ""
