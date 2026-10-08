extends SceneTree
## FUTURE #19 test: install candidates/hooks first. No human-listening claim.
const MUSIC := preload("res://scripts/campaign/music.gd")
const WEAPON := preload("res://scripts/weapon_audio.gd")
const MASTERY := preload("res://scripts/campaign/mastery.gd")
class DirectorStub extends Node:
	var radio_time := 0.0
	var radio := ""
	var boss: Node
	var mastery

var checks := 0
var failures: Array[String] = []
var saved_bus_state: Dictionary = {}
var created_buses: Array[String] = []
var cue_retirement_observations: Array[Dictionary] = []
var output_dir := OS.get_user_data_dir().path_join("audio-priority-review")

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output-dir="):
			output_dir = ProjectSettings.globalize_path(argument.trim_prefix("--output-dir="))
	if output_dir.is_empty():
		push_error("Audio controls output directory is empty")
		quit(1)
		return
	var directory_error := DirAccess.make_dir_recursive_absolute(output_dir)
	if directory_error != OK:
		push_error("Cannot create audio controls output directory: %s (%s)" % [output_dir, error_string(directory_error)])
		quit(1)
		return
	# This numerical suite does not need a physical audio session. Refuse a
	# launch that could briefly emit a production fixture's ready-time engine.
	if AudioServer.get_driver_name() != "Dummy":
		push_error("Audio controls require --audio-driver Dummy; no playback was started")
		quit(1)
		return
	_run.call_deferred()

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error(label)

func _advance(music: Node, duration: float, step := 1.0 / 60.0) -> void:
	var remaining := duration
	while remaining > .0000001:
		var used := minf(remaining, step)
		music.advance(used)
		remaining -= used

func _prepare_buses() -> void:
	for bus_name in ["Master", "Music", "Effects"]:
		var index := AudioServer.get_bus_index(bus_name)
		if index < 0:
			AudioServer.add_bus()
			index = AudioServer.bus_count - 1
			AudioServer.set_bus_name(index, bus_name)
			created_buses.append(bus_name)
		saved_bus_state[bus_name] = {"gain": AudioServer.get_bus_volume_db(index), "mute": AudioServer.is_bus_mute(index)}
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), true)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), linear_to_db(.37))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Effects"), linear_to_db(.68))

func _freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children():
		_freeze(child)

func _write_report(report: Dictionary) -> bool:
	var path := output_dir.path_join("audio-mix-controls-results.json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		check(false, "Cannot open audio controls report: %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		return false
	file.store_string(JSON.stringify(report, "\t"))
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		check(false, "Cannot finish audio controls report: %s (%s)" % [path, error_string(write_error)])
		return false
	return true

func _run() -> void:
	_prepare_buses()
	var music: Node = MUSIC.new()
	root.add_child(music)
	music.set_process(false)
	var weapon: Node = WEAPON.new()
	root.add_child(weapon)
	weapon.set_process(false)
	music.foreground_gain_changed.connect(weapon.set_alert_attenuation)
	var target_music_db := AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music"))
	var target_effects_db := AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Effects"))
	check(music.players.size() == 2 and music.cue_players.size() == 2, "Fixed two music / two cue voices")
	for step in [1.0 / 30.0, 1.0 / 60.0, 1.0 / 120.0]:
		music.stop()
		music.set_mode("flight")
		_advance(music, 1.5, step)
		check(music.notify_event("boss", "entry"), "Boss event accepted at fresh start")
		check(absf(music.duck_db) < .00001, "Event does not instantly jump music gain")
		_advance(music, .120, step)
		check(absf(music.duck_db - 4.0) < .001, "120ms reaches exact 4dB target at each frame rate")
		check(absf(weapon.alert_attenuation_db - 2.0) < .001, "Critical guard reaches 2dB without bus edits")
		_advance(music, .450, step)
		check(absf(music.duck_db - 4.0) < .001, "450ms hold preserves target")
		_advance(music, .350, step)
		check(absf(music.duck_db - 2.0) < .001, "Release midpoint is continuous at 350ms")
		_advance(music, .350, step)
		check(music.duck_db < .001 and weapon.alert_attenuation_db < .001, "700ms release returns both layers to original gain")
		check(absf(music.players[music.current].volume_db + 6.0) < .001, "Action music restores original player gain")
	music.stop()
	music.set_mode("flight")
	_advance(music, 1.5)
	check(music.notify_event("reward", "chain-4"), "First chain reward accepted")
	_advance(music, .040)
	var before: float = music.duck_db
	check(music.notify_event("radio_important", "raid-entry"), "Important radio supersedes low reward")
	check(absf(music.duck_db - before) < .001, "Retarget starts at current envelope")
	check(not music.notify_event("reward", "chain-8"), "Low reward cannot extend critical duck")
	check(not music.notify_event("radio_important", "raid-entry"), "Same semantic ID cannot retrigger")
	_advance(music, .001)
	check(weapon.alert_attenuation_db < .005, "Guard retarget also starts continuously after a reward")
	_advance(music, .119)
	check(absf(music.duck_db - 4.0) < .001, "Retarget reaches bounded critical depth")
	music.stop()
	check(music.notify_event("reward", "tail"), "Lower-priority cue starts on first fixed voice")
	check(music.notify_event("radio", "instruction"), "Second cue uses the remaining fixed voice")
	check(music.notify_event("boss", "preempt"), "Critical cue retires the lowest-priority occupied voice")
	check(music.cue_preemptions == 1 and not music._pending_cues[0].is_empty(), "Preemption stores one bounded pending cue")
	_advance(music, .0175)
	check(music.cue_players[0].volume_db < -22.9 and not music._pending_cues[0].is_empty(), "Low-priority tail fades before replacement")
	_advance(music, .0175)
	cue_retirement_observations.append({"case": "initial_retirement", "advanced_seconds": .035, "remaining_seconds": float(music._cue_retire[0]), "pending": not music._pending_cues[0].is_empty(), "pitch_scale": float(music.cue_players[0].pitch_scale)})
	# Native AudioStreamPlayer stores pitch as float32 (.72 -> .7200000286).
	# Keep the exact 35ms advances; only compare that native value approximately.
	check(music._pending_cues[0].is_empty() and is_equal_approx(music.cue_players[0].pitch_scale, .72), "Replacement starts only after its 35ms retirement")
	check(music.get_child_count() == 4, "Preemption allocates no extra voices")
	music.stop()
	check(music.notify_event("reward", "double-tail") and music.notify_event("radio", "double-radio"), "Repeated-preemption fixture fills the two real cue voices")
	check(music.notify_event("radio_important", "double-important"), "Important instruction begins retiring its lower-priority tail")
	_advance(music, .0175)
	var retiring_gain: float = music.cue_players[0].volume_db
	check(music.notify_event("danger", "parallel-danger"), "Parallel critical alert occupies the other lower-priority cue")
	check(music.notify_event("boss", "double-boss"), "Boss can replace an important cue still pending on the same voice")
	check(absf(music.cue_players[0].volume_db - retiring_gain) < .0001, "Second preemption leaves the current tail gain continuous")
	_advance(music, .005)
	check(music.cue_players[0].volume_db < retiring_gain and not music._pending_cues[0].is_empty(), "Repeated retirement keeps fading rather than reviving the original loud tail")
	_advance(music, .030)
	cue_retirement_observations.append({"case": "repeated_retirement", "advanced_seconds": .035, "remaining_seconds": float(music._cue_retire[0]), "pending": not music._pending_cues[0].is_empty(), "pitch_scale": float(music.cue_players[0].pitch_scale)})
	check(music._pending_cues[0].is_empty() and is_equal_approx(music.cue_players[0].pitch_scale, .72), "Most important pending cue starts after its complete replacement retirement")
	check(music.get_child_count() == 4, "Repeated retirement retains the four-node music/cue budget")
	music.stop()
	for kind in ["shot", "dca", "explosion", "engine", "laser"]:
		check(not music.notify_event(kind, "ordinary"), kind + " cannot pump the music")
	check(music.duck_db == 0 and music.mix_status().history == 0, "Normal combat leaves envelope/history idle")
	music.set_mode("flight")
	_advance(music, .3)
	music.set_mode("boss")
	music.set_mode("flight2")
	check(music.pending_mode == "flight2", "Rapid music retarget queues latest request without cutting an audible voice")
	_advance(music, 3.0)
	check(music.current_mode == "flight2" and music.pending_mode == "", "Queued transition resolves with two voices")
	check(absf(music.mix_status().music_gain_sum - 1.0) < .0001, "Crossfade amplitude budget never doubles")
	# Two consecutive victories reuse Music in App. They must not reuse an old
	# secondary flag/history or cancel the transition currently audible.
	var director := DirectorStub.new()
	director.mastery = MASTERY.new()
	director.mastery.secondary_complete = true
	music.begin_run()
	var first_events: int = music.events_accepted
	music.update_combat(director)
	check(music.events_accepted == first_events + 1 and music._secondary_seen, "First mission secondary reward is admitted")
	check(not music.notify_event("reward", "secondary"), "Secondary reward stays deduplicated within its mission")
	music.set_mode("victory")
	_advance(music, .3)
	music.set_mode("flight")
	var saved_mode: String = music.current_mode
	var saved_pending: String = music.pending_mode
	var saved_fade: float = music.fade
	var saved_gains: PackedFloat32Array = music._gains.duplicate()
	var second_events: int = music.events_accepted
	music.begin_run()
	check(music.current_mode == saved_mode and music.pending_mode == saved_pending and music.fade == saved_fade and music._gains == saved_gains, "New mission preserves both musical voices and its current/pending fade")
	check(music.players[0].playing and music.players[1].playing, "Run reset leaves both audible crossfade streams playing")
	check(music.duck_db == 0.0 and weapon.alert_attenuation_db == 0.0 and music.mix_status().history == 0, "New flight clears its old alert, weapon guard and semantic history")
	music.update_combat(director)
	check(music.events_accepted == second_events + 1 and music._secondary_seen, "Second consecutive mission admits its own secondary reward without waiting for the previous cooldown")
	check(music.notify_event("boss", "same-run-id"), "First run boss event is admitted")
	music.begin_run()
	check(music.notify_event("boss", "same-run-id"), "New flight resets both semantic deduplication and per-kind cooldown")
	director.free()
	for index in range(24):
		music.stop()
		check(music.notify_event("radio", "pool-%d" % index), "Cue reuse remains functional")
		_advance(music, 1.4)
	check(music.get_child_count() == 4, "Semantic events never allocate another audio node")
	music.stop()
	for index in range(24):
		music.notify_event("reward", "bounded-%d" % index)
		_advance(music, 4.0)
	check(music.mix_status().history <= 16, "Dedup history has a hard bound")
	music.stop()
	music.notify_event("boss", "preserve-slider")
	_advance(music, .06)
	check(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")) == target_music_db, "Music slider remains exact during duck")
	check(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Effects")) == target_effects_db, "Effects slider remains exact during guard")
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Music"), true)
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Effects"), true)
	_advance(music, 2.0)
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")) and AudioServer.is_bus_mute(AudioServer.get_bus_index("Effects")), "User mutes survive all envelope transitions")
	var prior := -1
	for kind in ["standard", "spread"]:
		for index in range(64):
			weapon.play_salvo(kind)
			check(weapon.last_variant != prior, "Original consecutive take variation survives signatures")
			prior = weapon.last_variant
			var voice: AudioStreamPlayer = weapon.voices[(weapon._cursor + WEAPON.VOICE_COUNT - 1) % WEAPON.VOICE_COUNT]
			var lower := .992 if kind == "standard" else .868
			var upper := 1.008 if kind == "standard" else .892
			check(voice.pitch_scale >= lower - .0001 and voice.pitch_scale <= upper + .0001, kind + " has a distinct bounded timbre")
			check(voice.volume_db <= (-5.0 if kind == "standard" else -6.0) + .001, kind + " does not increase original peak gain")
			check(voice.max_polyphony == 1 and voice.bus == "Effects", "Gun voice stays within pool and user Effects control")
	check(weapon.voices.size() == 8 and weapon.get_child_count() == 8, "Saturated salvo requests retain eight fixed voices")
	var beam := AudioStreamPlayer.new()
	beam.stream = preload("res://assets/campaign/laser-loop.wav").duplicate()
	root.add_child(beam)
	weapon.bind_laser(beam)
	weapon.set_alert_attenuation(0)
	weapon.set_laser_active(true)
	weapon.advance(.035)
	check(absf(weapon.laser_level - 1.0) < .001 and absf(beam.volume_db + 15.0) < .001, "Original laser has 35ms attack and unchanged full gain")
	weapon.set_laser_active(false)
	weapon.advance(.035)
	check(absf(weapon.laser_level - .5) < .001 and beam.playing, "Laser release has a real audible tail before stopping")
	weapon.set_laser_active(true)
	weapon.advance(.001)
	check(weapon.laser_level >= .5 and weapon.laser_level < .51, "Laser retrigger continues from current envelope without a gain jump")
	weapon.stop_all()
	check(not beam.playing and weapon.laser_level == 0.0, "Hard gameplay stop cancels pending laser tail/restart")
	check(beam.volume_db <= -75.0, "Gameplay stop primes a quiet first buffer for the next laser attack")
	weapon.process_mode = Node.PROCESS_MODE_PAUSABLE
	weapon.play_salvo("standard")
	weapon.set_laser_active(true)
	weapon.advance(.035)
	paused = true
	await process_frame
	check(not beam.playing and weapon.laser_level == 0.0 and not weapon._laser_active and weapon.voice_status().active == 0, "Real SceneTree pause discards gun/laser playback and its pending envelope")
	paused = false
	await process_frame
	weapon.advance(.2)
	check(not beam.playing and weapon.voice_status().active == 0, "Resume cannot resurrect the pre-pause weapon sounds")
	weapon.set_laser_active(true)
	weapon.advance(.035)
	weapon.process_mode = Node.PROCESS_MODE_DISABLED
	check(not beam.playing and weapon.laser_level == 0.0, "Disabling a run hard-stops its laser")
	weapon.process_mode = Node.PROCESS_MODE_PAUSABLE
	# Exercise the integrated Weapons hooks, rather than inferring a death/POW
	# stop from a direct call to this candidate's stop_all(). No gameplay advances.
	var fixture = preload("res://scenes/main.tscn").instantiate()
	root.add_child(fixture)
	_freeze(fixture)
	var real_weapons = fixture.get_node("Weapons")
	var real_player = fixture.get_node("Player")
	check(real_weapons.audio.get_script() == WEAPON, "Production fixture uses the exact integrated weapon candidate")
	check(real_weapons.audio.has_method("voice_status"), "Production fixture contains the weapon candidate")
	if real_weapons.audio.has_method("voice_status"):
		check(bool(real_weapons.audio.voice_status().laser_bound), "Production Weapons binds its real looping laser")
		real_weapons.set_power("laser")
		real_weapons.audio.set_laser_active(true)
		real_weapons.audio.advance(.035)
		real_player.destroyed.emit(real_player.global_position)
		check(real_weapons.power_type == "none" and not real_weapons.laser_audio.playing and real_weapons.audio.voice_status().active == 0 and real_weapons.audio.laser_level == 0.0, "Real player death signal hard-stops/reset Weapons audio")
		real_weapons.set_power("laser")
		real_weapons.audio.set_laser_active(true)
		real_weapons.audio.advance(.035)
		real_weapons.set_power("spread")
		check(not real_weapons.laser_audio.playing and real_weapons.audio.laser_level == 0.0 and real_weapons.audio.signature == "spread", "Real POW transition stops laser and applies the spread signature")
		real_weapons.audio.stop_all()
	root.remove_child(fixture)
	fixture.free()
	music.stop()
	weapon.stop_all()
	root.remove_child(beam)
	beam.free()
	root.remove_child(weapon)
	weapon.free()
	root.remove_child(music)
	music.free()
	await process_frame
	await process_frame
	await create_timer(.1).timeout
	for bus_name in saved_bus_state:
		var index := AudioServer.get_bus_index(bus_name)
		AudioServer.set_bus_volume_db(index, float(saved_bus_state[bus_name].gain))
		AudioServer.set_bus_mute(index, bool(saved_bus_state[bus_name].mute))
	created_buses.reverse()
	for bus_name in created_buses:
		AudioServer.remove_bus(AudioServer.get_bus_index(bus_name))
	var written := _write_report({"checks": checks, "failures": failures, "driver": AudioServer.get_driver_name(), "cue_retirement_observations": cue_retirement_observations, "waveform_peak": "SEPARATE_RECORDING_REQUIRED", "human_listening": "NOT_PERFORMED"})
	print("Audio mix controls: %d checks / %d failures" % [checks, failures.size()])
	quit(0 if written and failures.is_empty() else 1)
