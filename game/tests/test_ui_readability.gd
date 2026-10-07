extends SceneTree
## Inspect real UI controls and bindings. --capture-ui also renders proof images.
const FIXTURE := "user://ui-readability-regression-fixture.json"
var output_dir := OS.get_user_data_dir().path_join("ui-review")
var app: Control
var checks := 0
var failures: Array[String] = []
var geometry: Array[Dictionary] = []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output-dir="): output_dir = argument.trim_prefix("--output-dir=")
	DirAccess.make_dir_recursive_absolute(output_dir)
	_run.call_deferred()

func capture(name: String) -> void:
	if not "--capture-ui" in OS.get_cmdline_user_args(): return
	await create_timer(.28).timeout
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output_dir.path_join("issue-ui-"+name+".png"))==OK,"Capture "+name)

func _resize(dimensions: Vector2i) -> void:
	root.size = dimensions
	await process_frame
	await process_frame
	check(app.size.is_equal_approx(root.get_visible_rect().size),"App follows the canvas viewport at physical size "+str(dimensions))

func _new_app() -> void:
	if is_instance_valid(app):
		app._dispose_run()
		if is_instance_valid(app.music): app.music.stop()
		app.queue_free()
		await process_frame
	app = load("res://scenes/campaign.tscn").instantiate()
	app.testing = true
	app.profile.path = FIXTURE
	root.add_child(app)
	current_scene = app
	await process_frame

func _press(prefix: String) -> void:
	for button in app.buttons:
		if button.text.begins_with(prefix) and not button.disabled:
			button.pressed.emit()
			return
	check(false,"Accessible menu button: "+prefix)

func _inspect_briefing(number: int) -> void:
	app._show_briefing(number)
	await process_frame
	var orders: Label = app.design.get_node("MissionOrderText")
	var panel: Panel = app.design.get_node("MissionOrderPanel")
	var info: Panel = app.design.get_node("MissionInfoPanel")
	check(orders.text==app.missions[number-1].briefing and orders.visible_characters==-1,"Mission %02d displays every authored briefing character" % number)
	check(panel.get_rect().encloses(orders.get_rect()),"Mission %02d order text remains on its opaque panel" % number)
	check(orders.get_minimum_size().y<=orders.size.y+.1,"Mission %02d has space for every wrapped text line" % number)
	for child in app.design.get_children():
		if child is not Label or child.position.x<info.position.x or child.position.y<info.position.y or child.position.y>=info.get_rect().end.y: continue
		check(info.get_rect().encloses(child.get_rect()),"Mission %02d right-column text stays on its panel: %s" % [number,child.text.left(28)])
	for button in app.buttons:
		check(not button.get_rect().intersects(orders.get_rect()) and not button.get_rect().intersects(info.get_rect()),"Mission %02d keeps %s clear of its content" % [number,button.text])
	check(get_root().gui_get_focus_owner().text=="DÉCOLLER","Mission %02d opens with keyboard/gamepad focus on takeoff" % number)
	geometry.append({"resolution":str(root.size),"mission":number,"lines":orders.get_line_count(),"text_height":orders.get_minimum_size().y,"panel_end":panel.get_rect().end.y,"text_end":orders.get_rect().end.y})

func _bind(action: String, code: int) -> void:
	app._show_bindings()
	app.waiting_binding = action
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	app._input(event)
	check(int(app.profile.data.bindings.get(action,0))==code,"Real binding UI accepts "+action)

func _check_current_help() -> void:
	app._show_hangar()
	var hangar: Label = app.design.get_node("HangarCommands")
	check(hangar.text.contains("Impr. écran") and not hangar.text.begins_with("C :"),"Hangar displays the current special-key strike binding")
	check(hangar.get_rect().end.y<726 and hangar.get_minimum_size().y<=hangar.size.y,"Long hangar binding stays above upgrades")
	app._show_briefing(3)
	await process_frame
	var help: Label = app.design.get_node("FlightCommands")
	for expected in ["F6","Page préc.","Impr. écran","Verr. maj.","J / L / I / K","Stick / croix","Échap / Start"]:
		check(help.text.contains(expected),"Briefing reflects current keyboard/manette help: "+expected)
	check(app.design.get_node("MissionInfoPanel").get_rect().encloses(help.get_rect()),"Long remapped command names fit the briefing panel")
	await capture("briefing-remapped-"+str(root.size.y))
	_press("DÉCOLLER")
	app.cockpit.flight.process_mode = Node.PROCESS_MODE_DISABLED
	app._show_pause()
	var pause_help: Label = app.design.get_node("FlightCommands")
	for expected in ["F6","Page préc.","Impr. écran","Verr. maj.","J / L / I / K","Échap / Start"]:
		check(pause_help.text.contains(expected),"Pause reflects current command: "+expected)
	check(pause_help.get_rect().end.y<947 and pause_help.get_minimum_size().y<=pause_help.size.y,"Long pause help remains entirely visible")
	await capture("pause-remapped-"+str(root.size.y))
	app._show_main()
	await process_frame

func _inspect_jam(dimensions: Vector2i) -> void:
	await _resize(dimensions)
	app._launch(3)
	app.cockpit.flight.process_mode = Node.PROCESS_MODE_DISABLED
	var hud: Control = app.cockpit.get_node("CampaignHUD")
	app.director.assault.jam_remaining = 6
	hud._process(0)
	await process_frame

	await process_frame
	var badge: PanelContainer = hud.get_node("GroundJamStatus")
	var counter: Label = badge.get_node("Countdown")
	check(hud.size.is_equal_approx(app.cockpit.size),"HUD follows the real cockpit dimensions after resize "+str(dimensions))
	check(badge.visible and counter.text.contains("6.0 s"),"Jam badge displays its actual remaining duration")
	check(Rect2(Vector2.ZERO,hud.size).encloses(badge.get_rect()),"Jam badge is fully inside the viewport "+str(dimensions))
	# Inspect the measured badge against occupied HUD areas, not its placement formula.
	var u: float = app.cockpit.size.y/1080.0
	var chain_width: float = hud.FONT.get_string_size("CHAÎNE 999   ×5",HORIZONTAL_ALIGNMENT_LEFT,-1,maxi(12,int(23*u))).x
	var chain := Rect2(Vector2(18*u,app.cockpit.play_rect.position.y),Vector2(chain_width,85*u))
	var objective := Rect2(Vector2(app.cockpit.size.x-430*u,app.cockpit.play_rect.position.y),Vector2(410*u,72*u))
	var top := Rect2(Vector2.ZERO,Vector2(app.cockpit.size.x,64*u))
	check(not badge.get_rect().intersects(chain) and not badge.get_rect().intersects(objective) and not badge.get_rect().intersects(top),"Measured jam badge avoids chain, objectives, score and armor "+str(dimensions))
	var unchanged: float = app.director.assault.jam_remaining
	hud._process(.25)
	check(app.director.assault.jam_remaining==unchanged,"Displaying the jam countdown never changes gameplay duration")
	await capture("jammed-"+str(dimensions.x)+"x"+str(dimensions.y))
	app.director.assault.jam_remaining = 0
	hud._process(0)
	check(not badge.visible,"Jam badge hides when the real duration is exhausted")
	app._show_main()
	await process_frame

func _long_movement_help() -> void:
	for binding in [["move_left",KEY_KP_MULTIPLY],["move_right",KEY_KP_DIVIDE],["move_up",KEY_BACKSPACE],["move_down",KEY_PAGEDOWN]]: _bind(binding[0],binding[1])
	for dimensions in [Vector2i(1280,720),Vector2i(1920,1080)]:
		await _resize(dimensions)
		app._show_briefing(3)
		await process_frame
		var guide: Label = app.design.get_node("FlightCommands")
		check(guide.text.contains("Retour arrière") and guide.text.contains("Page suiv.") and not guide.text.contains("J / L / I / K"),"Four long movement bindings replace the old guide at "+str(dimensions))
		check(app.design.get_node("MissionInfoPanel").get_rect().encloses(guide.get_rect()) and guide.get_minimum_size().y<=guide.size.y,"Four long movement bindings fit every briefing line at "+str(dimensions))
		check(guide.get_theme_font_size("font_size")>=19,"Long movement guide remains readable at "+str(dimensions))
		await capture("briefing-long-keys-"+str(dimensions.y))
		_press("DÉCOLLER")
		app.cockpit.flight.process_mode = Node.PROCESS_MODE_DISABLED
		app._show_pause()
		guide = app.design.get_node("FlightCommands")
		check(guide.text.contains("Retour arrière") and guide.text.contains("Page suiv.") and guide.get_minimum_size().y<=guide.size.y,"Long movement bindings remain visible in pause at "+str(dimensions))
		await capture("pause-long-keys-"+str(dimensions.y))
		app._show_main()
		await process_frame

func _report(won: bool) -> Dictionary:
	return {"won":won,"score":10699,"mission_score":700,"kills":5,"naval_kills":0,"ground_kills":0,"deaths":0 if won else 3,"bonus":0,"grade":3 if won else 0,"lives":4,"power":"spread","rank":"A","best_chain":18,"accuracy":.5,"secondary":true}

func _inspect_results_and_credits() -> void:
	for mode in ["campaign","arcade","practice"]:
		for won in [false,true]:
			app._start_mode(mode,4 if mode=="practice" else 2)
			app.cockpit.flight.process_mode = Node.PROCESS_MODE_DISABLED
			app._show_result(_report(won))
			await process_frame
			var summary: Label = app.design.get_node("ResultSummary")
			if mode=="campaign":
				check(summary.text.contains("mission suivante") if won else summary.text.contains("point de sauvegarde"),"Campaign result describes its actual progression: "+str(won))
			elif mode=="arcade": check(summary.text.contains("si ce score est supérieur") and not summary.text.contains("déverrouillée"),"Arcade result only describes its score-attack record: "+str(won))
			else: check(summary.text.contains("Aucun record ni récompense de campagne") and not summary.text.contains("déverrouillée"),"Practice result describes unchanged campaign and records: "+str(won))
			check(summary.get_rect().end.y<842 and summary.get_minimum_size().y<=summary.size.y,"Mode result copy fits above all buttons")
			await capture("result-"+mode+("-won" if won else "-lost"))
			app._show_main()
			await process_frame
	app._launch(32)
	app.cockpit.flight.process_mode = Node.PROCESS_MODE_DISABLED
	app._show_result(_report(true))
	check(app.design.get_node("ResultSummary").text.contains("La campagne est terminée") and app.profile.data.completed,"Final campaign result matches completed campaign state")
	await capture("result-final-campaign")
	app._show_main()
	app._show_credits()
	var credits: RichTextLabel = app.design.find_child("CreditsText",true,false)
	check(credits.text.contains("MUSIQUE ACTIVE") and credits.text.contains("Juhani Junkala / SubspaceAudio — 5 Chiptunes (Action), CC0"),"Credits attribute the soundtrack actually played")
	check(credits.text.contains("COMPOSITIONS HISTORIQUES") and credits.text.contains("ne sont plus diffusées") and not credits.text.contains("Musique de combat adaptative :"),"Inactive procedural music is clearly distinguished from active tracks")
	for name in ["menu","flight","flight2","boss","victory"]: check(app.music.tracks[name].resource_path.ends_with(name+".wav"),"Active track named in credits exists in the actual music player: "+name)
	await capture("credits")
	app._show_main()

func _run() -> void:
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(FIXTURE+suffix): DirAccess.remove_absolute(FIXTURE+suffix)
	await _new_app()
	app.profile.data.unlocked = 32
	for dimensions in [Vector2i(1280,720),Vector2i(1920,1080)]:
		await _resize(dimensions)
		var longest := 1
		for number in range(1,33):
			await _inspect_briefing(number)
			if str(app.missions[number-1].briefing).length()>str(app.missions[longest-1].briefing).length(): longest = number
		app._show_briefing(3)
		await capture("briefing-03-"+str(dimensions.y))
		app._show_briefing(longest)
		await capture("briefing-longest-%02d-%d" % [longest,dimensions.y])
	# Reconfigure through the same handler as the real commands screen.
	_bind("move_left",KEY_J)
	check(app.COMMANDS.movement().contains("→,D") and app.COMMANDS.movement().contains("↑,W,Z") and not app.COMMANDS.movement().contains("WASD"),"A partial movement remap retains its real alternatives without advertising a broken preset")
	for binding in [["fire",KEY_F6],["bomb",KEY_PAGEUP],["strike",KEY_PRINT],["focus_flight",KEY_CAPSLOCK],["move_left",KEY_J],["move_right",KEY_L],["move_up",KEY_I],["move_down",KEY_K]]:
		_bind(binding[0],binding[1])
	for dimensions in [Vector2i(1280,720),Vector2i(1920,1080)]:
		await _resize(dimensions)
		await _check_current_help()
	check(app.profile.save()==OK,"Custom bindings save in an isolated fixture")
	await _new_app()
	await _check_current_help()
	await _long_movement_help()
	app._show_bindings()
	_press("RÉTABLIR")
	check(app.COMMANDS.movement()=="Flèches / ZQSD / WASD" and app.COMMANDS.keyboard("fire")=="Espace" and app.COMMANDS.keyboard("strike")=="C","Restore updates keyboard help and all useful default movement alternatives")
	check(app.COMMANDS.gamepad("fire")=="A" and app.COMMANDS.gamepad("focus_flight")=="LB","Restore retains gamepad flight alternatives")
	app._show_briefing(3)
	check(app.design.get_node("FlightCommands").text.contains("TIR  Espace / A"),"Restored binding is immediately visible in briefing")
	for dimensions in [Vector2i(1280,720),Vector2i(1920,1080),Vector2i(2560,1080)]: await _inspect_jam(dimensions)
	await _resize(Vector2i(1920,1080))
	await _inspect_results_and_credits()
	app._dispose_run()
	if is_instance_valid(app.music): app.music.stop()
	app.queue_free()
	await process_frame
	await create_timer(.2).timeout
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(FIXTURE+suffix): DirAccess.remove_absolute(FIXTURE+suffix)
	FileAccess.open(output_dir.path_join("issue-ui-geometry.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"briefings":geometry},"\t"))
	print("UI READABILITY TEST ",checks," checks, ",failures.size()," failures: ",failures)
	quit(0 if failures.is_empty() else 1)
