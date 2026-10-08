extends SceneTree
## FUTURE #19 validation: install candidates AND targeted hooks first.
## Records real audio-server output from production voices with a scripted
## cumulative stress schedule. This is not a human-play or audibility verdict.
## Silent launch contract (real WASAPI driver, never --headless/Dummy):
## --mute-ack-file=<new absolute JSON path> --mute-token=<unique nonce>
## --output-dir=<absolute directory>
## Wait for the printed handshake, mute/verify THIS PID in the Windows session
## mixer, then atomically publish {pid:<PID>,muted:true,volume:0,token:<nonce>}.
## No audio player is created before that acknowledgement is accepted.
const MUSIC := preload("res://scripts/campaign/music.gd")
const WEAPON := preload("res://scripts/weapon_audio.gd")
const CLIP_SECONDS := 8.0
const MUTE_ACK_TIMEOUT_SECONDS := 60.0
const WEAPON_RANDOM_SEED := 1942
const REQUEST_TRACE_CAPACITY := 160
const CUE_SCHEDULE := [
	{"at": 1.2, "kind": "reward"}, {"at": 2.0, "kind": "boss"},
	{"at": 3.4, "kind": "radio_important"}, {"at": 4.8, "kind": "danger"},
	{"at": 6.5, "kind": "reward"}
]
const PROFILES := [
	{"id": "full", "music": 1.0, "effects": 1.0},
	{"id": "music-only", "music": 1.0, "effects": 0.0},
	{"id": "effects-only", "music": 0.0, "effects": 1.0},
	{"id": "user-sliders", "music": .37, "effects": .68}
]
var checks := 0
var failures: Array[String] = []
var observations: Array[Dictionary] = []
var saved_buses: Dictionary = {}
var created_buses: Array[String] = []
var output_dir := OS.get_user_data_dir().path_join("audio-priority-review")
var mute_ack_file := ""
var mute_token := ""
var mute_ack: Dictionary = {}
var recorded_weapon_bases: Array[float] = []

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output-dir="):
			output_dir = ProjectSettings.globalize_path(argument.trim_prefix("--output-dir="))
		elif argument.begins_with("--mute-ack-file="):
			mute_ack_file = argument.trim_prefix("--mute-ack-file=")
		elif argument.begins_with("--mute-token="):
			mute_token = argument.trim_prefix("--mute-token=")
	if output_dir.is_empty():
		push_error("Audio recording output directory is empty")
		quit(1)
		return
	var directory_error := DirAccess.make_dir_recursive_absolute(output_dir)
	if directory_error != OK:
		push_error("Cannot create audio recording output directory: %s (%s)" % [output_dir, error_string(directory_error)])
		quit(1)
		return
	if AudioServer.get_driver_name() == "Dummy":
		push_error("Audio recording requires a real audio driver, not Dummy; no playback was started")
		quit(1)
		return
	if mute_ack_file.is_empty() or not mute_ack_file.is_absolute_path() or mute_token.is_empty():
		push_error("Audio recording requires --mute-ack-file=<new absolute path> and --mute-token=<unique nonce>")
		quit(1)
		return
	if FileAccess.file_exists(mute_ack_file) or DirAccess.dir_exists_absolute(mute_ack_file):
		push_error("Windows mute acknowledgement path already exists; refusing a stale handshake")
		quit(1)
		return
	_wait_for_mute_ack.call_deferred()

func _wait_for_mute_ack() -> void:
	print("Audio capture awaiting Windows mute ack: pid=%d path=%s token=%s" % [OS.get_process_id(), mute_ack_file, mute_token])
	var started_usec := Time.get_ticks_usec()
	while float(Time.get_ticks_usec() - started_usec) / 1000000.0 < MUTE_ACK_TIMEOUT_SECONDS:
		if FileAccess.file_exists(mute_ack_file):
			var file := FileAccess.open(mute_ack_file, FileAccess.READ)
			if file == null:
				push_error("Cannot read Windows mute acknowledgement (%s)" % error_string(FileAccess.get_open_error()))
				quit(1)
				return
			var contents := file.get_as_text()
			var read_error := file.get_error()
			file.close()
			var parsed = JSON.parse_string(contents)
			if read_error not in [OK, ERR_FILE_EOF] or not _valid_mute_ack(parsed):
				push_error("Windows mute acknowledgement is malformed or has the wrong PID/token/mute/volume")
				quit(1)
				return
			mute_ack = parsed.duplicate(true)
			mute_ack["ack_file"] = mute_ack_file
			mute_ack["wait_seconds"] = float(Time.get_ticks_usec() - started_usec) / 1000000.0
			mute_ack["verification"] = "EXTERNAL_WINDOWS_SESSION_HARNESS_ACKNOWLEDGED"
			await _run()
			return
		await process_frame
	push_error("Windows mute acknowledgement timed out after 60s; no playback was started")
	quit(1)

func _valid_mute_ack(value) -> bool:
	if not value is Dictionary:
		return false
	var data: Dictionary = value
	if typeof(data.get("pid")) not in [TYPE_INT, TYPE_FLOAT] or typeof(data.get("volume")) not in [TYPE_INT, TYPE_FLOAT]:
		return false
	return (
		is_finite(float(data.pid)) and float(data.pid) == float(OS.get_process_id())
		and typeof(data.get("muted")) == TYPE_BOOL and bool(data.muted)
		and is_finite(float(data.volume)) and float(data.volume) == 0.0
		and typeof(data.get("token")) == TYPE_STRING and str(data.token) == mute_token
	)

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error(label)

func _freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children():
		_freeze(child)

func _effects(node: Node) -> void:
	if node is AudioStreamPlayer or node is AudioStreamPlayer3D:
		node.bus = "Effects"
	for child in node.get_children():
		_effects(child)

func _prepare_buses() -> void:
	# This capture needs the real internal mixer. Silence the Godot process in
	# the Windows session mixer from the external harness, not this Master bus.
	for bus_name in ["Master", "Music", "Effects"]:
		var index := AudioServer.get_bus_index(bus_name)
		if index < 0:
			AudioServer.add_bus()
			index = AudioServer.bus_count - 1
			AudioServer.set_bus_name(index, bus_name)
			created_buses.append(bus_name)
		saved_buses[bus_name] = {"gain": AudioServer.get_bus_volume_db(index), "mute": AudioServer.is_bus_mute(index)}
		AudioServer.set_bus_mute(index, false)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), 0.0)

func _apply_profile(profile: Dictionary) -> void:
	for key in ["music", "effects"]:
		var index := AudioServer.get_bus_index("Music" if key == "music" else "Effects")
		var value := float(profile[key])
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(.001, value)))
		AudioServer.set_bus_mute(index, value == 0.0)

func _measure(stream: AudioStreamWAV) -> Dictionary:
	var bytes := stream.data
	var peak := 0
	var saturated := 0
	var squared := 0.0
	var bins: Array[Dictionary] = []
	var block := maxi(1, roundi(stream.mix_rate * .25) * (2 if stream.stereo else 1))
	var block_peak := 0
	var block_squared := 0.0
	var samples := bytes.size() / 2
	for sample_index in range(samples):
		var value := bytes.decode_s16(sample_index * 2)
		var absolute := absi(value)
		peak = maxi(peak, absolute)
		block_peak = maxi(block_peak, absolute)
		saturated += 1 if absolute >= 32767 else 0
		var normalised := float(value) / 32768.0
		squared += normalised * normalised
		block_squared += normalised * normalised
		if (sample_index + 1) % block == 0:
			bins.append({"start_seconds": float(sample_index + 1 - block) / (stream.mix_rate * (2 if stream.stereo else 1)), "peak_dbfs": linear_to_db(maxf(.000001, float(block_peak) / 32768.0)), "rms_dbfs": linear_to_db(maxf(.000001, sqrt(block_squared / block)))})
			block_peak = 0
			block_squared = 0.0
	return {"samples": samples, "duration": stream.get_length(), "peak_pcm16": peak, "peak_dbfs": linear_to_db(maxf(.000001, float(peak) / 32768.0)), "rms_dbfs": linear_to_db(maxf(.000001, sqrt(squared / maxi(samples, 1)))), "saturated_samples": saturated, "quarter_second_windows": bins}

func _record_request_timing(statistics: Dictionary, kind: String, scheduled: float, actual: float, accepted := true) -> void:
	# Aggregate other voices without an unbounded per-frame/per-shot trace.
	# Times are relative to the loop's monotonic start, not PCM sample indices.
	var delay_ms := (actual - scheduled) * 1000.0
	var summary: Dictionary = statistics.get(kind, {"requests": 0, "accepted": 0,
		"first_timeactual": actual, "last_timeactual": actual,
		"delay_min_ms": delay_ms, "delay_max_ms": delay_ms, "delay_sum_ms": 0.0})
	summary.requests = int(summary.requests) + 1
	summary.accepted = int(summary.accepted) + (1 if accepted else 0)
	summary.last_timeactual = actual
	summary.delay_min_ms = minf(float(summary.delay_min_ms), delay_ms)
	summary.delay_max_ms = maxf(float(summary.delay_max_ms), delay_ms)
	summary.delay_sum_ms = float(summary.delay_sum_ms) + delay_ms
	statistics[kind] = summary

func _record_profile(profile: Dictionary) -> void:
	_apply_profile(profile)
	var label := str(profile.id)
	var fixture = preload("res://scenes/main.tscn").instantiate()
	root.add_child(fixture)
	_freeze(fixture)
	_effects(fixture)
	var departure = fixture.get_node("Departure")
	var engine = departure.engine_audio
	var weapons = fixture.get_node("Weapons")
	var combat = fixture.get_node("Combat")
	var player = fixture.get_node("Player")
	var camera = fixture.get_node("Camera")
	check(weapons.audio.get_script() == WEAPON, label + " uses the integrated weapon candidate")
	if not weapons.audio.has_method("voice_status"):
		fixture.free()
		return
	check(bool(weapons.audio.voice_status().laser_bound), label + " requires the real Weapons.ready laser hook")
	# _ready randomizes normal gameplay; freeze only this fixture's private RNG
	# afterwards, before its first salvo. Same seed on each isolated profile.
	weapons.audio._rng.seed = WEAPON_RANDOM_SEED
	var initial_rng_state: String = str(weapons.audio._rng.state)
	var initial_weapon_base: float = weapons.audio.volume_db
	recorded_weapon_bases.append(initial_weapon_base)
	var weapon_base_unchanged := is_finite(initial_weapon_base)
	engine.stop()
	player.position = Vector3.ZERO
	camera.position = Vector3(0, 40, 0)
	departure.active = true
	departure.landing_active = false
	departure.elapsed = departure.RUN_END
	engine.start()
	engine.set_physics_process(false)
	var music: Node = MUSIC.new()
	root.add_child(music)
	music.set_process(false)
	music.foreground_gain_changed.connect(weapons.audio.set_alert_attenuation)
	music.set_mode("boss")
	# Warm the crossfade numerically, but engine attack is recorded from actual
	# production start(). Music playback then advances on the audio thread.
	music.advance(1.5)
	var recorder := AudioEffectRecord.new()
	recorder.format = AudioStreamWAV.FORMAT_16_BITS
	AudioServer.add_bus_effect(AudioServer.get_bus_index("Master"), recorder)
	recorder.set_recording_active(true)
	var elapsed := 0.0
	var previous_tick := Time.get_ticks_usec()
	var loop_started_usec := previous_tick
	var weapon_requests: Array[Dictionary] = []
	var trace_dropped := 0
	var request_timings: Dictionary = {}
	var cue_request_times: Array[Dictionary] = []
	var laser_request_times: Array[Dictionary] = []
	var previous_laser_active := false
	var next_salvo := .08
	var next_enemy := .06
	var next_bomber := .18
	var next_ground := .10
	var next_explosion := .44
	var fired_events: Dictionary = {}
	var max_guard := 0.0
	var max_duck := 0.0
	while elapsed < CLIP_SECONDS:
		await process_frame
		var now := Time.get_ticks_usec()
		var actual_seconds := float(now - loop_started_usec) / 1000000.0
		var delta := minf(.25, float(now - previous_tick) / 1000000.0)
		previous_tick = now
		elapsed += delta
		weapon_base_unchanged = weapon_base_unchanged and is_finite(float(weapons.audio.volume_db)) and is_equal_approx(float(weapons.audio.volume_db), initial_weapon_base)
		engine._physics_process(delta)
		music.advance(delta)
		weapons.audio.advance(delta)
		combat.ground_audio_cooldown = maxf(0.0, combat.ground_audio_cooldown - delta)
		var signature := "standard" if elapsed < 2.8 else "spread"
		if elapsed < 5.0 and elapsed >= next_salvo:
			weapons.audio.play_salvo(signature)
			if weapon_requests.size() < REQUEST_TRACE_CAPACITY:
				var voice: AudioStreamPlayer = weapons.audio.voices[(int(weapons.audio._cursor) + WEAPON.VOICE_COUNT - 1) % WEAPON.VOICE_COUNT]
				weapon_requests.append({"timeactual": actual_seconds, "scheduled_due": next_salvo,
					"variant": int(weapons.audio.last_variant), "pitch": voice.pitch_scale,
					"gain": voice.volume_db, "signature": str(weapons.audio.last_signature),
					"voicesstolen": int(weapons.audio.voices_stolen)})
			else:
				trace_dropped += 1
			_record_request_timing(request_timings, "player_salvo", next_salvo, actual_seconds)
			next_salvo = elapsed + .035 # Deliberately saturates the eight-voice pool.
		if elapsed >= next_enemy:
			combat.gun_audio.play()
			_record_request_timing(request_timings, "enemy_gun", next_enemy, actual_seconds)
			next_enemy = elapsed + .045
		if elapsed >= next_bomber:
			combat.bomber_audio.play()
			_record_request_timing(request_timings, "bomber_gun", next_bomber, actual_seconds)
			next_bomber = elapsed + .11
		if elapsed >= next_ground:
			var ground_ready: bool = float(combat.ground_audio_cooldown) <= 0.0
			combat.play_ground_volley("bunker" if fmod(elapsed, 1.0) < .5 else "gun", true)
			_record_request_timing(request_timings, "ground_volley", next_ground, actual_seconds, ground_ready)
			next_ground = elapsed + .04 # Production 75ms guard still applies.
		if elapsed >= next_explosion:
			combat.explosion_audio.play()
			_record_request_timing(request_timings, "explosion", next_explosion, actual_seconds)
			next_explosion = elapsed + .42
		var laser_active := elapsed >= 5.0 and elapsed < 7.0
		weapons.audio.set_laser_active(laser_active)
		if laser_active != previous_laser_active:
			laser_request_times.append({"active": laser_active, "timeactual": actual_seconds, "scheduled_due": 5.0 if laser_active else 7.0})
			previous_laser_active = laser_active
		for cue in CUE_SCHEDULE:
			var cue_id := "%s:%.1f" % [str(cue.kind), float(cue.at)]
			if elapsed >= float(cue.at) and not fired_events.has(cue_id):
				fired_events[cue_id] = music.notify_event(str(cue.kind), label + ":" + str(cue.at))
				cue_request_times.append({"kind": str(cue.kind), "timeactual": actual_seconds, "scheduled_due": float(cue.at), "accepted": bool(fired_events[cue_id])})
		max_guard = maxf(max_guard, float(weapons.audio.alert_attenuation_db))
		max_duck = maxf(max_duck, float(music.duck_db))
	recorder.set_recording_active(false)
	var stream: AudioStreamWAV = recorder.get_recording()
	var path := output_dir.path_join("audio-priority-" + label + ".wav")
	check(stream != null and stream.data.size() > 0, label + " records actual nonempty audio-server output")
	if stream != null:
		check(stream.save_to_wav(path) == OK, label + " saves its isolated listening clip")
		check(stream.format == AudioStreamWAV.FORMAT_16_BITS and stream.data.size() % 2 == 0, label + " is measured as complete signed PCM16 samples")
		if stream.format != AudioStreamWAV.FORMAT_16_BITS or stream.data.size() % 2 != 0:
			stream = null
	if stream != null:
		var measures := _measure(stream)
		measures["profile"] = profile
		measures["path"] = ProjectSettings.globalize_path(path)
		measures["events"] = fired_events
		measures["duck_max_db"] = max_duck
		measures["guard_max_db"] = max_guard
		measures["weapons"] = weapons.audio.voice_status()
		measures["music"] = music.mix_status()
		measures["weapon_rng"] = {"seed": WEAPON_RANDOM_SEED, "initial_state": initial_rng_state, "final_state": str(weapons.audio._rng.state)}
		measures["weapon_base_db"] = initial_weapon_base
		measures["weapon_request_trace"] = weapon_requests
		measures["trace_capacity"] = REQUEST_TRACE_CAPACITY
		measures["trace_dropped"] = trace_dropped
		measures["request_timings"] = request_timings
		measures["cue_request_times"] = cue_request_times
		measures["laser_request_times"] = laser_request_times
		measures["timing_limit"] = "Fixed RNG sequence per profile; frame/audio-buffer timing varies. No identical-PCM replay claim."
		observations.append(measures)
		check(weapon_base_unchanged, label + " keeps its selected player gun base level unchanged throughout the capture")
		check(weapon_requests.size() <= REQUEST_TRACE_CAPACITY and trace_dropped == 0 and weapon_requests.size() == int(weapons.audio.salvos_played), label + " has a complete bounded trace of every player salvo request")
		check(int(measures.peak_pcm16) > 100, label + " is audible instead of a silent/dummy mixer")
		check(int(measures.saturated_samples) == 0 and int(measures.peak_pcm16) < 32760, label + " has no PCM16 saturation at these cumulative levels")
		check(float(measures.duration) >= CLIP_SECONDS - .25, label + " contains the complete cumulative schedule")
		check(max_duck <= 4.001 and max_guard <= 2.001, label + " semantic attenuation remains bounded")
		check(weapons.audio.voices.size() == 8 and weapons.audio.get_child_count() == 8, label + " stress does not grow the gun pool")
		check(music.players.size() == 2 and music.cue_players.size() == 2 and music.get_child_count() == 4, label + " stress preserves music/cue node budgets")
		check(engine.voices.size() == 2 and engine.get_child_count() == 2, label + " approved engine keeps two stems")
		check(combat.gun_audio.max_polyphony == 8 and combat.explosion_audio.max_polyphony == 4 and combat.bomber_audio.max_polyphony == 4 and combat.ground_audio.max_polyphony == 4, label + " cumulative hostile/effect voices retain production limits")
		check(weapons.audio.voices_stolen > 0, label + " actually exercised bounded gun saturation")
		for cue in CUE_SCHEDULE:
			var cue_id := "%s:%.1f" % [str(cue.kind), float(cue.at)]
			check(bool(fired_events.get(cue_id, false)), label + " critical/reward event really ran: " + cue_id)
		for voice in music.players:
			check(voice.pitch_scale == 1.0 and voice.max_polyphony == 1, label + " action tempo and music polyphony are unchanged")
		for key in ["music", "effects"]:
			var index := AudioServer.get_bus_index("Music" if key == "music" else "Effects")
			check(AudioServer.is_bus_mute(index) == (float(profile[key]) == 0.0), label + " preserves the " + key + " mute")
			check(absf(AudioServer.get_bus_volume_db(index) - linear_to_db(maxf(.001, float(profile[key])))) < .0001, label + " preserves the " + key + " slider")
	# Remove this exact recorder, not an unrelated pre-existing bus effect.
	var master_index := AudioServer.get_bus_index("Master")
	for index in range(AudioServer.get_bus_effect_count(master_index) - 1, -1, -1):
		if AudioServer.get_bus_effect(master_index, index) == recorder:
			AudioServer.remove_bus_effect(master_index, index)
			break
	music.stop()
	weapons.audio.stop_all()
	engine.stop()
	for voice in [combat.gun_audio, combat.explosion_audio, combat.bomber_audio, combat.ground_audio]:
		voice.stop()
	root.remove_child(music)
	music.free()
	root.remove_child(fixture)
	fixture.free()
	await process_frame
	await process_frame
	await create_timer(.1).timeout

func _run() -> void:
	_prepare_buses()
	for profile in PROFILES:
		await _record_profile(profile)
	var completed_ids: Array[String] = []
	for observation in observations:
		completed_ids.append(str(observation.profile.id))
	check(observations.size() == PROFILES.size() and completed_ids == ["full", "music-only", "effects-only", "user-sliders"], "All four distinct physical-mixer profiles completed and produced measurable recordings")
	var matching_bases := recorded_weapon_bases.size() == PROFILES.size()
	for base in recorded_weapon_bases:
		matching_bases = matching_bases and is_finite(base) and is_equal_approx(base, recorded_weapon_bases[0])
	check(matching_bases, "All four slider profiles use the same unchanged player gun base level")
	for bus_name in saved_buses:
		var index := AudioServer.get_bus_index(bus_name)
		AudioServer.set_bus_volume_db(index, float(saved_buses[bus_name].gain))
		AudioServer.set_bus_mute(index, bool(saved_buses[bus_name].mute))
	created_buses.reverse()
	for bus_name in created_buses:
		AudioServer.remove_bus(AudioServer.get_bus_index(bus_name))
	var hashes: Dictionary = {}
	for path in ["res://assets/campaign/music/flight.wav", "res://assets/campaign/music/flight2.wav", "res://assets/campaign/music/boss.wav", "res://assets/campaign/music/radio-cue.wav", "res://assets/campaign/laser-loop.wav", "res://assets/audio/engine/merlin-exhaust.wav", "res://assets/audio/engine/merlin-body.wav"]:
		hashes[path] = FileAccess.get_sha256(path)
	var report := {"checks": checks, "failures": failures, "recordings": observations, "source_hashes": hashes, "mute_ack": mute_ack, "fixture": "Production main scene/audio players, frozen gameplay and scripted cumulative requests", "headroom": "Actual captured PCM16 peaks; not a limiter or a perceptual judgement", "human_listening": "NOT_PERFORMED", "alert_intelligibility": "HUMAN_LISTEN_REQUIRED", "driver": AudioServer.get_driver_name(), "performance": "NOT_MEASURED"}
	var file := FileAccess.open(output_dir.path_join("audio-priority-recording-results.json"), FileAccess.WRITE)
	var written := false
	if file == null:
		check(false, "Cannot open audio recording report: %s (%s)" % [output_dir, error_string(FileAccess.get_open_error())])
	else:
		file.store_string(JSON.stringify(report, "\t"))
		file.flush()
		var write_error := file.get_error()
		file.close()
		written = write_error == OK
		if not written:
			check(false, "Audio recording report cannot be completely written (%s)" % error_string(write_error))
	print("Audio priority recordings: %d checks / %d failures" % [checks, failures.size()])
	quit(0 if written and failures.is_empty() else 1)
