extends SceneTree
## Silent integration of production event signatures and bounded voice lifecycle.
const MUSIC := preload("res://scripts/campaign/music.gd")
const BANK := preload("res://scripts/campaign/event_audio.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	if AudioServer.get_driver_name() != "Dummy":
		push_error("Event audio validation requires --audio-driver Dummy")
		quit(1)
		return
	_run.call_deferred()

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error(label)

func _run() -> void:
	var created_buses: Array[String] = []
	for bus_name in ["Music", "Effects"]:
		if AudioServer.get_bus_index(bus_name) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus_name)
			created_buses.append(bus_name)
	var effects_index := AudioServer.get_bus_index("Effects")
	var original_gain := AudioServer.get_bus_volume_db(effects_index)
	var original_mute := AudioServer.is_bus_mute(effects_index)
	AudioServer.set_bus_volume_db(effects_index, -9.0)
	AudioServer.set_bus_mute(effects_index, true)
	var music: Node = MUSIC.new()
	root.add_child(music)
	music.set_process(false)
	var streams: Array[int] = []
	var observations: Dictionary = {}
	for kind in MUSIC.EVENTS:
		music.stop()
		var stream: AudioStreamWAV = BANK.stream(kind)
		check(stream.get_instance_id() not in streams, kind + " owns a distinct shared signature")
		streams.append(stream.get_instance_id())
		check(stream == BANK.stream(kind), kind + " never synthesizes or duplicates on event admission")
		check(stream.format == AudioStreamWAV.FORMAT_16_BITS and stream.mix_rate == 44100 and not stream.stereo, kind + " is uncompressed mono PCM at 44.1kHz")
		check(stream.loop_mode == AudioStreamWAV.LOOP_DISABLED, kind + " cannot leave a looping alert")
		var pcm := stream.data
		var peak := 0
		var step := 0
		var previous := 0
		var boundary_silent := true
		for offset in range(0, pcm.size(), 2):
			var sample := pcm.decode_s16(offset)
			peak = maxi(peak, absi(sample))
			step = maxi(step, absi(sample - previous))
			previous = sample
			if offset < 512 or offset >= pcm.size() - 512:
				boundary_silent = boundary_silent and sample == 0
		check(peak > 1000 and peak <= 5898, kind + " audible PCM peak stays below the former cue")
		check(step < 1800 and boundary_silent, kind + " has bounded sample steps and silent boundaries")
		check(music.notify_event(kind, "production-" + kind), kind + " is accepted through production semantic API")
		var voice: AudioStreamPlayer = music.cue_players[0]
		check(voice.stream == stream and voice.bus == "Effects" and voice.max_polyphony == 1, kind + " reaches the real Effects voice")
		var duration: float = stream.get_length() / float(MUSIC.EVENTS[kind].pitch)
		check(absf(music._cue_remaining[0] - duration) < .0001 and duration < 1.0, kind + " reserves the full pitched duration below one second")
		music.advance(duration * .8)
		check(music._cue_remaining[0] > 0.0, kind + " retains its voice through the tail")
		music.advance(duration)
		check(music._cue_remaining[0] == 0.0, kind + " naturally releases its reservation")
		check(AudioServer.get_bus_volume_db(effects_index) == -9.0 and AudioServer.is_bus_mute(effects_index), kind + " preserves player gain and mute")
		observations[kind] = {"duration": duration, "pcm_peak": peak, "max_sample_step": step}
	# A long warning must replace the actual queued signature after retirement,
	# and a new mission must discard it instead of reviving it on resume.
	music.stop()
	check(music.notify_event("reward", "reward") and music.notify_event("radio", "radio"), "Two real low-priority voices occupy the pool")
	check(music.notify_event("boss", "arrival"), "A major warning preempts the reward")
	music.advance(.0175)
	check(music.cue_players[0].stream == BANK.stream("reward"), "Old waveform continues during smooth retirement")
	music.advance(.0175)
	check(music.cue_players[0].stream == BANK.stream("boss") and music._pending_cues[0].is_empty(), "Retirement starts the correct replacement waveform")
	music.begin_run()
	check(not music.cue_players[0].playing and not music.cue_players[1].playing and music._cue_remaining[0] == 0.0 and music._cue_remaining[1] == 0.0, "Mission reset stops both voices and clears reservations")
	music.advance(3.0)
	check(not music.cue_players[0].playing and music.duck_db == 0.0, "A reset warning cannot restart or leave the mix ducked")
	for index in range(160):
		music.stop()
		var kind: String = MUSIC.EVENTS.keys()[index % MUSIC.EVENTS.size()]
		check(music.notify_event(kind, str(index)), "Repeated semantic admission remains valid")
		music.advance(2.0)
	check(music.get_child_count() == 4 and music.cue_players.size() == 2, "Repeated events keep exactly two music and two cue voices")
	check(BANK.stream("unknown") == BANK.stream("radio"), "Unknown bank requests have a stable fallback")
	music.stop()
	music.free()
	await process_frame
	await create_timer(.15).timeout
	AudioServer.set_bus_volume_db(effects_index, original_gain)
	AudioServer.set_bus_mute(effects_index, original_mute)
	created_buses.reverse()
	for bus_name in created_buses:
		AudioServer.remove_bus(AudioServer.get_bus_index(bus_name))
	var file := FileAccess.open("user://event-audio-results.json", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({"checks": checks, "failures": failures, "cues": observations, "human_listening": "NOT_PERFORMED"}, "\t"))
		file.close()
	else:
		check(false, "Event audio report can be saved")
	print("Event audio: %d checks / %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
