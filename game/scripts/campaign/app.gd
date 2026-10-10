extends Control
const PROFILE := preload("res://scripts/campaign/profile.gd")
const DIRECTOR := preload("res://scripts/campaign/director.gd")
const HUD := preload("res://scripts/campaign/hud.gd")
const COMMANDS := preload("res://scripts/campaign/command_labels.gd")
const LOADOUT := preload("res://scripts/campaign/loadout.gd")
const RULES := preload("res://scripts/campaign/scoring_rules.gd")
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
var result_earned := 0
var notice: Label
var buttons: Array[Button] = []
var settings_from_pause := false
var testing := false
var quitting := false
var preparing := false
var prepare_in_tests := false
var last_preparation_ms := 0
var last_preparation_count := 0
var music: Node
var play_mode := "campaign"
var waiting_binding := ""
var module_group := 0
var rules_from := "briefing"
var seen_departures: Dictionary = {}
var session_profile: RefCounted
var asset_cache: Array[Resource] = []
const BIND_NAMES := {"move_left":"Gauche","move_right":"Droite","move_up":"Monter","move_down":"Descendre","fire":"Tirer","bomb":"Bombe","strike":"Capacité de l'avion","focus_flight":"Vol de précision"}

func _apply_bindings() -> void:
	for action in profile.data.bindings:
		if not BIND_NAMES.has(action): continue
		for event in InputMap.action_get_events(action):
			if event is InputEventKey: InputMap.action_erase_event(action,event)
		var key := InputEventKey.new()
		key.keycode = int(profile.data.bindings[action])
		InputMap.action_add_event(action,key)

func _show_bindings() -> void:
	page = "bindings"
	_clear_menu("COMMANDES","Sélectionnez une action puis appuyez sur une touche. Échap annule. Manette : stick / A / B / X / LB.")
	var i := 0
	for action in BIND_NAMES:
		var label := ""
		for event in InputMap.action_get_events(action):
			if event is InputEventKey: label += (" / " if label!="" else "")+OS.get_keycode_string(event.keycode)
		_button(BIND_NAMES[action]+"  :  "+label,Vector2(94+(i%2)*860,290+(i/2)*125),Vector2(810,76),func(): waiting_binding=action; notice.text="Appuyez sur la nouvelle touche pour "+BIND_NAMES[action])
		i += 1
	_button("RÉTABLIR",Vector2(94,862),Vector2(330,60),func():
		profile.data.bindings.clear()
		for action in BIND_NAMES:
			for event in InputMap.action_get_events(action):
				if event is InputEventKey: InputMap.action_erase_event(action,event)
		_bind_controls(); _save(); _show_bindings())
	_button("RETOUR",Vector2(454,862),Vector2(330,60),func(): _show_settings(settings_from_pause))
	_focus_first()

func _show_graphics() -> void:
	page = "graphics"
	_clear_menu("GRAPHISMES & CONFORT","Les effets utilisent des capacités fixes. Choisissez le compromis adapté à votre écran.")
	for i in range(3):
		_button(("✓  " if int(profile.data.settings.get("quality",1))==i else "")+["PERFORMANCE","ÉQUILIBRÉ","QUALITÉ"][i],Vector2(94+i*560,320),Vector2(520,80),func(): profile.data.settings.quality=i; _apply_graphics(); _save(); _show_graphics())
	_label("Performance : sans ombres dynamiques ni débris, anti-crénelage désactivé.\nÉquilibré : ombres, débris et anti-crénelage 2×.\nQualité : anti-crénelage 4×. Le gameplay et les nuages restent identiques.",Vector2(94,450),Vector2(1640,180),31,MUTED)
	for i in range(2):
		var key: String = ["vsync","fps"][i]
		var check := CheckButton.new()
		check.text = ["Synchronisation verticale","Afficher les FPS"][i]
		check.position = Vector2(94+i*700,700)
		check.button_pressed = profile.data.settings.get(key,true if i==0 else false)
		check.toggled.connect(func(value): profile.data.settings[key]=value; _apply_settings(); _save())
		design.add_child(check)
	var short_intro := CheckButton.new()
	short_intro.name = "ShortRetryIntro"
	short_intro.text = "Stabilisation courte après un décollage déjà vu"
	short_intro.position = Vector2(94,768)
	short_intro.size = Vector2(1160,56)
	short_intro.button_pressed = bool(profile.data.settings.get("short_retry_intro",false))
	short_intro.toggled.connect(func(value): profile.data.settings.short_retry_intro=value; _apply_settings(); _save())
	design.add_child(short_intro)
	_label("Première découverte : décollage complet depuis le porte-avions. Réessayer : stabilisation de 1,6 s si activée.\nSans effet en entraînement aux boss. Le retour au porte-avions reste complet.",Vector2(94,833),Vector2(1670,71),25,MUTED).name = "ShortRetryExplanation"
	_button("RETOUR",Vector2(94,946),Vector2(330,55),func(): _show_settings(settings_from_pause))
	_focus_first()

func _apply_graphics() -> void:
	if not is_instance_valid(cockpit): return
	var quality := int(profile.data.settings.get("quality",1))
	cockpit.viewport.msaa_3d = [Viewport.MSAA_DISABLED,Viewport.MSAA_2X,Viewport.MSAA_4X][quality]
	cockpit.flight.get_node("KeyLight").shadow_enabled = quality>0
	if is_instance_valid(director) and is_instance_valid(director.details): director.details.enabled = quality>0
	if is_instance_valid(director) and is_instance_valid(director.details): director.details.reduced_flash = not bool(profile.data.settings.flashes)
	if is_instance_valid(director) and is_instance_valid(director.score_bursts): director.score_bursts.reduced_flash = not bool(profile.data.settings.flashes)
	if is_instance_valid(director) and is_instance_valid(director.assault): director.assault.set_quality(quality)

func _show_challenges(mode: String) -> void:
	page = "challenges"
	_clear_menu("ARCADE  /  SCORE ATTACK" if mode=="arcade" else "ÉCOLE DE CHASSE  /  BOSS","Équipement fixe, difficulté Pilote. Aucun changement à la progression de votre campagne.")
	var index := 0
	for m in missions:
		if mode=="practice" and m.boss=="": continue
		var key := "%d:%d" % [int(m.id),profile.data.aircraft]
		var label := "%02d  /  %s\n%s" % [int(m.id),m.title,"RECORD  %08d" % int(profile.data.arcade_records.get(key,0)) if mode=="arcade" else "ENTRAÎNEMENT  /  MULTI-TIR"]
		var button := _button(label,Vector2(94+(index%4)*437,270+(index/4)*80),Vector2(418,72),_start_mode.bind(mode,int(m.id)))
		button.add_theme_font_size_override("font_size",19)
		index += 1
	_button("RETOUR",Vector2(94,944),Vector2(300,56),_show_main)
	_focus_first()

func _start_mode(mode: String, number: int) -> void:
	_launch(number,mode)

func _can_launch(number: int, mode: String) -> bool:
	if mode not in ["campaign","arcade","practice"] or number < 1 or number > missions.size(): return false
	if mode=="campaign": return number <= int(profile.data.unlocked)
	if mode=="practice": return preload("res://scripts/campaign/boss.gd").MODELS.has(str(missions[number-1].get("boss","")))
	return true

func _campaign_context(number: int) -> void:
	# The hangar, map and briefing always display the persistent campaign profile.
	# Keep their launch context aligned, including when leaving an isolated mode.
	play_mode = "campaign"
	session_profile = profile
	selected_mission = clampi(number,1,mini(int(profile.data.unlocked),missions.size()))

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().auto_accept_quit = false
	missions = JSON.parse_string(FileAccess.get_file_as_string("res://data/missions.json"))
	for i in range(missions.size()): missions[i] = preload("res://scripts/campaign/operations.gd").prepare(missions[i])
	profile.load_profile()
	_bind_controls()
	_apply_bindings()
	_setup_audio()
	_build_theme()
	# Keep boss resources resident from the menu, avoiding disk loads mid-fight.
	for path in preload("res://scripts/campaign/boss.gd").MODELS.values():
		var resource := load(path)
		if not asset_cache.has(resource): asset_cache.append(resource)
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
	if is_instance_valid(session_profile) and session_profile!=profile: session_profile.data.settings=profile.data.settings.duplicate()
	for pair in [["Master","master"],["Music","music"],["Effects","effects"]]:
		var volume: float = profile.data.settings[pair[1]]
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index(pair[0]),linear_to_db(maxf(0.0001,volume)))
		AudioServer.set_bus_mute(AudioServer.get_bus_index(pair[0]),volume <= 0)
	_apply_graphics()
	if not testing and DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if profile.data.settings.get("vsync",true) else DisplayServer.VSYNC_DISABLED)
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
	waiting_binding = ""
	background.texture = load("res://assets/campaign/title-ocean.png")
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
	label.position = position_at
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_override("font",TITLE if title else FONT)
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Give wrapping a width before adding text. At width zero the first minimum
	# height can span thousands of pixels and prevent a later size assignment.
	label.size = dimensions
	label.text = text
	design.add_child(label)
	label.size = dimensions
	return label

func _fit_label(label: Label, maximum_height: float, minimum_font_size := 18) -> void:
	var pixels := label.get_theme_font_size("font_size")
	while label.get_minimum_size().y>maximum_height and pixels>minimum_font_size:
		pixels -= 1
		label.add_theme_font_size_override("font_size",pixels)
	label.size.y = maximum_height

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
	_campaign_context(int(profile.data.next_mission))
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
	_button("ARCADE  /  SCORE ATTACK",Vector2(1290,590),Vector2(510,58),_show_challenges.bind("arcade"))
	_button("ENTRAÎNEMENT AUX BOSS",Vector2(1290,667),Vector2(510,58),_show_challenges.bind("practice"))
	_label("CARNET DE VOL",Vector2(1290,792),Vector2(520,45),26,GOLD)
	_label("%02d / 32 missions accomplies\nRecord  %08d\n%d pièces disponibles au hangar" % [completed,profile.data.high_score,profile.data.credits],Vector2(1290,842),Vector2(520,120),29,Color("dae5e7"))
	if not profile.data.records.is_empty() or profile.last_error==ERR_FILE_CORRUPT: _button("NOUVELLE CAMPAGNE",Vector2(1290,950),Vector2(510,52),_confirm_new_campaign)
	if profile.last_error==ERR_FILE_CORRUPT: notice.text = "SAUVEGARDE ILLISIBLE — fichiers conservés. Progression non enregistrée. Nouvelle campagne permet de repartir après confirmation."
	_focus_first()

func _show_missions() -> void:
	_campaign_context(selected_mission)
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
	if not _can_launch(number,"campaign"): return
	_campaign_context(number)
	page = "briefing"
	var m: Dictionary = missions[number-1]
	_clear_menu("MISSION %02d  /  %s" % [number,str(m.region).to_upper()],str(m.title).to_upper())
	preload("res://scripts/campaign/carrier_menu.gd").new().briefing(self,m)
	_focus_first()

func _show_hangar() -> void:
	_campaign_context(selected_mission)
	page = "hangar"
	_clear_menu("HANGAR D'ESCADRILLE","APPAREILS & RANGS  /  STATISTIQUES SANS POW, AVEC VOTRE ÉQUIPEMENT")
	preload("res://scripts/campaign/carrier_menu.gd").new().hangar(self)
	var assigned_aircraft: Button = design.get_node("SelectAircraft_%d" % int(profile.data.aircraft))
	assigned_aircraft.grab_focus()

func _select_aircraft(index: int) -> void:
	profile.data.aircraft = index
	_save()
	_show_hangar()

func _buy(index: int) -> void:
	var purchased: bool = profile.buy_upgrade(index)
	_show_hangar()
	if not purchased and profile.last_error != OK: notice.text = "Achat annulé : la sauvegarde n’a pas pu être écrite."

func _show_modules(group := -1, focus_id := "") -> void:
	_campaign_context(selected_mission)
	if group>=0: module_group = clampi(group,0,4)
	page = "modules"
	_clear_menu("ATELIER D'ÉQUIPEMENT","DEUX EMPLACEMENTS MAXIMUM  /  UN MODULE PAR FAMILLE  /  CHANGEMENTS GRATUITS ENTRE LES MISSIONS")
	preload("res://scripts/campaign/carrier_menu.gd").new().modules(self)
	_focus_first()
	if focus_id.is_empty(): focus_id = "ModuleTab_%d" % module_group
	if not focus_id.is_empty():
		var focused: Button = design.find_child(focus_id,true,false)
		if is_instance_valid(focused) and not focused.disabled: focused.grab_focus()

func _show_rules(from_page := "briefing") -> void:
	rules_from = from_page
	page = "rules"
	_clear_menu("GUIDE DE VOL  /  SCORE & MAÎTRISE","RÈGLES DE CAMPAGNE  /  LA MÉDAILLE ET LE RANG ÉVALUENT DES CRITÈRES DIFFÉRENTS")
	preload("res://scripts/campaign/carrier_menu.gd").new().scoring_guide(self)
	_button("RETOUR AU BRIEFING" if rules_from=="briefing" else "RETOUR AU BILAN",Vector2(94,946),Vector2(440,55),_return_from_rules).name = "RulesReturn"
	_focus_first()

func _show_criteria() -> void:
	if result.is_empty() or not is_instance_valid(director): return
	page = "criteria"
	_clear_menu("DÉBRIEFING  /  MÉDAILLE & RANG","MISSION %02d  /  %s  /  %s" % [selected_mission,director.mission.title,play_mode.to_upper()])
	preload("res://scripts/campaign/carrier_menu.gd").new().scoring_criteria(self,result)
	_button("RETOUR AU RÉSULTAT",Vector2(94,946),Vector2(440,55),_draw_result.bind(result)).name = "CriteriaReturn"
	_button("GUIDE DE SCORE",Vector2(559,946),Vector2(440,55),_show_rules.bind("criteria")).name = "CriteriaRules"
	_focus_first()

func _return_from_rules() -> void:
	if rules_from=="criteria": _show_criteria()
	else: _show_briefing(selected_mission)

func _buy_module(id: String) -> void:
	var purchased: bool = profile.buy_module(id)
	_show_modules(-1,"EquipModule_"+id if purchased else "BuyModule_"+id)
	if purchased: notice.text = "MODULE ACQUIS — équipez-le sur un emplacement libre."
	elif profile.last_error!=OK: notice.text = "Achat annulé : la sauvegarde n’a pas pu être écrite."

func _equip_module(id: String) -> void:
	var previously_equipped: bool = id in profile.data.equipped_modules
	var changed: bool = profile.equip_module(id)
	_show_modules(-1,"EquipModule_"+id)
	if changed: notice.text = "MODULE RETIRÉ — emplacement libre." if previously_equipped else "MODULE ÉQUIPÉ — statistiques actualisées pour les trois appareils."
	elif profile.last_error!=OK: notice.text = "Modification annulée : la sauvegarde n’a pas pu être écrite."
	else: notice.text = "Retirez d'abord le module de cette famille ou libérez un emplacement."

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
	_button("COMMANDES",Vector2(410,947),Vector2(280,56),_show_bindings)
	_button("GRAPHISMES",Vector2(726,947),Vector2(280,56),_show_graphics)
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
	text.text = "PACIFIC STRIKE — CAMPAGNE 1942\n\nConception, programmation et assets originaux : projet Cyril / Codex.\nMoteur Godot (licence MIT), modélisation Blender, illustrations et textures générées avec imagegen.\n\nMUSIQUE ACTIVE\nMenus, vol, combats de boss et victoire : Juhani Junkala / SubspaceAudio — 5 Chiptunes (Action), CC0. Les pistes gardent leur tempo et leurs mélodies d'origine, avec des transitions en fondu.\n\nCOMPOSITIONS HISTORIQUES\nLes anciennes compositions procédurales Pacific Strike et leurs pistes pulse / drive / hero sont conservées dans les sources ; elles ne sont plus diffusées comme musique de combat. Le signal radio original reste utilisé sur le bus des effets. Le son du laser est également une création procédurale originale.\n\n1942 et 1942: Joint Strike appartiennent à leurs ayants droit ; ce projet indépendant n'est pas affilié à Capcom.\n\nPOLICES\nBarlow Condensed, Black Ops One et DSEG : licences distribuées dans assets/ui/fonts.\n\n"
	text.name = "CreditsText"
	for file in ["res://assets/audio/engine/CREDITS.md","res://assets/audio/weapons/CREDITS.md","res://assets/campaign/music/CREDITS.txt"]:
		text.text += FileAccess.get_file_as_string(file)+"\n\n"
	scroll.add_child(text)
	_button("RETOUR",Vector2(94,936),Vector2(280,56),_show_main)
	_focus_first()

func _launch(number: int, mode := "", retry := false) -> void:
	if preparing or quitting: return
	var launch_mode: String = play_mode if mode.is_empty() else mode
	if not _can_launch(number,launch_mode):
		if is_instance_valid(notice): notice.text = "Mission indisponible dans ce mode. Choisissez une mission accessible."
		return
	var warm := (not testing or prepare_in_tests) and DisplayServer.get_name()!="headless"
	var cover: ColorRect
	if warm:
		preparing = true
		page = "loading"
		cover = ColorRect.new()
		cover.name = "MissionPreparation"
		cover.color = Color("07141c")
		cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		cover.z_index = 100
		add_child(cover)
		var title := Label.new()
		title.text = "PRÉPARATION DU VOL"
		title.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		title.add_theme_font_override("font",TITLE)
		title.add_theme_font_size_override("font_size",36)
		title.modulate = GOLD
		cover.add_child(title)
		await RenderingServer.frame_post_draw
		if quitting: return
	_build_run(number,launch_mode,retry)
	if warm:
		page = "loading"
		cockpit.process_mode = Node.PROCESS_MODE_DISABLED
		var engine_audio: Node = cockpit.flight.get_node("Departure").engine_audio
		engine_audio.stop()
		var started := Time.get_ticks_msec()
		var preparation := preload("res://scripts/campaign/render_preparation.gd").new()
		cockpit.flight.add_child(preparation)
		await preparation.prepare(cockpit.flight,director)
		if quitting or not is_instance_valid(cockpit): return
		last_preparation_count = preparation.prepared_count
		preparation.queue_free()
		await RenderingServer.frame_post_draw
		if quitting or not is_instance_valid(cockpit): return
		last_preparation_ms = Time.get_ticks_msec()-started
		if cockpit.flight.get_node("Departure").active: engine_audio.start()
		cockpit.process_mode = Node.PROCESS_MODE_PAUSABLE
		cover.queue_free()
		page = "playing"
		preparing = false
		if not testing and not DisplayServer.window_is_focused(): _show_pause()

func _build_run(number: int, launch_mode: String, retry: bool) -> void:
	_dispose_run()
	play_mode = launch_mode
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
	session_profile = profile
	if play_mode!="campaign":
		session_profile = PROFILE.new()
		session_profile.data.aircraft = profile.data.aircraft
		session_profile.data.settings = profile.data.settings.duplicate()
		session_profile.data.difficulty = 1
		session_profile.data.power = "spread" if play_mode=="practice" else "none"
	director.profile = session_profile
	director.practice = play_mode=="practice"
	director.first_takeoff = true
	director.finished.connect(func(report): _show_result.call_deferred(report))
	if is_instance_valid(music):
		music.foreground_gain_changed.connect(cockpit.flight.get_node("Weapons").audio.set_alert_attenuation)
		music.begin_run()
		director.audio_event.connect(_on_audio_event)
	cockpit.flight.add_child(director)
	cockpit.flight.get_node("Weapons").set_power(session_profile.data.power)
	var departure = cockpit.flight.get_node("Departure")
	var departure_key := "%s:%d" % [play_mode,number]
	var use_short_intro: bool = retry and play_mode!="practice" and bool(profile.data.settings.get("short_retry_intro",false)) and seen_departures.has(departure_key)
	# Mark only a normal takeoff that actually reached flight. Leaving the menu
	# during its choreography never makes the next attempt skip that discovery.
	if play_mode!="practice" and not use_short_intro:
		departure.flight_started.connect(func(): seen_departures[departure_key]=true,CONNECT_ONE_SHOT)
	if use_short_intro: departure.begin_short_retry()
	var hud := HUD.new()
	hud.name = "CampaignHUD"
	hud.cockpit = cockpit
	hud.director = director
	cockpit.add_child(hud)
	if play_mode=="practice":
		departure.finish_immediately()
		director._spawn_boss(director.mission.boss)
	_apply_graphics()
	_assign_audio(cockpit)
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	if is_instance_valid(music): music.set_mode("flight")

func _on_audio_event(kind: String, event_id: String) -> void:
	if not is_instance_valid(music): return
	music.notify_event(kind, event_id)
	if is_instance_valid(director): music.previous_radio = director.radio

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
	_button("RECOMMENCER LA MISSION",Vector2(94,509),Vector2(580,64),_launch.bind(selected_mission,"",true))
	_button("RETOUR À L'ACCUEIL",Vector2(94,603),Vector2(580,64),_show_main)
	_label("La progression est enregistrée entre les missions.\nReprendre depuis l'accueil relance le briefing de la mission.",Vector2(850,325),Vector2(870,150),32,MUTED)
	_label("COMMANDES  /  CLAVIER · MANETTE",Vector2(850,495),Vector2(870,48),27,GOLD)
	var commands := _label(COMMANDS.flight_guide(),Vector2(850,555),Vector2(870,325),30,MUTED)
	commands.name = "FlightCommands"
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
	cockpit.get_node("CampaignHUD").hide()
	if is_instance_valid(music):
		if report.won: music.set_mode("victory")
		else: music.stop()
	page = "result"
	get_tree().paused = true
	director.paused = true
	result_earned = 0
	if play_mode=="campaign": profile.data.high_score = maxi(profile.data.high_score,int(report.score))
	elif play_mode=="arcade":
		var key := "%d:%d" % [selected_mission,profile.data.aircraft]
		profile.data.arcade_records[key] = maxi(int(profile.data.arcade_records.get(key,0)),int(report.get("mission_score",report.score)))
	if report.won and play_mode=="campaign":
		profile.data.run_score = int(report.score)
		profile.data.run_lives = int(report.get("lives",3))
		profile.data.power = report.get("power","none")
		profile.data.pow_ready = profile.data.power == "spread"
		result_earned = profile.record_victory(selected_mission,report.get("mission_score",report.score),report.grade)
	if play_mode=="campaign" and report.won:
		var record: Dictionary = profile.data.records[str(selected_mission)]
		record.best_chain = maxi(int(record.get("best_chain",0)),int(report.get("best_chain",0)))
		var ranks := ["D","C","B","A","S"]
		if ranks.find(str(report.get("rank","D")))>ranks.find(str(record.get("rank","D"))): record.rank=report.rank
	_draw_result(report)
	_save()

func _draw_result(report: Dictionary) -> void:
	if not is_instance_valid(director): return
	page = "result"
	var victory: bool = report.won and selected_mission == 32 and play_mode=="campaign"
	# Explicit terminal cause takes precedence over an old cached objective flag.
	# Zero lives also keeps historical reports without game_over unambiguous.
	var game_over: bool = not report.won and (bool(report.get("game_over",false)) or int(report.get("lives",1))<=0)
	var objective_failed: bool = not game_over and bool(report.get("objective_failed",false))
	_clear_menu("LE PACIFIQUE EST LIBRE" if victory else ("MISSION ACCOMPLIE" if report.won else ("MISSION INACCOMPLIE" if objective_failed else "GAME OVER")),"%02d / 32  •  %s" % [selected_mission,director.mission.title])
	_label(["—","BRONZE","ARGENT","OR"][int(report.grade)] if report.won else ("OBJECTIF NON ATTEINT" if objective_failed else "AUCUNE VIE RESTANTE"),Vector2(94,298),Vector2(1050,100),62 if objective_failed else 70,GOLD,true)
	_label("SCORE TOTAL    %08d\nCETTE MISSION    +%d\nAIR / MER / SOL    %d / %d / %d\nVIES PERDUES    %d\nBONUS DE FIN    %d  •  PIÈCES    +%d" % [report.score,report.get("mission_score",report.score),report.kills-report.naval_kills-int(report.get("ground_kills",0)),report.naval_kills,report.get("ground_kills",0),report.deaths,report.bonus,result_earned],Vector2(94,438),Vector2(1040,300),35,Color("d4dfe1")).name = "ResultScoreDetails"
	var summary := "32 missions. Huit secteurs. Une route jusqu'à l'aube.\n\nLa campagne est terminée. Les missions restent disponibles pour obtenir toutes les médailles d'or." if victory else ("La mission suivante est disponible.\nProfitez du hangar pour préparer votre appareil." if report.won else "Votre meilleur score est conservé.\n\nRéessayer reprend le début de cette mission avec le score et les vies du dernier point de sauvegarde.")
	if play_mode!="campaign": summary = ("Le record Arcade est mis à jour si ce score est supérieur." if play_mode=="arcade" else "Entraînement terminé. Aucun record ni récompense de campagne.")+"\n\nRejouer conserve ce mode et son équipement fixe. Le hangar vous ramène à la campagne sauvegardée."
	var summary_y := 336.0
	var summary_height := 320.0
	var ground_status: Dictionary = report.get("ground_status",{})
	if not ground_status.is_empty():
		var ground_text := "CIBLES DÉTRUITES  %d / %d" % [int(ground_status.get("kills",0)),int(ground_status.get("quota",0))]
		var priority_total := int(ground_status.get("priority_total",0))
		if priority_total>0:
			ground_text += "\nPRIORITÉS  %d / %d" % [int(ground_status.get("priority_destroyed",0)),priority_total]
			var escaped: Array = ground_status.get("escaped_priority_ids",[])
			if not escaped.is_empty(): ground_text += "  •  %d ÉCHAPPÉE(S)" % escaped.size()
		var ground_label := _label(ground_text,Vector2(1210,336),Vector2(590,92),27,GOLD if bool(ground_status.get("main_met",false)) else Color("ff986c"))
		ground_label.name = "ResultGroundObjective"
		_fit_label(ground_label,92,21)
		summary_y = 448.0
		summary_height = 208.0
	var summary_label := _label(summary,Vector2(1210,summary_y),Vector2(590,summary_height),30,MUTED)
	summary_label.name = "ResultSummary"
	_fit_label(summary_label,summary_height,21)
	if report.won and selected_mission < 32 and play_mode=="campaign":
		_button("MISSION SUIVANTE",Vector2(94,842),Vector2(440,66),_briefing_after_result.bind(selected_mission+1))
	else: _button("REJOUER LA MISSION" if report.won else "RÉESSAYER LA MISSION",Vector2(94,842),Vector2(440,66),_launch.bind(selected_mission,"",true))
	_button("HANGAR",Vector2(559,842),Vector2(320,66),_hangar_after_result)
	_button("ACCUEIL",Vector2(904,842),Vector2(320,66),_show_main)
	_button("MÉDAILLE & RANG  /  DÉTAILS",Vector2(1249,842),Vector2(551,66),_show_criteria).name = "ResultCriteria"
	if victory: _button("CRÉDITS",Vector2(94,931),Vector2(320,55),_credits_after_result)
	if play_mode!="campaign": _label("MODE "+play_mode.to_upper()+"  /  CAMPAGNE INCHANGÉE",Vector2(1210,665),Vector2(590,70),26,GOLD)
	_label("RANG %s   •   CHAÎNE MAX %d   •   PRÉCISION %d %%\nOBJECTIF SECONDAIRE : %s" % [report.get("rank","C"),report.get("best_chain",0),int(float(report.get("accuracy",0))*100),"ACCOMPLI" if report.get("secondary",false) else "NON ACCOMPLI"],Vector2(94,744),Vector2(1620,85),27,GOLD)
	_focus_first()

func _briefing_after_result(number: int) -> void:
	_dispose_run()
	_show_briefing(number)
func _hangar_after_result() -> void:
	if play_mode!="campaign": selected_mission = int(profile.data.next_mission)
	elif result.get("won",false): selected_mission = mini(missions.size(),selected_mission+1)
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
	if preparing:
		get_viewport().set_input_as_handled()
		return
	if waiting_binding!="" and event is InputEventKey and event.pressed and not event.echo:
		get_viewport().set_input_as_handled()
		if event.keycode==KEY_ESCAPE:
			waiting_binding = ""
			_show_bindings()
			return
		if event.keycode in [KEY_ENTER,KEY_TAB] or event.alt_pressed or event.ctrl_pressed or event.meta_pressed:
			notice.text = "Cette touche est réservée à la navigation. Choisissez une autre touche."
			return
		for action in BIND_NAMES:
			if action==waiting_binding: continue
			for bound in InputMap.action_get_events(action):
				if bound is InputEventKey and bound.keycode==event.keycode:
					notice.text = "Touche déjà utilisée : "+BIND_NAMES[action]
					return
		profile.data.bindings[waiting_binding] = event.keycode
		waiting_binding = ""
		_apply_bindings()
		_save()
		_show_bindings()
		return
	if event.is_action_pressed("quit_game") and not event.is_echo():
		get_viewport().set_input_as_handled()
		match page:
			"playing": _show_pause()
			"pause": _resume()
			"bindings", "graphics": _show_settings(settings_from_pause)
			"modules": _show_hangar()
			"rules": _return_from_rules()
			"criteria": _draw_result(result)
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
	if quitting: return
	quitting = true
	_save()
	_dispose_run()
	if is_instance_valid(music):
		music.stop()
		music.set_process(false)
	# A slow startup frame can consume a delta-based timer immediately. Allow
	# real mixer time to retire the WAV playback before the audio server exits.
	var drain_until := Time.get_ticks_msec()+300
	while Time.get_ticks_msec()<drain_until:
		await get_tree().create_timer(.05).timeout
	get_tree().quit()


func _process(_delta: float) -> void:
	if page == "playing" and is_instance_valid(director) and is_instance_valid(music):
		music.update_combat(director)
		music.set_mode("victory" if director.ending else ("boss" if is_instance_valid(director.boss) and director.boss.alive else ("flight" if int(director.mission.sector)%2==0 else "flight2")))

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
	var bindings: Dictionary = profile.data.bindings.duplicate()
	var arcade: Dictionary = profile.data.arcade_records.duplicate()
	profile.reset()
	profile.data.bindings = bindings
	profile.data.arcade_records = arcade
	profile.data.settings = options
	profile.data.high_score = record
	selected_mission = 1
	_save()
	_show_briefing(1)
