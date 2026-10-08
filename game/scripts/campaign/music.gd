extends Node
## Phase 5 candidate #19. Existing action tracks; two bounded music voices.
## Semantic events duck individual players, never the user's bus sliders.
signal foreground_gain_changed(attenuation_db: float)
const TRACK_KEYS := ["menu", "flight", "flight2", "boss", "victory"]
const MUSIC_BASE_DB := -6.0
const CROSSFADE_SECONDS := 1.5
const ATTACK_SECONDS := .120
const HOLD_SECONDS := .450
const RELEASE_SECONDS := .700
const CUE_VOICES := 2
const CUE_RETIRE_SECONDS := .035
const EVENT_HISTORY_CAPACITY := 16
const EVENTS := {
	"boss": {"priority": 4, "duck": 4.0, "guard": 2.0, "cooldown": 1.0, "pitch": .72, "gain": -13.0},
	"danger": {"priority": 4, "duck": 4.0, "guard": 2.0, "cooldown": 2.0, "pitch": 1.22, "gain": -14.0},
	"radio_important": {"priority": 3, "duck": 4.0, "guard": 2.0, "cooldown": .9, "pitch": 1.0, "gain": -12.0},
	"radio": {"priority": 2, "duck": 2.0, "guard": 0.0, "cooldown": .8, "pitch": 1.0, "gain": -14.0},
	"reward": {"priority": 1, "duck": 1.5, "guard": 0.0, "cooldown": .9, "pitch": 1.48, "gain": -17.0}
}
enum DuckPhase { IDLE, ATTACK, HOLD, RELEASE }
var players: Array[AudioStreamPlayer] = []
var cue_players: Array[AudioStreamPlayer] = []
var radio_player: AudioStreamPlayer # Existing caller compatibility: first cue voice.
var tracks: Dictionary = {}
var current_mode := ""
var pending_mode := ""
var current := 0
var fade := 1.0
var previous_radio := ""
var duck_db := 0.0
var duck_phase := DuckPhase.IDLE
var events_accepted := 0
var events_suppressed := 0
var cue_preemptions := 0
var _clock := 0.0
var _gains := PackedFloat32Array([0.0, 0.0])
var _fade_from := PackedFloat32Array([0.0, 0.0])
var _duck_from := 0.0
var _duck_target := 0.0
var _duck_elapsed := 0.0
var _hold_remaining := 0.0
var _duck_priority := 0
var _guard_target := 0.0
var _guard_from := 0.0
var _guard_db := 0.0
var _last_guard := 0.0
var _last_kind_time: Dictionary = {}
var _recent_keys: Array[String] = []
var _cue_priorities := PackedInt32Array([0, 0])
var _cue_remaining := PackedFloat32Array([0.0, 0.0])
var _cue_retire := PackedFloat32Array([0.0, 0.0])
var _cue_base := PackedFloat32Array([-14.0, -14.0])
var _pending_cues: Array[Dictionary] = [{}, {}]
var _last_boss_id := 0
var _last_boss_phase := 0
var _last_multiplier := 1
var _secondary_seen := false

func _ready() -> void:
	for key in TRACK_KEYS:
		var stream: AudioStreamWAV = load("res://assets/campaign/music/" + key + ".wav").duplicate()
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_end = roundi(stream.get_length() * stream.mix_rate)
		tracks[key] = stream
	for index in range(2):
		var voice := AudioStreamPlayer.new()
		voice.bus = "Music"
		voice.max_polyphony = 1
		voice.pitch_scale = 1.0
		add_child(voice)
		players.append(voice)
	for index in range(CUE_VOICES):
		var voice := AudioStreamPlayer.new()
		voice.stream = preload("res://assets/campaign/music/radio-cue.wav")
		voice.bus = "Effects"
		voice.max_polyphony = 1
		add_child(voice)
		cue_players.append(voice)
	radio_player = cue_players[0]

func notify_event(kind: String, event_id: String = "") -> bool:
	# Shot / DCA / explosion / engine are intentionally absent from EVENTS.
	if not EVENTS.has(kind):
		return false
	var spec: Dictionary = EVENTS[kind]
	var key := kind + ":" + event_id
	if not event_id.is_empty() and key in _recent_keys:
		events_suppressed += 1
		return false
	if _clock - float(_last_kind_time.get(kind, -INF)) < float(spec.cooldown):
		events_suppressed += 1
		return false
	if duck_phase != DuckPhase.IDLE and int(spec.priority) < _duck_priority:
		events_suppressed += 1
		return false
	if not _schedule_cue(spec):
		events_suppressed += 1
		return false
	_last_kind_time[kind] = _clock
	if not event_id.is_empty():
		_recent_keys.append(key)
		if _recent_keys.size() > EVENT_HISTORY_CAPACITY:
			_recent_keys.pop_front()
	events_accepted += 1
	_duck_priority = int(spec.priority)
	_guard_from = _guard_db
	_guard_target = maxf(_guard_db, float(spec.guard))
	_duck_from = duck_db
	_duck_target = maxf(duck_db, float(spec.duck))
	_duck_elapsed = 0.0
	_hold_remaining = HOLD_SECONDS
	duck_phase = DuckPhase.ATTACK if _duck_target > duck_db + .00001 or _guard_target > _guard_db + .00001 else DuckPhase.HOLD
	return true

func _schedule_cue(spec: Dictionary) -> bool:
	var chosen := -1
	for index in range(CUE_VOICES):
		if _cue_remaining[index] <= 0.0 and _pending_cues[index].is_empty():
			chosen = index
			break
	if chosen >= 0:
		_start_cue(chosen, spec)
		return true
	chosen = 0 if _cue_priorities[0] < _cue_priorities[1] else 1
	if int(spec.priority) <= _cue_priorities[chosen]:
		return false
	# A critical event retires a low-priority tail over 35ms, then reuses that
	# voice. At most one pending event per voice; no queue of stale rewards.
	# A second preemption must continue from the already attenuated tail,
	# rather than restoring the original cue gain for another 35ms fade.
	_cue_base[chosen] = cue_players[chosen].volume_db
	_pending_cues[chosen] = spec.duplicate()
	_cue_priorities[chosen] = int(spec.priority)
	_cue_retire[chosen] = CUE_RETIRE_SECONDS
	cue_preemptions += 1
	return true

func _start_cue(index: int, spec: Dictionary) -> void:
	var voice := cue_players[index]
	voice.pitch_scale = float(spec.pitch)
	voice.volume_db = float(spec.gain)
	voice.play()
	_cue_base[index] = float(spec.gain)
	_cue_priorities[index] = int(spec.priority)
	_cue_remaining[index] = voice.stream.get_length() / voice.pitch_scale
	_cue_retire[index] = 0.0
	_pending_cues[index] = {}

func update_combat(director: Node) -> void:
	# Ordinary compatibility radio has no language-dependent string heuristics.
	# Important radio can explicitly call notify_event("radio_important", id).
	if director.radio_time > 0.0:
		if director.radio != previous_radio:
			previous_radio = str(director.radio)
			notify_event("radio", previous_radio + ":" + str(events_accepted))
	else:
		previous_radio = ""
	var boss = director.get("boss")
	if is_instance_valid(boss) and boss.alive:
		var id: int = boss.get_instance_id()
		if id != _last_boss_id:
			_last_boss_id = id
			_last_boss_phase = int(boss.phase)
			notify_event("boss", str(id))
		elif int(boss.phase) > _last_boss_phase:
			_last_boss_phase = int(boss.phase)
			notify_event("danger", "%d:%d" % [id, _last_boss_phase])
	var mastery = director.get("mastery")
	if is_instance_valid(mastery):
		var multiplier := int(mastery.multiplier)
		if multiplier > _last_multiplier:
			notify_event("reward", "chain:%d:%d" % [int(mastery.best_chain), events_accepted])
		_last_multiplier = multiplier
		if mastery.secondary_complete and not _secondary_seen:
			_secondary_seen = true
			notify_event("reward", "secondary")

func set_mode(mode: String) -> void:
	if not tracks.has(mode):
		return
	if mode == current_mode:
		pending_mode = ""
		return
	if fade < 1.0:
		pending_mode = mode
		return
	_begin_mode(mode)

func _begin_mode(mode: String) -> void:
	current_mode = mode
	current = 1 - current
	_fade_from = _gains.duplicate()
	players[current].stream = tracks[mode]
	players[current].volume_db = -86.0
	players[current].play()
	fade = 0.0

func _process(delta: float) -> void:
	advance(delta)

func advance(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	_clock += delta
	_advance_crossfade(delta)
	_advance_duck(delta)
	_advance_cues(delta)
	for index in range(2):
		players[index].volume_db = MUSIC_BASE_DB + linear_to_db(maxf(.0001, _gains[index])) - duck_db
	var guard := _guard_db
	if absf(guard - _last_guard) > .00001:
		_last_guard = guard
		foreground_gain_changed.emit(guard)

func _advance_crossfade(delta: float) -> void:
	var remaining := delta
	for transition in range(2):
		if fade >= 1.0:
			break
		var used := minf(remaining, (1.0 - fade) * CROSSFADE_SECONDS)
		remaining -= used
		fade = minf(1.0, fade + used / CROSSFADE_SECONDS)
		for index in range(2):
			_gains[index] = lerpf(_fade_from[index], 1.0 if index == current else 0.0, fade)
		if fade >= 1.0:
			players[1 - current].stop()
			if not pending_mode.is_empty():
				var requested := pending_mode
				pending_mode = ""
				_begin_mode(requested)

func _advance_duck(delta: float) -> void:
	var remaining := delta
	for transition in range(3):
		if duck_phase == DuckPhase.IDLE or remaining <= 0.0:
			break
		if duck_phase == DuckPhase.HOLD:
			var used := minf(remaining, _hold_remaining)
			remaining -= used
			_hold_remaining -= used
			if _hold_remaining <= .000001:
				duck_phase = DuckPhase.RELEASE
				_duck_from = duck_db
				_guard_from = _guard_db
				_duck_elapsed = 0.0
			continue
		var duration := ATTACK_SECONDS if duck_phase == DuckPhase.ATTACK else RELEASE_SECONDS
		var used := minf(remaining, duration - _duck_elapsed)
		remaining -= used
		_duck_elapsed = minf(duration, _duck_elapsed + used)
		var t := smoothstep(0.0, 1.0, _duck_elapsed / duration)
		duck_db = lerpf(_duck_from, _duck_target if duck_phase == DuckPhase.ATTACK else 0.0, t)
		_guard_db = lerpf(_guard_from, _guard_target if duck_phase == DuckPhase.ATTACK else 0.0, t)
		if _duck_elapsed >= duration:
			if duck_phase == DuckPhase.ATTACK:
				duck_phase = DuckPhase.HOLD
			else:
				duck_phase = DuckPhase.IDLE
				duck_db = 0.0
				_duck_priority = 0
				_guard_target = 0.0
				_guard_db = 0.0

func _advance_cues(delta: float) -> void:
	for index in range(CUE_VOICES):
		_cue_remaining[index] = maxf(0.0, _cue_remaining[index] - delta)
		if _cue_retire[index] <= 0.0:
			continue
		_cue_retire[index] = maxf(0.0, _cue_retire[index] - delta)
		cue_players[index].volume_db = _cue_base[index] + linear_to_db(maxf(.0001, _cue_retire[index] / CUE_RETIRE_SECONDS))
		if _cue_retire[index] <= .000001:
			_cue_retire[index] = 0.0
			cue_players[index].stop()
			_start_cue(index, _pending_cues[index])

func mix_status() -> Dictionary:
	return {"duck_db": duck_db, "duck_phase": duck_phase, "priority": _duck_priority,
		"guard_db": _last_guard, "events": events_accepted, "suppressed": events_suppressed,
		"preemptions": cue_preemptions, "history": _recent_keys.size(),
		"music_voices": players.size(), "cue_voices": cue_players.size(),
		"music_gain_sum": _gains[0] + _gains[1], "mode": current_mode, "pending_mode": pending_mode}

func begin_run() -> void:
	# A campaign can advance after a win without stopping Music. Reset only
	# mission-local admission/alert state; keep both music voices and their fade.
	_reset_events()
	for index in range(players.size()):
		players[index].volume_db = MUSIC_BASE_DB + linear_to_db(maxf(.0001, _gains[index]))

func _reset_events() -> void:
	for voice in cue_players:
		voice.stop()
	_cue_remaining.fill(0.0)
	_cue_retire.fill(0.0)
	_cue_priorities.fill(0)
	_pending_cues = [{}, {}]
	previous_radio = ""
	_clock = 0.0
	duck_db = 0.0
	duck_phase = DuckPhase.IDLE
	_duck_from = 0.0
	_duck_target = 0.0
	_duck_elapsed = 0.0
	_hold_remaining = 0.0
	_duck_priority = 0
	_guard_target = 0.0
	_guard_from = 0.0
	_guard_db = 0.0
	_last_guard = 0.0
	_last_boss_id = 0
	_last_boss_phase = 0
	_last_multiplier = 1
	_secondary_seen = false
	_recent_keys.clear()
	_last_kind_time.clear()
	foreground_gain_changed.emit(0.0)

func stop() -> void:
	for voice in players:
		voice.stop()
	_gains.fill(0.0)
	fade = 1.0
	current_mode = ""
	pending_mode = ""
	_reset_events()
