extends SceneTree
var failures: Array[String] = []
var checks := 0
var attack_observations: Array[Dictionary] = []
var audio_output_dir := "user://takeoff-audio-review"
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)
func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output-dir="): audio_output_dir = argument.trim_prefix("--output-dir=")
	DirAccess.make_dir_recursive_absolute(audio_output_dir)
	_run.call_deferred()
func _freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children(): _freeze(child)

func _levels(sound: Node) -> Array[float]:
	var levels: Array[float] = []
	for voice in sound.voices: levels.append(voice.volume_db)
	return levels

func _voice_attack_cases() -> void:
	# Stationary aircraft/camera and fixed throttle isolate the audible attack
	# from motion and cinematic timing. We inspect real voice levels; this test
	# does not calculate or duplicate the engine's easing/envelope formula.
	for mode in ["normal","short","landing"]:
		var fixture = load("res://scenes/main.tscn").instantiate()
		root.add_child(fixture)
		_freeze(fixture)
		var departure = fixture.get_node("Departure")
		var sound = departure.engine_audio
		var player = fixture.get_node("Player")
		var camera = fixture.get_node("Camera")
		check(not sound.finished and sound.voices.size()==2,mode+" initial _ready starts both voices")
		for voice in sound.voices: check(voice.playing and voice.volume_db<=-60,mode+" initial _ready primes quiet playback")
		if mode=="short": check(departure.begin_short_retry(),"Short intro starts through the real departure method")
		player.position = Vector3.ZERO
		camera.position = Vector3(0,40,0)
		# Warm a reference at the actual mode's fixed regime and identical pose.
		# Only steady playback is compared, preserving the approved layer mix.
		sound.last_distance = 40.0
		sound.radial_speed = 0
		if mode=="landing": departure.begin_landing()
		sound._physics_process(1.0)
		var reference := _levels(sound)
		var reference_pitch: float = sound.voices[0].pitch_scale
		for voice in sound.voices: check(is_finite(voice.volume_db) and is_finite(voice.pitch_scale),mode+" warmed reference has finite audible parameters")
		if mode=="landing":
			sound.stop()
			check(sound.finished and not sound.voices[0].playing,"Landing fixture really stops old playback before restart")
			# This invokes production start(), rather than duplicating the caller's
			# former finished/fade/voice.play bookkeeping in the fixture.
			departure.begin_landing()
		else:
			sound.start()
		_freeze(fixture)
		check(not sound.finished and sound.voices.size()==2 and sound.get_child_count()==2,mode+" playback restart keeps the same two fixed voices")
		for voice in sound.voices: check(voice.playing and voice.volume_db<=-60,mode+" restart begins quietly at the real voice")
		var previous := _levels(sound)
		var first: Array[float] = []
		var early: Array[float] = []
		var middle: Array[float] = []
		for tick in range(60):
			sound._physics_process(1.0/60.0)
			var now := _levels(sound)
			if tick==0: first = now.duplicate()
			if tick==5: early = now.duplicate()
			if tick==11: middle = now.duplicate()
			for index in range(sound.voices.size()):
				check(is_finite(now[index]) and is_finite(sound.voices[index].pitch_scale),mode+" every attack sample has finite level and pitch")
				# Initial output can be below the quiet priming value (-60 dB);
				# after the first sample, a stationary attack must grow smoothly.
				if tick>0: check(now[index]>=previous[index]-.001,mode+" actual level rises monotonically without a phase-dependent jump")
			previous = now
		var final := _levels(sound)
		for index in range(sound.voices.size()):
			check(first[index]<reference[index]-25,mode+" first playback frame remains well below the accepted steady regime")
			check(early[index]<reference[index]-8,mode+" attack is still subdued after 100 ms instead of jumping on the second frame")
			check(middle[index]<reference[index]-2 and middle[index]>early[index]+3,mode+" attack continues to rise progressively through 200 ms")
			check(absf(final[index]-reference[index])<.01,mode+" attack reaches the unchanged approved steady voice level")
			check(final[index]>-35 and final[index]<0,mode+" steady engine remains audible with headroom")
		check(absf(sound.voices[0].pitch_scale-reference_pitch)<.0001,mode+" normal mode RPM/pitch returns after the attack")
		check(absf(final[1]-final[0]-7.0)<.001,mode+" original body/exhaust balance stays seven decibels apart")
		attack_observations.append({"mode":mode,"first_frame_db":first,"after_100ms_db":early,"after_200ms_db":middle,"steady_reference_db":reference,"after_attack_db":final,"pitch":sound.voices[0].pitch_scale})
		sound.stop()
		fixture.queue_free()
		await process_frame
		await create_timer(.1).timeout

func _run() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	scene.get_node("Combat").set_physics_process(false)
	var departure = scene.get_node("Departure")
	var sound = departure.engine_audio
	var recorder := AudioEffectRecord.new()
	recorder.format = AudioStreamWAV.FORMAT_16_BITS
	AudioServer.add_bus_effect(0, recorder)
	recorder.set_recording_active(true)
	var minimum := 1.0
	var maximum := 1.0
	for tick in range(690):
		await physics_frame
		minimum = minf(minimum, sound.doppler)
		maximum = maxf(maximum, sound.doppler)
	check(minimum < 0.90 and maximum > 1.15, "Approach raises pitch, departure lowers it")
	check(sound.finished, "Engine fades out after opening")
	check(sound.voices.size() == 2 and sound.get_child_count() == 2, "Only two fixed engine voices")
	for voice in sound.voices: check(not voice.playing, "Engine loop stopped")
	recorder.set_recording_active(false)
	var recording := recorder.get_recording()
	check(recording.save_to_wav(audio_output_dir.path_join("takeoff-ingame.wav"))==OK,"Engine mix recording is saved to its isolated validation directory")
	var bytes := recording.data
	var peak := 0
	for offset in range(0, bytes.size(), 2):
		peak = maxi(peak, absi(bytes.decode_s16(offset)))
	check(peak > 1000 and peak < 28000, "Audible mix with unclipped headroom")
	AudioServer.remove_bus_effect(0, AudioServer.get_bus_effect_count(0)-1)
	departure.finish_immediately()
	check(sound.finished, "Skipping opening stops loops")
	scene.queue_free()
	await create_timer(0.4).timeout
	await _voice_attack_cases()
	FileAccess.open("res://tests/takeoff-audio-results.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"doppler_min":minimum,"doppler_max":maximum,"mix_peak":peak,"voice_attacks":attack_observations},"\t"))
	print("TAKEOFF AUDIO: ", "PASS" if failures.is_empty() else failures, "; Doppler=", minimum, "..", maximum, "; peak=", peak)
	quit(0 if failures.is_empty() else 1)
