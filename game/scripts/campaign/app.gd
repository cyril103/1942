extends Control
const L10N := preload("res://scripts/campaign/localization.gd")
const PROFILE := preload("res://scripts/campaign/profile.gd")
const DIRECTOR := preload("res://scripts/campaign/director.gd")
const HUD := preload("res://scripts/campaign/hud.gd")
const COMMANDS := preload("res://scripts/campaign/command_labels.gd")
const GAMEPAD := preload("res://scripts/campaign/gamepad_bindings.gd")
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
var result_previous_best := 0
var result_generation := -1
var operation_sector := -1
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
var boss_rush = preload("res://scripts/campaign/boss_rush.gd").new()
var run_generation := 0
var asset_cache: Array[Resource] = []
var active_joypad := -1
var disconnected_joypad := -1
var pending_controller_disconnect := -1
var resume_remaining := 0.0
var resume_label: Label
var controller_device := -1
var controller_menu: RefCounted
var menu_gamepad_navigation: RefCounted
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
	_clear_menu(L10N.text("COMMANDES CLAVIER"),L10N.text("Sélectionnez une action puis appuyez sur une touche. Pour les boutons et sticks, ouvrez Commandes manette."))
	var i := 0
	for action in BIND_NAMES:
		var label := " / ".join(COMMANDS.keys(action))
		_button(L10N.text(BIND_NAMES[action])+"  :  "+label,Vector2(94+(i%2)*860,290+(i/2)*125),Vector2(810,76),func(): waiting_binding=action; notice.text=L10N.text("Appuyez sur la nouvelle touche pour ")+L10N.text(BIND_NAMES[action]))
		i += 1
	var automatic := CheckButton.new()
	automatic.name = "AutomaticFire"
	automatic.text = L10N.text("TIR AUTOMATIQUE  /  libère la touche de tir pendant le vol")
	automatic.position = Vector2(94,786)
	automatic.size = Vector2(1600,52)
	automatic.button_pressed = bool(profile.data.settings.get("auto_fire",false))
	automatic.toggled.connect(func(value): profile.data.settings.auto_fire=value; _apply_settings(); _save())
	design.add_child(automatic)
	_button(L10N.text("RÉTABLIR"),Vector2(94,862),Vector2(330,60),func():
		profile.data.bindings.clear()
		for action in BIND_NAMES:
			for event in InputMap.action_get_events(action):
				if event is InputEventKey: InputMap.action_erase_event(action,event)
		_bind_controls(); _save(); _show_bindings())
	_button(L10N.text("RETOUR"),Vector2(454,862),Vector2(330,60),func(): _show_settings(settings_from_pause))
	_button(L10N.text("COMMANDES MANETTE"),Vector2(814,862),Vector2(650,60),_show_gamepad).name = "GamepadTab"
	_focus_first()

func _show_gamepad() -> void:
	controller_menu.show()

func _pad_label(button: int) -> String:
	return GAMEPAD.binding_label({"kind":"button","index":button},controller_device)

func _select_controller(device: int) -> void:
	controller_device = device
	COMMANDS.active_device = device
	GAMEPAD.apply(profile.data,device)

func _show_graphics() -> void:
	page = "graphics"
	_clear_menu(L10N.text("GRAPHISMES & CONFORT"),L10N.text("Les effets utilisent des capacités fixes. Choisissez le compromis adapté à votre écran."))
	for i in range(3):
		_button(("✓  " if int(profile.data.settings.get("quality",1))==i else "")+[L10N.text("PERFORMANCE"),L10N.text("ÉQUILIBRÉ"),L10N.text("QUALITÉ")][i],Vector2(94+i*560,320),Vector2(520,80),func(): profile.data.settings.quality=i; _apply_graphics(); _save(); _show_graphics())
	_label(L10N.text("Performance : sans ombres dynamiques ni débris, anti-crénelage désactivé.\nÉquilibré : ombres, débris et anti-crénelage 2×.\nQualité : anti-crénelage 4×. Le gameplay et les nuages restent identiques."),Vector2(94,450),Vector2(1640,180),31,MUTED)
	for i in range(2):
		var key: String = ["vsync","fps"][i]
		var check := CheckButton.new()
		check.text = [L10N.text("Synchronisation verticale"),L10N.text("Afficher les FPS")][i]
		check.position = Vector2(94+i*700,700)
		check.button_pressed = profile.data.settings.get(key,true if i==0 else false)
		check.toggled.connect(func(value): profile.data.settings[key]=value; _apply_settings(); _save())
		design.add_child(check)
	var short_intro := CheckButton.new()
	short_intro.name = "ShortRetryIntro"
	short_intro.text = L10N.text("Stabilisation courte après un décollage déjà vu")
	short_intro.position = Vector2(94,768)
	short_intro.size = Vector2(1160,56)
	short_intro.button_pressed = bool(profile.data.settings.get("short_retry_intro",false))
	short_intro.toggled.connect(func(value): profile.data.settings.short_retry_intro=value; _apply_settings(); _save())
	design.add_child(short_intro)
	_label(L10N.text("Première découverte : décollage complet depuis le porte-avions. Réessayer : stabilisation de 1,6 s si activée.\nSans effet en entraînement aux boss. Le retour au porte-avions reste complet."),Vector2(94,833),Vector2(1670,71),25,MUTED).name = "ShortRetryExplanation"
	_button(L10N.text("RETOUR"),Vector2(94,946),Vector2(330,55),func(): _show_settings(settings_from_pause))
	_button(L10N.text("CONFORT DE VOL & MANETTE"),Vector2(454,946),Vector2(780,55),_show_flight_comfort).name = "FlightComfortEntry"
	_focus_first()

func _show_flight_comfort() -> void:
	page = "flight_comfort"
	_clear_menu(L10N.text("CONFORT DE VOL & MANETTE"),L10N.text("Gardez le temps de vous replacer avant de retrouver le combat."))
	var rows := [
		["resume_countdown","Compte à rebours avant la reprise","Le vol reste figé pendant 3 secondes. Échap, Start ou B annule la reprise. Aucun mouvement ni flash supplémentaire."],
		["pause_on_disconnect","Pause si la manette active est déconnectée","Protège le vol lorsque la manette utilisée se déconnecte. Reconnectez-la ou utilisez le clavier, puis reprenez quand vous êtes prêt."],
	]
	for i in range(rows.size()):
		var key: String = rows[i][0]
		var check := CheckButton.new()
		check.name = "ResumeCountdown" if i==0 else "PauseOnDisconnect"
		check.text = L10N.text(rows[i][1])
		check.position = Vector2(94,310+i*230)
		check.size = Vector2(1660,62)
		check.button_pressed = bool(profile.data.settings.get(key,true))
		check.toggled.connect(func(value): profile.data.settings[key]=value; _apply_settings(); _save())
		design.add_child(check)
		_label(L10N.text(rows[i][2]),Vector2(94,394+i*230),Vector2(1640,106),30,MUTED)
	_label(L10N.text("MANETTE  /  A : valider  •  B : revenir  •  Start : pause\nEn vol, B conserve sa fonction de bombe."),Vector2(94,795),Vector2(1640,90),29,GOLD)
	_button(L10N.text("RETOUR"),Vector2(94,946),Vector2(330,55),_show_graphics)
	design.get_node("ResumeCountdown").grab_focus()

func _apply_graphics() -> void:
	if not is_instance_valid(cockpit): return
	var quality := int(profile.data.settings.get("quality",1))
	cockpit.set_presentation(str(director.mission.get("biome","coral")) if is_instance_valid(director) else "coral",quality)
	cockpit.viewport.msaa_3d = [Viewport.MSAA_DISABLED,Viewport.MSAA_2X,Viewport.MSAA_4X][quality]
	cockpit.flight.get_node("KeyLight").shadow_enabled = quality>0
	if is_instance_valid(director) and is_instance_valid(director.details): director.details.enabled = quality>0
	if is_instance_valid(director) and is_instance_valid(director.details): director.details.reduced_flash = not bool(profile.data.settings.flashes)
	if is_instance_valid(director) and is_instance_valid(director.score_bursts): director.score_bursts.reduced_flash = not bool(profile.data.settings.flashes)
	if is_instance_valid(director) and is_instance_valid(director.assault): director.assault.set_quality(quality)

func _show_challenges(mode: String) -> void:
	page = "challenges"
	_clear_menu(L10N.text("ARCADE  /  SCORE ATTACK") if mode=="arcade" else L10N.text("ÉCOLE DE CHASSE  /  BOSS"),L10N.text("Équipement fixe, difficulté Pilote. Aucun changement à la progression de votre campagne."))
	var index := 0
	for m in missions:
		if mode=="practice" and m.boss=="": continue
		var key := "%d:%d" % [int(m.id),profile.data.aircraft]
		var label := "%02d  /  %s\n%s" % [int(m.id),m.title,L10N.text("RECORD  %08d") % int(profile.data.arcade_records.get(key,0)) if mode=="arcade" else L10N.text("ENTRAÎNEMENT  /  MULTI-TIR")]
		var button := _button(label,Vector2(94+(index%4)*437,270+(index/4)*80),Vector2(418,72),_start_mode.bind(mode,int(m.id)))
		button.add_theme_font_size_override("font_size",19)
		index += 1
	_button(L10N.text("RETOUR"),Vector2(94,944),Vector2(300,56),_show_main)
	_focus_first()

func _start_mode(mode: String, number: int) -> void:
	_launch(number,mode)

func _can_launch(number: int, mode: String) -> bool:
	if mode not in ["campaign","arcade","practice","boss_rush"] or number < 1 or number > missions.size(): return false
	if mode=="campaign": return number <= int(profile.data.unlocked)
	if mode=="boss_rush": return boss_rush.active and boss_rush.stage_open and number==boss_rush.mission_id() and preload("res://scripts/campaign/boss.gd").MODELS.has(str(missions[number-1].get("boss","")))
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
	# Explicit source-key translation is applied before formatting. Disable
	# Godot's automatic second pass for this entire UI and its child controls.
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	get_tree().auto_accept_quit = false
	profile.load_profile()
	L10N.set_locale(str(profile.data.settings.get("language","fr")))
	_update_window_title()
	_prepare_missions()
	_bind_controls()
	_apply_bindings()
	controller_menu = preload("res://scripts/campaign/controller_menu.gd").new(self)
	menu_gamepad_navigation = preload("res://scripts/campaign/menu_gamepad_navigation.gd").new(self)
	var controllers := Input.get_connected_joypads()
	_select_controller(controllers[0] if not controllers.is_empty() else -1)
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
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

func _prepare_missions() -> void:
	# Always begin with canonical data: prepared briefings contain translated
	# text and cannot safely be used as the source for a second language.
	missions = JSON.parse_string(FileAccess.get_file_as_string("res://data/missions.json"))
	for i in range(missions.size()):
		missions[i] = preload("res://scripts/campaign/operations.gd").prepare(missions[i])

func _update_window_title() -> void:
	if DisplayServer.get_name()!="headless":
		DisplayServer.window_set_title(L10N.text("Pacific Strike — Campagne 1942"))

func _set_language(code: String) -> void:
	if code not in L10N.SUPPORTED: return
	if code == L10N.locale and profile.data.settings.get("language","fr") == code: return
	var focus_name := ""
	var focused := get_viewport().gui_get_focus_owner()
	if is_instance_valid(focused): focus_name = str(focused.name)
	L10N.set_locale(code)
	_update_window_title()
	profile.data.settings.language = L10N.locale
	if is_instance_valid(session_profile) and session_profile!=profile:
		session_profile.data.settings.language = L10N.locale
	_prepare_missions()
	if is_instance_valid(director):
		# Refresh narrative data only. Keep combat, timers, equipment and score.
		for mission in missions:
			if int(mission.id)==int(director.mission.id):
				director.mission = mission.duplicate(true)
				break
		director.refresh_localization()
	if page=="settings": _show_settings(settings_from_pause)
	elif page=="main": _show_main()
	if not focus_name.is_empty():
		var restored := design.find_child(focus_name,true,false) as Control
		if is_instance_valid(restored): restored.grab_focus()
	_save()

func _mode_label() -> String:
	match play_mode:
		"campaign": return L10N.text("CAMPAGNE")
		"practice": return L10N.text("ENTRAÎNEMENT")
		"boss_rush": return "BOSS RUSH"
		_: return "ARCADE"

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
	GAMEPAD.apply(profile.data,controller_device)
	# Godot 4.7's built-in ui_accept contains keyboard events only. Keep menu
	# confirmation stable even when the flight fire button is reassigned.
	var accept := InputEventJoypadButton.new()
	accept.device = -1
	accept.button_index = JOY_BUTTON_A
	if not InputMap.action_has_event("ui_accept",accept): InputMap.action_add_event("ui_accept",accept)

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
	if is_instance_valid(director): director.weapons.auto_fire = bool(profile.data.settings.get("auto_fire",false))
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
	if is_instance_valid(menu_gamepad_navigation): menu_gamepad_navigation.reset()
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
	notice = _label(L10N.text("FLÈCHES / STICK  •  %s / ENTRÉE : VALIDER  •  %s / ÉCHAP : REVENIR") % [_pad_label(JOY_BUTTON_A),_pad_label(JOY_BUTTON_B)],Vector2(94,1010),Vector2(1700,35),21,MUTED)

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
	if profile.save() != OK and is_instance_valid(notice): notice.text = L10N.text("SAUVEGARDE IMPOSSIBLE — progression conservée pour cette session.")

func _show_main() -> void:
	_dispose_run()
	page = "main"
	_campaign_context(int(profile.data.next_mission))
	if is_instance_valid(music): music.set_mode("menu")
	_clear_menu("PACIFIC STRIKE", L10N.text("ULTIMATE 2.4  /  CAMPAGNE 1942  /  32 MISSIONS  /  8 SECTEURS"),false)
	var radar := preload("res://scripts/campaign/title_radar.gd").new()
	radar.name = "PacificOperationsRadar"
	radar.position = Vector2(680,242)
	radar.size = Vector2(570,700)
	radar.reduced_motion = not bool(profile.data.settings.shake)
	design.add_child(radar)
	var completed: int = profile.data.records.size()
	_label(L10N.text("CHAQUE ESQUIVE\nCOMPTE."),Vector2(94,266),Vector2(900,190),64,GOLD,true)
	_label(L10N.text("Frôlez le danger. Brisez leurs formations.\nDes récifs du Pacifique au dernier rempart,\nla maîtrise fait la différence."),Vector2(96,470),Vector2(660,110),29,Color("d5dfe0"))
	_button(L10N.text("COMMENCER LA CAMPAGNE") if profile.data.records.is_empty() else L10N.text("REPRENDRE  /  MISSION %02d") % profile.data.next_mission,Vector2(94,590),Vector2(490,62),func(): _show_briefing(profile.data.next_mission))
	_button(L10N.text("CARTE DES MISSIONS"),Vector2(94,670),Vector2(490,56),_show_missions)
	_button(L10N.text("HANGAR & AMÉLIORATIONS"),Vector2(94,744),Vector2(490,56),_show_hangar)
	_button(L10N.text("OPTIONS"),Vector2(94,818),Vector2(235,54),func(): _show_settings(false))
	_button(L10N.text("CRÉDITS"),Vector2(349,818),Vector2(235,54),_show_credits)
	_button(L10N.text("QUITTER"),Vector2(94,892),Vector2(490,54),_quit)
	_label(L10N.text("L'ÉPREUVE ULTIME"),Vector2(1290,294),Vector2(510,44),25,GOLD)
	_label(L10N.text("8 BOSS.\n3 VIES.\nUNE SEULE CHANCE."),Vector2(1290,346),Vector2(510,165),41,Color("f1ede2"),true)
	_button(L10N.text("BOSS RUSH  /  ENTRER DANS L'ARÈNE"),Vector2(1290,534),Vector2(510,62),_show_boss_rush).name = "BossRushEntry"
	_button(L10N.text("ARCADE  /  SCORE ATTACK"),Vector2(1290,612),Vector2(510,58),_show_challenges.bind("arcade"))
	_button(L10N.text("ENTRAÎNEMENT AUX BOSS"),Vector2(1290,686),Vector2(510,58),_show_challenges.bind("practice"))
	_button(L10N.text("GUIDE DU PILOTE"),Vector2(1290,760),Vector2(510,54),_show_pilot_guide)
	_label(L10N.text("%02d / 32 MISSIONS  •  %d PIÈCES\nRECORD CAMPAGNE  %08d") % [completed,profile.data.credits,profile.data.high_score],Vector2(1290,842),Vector2(520,90),26,Color("dae5e7"))
	if not profile.data.records.is_empty() or profile.last_error==ERR_FILE_CORRUPT: _button(L10N.text("NOUVELLE CAMPAGNE"),Vector2(1290,950),Vector2(510,52),_confirm_new_campaign)
	if profile.last_error==ERR_FILE_CORRUPT: notice.text = L10N.text("SAUVEGARDE ILLISIBLE — fichiers conservés. Progression non enregistrée. Nouvelle campagne permet de repartir après confirmation.")
	var language := _button("Français  /  English",Vector2(1470,81),Vector2(330,52),func(): _set_language("en" if L10N.locale=="fr" else "fr"))
	language.name = "LanguageMenu"
	language.tooltip_text = "Switch to English" if L10N.locale=="fr" else "Passer en français"
	language.add_theme_font_size_override("font_size",23)
	_focus_first()

func _show_pilot_guide() -> void:
	page = "pilot_guide"
	_clear_menu(L10N.text("GUIDE DU PILOTE"),L10N.text("LE VOL EST SIMPLE À PRENDRE EN MAIN. LA MAÎTRISE SE CONSTRUIT À CHAQUE SORTIE."))
	_label(L10N.text("01  /  PILOTER"),Vector2(94,282),Vector2(790,52),32,GOLD,true)
	_label(COMMANDS.flight_guide(),Vector2(94,352),Vector2(790,340),31,Color("d4dfe1"))
	_label(L10N.text("02  /  LIRE LE DANGER"),Vector2(1000,282),Vector2(800,52),32,GOLD,true)
	_label(L10N.text("Vos tirs sont cyan. Les tirs ennemis sont orangés.\nMaintenez la précision pour ajuster votre trajectoire et voir le centre vulnérable de votre avion.\n\nLe HUD annonce le motif du boss et un conseil pour l'éviter. Observez sa charge, puis esquivez les projectiles. Détruisez ses deux points faibles pour réduire sa puissance."),Vector2(1000,352),Vector2(800,310),29,Color("d4dfe1"))
	_label(L10N.text("03  /  FRÔLER & ENCHAÎNER"),Vector2(94,729),Vector2(1660,48),32,GOLD,true)
	_label(L10N.text("Un projectile évité de très près rapporte 25 points et jusqu'à 0,6 % de charge spéciale, une seule fois par balle.\nDétruisez à nouveau en 4,5 s pour entretenir votre chaîne, jusqu'à ×5. Utilisez votre bombe avant d'être encerclé."),Vector2(94,800),Vector2(1660,100),29,MUTED)
	_button(L10N.text("RETOUR À L'ACCUEIL"),Vector2(94,942),Vector2(440,58),_show_main)
	_focus_first()

func _show_boss_rush() -> void:
	page = "boss_rush"
	_clear_menu(L10N.text("BOSS RUSH  /  LA TRAVERSÉE"),L10N.text("HUIT ADVERSAIRES. UN STOCK DE VIES COMMUN. LE DÉFI EST OUVERT DÈS LE PREMIER VOL."))
	var boss_script := preload("res://scripts/campaign/boss.gd")
	for index in range(boss_rush.ROUTE.size()):
		var mission: Dictionary = missions[boss_rush.ROUTE[index]-1]
		var at := Vector2(94+(index%4)*437,286+(index/4)*164)
		_label("%02d  /  %s" % [index+1,str(mission.region).to_upper()],at,Vector2(402,40),22,MUTED)
		_label(boss_script.display_name(mission.boss).split(" • ")[0],at+Vector2(0,48),Vector2(402,53),32,GOLD,true)
		_label(str(mission.title),at+Vector2(0,100),Vector2(402,48),22,Color("d4dfe1"))
	_label(L10N.text("VOTRE APPAREIL"),Vector2(94,656),Vector2(650,45),25,GOLD)
	for index in range(3):
		_button(("✓  " if int(profile.data.aircraft)==index else "")+PROFILE.AIRCRAFT[index],Vector2(94+index*570,714),Vector2(542,57),func(): profile.data.aircraft=index; _save(); _show_boss_rush())
	var record := int(profile.data.arcade_records.get("rush:%d" % profile.data.aircraft,0))
	_label(L10N.text("Difficulté Pilote • Multi-tir • Aucun module • Blindage et bombes restaurés entre les duels.\nLes vies et le score se conservent. Recommencer relance les huit boss. Record validé après la traversée complète."),Vector2(94,801),Vector2(1720,89),27,MUTED)
	_button(L10N.text("LANCER LA TRAVERSÉE"),Vector2(94,938),Vector2(540,62),_begin_boss_rush).name = "StartBossRush"
	_button(L10N.text("RETOUR"),Vector2(665,938),Vector2(280,62),_show_main)
	_label(L10N.text("RECORD  %08d") % record,Vector2(1200,943),Vector2(600,50),30,GOLD)
	_focus_first()

func _begin_boss_rush() -> void:
	boss_rush.begin(int(profile.data.aircraft))
	_launch(boss_rush.mission_id(),"boss_rush")

func _next_boss_rush() -> void:
	if boss_rush.advance(): _launch(boss_rush.mission_id(),"boss_rush")

func _show_missions(sector := -1) -> void:
	_campaign_context(selected_mission)
	page = "missions"
	_clear_menu(L10N.text("CARTE DES OPÉRATIONS"),L10N.text("Huit secteurs. Les missions accomplies restent rejouables pour améliorer leur médaille."))
	operation_sector = clampi(sector if sector>=0 else (selected_mission-1)/4,0,7)
	preload("res://scripts/campaign/operation_map.gd").new().build(self,operation_sector)

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
	_clear_menu(L10N.text("HANGAR D'ESCADRILLE"),L10N.text("APPAREILS & RANGS  /  STATISTIQUES SANS POW, AVEC VOTRE ÉQUIPEMENT"))
	preload("res://scripts/campaign/carrier_menu.gd").new().hangar(self)
	var assigned_aircraft: Button = design.get_node("SelectAircraft_%d" % int(profile.data.aircraft))
	assigned_aircraft.grab_focus()

func _select_aircraft(index: int) -> void:
	profile.data.aircraft = index
	_save()
	_show_hangar()

func _show_aircraft_gallery(index := -1) -> void:
	page = "aircraft_gallery"
	var shown := int(profile.data.aircraft) if index<0 else clampi(index,0,2)
	_clear_menu(L10N.text("LES AILES DU PACIFIQUE"),L10N.text("HANGAR  /  INSPECTION DES APPAREILS  /  TROIS VUES DISPONIBLES"))
	preload("res://scripts/campaign/carrier_menu.gd").new().gallery(self,shown)
	_focus_first()

func _buy(index: int) -> void:
	var purchased: bool = profile.buy_upgrade(index)
	_show_hangar()
	if not purchased and profile.last_error != OK: notice.text = L10N.text("Achat annulé : la sauvegarde n’a pas pu être écrite.")

func _show_modules(group := -1, focus_id := "") -> void:
	_campaign_context(selected_mission)
	if group>=0: module_group = clampi(group,0,4)
	page = "modules"
	_clear_menu(L10N.text("ATELIER D'ÉQUIPEMENT"),L10N.text("DEUX EMPLACEMENTS MAXIMUM  /  UN MODULE PAR FAMILLE  /  CHANGEMENTS GRATUITS ENTRE LES MISSIONS"))
	preload("res://scripts/campaign/carrier_menu.gd").new().modules(self)
	_focus_first()
	if focus_id.is_empty(): focus_id = "ModuleTab_%d" % module_group
	if not focus_id.is_empty():
		var focused: Button = design.find_child(focus_id,true,false)
		if is_instance_valid(focused) and not focused.disabled: focused.grab_focus()

func _show_rules(from_page := "briefing") -> void:
	rules_from = from_page
	page = "rules"
	_clear_menu(L10N.text("GUIDE DE VOL  /  SCORE & MAÎTRISE"),L10N.text("RÈGLES DE CAMPAGNE  /  LA MÉDAILLE ET LE RANG ÉVALUENT DES CRITÈRES DIFFÉRENTS"))
	preload("res://scripts/campaign/carrier_menu.gd").new().scoring_guide(self)
	_button(L10N.text("RETOUR AU BRIEFING") if rules_from=="briefing" else L10N.text("RETOUR AU BILAN"),Vector2(94,946),Vector2(440,55),_return_from_rules).name = "RulesReturn"
	_focus_first()

func _show_criteria() -> void:
	if result.is_empty() or not is_instance_valid(director): return
	page = "criteria"
	_clear_menu(L10N.text("DÉBRIEFING  /  MÉDAILLE & RANG"),"MISSION %02d  /  %s  /  %s" % [selected_mission,director.mission.title,_mode_label()])
	preload("res://scripts/campaign/carrier_menu.gd").new().scoring_criteria(self,result)
	_button(L10N.text("RETOUR AU RÉSULTAT"),Vector2(94,946),Vector2(440,55),_draw_result.bind(result)).name = "CriteriaReturn"
	_button(L10N.text("GUIDE DE SCORE"),Vector2(559,946),Vector2(440,55),_show_rules.bind("criteria")).name = "CriteriaRules"
	_focus_first()

func _return_from_rules() -> void:
	if rules_from=="criteria": _show_criteria()
	else: _show_briefing(selected_mission)

func _buy_module(id: String) -> void:
	var purchased: bool = profile.buy_module(id)
	_show_modules(-1,"EquipModule_"+id if purchased else "BuyModule_"+id)
	if purchased: notice.text = L10N.text("MODULE ACQUIS — équipez-le sur un emplacement libre.")
	elif profile.last_error!=OK: notice.text = L10N.text("Achat annulé : la sauvegarde n’a pas pu être écrite.")

func _equip_module(id: String) -> void:
	var previously_equipped: bool = id in profile.data.equipped_modules
	var changed: bool = profile.equip_module(id)
	_show_modules(-1,"EquipModule_"+id)
	if changed: notice.text = L10N.text("MODULE RETIRÉ — emplacement libre.") if previously_equipped else L10N.text("MODULE ÉQUIPÉ — statistiques actualisées pour les trois appareils.")
	elif profile.last_error!=OK: notice.text = L10N.text("Modification annulée : la sauvegarde n’a pas pu être écrite.")
	else: notice.text = L10N.text("Retirez d'abord le module de cette famille ou libérez un emplacement.")

func _show_settings(from_pause: bool) -> void:
	settings_from_pause = from_pause
	page = "settings"
	_clear_menu(L10N.text("OPTIONS"),L10N.text("Réglages enregistrés automatiquement. Aucun clignotement stroboscopique n'est nécessaire au gameplay."))
	var labels := [L10N.text("VOLUME GÉNÉRAL"),L10N.text("MUSIQUE"),L10N.text("EFFETS SONORES")]
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
	_label("LANGUE / LANGUAGE",Vector2(94,620),Vector2(420,48),28,GOLD).name = "LanguageTitle"
	for i in range(L10N.SUPPORTED.size()):
		var code: String = L10N.SUPPORTED[i]
		var caption: String = ("✓  " if L10N.locale==code else "")+["Français","English"][i]
		var language := _button(caption,Vector2(530+i*380,615),Vector2(350,54),_set_language.bind(code))
		language.name = "Language_"+code
		language.tooltip_text = L10N.text("Interface, missions et radio. Changement immédiat.")
	var language_hint := _label(L10N.text("Interface, missions et radio. Changement immédiat."),Vector2(1320,614),Vector2(500,58),23,MUTED)
	language_hint.name = "LanguageExplanation"
	_fit_label(language_hint,58,21)
	for i in range(3):
		var key: String = ["fullscreen","shake","flashes"][i]
		var check := CheckButton.new()
		check.text = [L10N.text("Plein écran"),L10N.text("Secousses de l'écran"),L10N.text("Effets lumineux renforcés")][i]
		check.position = Vector2(94+i*550,687)
		check.size = Vector2(520,64)
		check.button_pressed = profile.data.settings[key]
		design.add_child(check)
		check.toggled.connect(func(value): profile.data.settings[key]=value; _apply_settings(); _save())
	for i in range(3):
		_button(("✓  " if profile.data.difficulty == i else "")+L10N.text(PROFILE.DIFFICULTIES[i]),Vector2(94+i*320,802),Vector2(295,58),_difficulty.bind(i),from_pause)
	_label(L10N.text("La difficulté agit sur les projectiles ennemis et la résistance des boss. Modifiable entre les missions."),Vector2(94,885),Vector2(1600,42),24,MUTED)
	_button(L10N.text("RETOUR"),Vector2(94,947),Vector2(280,56),_show_pause if from_pause else _show_main)
	_button(L10N.text("COMMANDES"),Vector2(410,947),Vector2(280,56),_show_bindings)
	_button(L10N.text("GRAPHISMES"),Vector2(726,947),Vector2(280,56),_show_graphics)
	_button(L10N.text("MANETTE"),Vector2(1042,947),Vector2(340,56),_show_gamepad).name = "ControllerSettingsEntry"
	_focus_first()

func _difficulty(index: int) -> void:
	profile.data.difficulty = index
	_save()
	_show_settings(false)

func _show_credits() -> void:
	page = "credits"
	_clear_menu(L10N.text("CRÉDITS & SOURCES"),L10N.text("Campagne originale réalisée avec Godot et Blender. Inspirée des shmups de la série 194X."))
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(94,270)
	scroll.size = Vector2(1710,620)
	design.add_child(scroll)
	var text := RichTextLabel.new()
	text.custom_minimum_size = Vector2(1650,0)
	text.fit_content = true
	text.bbcode_enabled = false
	text.add_theme_font_size_override("normal_font_size",25)
	text.text = L10N.text("PACIFIC STRIKE — CAMPAGNE 1942\n\nConception, programmation et assets originaux : projet Cyril / Codex.\nMoteur Godot (licence MIT), modélisation Blender, illustrations et textures générées avec imagegen.\n\nMUSIQUE ACTIVE\nMenus, vol, combats de boss et victoire : Juhani Junkala / SubspaceAudio — 5 Chiptunes (Action), CC0. Les pistes gardent leur tempo et leurs mélodies d'origine, avec des transitions en fondu.\n\nCOMPOSITIONS HISTORIQUES\nLes anciennes compositions procédurales Pacific Strike et leurs pistes pulse / drive / hero sont conservées dans les sources ; elles ne sont plus diffusées comme musique de combat. Les cinq signatures sonores des événements et le son du laser sont des créations procédurales originales.\n\n1942 et 1942: Joint Strike appartiennent à leurs ayants droit ; ce projet indépendant n'est pas affilié à Capcom.\n\nPOLICES\nBarlow Condensed, Black Ops One et DSEG : licences distribuées dans assets/ui/fonts.\n\n")
	text.name = "CreditsText"
	for file in ["res://assets/audio/engine/CREDITS.md","res://assets/audio/weapons/CREDITS.md","res://assets/campaign/music/CREDITS.txt"]:
		text.text += FileAccess.get_file_as_string(file)+"\n\n"
	scroll.add_child(text)
	_button(L10N.text("RETOUR"),Vector2(94,936),Vector2(280,56),_show_main)
	_focus_first()

func _launch(number: int, mode := "", retry := false) -> void:
	if preparing or quitting: return
	var launch_mode: String = play_mode if mode.is_empty() else mode
	if not _can_launch(number,launch_mode):
		if is_instance_valid(notice): notice.text = L10N.text("Mission indisponible dans ce mode. Choisissez une mission accessible.")
		return
	pending_controller_disconnect = -1
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
		title.text = L10N.text("PRÉPARATION DU VOL")
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
		remove_child(cover)
		cover.queue_free()
		page = "playing"
		preparing = false
	_apply_launch_safety()

func _apply_launch_safety() -> void:
	if pending_controller_disconnect>=0:
		disconnected_joypad = pending_controller_disconnect
		pending_controller_disconnect = -1
		_show_pause("MANETTE DÉCONNECTÉE  •  Vol suspendu. Reconnectez-la ou utilisez le clavier.")
	elif not _resume_window_focused():
		_show_pause()

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
		session_profile.data.power = "spread" if play_mode in ["practice","boss_rush"] else "none"
		if play_mode=="boss_rush":
			session_profile.data.aircraft = boss_rush.aircraft
			session_profile.data.run_score = boss_rush.score
			session_profile.data.run_lives = boss_rush.lives
	director.profile = session_profile
	director.practice = play_mode in ["practice","boss_rush"]
	director.boss_rush = play_mode=="boss_rush"
	director.first_takeoff = true
	director.finished.connect(_queue_run_result.bind(run_generation))
	if is_instance_valid(music):
		music.foreground_gain_changed.connect(cockpit.flight.get_node("Weapons").audio.set_alert_attenuation)
		music.begin_run()
		director.audio_event.connect(_on_audio_event)
	cockpit.flight.add_child(director)
	cockpit.flight.get_node("Weapons").set_power(session_profile.data.power)
	director.weapons.auto_fire = bool(profile.data.settings.get("auto_fire",false))
	var departure = cockpit.flight.get_node("Departure")
	var departure_key := "%s:%d" % [play_mode,number]
	var use_short_intro: bool = retry and play_mode not in ["practice","boss_rush"] and bool(profile.data.settings.get("short_retry_intro",false)) and seen_departures.has(departure_key)
	# Mark only a normal takeoff that actually reached flight. Leaving the menu
	# during its choreography never makes the next attempt skip that discovery.
	if play_mode not in ["practice","boss_rush"] and not use_short_intro:
		departure.flight_started.connect(func(): seen_departures[departure_key]=true,CONNECT_ONE_SHOT)
	if use_short_intro: departure.begin_short_retry()
	var hud := HUD.new()
	hud.name = "CampaignHUD"
	hud.cockpit = cockpit
	hud.director = director
	cockpit.add_child(hud)
	if play_mode in ["practice","boss_rush"]:
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

func _show_pause(message := "") -> void:
	if not is_instance_valid(director): return
	resume_remaining = 0.0
	resume_label = null
	page = "pause"
	get_tree().paused = true
	director.paused = true
	_clear_menu(L10N.text("VOL SUSPENDU"),"MISSION %02d  /  %s" % [selected_mission,director.mission.title])
	_button(L10N.text("REPRENDRE LE VOL"),Vector2(94,315),Vector2(580,70),_resume)
	_button(L10N.text("OPTIONS"),Vector2(94,415),Vector2(580,64),func(): _show_settings(true))
	_button(L10N.text("RECOMMENCER LA TRAVERSÉE") if play_mode=="boss_rush" else L10N.text("RECOMMENCER LA MISSION"),Vector2(94,509),Vector2(580,64),_begin_boss_rush if play_mode=="boss_rush" else _launch.bind(selected_mission,"",true))
	_button(L10N.text("RETOUR À L'ACCUEIL"),Vector2(94,603),Vector2(580,64),_show_main)
	_label(L10N.text("BOSS RUSH  /  DUEL %d SUR 8\n%d vies restantes. Recommencer remet le score à zéro et relance le premier boss.") % [boss_rush.cursor+1,director.combat.remaining_lives] if play_mode=="boss_rush" else L10N.text("La progression est enregistrée entre les missions.\nReprendre depuis l'accueil relance le briefing de la mission."),Vector2(850,325),Vector2(870,150),32,MUTED)
	_label(L10N.text("COMMANDES  /  CLAVIER · MANETTE"),Vector2(850,495),Vector2(870,48),27,GOLD)
	var commands := _label(COMMANDS.flight_guide(),Vector2(850,555),Vector2(870,325),30,MUTED)
	commands.name = "FlightCommands"
	if not message.is_empty(): notice.text = L10N.text(message)
	_focus_first()

func _resume() -> void:
	if page!="pause" or not is_instance_valid(director): return
	if not _resume_window_focused(): return
	if not bool(profile.data.settings.get("resume_countdown",true)):
		_finish_resume()
		return
	page = "resuming"
	resume_remaining = 3.0
	_clear_menu("","",false)
	# A compact card leaves the boss/chain HUD and the player's position visible.
	for child in design.get_children():
		if child!=notice: child.hide()
	shade.color.a = .35
	var card := Panel.new()
	card.name = "ResumeCard"
	card.position = Vector2(640,268)
	card.size = Vector2(640,422)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(.018,.055,.07,.96)
	style.border_color = Color(.88,.76,.51,.65)
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	card.add_theme_stylebox_override("panel",style)
	design.add_child(card)
	var title := _label(L10N.text("PRÊT À REPRENDRE"),Vector2(670,294),Vector2(580,60),38,GOLD,true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var explanation := _label(L10N.text("Le combat reprend à la fin du compte à rebours."),Vector2(678,369),Vector2(564,62),25,MUTED)
	explanation.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	resume_label = _label("3",Vector2(710,426),Vector2(500,150),112,GOLD,true)
	resume_label.name = "ResumeCount"
	resume_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	resume_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_button(L10N.text("RESTER EN PAUSE"),Vector2(700,608),Vector2(520,62),_show_pause)
	notice.text = L10N.text("ÉCHAP / START / B  •  RESTER EN PAUSE")
	_focus_first()

func _advance_resume(delta: float) -> void:
	if page!="resuming" or not is_instance_valid(director): return
	resume_remaining = maxf(0.0,resume_remaining-maxf(0.0,delta))
	if is_zero_approx(resume_remaining):
		_finish_resume()
	elif is_instance_valid(resume_label):
		resume_label.text = str(ceili(resume_remaining))

func _finish_resume() -> void:
	if page not in ["pause","resuming"] or not is_instance_valid(director): return
	if not _resume_window_focused():
		_show_pause()
		return
	resume_remaining = 0.0
	resume_label = null
	disconnected_joypad = -1
	get_tree().paused = false
	director.paused = false
	page = "playing"
	menu.hide()
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN

func _resume_window_focused() -> bool:
	return testing or DisplayServer.get_name()=="headless" or DisplayServer.window_is_focused()

func _track_input_device(event: InputEvent) -> void:
	var joy_activity := false
	if event is InputEventJoypadButton and event.pressed:
		active_joypad = event.device
		joy_activity = true
	elif event is InputEventJoypadMotion and absf(event.axis_value)>.35:
		if event.axis in [JOY_AXIS_TRIGGER_LEFT,JOY_AXIS_TRIGGER_RIGHT] and event.axis_value<0: return
		active_joypad = event.device
		joy_activity = true
	elif event is InputEventKey and event.pressed and not event.echo:
		active_joypad = -1
	if joy_activity and page!="gamepad" and active_joypad>=0 and active_joypad!=controller_device and active_joypad in Input.get_connected_joypads():
		_select_controller(active_joypad)
		# This event was parsed against the previous device's map. Preserve its
		# first press after switching instead of requiring a second button press.
		for action in GAMEPAD.ACTIONS:
			if event.is_action_pressed(action): Input.action_press(action,event.get_action_strength(action))

func _on_joy_connection_changed(device: int, connected: bool) -> void:
	# Apply the saved model profile before redrawing a hot-plugged controller.
	if connected and (controller_device<0 or controller_device==device):
		_select_controller(device)
	elif not connected and controller_device==device:
		var remaining := Input.get_connected_joypads()
		remaining.erase(device)
		_select_controller(remaining[0] if not remaining.is_empty() else -1)
	if is_instance_valid(controller_menu): controller_menu.connection_changed(device,connected)
	if is_instance_valid(menu_gamepad_navigation): menu_gamepad_navigation.reset()
	if connected:
		if pending_controller_disconnect>=0:
			pending_controller_disconnect = -1
			active_joypad = device
		if disconnected_joypad>=0 and page=="pause" and is_instance_valid(notice):
			notice.text = L10N.text("MANETTE RECONNECTÉE  •  Reprenez le vol quand vous êtes prêt.")
			disconnected_joypad = -1
			active_joypad = device
		return
	if device!=active_joypad: return
	active_joypad = -1
	if page=="loading" and bool(profile.data.settings.get("pause_on_disconnect",true)):
		pending_controller_disconnect = device
		return
	if page in ["playing","resuming"] and bool(profile.data.settings.get("pause_on_disconnect",true)):
		disconnected_joypad = device
		_show_pause("MANETTE DÉCONNECTÉE  •  Vol suspendu. Reconnectez-la ou utilisez le clavier.")

func _queue_run_result(report: Dictionary, generation: int) -> void:
	_accept_run_result.call_deferred(report,generation)

func _accept_run_result(report: Dictionary, generation: int) -> void:
	# A queued report belongs to the flight that emitted it, even after restart.
	if generation!=run_generation: return
	_show_result(report)

func _show_result(report: Dictionary) -> void:
	if not is_instance_valid(director): return
	# A result screen may be redrawn, but a flight is recorded only once.
	if result_generation==run_generation: return
	if play_mode=="boss_rush" and not boss_rush.accept(report): return
	result_generation = run_generation
	result_previous_best = 0
	if play_mode=="campaign": result_previous_best=int(profile.data.records.get(str(selected_mission),{}).get("score",0))
	elif play_mode=="arcade": result_previous_best=int(profile.data.arcade_records.get("%d:%d" % [selected_mission,profile.data.aircraft],0))
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
	elif play_mode=="boss_rush" and boss_rush.complete():
		var key: String = boss_rush.record_key()
		profile.data.arcade_records[key] = maxi(int(profile.data.arcade_records.get(key,0)),boss_rush.score)
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
	if play_mode=="boss_rush":
		_draw_rush_result(report)
		return
	page = "result"
	var victory: bool = report.won and selected_mission == 32 and play_mode=="campaign"
	# Explicit terminal cause takes precedence over an old cached objective flag.
	# Zero lives also keeps historical reports without game_over unambiguous.
	var game_over: bool = not report.won and (bool(report.get("game_over",false)) or int(report.get("lives",1))<=0)
	var objective_failed: bool = not game_over and bool(report.get("objective_failed",false))
	_clear_menu(L10N.text("LE PACIFIQUE EST LIBRE") if victory else (L10N.text("MISSION ACCOMPLIE") if report.won else (L10N.text("MISSION INACCOMPLIE") if objective_failed else "GAME OVER")),"%02d / 32  •  %s" % [selected_mission,director.mission.title])
	_label(["—",L10N.text("BRONZE"),L10N.text("ARGENT"),L10N.text("OR")][int(report.grade)] if report.won else (L10N.text("OBJECTIF NON ATTEINT") if objective_failed else L10N.text("AUCUNE VIE RESTANTE")),Vector2(94,298),Vector2(1050,100),62 if objective_failed else 70,GOLD,true)
	_label(L10N.text("SCORE TOTAL    %08d\nCETTE MISSION    +%d\nAIR / MER / SOL    %d / %d / %d\nVIES PERDUES    %d\nFRÔLEMENTS    %d  /  +%d POINTS\nBONUS DE FIN    %d  •  PIÈCES    +%d") % [report.score,report.get("mission_score",report.score),report.kills-report.naval_kills-int(report.get("ground_kills",0)),report.naval_kills,report.get("ground_kills",0),report.deaths,report.get("grazes",0),report.get("graze_score",0),report.bonus,result_earned],Vector2(94,438),Vector2(1040,300),35,Color("d4dfe1")).name = "ResultScoreDetails"
	var summary := L10N.text("32 missions. Huit secteurs. Une route jusqu'à l'aube.\n\nLa campagne est terminée. Les missions restent disponibles pour obtenir toutes les médailles d'or.") if victory else (L10N.text("La mission suivante est disponible.\nProfitez du hangar pour préparer votre appareil.") if report.won else L10N.text("Votre meilleur score est conservé.\n\nRéessayer reprend le début de cette mission avec le score et les vies du dernier point de sauvegarde."))
	if play_mode!="campaign": summary = (L10N.text("Le record Arcade est mis à jour si ce score est supérieur.") if play_mode=="arcade" else L10N.text("Entraînement terminé. Aucun record ni récompense de campagne."))+L10N.text("\n\nRejouer conserve ce mode et son équipement fixe. Le hangar vous ramène à la campagne sauvegardée.")
	var summary_y := 336.0
	var summary_height := 320.0
	var ground_status: Dictionary = report.get("ground_status",{})
	if not ground_status.is_empty():
		var ground_text := L10N.text("CIBLES DÉTRUITES  %d / %d") % [int(ground_status.get("kills",0)),int(ground_status.get("quota",0))]
		var priority_total := int(ground_status.get("priority_total",0))
		if priority_total>0:
			ground_text += L10N.text("\nPRIORITÉS  %d / %d") % [int(ground_status.get("priority_destroyed",0)),priority_total]
			var escaped: Array = ground_status.get("escaped_priority_ids",[])
			if not escaped.is_empty(): ground_text += L10N.text("  •  %d ÉCHAPPÉE(S)") % escaped.size()
		var ground_label := _label(ground_text,Vector2(1210,336),Vector2(590,92),27,GOLD if bool(ground_status.get("main_met",false)) else Color("ff986c"))
		ground_label.name = "ResultGroundObjective"
		_fit_label(ground_label,92,21)
		summary_y = 448.0
		summary_height = 208.0
	var summary_label := _label(summary,Vector2(1210,summary_y),Vector2(590,summary_height),30,MUTED)
	summary_label.name = "ResultSummary"
	_fit_label(summary_label,summary_height,21)
	if report.won and selected_mission < 32 and play_mode=="campaign":
		_button(L10N.text("MISSION SUIVANTE"),Vector2(94,842),Vector2(440,66),_briefing_after_result.bind(selected_mission+1))
	else: _button(L10N.text("REJOUER LA MISSION") if report.won else L10N.text("RÉESSAYER LA MISSION"),Vector2(94,842),Vector2(440,66),_launch.bind(selected_mission,"",true))
	_button(L10N.text("HANGAR"),Vector2(559,842),Vector2(320,66),_hangar_after_result)
	_button(L10N.text("ACCUEIL"),Vector2(904,842),Vector2(320,66),_show_main)
	_button(L10N.text("MÉDAILLE & RANG  /  DÉTAILS"),Vector2(1249,842),Vector2(551,66),_show_criteria).name = "ResultCriteria"
	_button(L10N.text("ANALYSE DU VOL"),Vector2(1249,931),Vector2(551,55),_show_debrief).name="FlightAnalysisEntry"
	if victory: _button(L10N.text("CRÉDITS"),Vector2(94,931),Vector2(320,55),_credits_after_result)
	if play_mode!="campaign": _label("MODE "+_mode_label()+L10N.text("  /  CAMPAGNE INCHANGÉE"),Vector2(1210,665),Vector2(590,70),26,GOLD)
	_label(L10N.text("RANG %s   •   CHAÎNE MAX %d   •   PRÉCISION %d %%\nOBJECTIF SECONDAIRE : %s") % [report.get("rank","C"),report.get("best_chain",0),int(float(report.get("accuracy",0))*100),L10N.text("ACCOMPLI") if report.get("secondary",false) else L10N.text("NON ACCOMPLI")],Vector2(94,744),Vector2(1620,85),27,GOLD)
	_focus_first()

func _show_debrief() -> void:
	if not is_instance_valid(director) or result.is_empty(): return
	page="debrief"
	_clear_menu(L10N.text("ANALYSE DU VOL"),"%02d  /  %s  •  %s" % [selected_mission,director.mission.title,_mode_label()])
	preload("res://scripts/campaign/debrief_view.gd").new().build(self,result,result_previous_best)

func _draw_rush_result(report: Dictionary) -> void:
	page = "result"
	var complete: bool = boss_rush.complete()
	var continuing: bool = boss_rush.active and boss_rush.last_won
	_clear_menu(L10N.text("TRAVERSÉE ACCOMPLIE") if complete else (L10N.text("BOSS NEUTRALISÉ") if continuing else L10N.text("FIN DE LA TRAVERSÉE")),L10N.text("BOSS RUSH  /  %d ADVERSAIRES VAINCUS SUR 8  /  %s") % [boss_rush.cleared,PROFILE.AIRCRAFT[boss_rush.aircraft]])
	_label("%02d / 08" % boss_rush.cleared,Vector2(94,295),Vector2(920,160),108,GOLD,true)
	_label(L10N.text("SCORE TOTAL  %08d\nVIES RESTANTES  %d\nTEMPS DE COMBAT  %02d:%02d\nFRÔLEMENTS  %d") % [boss_rush.score,boss_rush.lives,int(boss_rush.seconds)/60,int(boss_rush.seconds)%60,boss_rush.grazes],Vector2(94,497),Vector2(950,262),39,Color("e1e8e5")).name = "RushScoreDetails"
	var summary := L10N.text("Les huit chefs de secteur sont tombés.\nVotre record de traversée a été enregistré pour cet appareil.")
	if continuing:
		var next_mission: Dictionary = missions[boss_rush.ROUTE[boss_rush.cursor+1]-1]
		summary = L10N.text("PROCHAINE CIBLE\n%s\n\nLe blindage et les bombes sont restaurés. Vos %d vies et vos %d points restent en jeu.") % [preload("res://scripts/campaign/boss.gd").display_name(next_mission.boss),boss_rush.lives,boss_rush.score]
	elif not complete: summary = L10N.text("La traversée s'arrête ici.\nEntraînez-vous contre les boss pour apprendre leurs motifs, puis tentez une nouvelle route.\n\nUn record exige de vaincre les huit adversaires.")
	_label(summary,Vector2(1120,340),Vector2(680,380),32,MUTED).name = "RushSummary"
	_label(L10N.text("RECORD DE CET APPAREIL  %08d") % int(profile.data.arcade_records.get(boss_rush.record_key(),0)),Vector2(94,785),Vector2(1040,53),30,GOLD)
	_button(L10N.text("ANALYSE DU VOL"),Vector2(1194,794),Vector2(606,55),_show_debrief).name="FlightAnalysisEntry"
	_button(L10N.text("AFFRONTER LE BOSS SUIVANT") if continuing else L10N.text("RETENTER LA TRAVERSÉE"),Vector2(94,902),Vector2(650,72),_next_boss_rush if continuing else _begin_boss_rush).name = "RushContinue"
	_button(L10N.text("ACCUEIL"),Vector2(774,902),Vector2(390,72),_show_main)
	_button(L10N.text("ENTRAÎNEMENT AUX BOSS"),Vector2(1194,902),Vector2(606,72),func(): _dispose_run(); _show_challenges("practice"))
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
	run_generation += 1
	resume_remaining = 0.0
	resume_label = null
	disconnected_joypad = -1
	if not preparing: pending_controller_disconnect = -1
	get_tree().paused = false
	if is_instance_valid(cockpit):
		cockpit._stop_audio(cockpit)
		cockpit.hide()
		cockpit.process_mode = Node.PROCESS_MODE_DISABLED
		cockpit.queue_free()
	cockpit = null
	director = null

func _input(event: InputEvent) -> void:
	if is_instance_valid(controller_menu) and controller_menu.handle_input(event):
		if is_instance_valid(menu_gamepad_navigation): menu_gamepad_navigation.reset()
		get_viewport().set_input_as_handled()
		return
	if is_instance_valid(menu_gamepad_navigation): menu_gamepad_navigation.handle_input(event)
	_track_input_device(event)
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
			notice.text = L10N.text("Cette touche est réservée à la navigation. Choisissez une autre touche.")
			return
		for action in BIND_NAMES:
			if action==waiting_binding: continue
			for bound in InputMap.action_get_events(action):
				if bound is InputEventKey and bound.keycode==event.keycode:
					notice.text = L10N.text("Touche déjà utilisée : ")+L10N.text(BIND_NAMES[action])
					return
		profile.data.bindings[waiting_binding] = event.keycode
		waiting_binding = ""
		_apply_bindings()
		_save()
		_show_bindings()
		return
	# B is a menu back button only; its flight binding remains the bomb.
	var pad_back: bool = event is InputEventJoypadButton and event.pressed and event.button_index==JOY_BUTTON_B and page!="playing"
	# Flight pause is configurable; menu Back remains Escape/B/Start so that
	# mapping a flight action to A or a direction cannot hijack menu navigation.
	var back: bool = event.is_action_pressed("quit_game") if page=="playing" else ((event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE) or (event is InputEventJoypadButton and event.pressed and event.button_index==JOY_BUTTON_START))
	if page=="playing" and event is InputEventJoypadMotion:
		back = back and Input.is_action_just_pressed("quit_game")
	if (back or pad_back) and not event.is_echo():
		get_viewport().set_input_as_handled()
		if pad_back and page=="main": return
		if waiting_binding!="":
			waiting_binding = ""
			_show_bindings()
			return
		match page:
			"playing": _show_pause()
			"pause": _resume()
			"resuming": _show_pause()
			"bindings", "graphics": _show_settings(settings_from_pause)
			"gamepad": _show_bindings()
			"flight_comfort": _show_graphics()
			"modules", "aircraft_gallery": _show_hangar()
			"rules": _return_from_rules()
			"criteria", "debrief": _draw_result(result)
			"settings":
				if settings_from_pause: _show_pause()
				else: _show_main()
			"result": _show_main()
			"main": _quit()
			_: _show_main()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_instance_valid(menu_gamepad_navigation): menu_gamepad_navigation.reset()
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and page in ["playing","resuming"] and not testing: _show_pause()
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


func _process(delta: float) -> void:
	if is_instance_valid(controller_menu): controller_menu.update(delta)
	if is_instance_valid(menu_gamepad_navigation):
		menu_gamepad_navigation.blocked = page=="gamepad" and (not controller_menu.waiting.is_empty() or controller_menu.testing_inputs)
		menu_gamepad_navigation.update(delta)
	_advance_resume(delta)
	if page == "playing" and is_instance_valid(director) and is_instance_valid(music):
		music.update_combat(director)
		music.set_mode("victory" if director.ending else ("boss" if is_instance_valid(director.boss) and director.boss.alive else ("flight" if int(director.mission.sector)%2==0 else "flight2")))

func _confirm_new_campaign() -> void:
	page = "new_campaign"
	_clear_menu(L10N.text("NOUVELLE CAMPAGNE"),L10N.text("Le record et les options seront conservés."))
	_label(L10N.text("Repartir de la mission 01 ?"),Vector2(94,320),Vector2(1400,100),48,GOLD,true)
	_label(L10N.text("Les médailles, les missions débloquées et les améliorations de cette campagne seront réinitialisées."),Vector2(94,465),Vector2(1300,150),34,MUTED)
	_button(L10N.text("CONSERVER MA CAMPAGNE"),Vector2(94,735),Vector2(520,64),_show_main)
	_button(L10N.text("RECOMMENCER"),Vector2(650,735),Vector2(400,64),_new_campaign)
	_focus_first()

func _new_campaign() -> void:
	var options: Dictionary = profile.data.settings.duplicate()
	var record: int = profile.data.high_score
	var bindings: Dictionary = profile.data.bindings.duplicate()
	var gamepad_profiles: Dictionary = profile.data.get("gamepad_profiles",{}).duplicate(true)
	var arcade: Dictionary = profile.data.arcade_records.duplicate()
	profile.reset()
	profile.data.bindings = bindings
	profile.data.gamepad_profiles = gamepad_profiles
	profile.data.arcade_records = arcade
	profile.data.settings = options
	profile.data.high_score = record
	selected_mission = 1
	_save()
	_show_briefing(1)
