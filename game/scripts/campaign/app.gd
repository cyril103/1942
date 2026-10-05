extends Control
const PROFILE := preload("res://scripts/campaign/profile.gd")
const DIRECTOR := preload("res://scripts/campaign/director.gd")
const HUD := preload("res://scripts/campaign/hud.gd")
const FONT := preload("res://assets/ui/fonts/BarlowCondensed-Medium.ttf")
const TITLE := preload("res://assets/ui/fonts/BlackOpsOne-Regular.ttf")
const GOLD := Color("e2c383")
const MUTED := Color("9badb5")
var profile = PROFILE.new()
var missions: Array = []
var cockpit: Control
var director: Node
var menu: Control
var design: Control
var shade: ColorRect
var background: TextureRect
var page := "main"
var selected_mission := 1
var result: Dictionary = {}
var notice: Label
var buttons: Array[Button] = []
var settings_from_pause := false
var testing := false
var music: Node

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().auto_accept_quit = false
	missions = JSON.parse_string(FileAccess.get_file_as_string("res://data/missions.json"))
	profile.load_profile()
	_bind_controls()
	_setup_audio()
	_build_theme()
	background = TextureRect.new()
	background.texture = load("res://assets/campaign/title-ocean.png")
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	menu = Control.new()
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(menu)
	shade = ColorRect.new()
	shade.color = Color(0.01,0.025,0.035,0.36)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu.add_child(shade)
	design = Control.new()
	menu.add_child(design)
	design.size = Vector2(1920,1080)
	resized.connect(_layout)
	_layout()
	_apply_settings()
	_show_main()

func _layout() -> void:
	if not is_instance_valid(design): return
	var factor := minf(size.x/1920.0,size.y/1080.0)
	design.scale = Vector2.ONE*factor
	design.position = (size-Vector2(1920,1080)*factor)*0.5

func _bind_controls() -> void:
	var keys := {"move_left":[KEY_LEFT,KEY_A,KEY_Q],"move_right":[KEY_RIGHT,KEY_D],"move_up":[KEY_UP,KEY_W,KEY_Z],"move_down":[KEY_DOWN,KEY_S],"fire":[KEY_SPACE],"bomb":[KEY_X],"strike":[KEY_C],"focus_flight":[KEY_SHIFT],"quit_game":[KEY_ESCAPE],"restart_test":[KEY_R]}
	for action in keys:
		if not InputMap.has_action(action): InputMap.add_action(action,0.18)
		for code in keys[action]:
			var event := InputEventKey.new()
			event.keycode = code
			if not InputMap.action_has_event(action,event): InputMap.action_add_event(action,event)
	var pads := {"fire":JOY_BUTTON_A,"bomb":JOY_BUTTON_B,"strike":JOY_BUTTON_X,"focus_flight":JOY_BUTTON_LEFT_SHOULDER,"quit_game":JOY_BUTTON_START,"move_left":JOY_BUTTON_DPAD_LEFT,"move_right":JOY_BUTTON_DPAD_RIGHT,"move_up":JOY_BUTTON_DPAD_UP,"move_down":JOY_BUTTON_DPAD_DOWN}
	for action in pads:
		var event := InputEventJoypadButton.new()
		event.button_index = pads[action]
		if not InputMap.action_has_event(action,event): InputMap.action_add_event(action,event)
	for spec in [["move_left",JOY_AXIS_LEFT_X,-1.0],["move_right",JOY_AXIS_LEFT_X,1.0],["move_up",JOY_AXIS_LEFT_Y,-1.0],["move_down",JOY_AXIS_LEFT_Y,1.0]]:
		var event := InputEventJoypadMotion.new()
		event.axis = spec[1]
		event.axis_value = spec[2]
		if not InputMap.action_has_event(spec[0],event): InputMap.action_add_event(spec[0],event)

func _setup_audio() -> void:
	for bus_name in ["Music","Effects"]:
		if AudioServer.get_bus_index(bus_name) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count-1,bus_name)
	if ResourceLoader.exists("res://scripts/campaign/music.gd"):
		music = load("res://scripts/campaign/music.gd").new()
		add_child(music)

func _apply_settings() -> void:
	for pair in [["Master","master"],["Music","music"],["Effects","effects"]]:
		var volume: float = profile.data.settings[pair[1]]
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index(pair[0]),linear_to_db(maxf(0.0001,volume)))
		AudioServer.set_bus_mute(AudioServer.get_bus_index(pair[0]),volume <= 0)
	if not testing and DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if profile.data.settings.fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)

func _build_theme() -> void:
	var t := Theme.new()
	t.default_font = FONT
	t.default_font_size = 25
	for state in ["normal","hover","pressed","focus","disabled"]:
		var box := StyleBoxFlat.new()
		box.bg_color = Color(0.025,0.075,0.09,0.93)
		box.border_color = Color("47616b")
		box.set_border_width_all(1)
		box.set_corner_radius_all(4)
		box.content_margin_left = 24
		box.content_margin_right = 24
		box.content_margin_top = 12
		box.content_margin_bottom = 12
		if state in ["hover","focus"]:
			box.border_color = GOLD
			box.bg_color = Color(0.13,0.17,0.17,0.96)
		if state == "pressed": box.bg_color = Color("57492f")
		if state == "disabled": box.bg_color = Color(0.025,0.04,0.045,0.85)
		t.set_stylebox(state,"Button",box)
	t.set_color("font_color","Button",GOLD)
	t.set_color("font_disabled_color","Button",Color("65727a"))
	t.set_color("font_color","Label",Color("dce5e5"))
	t.set_color("font_color","CheckButton",GOLD)
	theme = t

func _clear_menu(title: String, subtitle: String, dark := true) -> void:
	for child in design.get_children():
		design.remove_child(child)
		child.queue_free()
	buttons.clear()
	menu.show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	shade.color.a = 0.84 if dark else 0.27
	_label(title,Vector2(90,60),Vector2(1740,90),60,GOLD,true)
	_label(subtitle,Vector2(94,152),Vector2(1730,62),25,MUTED)
	var rule := ColorRect.new()
	rule.position = Vector2(94,226)
	rule.size = Vector2(1732,1)
	rule.color = Color("6a6957")
	design.add_child(rule)
	notice = _label("FLÈCHES / MANETTE  •  ENTRÉE POUR VALIDER  •  ÉCHAP POUR REVENIR",Vector2(94,1010),Vector2(1700,35),21,MUTED)

func _label(text: String, position_at: Vector2, dimensions: Vector2, font_size := 26, color := Color.WHITE, title := false) -> Label:
	var label := Label.new()
	label.text = text
	label.position = position_at
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_override("font",TITLE if title else FONT)
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	design.add_child(label)
	# Set the width after wrapping/font overrides; otherwise the initial text's
	# minimum width can expand the control beyond the right column.
	label.size = dimensions
	return label

func _button(text: String, at: Vector2, dimensions: Vector2, callback: Callable, disabled := false) -> Button:
	var button := Button.new()
	button.text = text
	button.position = at
	button.size = dimensions
	button.disabled = disabled
	button.pressed.connect(callback)
	design.add_child(button)
	buttons.append(button)
	return button

func _focus_first() -> void:
	for button in buttons:
		if not button.disabled:
			button.grab_focus()
			return

func _save() -> void:
	if testing: return
	if profile.save() != OK and is_instance_valid(notice): notice.text = "SAUVEGARDE IMPOSSIBLE — progression conservée pour cette session."

func _show_main() -> void:
	_dispose_run()
	page = "main"
	if is_instance_valid(music): music.set_mode("menu")
	_clear_menu("PACIFIC STRIKE", "CAMPAGNE 1942  /  32 MISSIONS  /  8 SECTEURS",false)
	var completed: int = profile.data.records.size()
	_label("LE PACIFIQUE\nVOUS ATTEND.",Vector2(94,266),Vector2(730,190),66,GOLD,true)
	_label("Du premier décollage à la dernière offensive.\nUne campagne aérienne à travers les îles, les convois et les tempêtes.",Vector2(96,475),Vector2(630,90),29,Color("c5d1d5"))
	_button("COMMENCER LA CAMPAGNE" if profile.data.records.is_empty() else "REPRENDRE  /  MISSION %02d" % profile.data.next_mission,Vector2(94,590),Vector2(490,62),func(): _show_briefing(profile.data.next_mission))
	_button("CARTE DES MISSIONS",Vector2(94,670),Vector2(490,56),_show_missions)
	_button("HANGAR & AMÉLIORATIONS",Vector2(94,744),Vector2(490,56),_show_hangar)
	_button("OPTIONS",Vector2(94,818),Vector2(235,54),func(): _show_settings(false))
	_button("CRÉDITS",Vector2(349,818),Vector2(235,54),_show_credits)
	_button("QUITTER",Vector2(94,892),Vector2(490,54),_quit)
	_label("CARNET DE VOL",Vector2(1290,792),Vector2(520,45),26,GOLD)
	_label("%02d / 32 missions accomplies\nRecord  %08d\n%d pièces disponibles au hangar" % [completed,profile.data.high_score,profile.data.credits],Vector2(1290,842),Vector2(520,120),29,Color("dae5e7"))
	if not profile.data.records.is_empty(): _button("NOUVELLE CAMPAGNE",Vector2(1290,950),Vector2(510,52),_confirm_new_campaign)
	_focus_first()

func _show_missions() -> void:
	page = "missions"
	_clear_menu("CARTE DES OPÉRATIONS","Huit secteurs. Les missions accomplies restent rejouables pour améliorer leur médaille.")
	for i in range(32):
		var m: Dictionary = missions[i]
		var record: Dictionary = profile.data.records.get(str(i+1),{})
		var medal: String = ["—","BRONZE","ARGENT","OR"][int(record.get("grade",0))]
		var text := "%02d  /  %s\n%s\n%s" % [i+1,str(m.region).to_upper(),m.title,medal]
		var button := _button(text,Vector2(94+(i%4)*437,256+(i/4)*81),Vector2(418,72),_show_briefing.bind(i+1),i+1>profile.data.unlocked)
		button.add_theme_font_size_override("font_size",18)
		for state in ["normal","hover","pressed","focus","disabled"]:
			var style := button.get_theme_stylebox(state).duplicate() as StyleBoxFlat
			style.content_margin_top = 2
			style.content_margin_bottom = 2
			button.add_theme_stylebox_override(state,style)
	_button("RETOUR",Vector2(94,936),Vector2(260,56),_show_main)
	_focus_first()

func _show_briefing(number: int) -> void:
	if number < 1 or number > profile.data.unlocked: return
	selected_mission = number
	page = "briefing"
	var m: Dictionary = missions[number-1]
	_clear_menu("MISSION %02d  /  %s" % [number,str(m.region).to_upper()],str(m.title).to_upper())
	_label(m.title,Vector2(94,285),Vector2(1080,100),48,GOLD,true)
	_label(m.briefing,Vector2(94,420),Vector2(920,180),33,Color("d6e0e2"))
	var objective := "Rejoindre le point de sortie en vie."
	if m.boss != "": objective = "Détruire le commandant du secteur."
	var mastery := "Détruire %d adversaires." % int(m.quota)
	if m.objective == "strike": mastery = "Couler %d navires." % int(m.quota)
	if m.boss != "": mastery = "Détruire le boss."
	_label("OBJECTIF PRINCIPAL\n"+objective+"\n\nMÉDAILLE D'OR\nAucune vie perdue, deux impacts au maximum.\n"+mastery,Vector2(94,628),Vector2(920,250),28,MUTED)
	_label("PRÉPARATION DU VOL",Vector2(1170,289),Vector2(600,48),31,GOLD)
	_label("APPAREIL   %s\nDIFFICULTÉ   %s\n\nFlèches / WASD / ZQSD : piloter\nEspace : tir continu\nMaj : déplacement précis\nX : bombe d'urgence\nC : frappe spéciale à 100%%\nÉchap : pause\n\nManette : stick, A, B, X et LB." % [PROFILE.AIRCRAFT[profile.data.aircraft],PROFILE.DIFFICULTIES[profile.data.difficulty]],Vector2(1170,365),Vector2(610,440),29,Color("d6e0e2"))
	_button("DÉCOLLER",Vector2(94,910),Vector2(360,64),_launch.bind(number))
	_button("HANGAR",Vector2(479,910),Vector2(260,64),_show_hangar)
	_button("RETOUR",Vector2(764,910),Vector2(260,64),_show_missions)
	_focus_first()

func _show_hangar() -> void:
	page = "hangar"
	_clear_menu("HANGAR","%d PIÈCES DISPONIBLES  •  Les premières victoires et les nouvelles médailles financent les améliorations." % profile.data.credits)
	var descriptions := ["POLYVALENT\nVitesse 9  •  Coque 3  •  Bombes 2\nUn équilibre entre mobilité et résistance.","INTERCEPTEUR\nVitesse 11  •  Coque 2  •  Bombes 2\nTir plus rapide, esquives plus vives.","ASSAUT\nVitesse 7,8  •  Coque 4  •  Bombes 3\nPlus de réserve pour les engagements lourds."]
	for i in range(3):
		var x := 94+i*580
		_label(PROFILE.AIRCRAFT[i].to_upper(),Vector2(x,290),Vector2(540,50),37,GOLD,true)
		_label(descriptions[i],Vector2(x,370),Vector2(510,180),28,MUTED)
		_button("SÉLECTIONNÉ" if profile.data.aircraft == i else "CHOISIR",Vector2(x,555),Vector2(510,56),_select_aircraft.bind(i))
	var names := ["ARMEMENT","BLINDAGE","CONDENSATEUR"]
	var details := ["Cadence +6% par rang. Rang III : dégâts doublés.","Un point de coque supplémentaire par rang.","La frappe se recharge plus vite à chaque destruction."]
	for i in range(3):
		var x := 94+i*580
		_label("%s  /  %d–3" % [names[i],profile.data.upgrades[i]],Vector2(x,684),Vector2(530,42),30,GOLD)
		_label(details[i],Vector2(x,746),Vector2(510,78),25,MUTED)
		var maximum: bool = int(profile.data.upgrades[i]) >= 3
		var cost: int = profile.upgrade_cost(i)
		_button("RANG MAXIMUM" if maximum else "AMÉLIORER  /  %d PIÈCES" % cost,Vector2(x,846),Vector2(510,56),_buy.bind(i),maximum or profile.data.credits<cost)
	_button("RETOUR AU BRIEFING",Vector2(94,936),Vector2(360,56),_show_briefing.bind(selected_mission))
	_button("ACCUEIL",Vector2(479,936),Vector2(240,56),_show_main)
	_focus_first()

func _select_aircraft(index: int) -> void:
	profile.data.aircraft = index
	_save()
	_show_hangar()

func _buy(index: int) -> void:
	var purchased: bool = profile.buy_upgrade(index)
	_show_hangar()
	if not purchased and profile.last_error != OK: notice.text = "Achat annulé : la sauvegarde n’a pas pu être écrite."

func _show_settings(from_pause: bool) -> void:
	settings_from_pause = from_pause
	page = "settings"
	_clear_menu("OPTIONS","Réglages enregistrés automatiquement. Aucun clignotement stroboscopique n'est nécessaire au gameplay.")
	var labels := ["VOLUME GÉNÉRAL","MUSIQUE","EFFETS SONORES"]
	var keys := ["master","music","effects"]
	for i in range(3):
		_label(labels[i],Vector2(94,292+i*122),Vector2(420,50),28,GOLD)
		var slider := HSlider.new()
		slider.position = Vector2(530,303+i*122)
		slider.size = Vector2(750,36)
		slider.min_value = 0
		slider.max_value = 100
		slider.step = 1
		slider.value = profile.data.settings[keys[i]]*100
		design.add_child(slider)
		var value_label := _label("%d %%" % slider.value,Vector2(1340,292+i*122),Vector2(180,50),28,MUTED)
		slider.value_changed.connect(func(value): profile.data.settings[keys[i]]=value/100.0; value_label.text="%d %%" % value; _apply_settings(); _save())
	for i in range(3):
		var key: String = ["fullscreen","shake","flashes"][i]
		var check := CheckButton.new()
		check.text = ["Plein écran","Secousses de l'écran","Effets lumineux renforcés"][i]
		check.position = Vector2(94+i*550,687)
		check.size = Vector2(520,64)
		check.button_pressed = profile.data.settings[key]
		design.add_child(check)
		check.toggled.connect(func(value): profile.data.settings[key]=value; _apply_settings(); _save())
	for i in range(3):
		_button(("✓  " if profile.data.difficulty == i else "")+PROFILE.DIFFICULTIES[i],Vector2(94+i*320,802),Vector2(295,58),_difficulty.bind(i),from_pause)
	_label("La difficulté agit sur les projectiles ennemis et la résistance des boss. Modifiable entre les missions.",Vector2(94,885),Vector2(1600,42),24,MUTED)
	_button("RETOUR",Vector2(94,947),Vector2(280,56),_show_pause if from_pause else _show_main)
	_focus_first()

func _difficulty(index: int) -> void:
	profile.data.difficulty = index
	_save()
	_show_settings(false)

func _show_credits() -> void:
	page = "credits"
	_clear_menu("CRÉDITS & SOURCES","Campagne originale réalisée avec Godot et Blender. Inspirée des shmups de la série 194X.")
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(94,270)
	scroll.size = Vector2(1710,620)
	design.add_child(scroll)
	var text := RichTextLabel.new()
	text.custom_minimum_size = Vector2(1650,0)
	text.fit_content = true
	text.bbcode_enabled = false
	text.add_theme_font_size_override("normal_font_size",25)
	text.text = "PACIFIC STRIKE — CAMPAGNE 1942\n\nConception, programmation et assets originaux : projet Cyril / Codex.\nMoteur Godot (licence MIT), modélisation Blender, illustrations et textures générées avec imagegen.\nMusique : compositions procédurales originales du projet.\n1942 et 1942: Joint Strike appartiennent à leurs ayants droit ; ce projet indépendant n'est pas affilié à Capcom.\n\nPOLICES\nBarlow Condensed, Black Ops One et DSEG : licences distribuées dans assets/ui/fonts.\n\n"
	for file in ["res://assets/audio/engine/CREDITS.md","res://assets/audio/weapons/CREDITS.md"]:
		text.text += FileAccess.get_file_as_string(file)+"\n\n"
	scroll.add_child(text)
	_button("RETOUR",Vector2(94,936),Vector2(280,56),_show_main)
	_focus_first()

func _launch(number: int) -> void:
	_dispose_run()
	selected_mission = number
	page = "playing"
	menu.hide()
	cockpit = preload("res://scenes/cockpit.tscn").instantiate()
	cockpit.campaign_mode = true
	cockpit.persistence_enabled = false
	cockpit.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(cockpit)
	move_child(cockpit,menu.get_index())
	cockpit.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	director = DIRECTOR.new()
	director.cockpit = cockpit
	director.mission = missions[number-1].duplicate(true)
	director.profile = profile
	director.first_takeoff = number%4 == 1
	director.finished.connect(func(report): _show_result.call_deferred(report))
	cockpit.flight.add_child(director)
	if number == profile.data.next_mission and profile.data.pow_ready: cockpit.flight.get_node("Weapons").upgrade_spread()
	var hud := HUD.new()
	hud.cockpit = cockpit
	hud.director = director
	cockpit.add_child(hud)
	_assign_audio(cockpit)
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	if is_instance_valid(music): music.set_mode("flight")

func _assign_audio(node: Node) -> void:
	if node is AudioStreamPlayer or node is AudioStreamPlayer3D: node.bus = "Effects"
	for child in node.get_children(): _assign_audio(child)

func _show_pause() -> void:
	if not is_instance_valid(director): return
	page = "pause"
	get_tree().paused = true
	director.paused = true
	_clear_menu("VOL SUSPENDU","MISSION %02d  /  %s" % [selected_mission,director.mission.title])
	_button("REPRENDRE LE VOL",Vector2(94,315),Vector2(580,70),_resume)
	_button("OPTIONS",Vector2(94,415),Vector2(580,64),func(): _show_settings(true))
	_button("RECOMMENCER LA MISSION",Vector2(94,509),Vector2(580,64),_launch.bind(selected_mission))
	_button("RETOUR À L'ACCUEIL",Vector2(94,603),Vector2(580,64),_show_main)
	_label("La progression est enregistrée entre les missions.\nReprendre depuis l'accueil relance le briefing de la mission.\n\nEspace : tirer  •  Maj : précision\nX : bombe  •  C : frappe spéciale",Vector2(850,325),Vector2(870,320),32,MUTED)
	_focus_first()

func _resume() -> void:
	get_tree().paused = false
	director.paused = false
	page = "playing"
	menu.hide()
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN

func _show_result(report: Dictionary) -> void:
	if not is_instance_valid(director): return
	result = report
	page = "result"
	get_tree().paused = true
	director.paused = true
	var earned := 0
	if selected_mission >= profile.data.next_mission: profile.data.pow_ready = report.won and report.get("spread",false)
	if report.won: earned = profile.record_victory(selected_mission,report.score,report.grade)
	var victory: bool = report.won and selected_mission == 32
	_clear_menu("LE PACIFIQUE EST LIBRE" if victory else ("MISSION ACCOMPLIE" if report.won else "APPAREIL PERDU"),"%02d / 32  •  %s" % [selected_mission,director.mission.title])
	_label(["—","BRONZE","ARGENT","OR"][int(report.grade)] if report.won else "NE RENONCEZ PAS.",Vector2(94,298),Vector2(1050,100),70,GOLD,true)
	_label("SCORE DE MISSION    %08d\nAPPAREILS / NAVIRES DÉTRUITS    %d / %d\nVIES PERDUES    %d\nBONUS DE FIN    %d\nPIÈCES GAGNÉES    +%d" % [report.score,report.kills-report.naval_kills,report.naval_kills,report.deaths,report.bonus,earned],Vector2(94,438),Vector2(1040,300),35,Color("d4dfe1"))
	_label("32 missions. Huit secteurs. Une route jusqu'à l'aube.\n\nLa campagne est terminée. Les missions restent disponibles pour obtenir toutes les médailles d'or." if victory else ("La mission suivante est déverrouillée.\nProfitez du hangar pour préparer votre appareil." if report.won else "Votre progression est conservée.\nEssayez un autre profil, utilisez la précision et gardez une bombe pour vous dégager."),Vector2(1210,336),Vector2(590,310),33,MUTED)
	if report.won and selected_mission < 32:
		_button("MISSION SUIVANTE",Vector2(94,842),Vector2(440,66),_briefing_after_result.bind(selected_mission+1))
	else: _button("REJOUER LA MISSION",Vector2(94,842),Vector2(440,66),_launch.bind(selected_mission))
	_button("HANGAR",Vector2(559,842),Vector2(320,66),_hangar_after_result)
	_button("ACCUEIL",Vector2(904,842),Vector2(320,66),_show_main)
	if victory: _button("CRÉDITS",Vector2(1249,842),Vector2(320,66),_credits_after_result)
	_save()
	_focus_first()

func _briefing_after_result(number: int) -> void:
	_dispose_run()
	_show_briefing(number)
func _hangar_after_result() -> void:
	if result.get("won",false): selected_mission = mini(32,selected_mission+1)
	_dispose_run()
	_show_hangar()
func _credits_after_result() -> void:
	_dispose_run()
	_show_credits()

func _dispose_run() -> void:
	get_tree().paused = false
	if is_instance_valid(cockpit):
		cockpit._stop_audio(cockpit)
		cockpit.hide()
		cockpit.process_mode = Node.PROCESS_MODE_DISABLED
		cockpit.queue_free()
	cockpit = null
	director = null

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("quit_game") and not event.is_echo():
		get_viewport().set_input_as_handled()
		match page:
			"playing": _show_pause()
			"pause": _resume()
			"settings":
				if settings_from_pause: _show_pause()
				else: _show_main()
			"result": _show_main()
			"main": _quit()
			_: _show_main()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and page == "playing" and not testing: _show_pause()
	if what == NOTIFICATION_WM_CLOSE_REQUEST: _quit()

func _quit() -> void:
	_save()
	_dispose_run()
	if is_instance_valid(music): music.stop()
	await get_tree().create_timer(0.15).timeout
	get_tree().quit()


func _process(_delta: float) -> void:
	if page == "playing" and is_instance_valid(director) and is_instance_valid(music):
		music.set_mode("boss" if is_instance_valid(director.boss) and director.boss.alive else "flight")

func _confirm_new_campaign() -> void:
	page = "new_campaign"
	_clear_menu("NOUVELLE CAMPAGNE","Le record et les options seront conservés.")
	_label("Repartir de la mission 01 ?",Vector2(94,320),Vector2(1400,100),48,GOLD,true)
	_label("Les médailles, les missions débloquées et les améliorations de cette campagne seront réinitialisées.",Vector2(94,465),Vector2(1300,150),34,MUTED)
	_button("CONSERVER MA CAMPAGNE",Vector2(94,735),Vector2(520,64),_show_main)
	_button("RECOMMENCER",Vector2(650,735),Vector2(400,64),_new_campaign)
	_focus_first()

func _new_campaign() -> void:
	var options: Dictionary = profile.data.settings.duplicate()
	var record: int = profile.data.high_score
	profile.reset()
	profile.data.settings = options
	profile.data.high_score = record
	selected_mission = 1
	_save()
	_show_briefing(1)
