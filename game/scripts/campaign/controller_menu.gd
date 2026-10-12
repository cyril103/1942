extends RefCounted
## Controller setup owns capture before the normal menu/flight input path.
const PAD := preload("res://scripts/campaign/gamepad_bindings.gd")
const L10N := preload("res://scripts/campaign/localization.gd")
const ACTIONS := {"move_left":"Gauche","move_right":"Droite","move_up":"Monter","move_down":"Descendre","fire":"Tirer","bomb":"Bombe","strike":"Capacité de l'avion","focus_flight":"Vol de précision","quit_game":"Pause"}
var app: Control
var waiting := ""
var seconds_left := 0.0
var neutral_required: Dictionary = {}
var suppressed: Dictionary = {}
var testing_inputs := false
var last_input := "—"
var status: Label
var live: Label
var deadzone_label: Label
var deadzone_slider: HSlider
var cancel_button: Button
var capture_device := -1

func _init(owner: Control) -> void:
	app = owner

func show(focus_action := "") -> void:
	waiting = ""
	testing_inputs = false
	app.page = "gamepad"
	app._clear_menu(L10N.text("COMMANDES MANETTE"),L10N.text("Votre manette, vos commandes. Les réglages sont enregistrés automatiquement pour ce modèle."))
	var device: int = app.controller_device
	var connected := Input.get_connected_joypads()
	var title := PAD.device_name(device) if device in connected else L10N.text("Aucune manette connectée")
	var title_label: Label = app._label(title,Vector2(94,255),Vector2(1290,54),36,app.GOLD)
	title_label.name = "ControllerName"
	app._fit_label(title_label,54,24)
	app._button(L10N.text("CHANGER DE MANETTE"),Vector2(1410,253),Vector2(415,58),_cycle_device,connected.size()<2).name = "ControllerSelect"
	var description := L10N.text("Branchez une manette pour la configurer. Le clavier et la souris restent disponibles.")
	if device in connected:
		description = L10N.text("Reconnue par le jeu") if Input.is_joy_known(device) else L10N.text("Manette générique : affectez les boutons selon votre préférence.")
	app._label(description,Vector2(94,326),Vector2(1700,48),26,app.MUTED).name = "ControllerStatus"
	var index := 0
	for action in ACTIONS:
		var text := L10N.text(ACTIONS[action])+"  :  "+PAD.describe_bindings(app.profile.data,device,action)
		var button: Button = app._button(text,Vector2(94+(index%2)*580,400+(index/2)*78),Vector2(552,64),begin_capture.bind(action),device not in connected)
		button.name = "PadBind_"+action
		button.add_theme_font_size_override("font_size",25)
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.tooltip_text = text
		index += 1
	app._label(L10N.text("TEST EN DIRECT"),Vector2(1310,403),Vector2(500,44),30,app.GOLD)
	live = app._label("",Vector2(1310,469),Vector2(500,225),26,app.MUTED)
	live.name = "ControllerLiveInput"
	app._label(L10N.text("Testez sticks, croix, boutons et gâchettes sans quitter cet écran."),Vector2(1310,702),Vector2(500,88),25,app.MUTED)
	app._button(L10N.text("TESTER LES ENTRÉES"),Vector2(1310,807),Vector2(515,60),begin_test,device not in connected).name = "ControllerTest"
	deadzone_label = app._label("",Vector2(94,810),Vector2(550,44),27,app.GOLD)
	deadzone_slider = HSlider.new()
	deadzone_slider.name = "ControllerDeadzone"
	deadzone_slider.position = Vector2(674,812)
	deadzone_slider.size = Vector2(552,42)
	deadzone_slider.min_value = 10
	deadzone_slider.max_value = PAD.MAX_DEADZONE*100.0
	deadzone_slider.step = 1
	deadzone_slider.value = PAD.deadzone_for(app.profile.data,device)*100.0
	deadzone_slider.editable = device in connected
	app.design.add_child(deadzone_slider)
	deadzone_slider.value_changed.connect(func(value):
		PAD.set_deadzone(app.profile.data,app.controller_device,value/100.0)
		PAD.apply(app.profile.data,app.controller_device)
		_update_deadzone_label()
		app._save())
	_update_deadzone_label()
	app._label(L10N.text("Augmentez la zone morte si l'avion bouge quand le stick est au repos."),Vector2(94,867),Vector2(1132,45),23,app.MUTED)
	app._button(L10N.text("RETOUR"),Vector2(94,938),Vector2(300,60),app._show_bindings).name = "ControllerBack"
	app._button(L10N.text("RÉTABLIR LA MANETTE"),Vector2(420,938),Vector2(530,60),_restore,device not in connected).name = "ControllerReset"
	cancel_button = app._button(L10N.text("ANNULER"),Vector2(975,938),Vector2(350,60),cancel)
	cancel_button.name = "ControllerCancel"
	cancel_button.hide()
	status = app.notice
	status.text = L10N.text("%s / ENTRÉE : CHOISIR  •  %s / ÉCHAP : RETOUR  •  Choisissez une action pour la modifier.") % [app._pad_label(JOY_BUTTON_A),app._pad_label(JOY_BUTTON_B)]
	update(0.0)
	if not focus_action.is_empty():
		var focused := app.design.get_node_or_null("PadBind_"+focus_action) as Button
		if is_instance_valid(focused) and not focused.disabled:
			focused.grab_focus()
			return
	app._focus_first()

func _update_deadzone_label() -> void:
	deadzone_label.text = L10N.text("ZONE MORTE DES STICKS  %d %%") % roundi(deadzone_slider.value)

func _cycle_device() -> void:
	var devices := Input.get_connected_joypads()
	if devices.is_empty(): return
	app._select_controller(devices[(devices.find(app.controller_device)+1)%devices.size()])
	show()

func _restore() -> void:
	PAD.reset(app.profile.data,app.controller_device)
	PAD.apply(app.profile.data,app.controller_device)
	show()
	status.text = L10N.text("Commandes et zone morte de cette manette rétablies.")
	app._save()

func _lock_controls() -> void:
	for button in app.buttons: button.disabled = button!=cancel_button
	deadzone_slider.editable = false
	cancel_button.show()
	cancel_button.grab_focus()

func begin_capture(action: String) -> void:
	if not ACTIONS.has(action): return
	waiting = action
	testing_inputs = false
	capture_device = app.controller_device
	seconds_left = 12.0
	neutral_required.clear()
	# Ignore the held button/axis used to enter capture until it is released.
	for index in range(JOY_BUTTON_MAX):
		if Input.is_joy_button_pressed(capture_device,index): neutral_required["b"+str(index)] = true
	for index in range(JOY_AXIS_MAX):
		var value := Input.get_joy_axis(capture_device,index)
		if (value>.4 if index in [JOY_AXIS_TRIGGER_LEFT,JOY_AXIS_TRIGGER_RIGHT] else absf(value)>.4): neutral_required["a"+str(index)] = true
	_lock_controls()
	_update_capture_notice()

func begin_test() -> void:
	testing_inputs = true
	waiting = ""
	_lock_controls()
	status.text = L10N.text("TEST ACTIF  •  Bougez les sticks et appuyez sur les boutons. %s / Échap : terminer.") % app._pad_label(JOY_BUTTON_B)

func cancel() -> void:
	var action := waiting
	waiting = ""
	testing_inputs = false
	show(action)

func _event_id(event: InputEvent) -> String:
	if event is InputEventJoypadButton: return "b"+str(event.button_index)
	if event is InputEventJoypadMotion: return "a"+str(event.axis)
	return ""

func _released(event: InputEvent) -> bool:
	if event is InputEventJoypadMotion and event.axis in [JOY_AXIS_TRIGGER_LEFT,JOY_AXIS_TRIGGER_RIGHT]: return event.axis_value<.3
	return (event is InputEventJoypadButton and not event.pressed) or (event is InputEventJoypadMotion and absf(event.axis_value)<.3)

func handle_input(event: InputEvent) -> bool:
	var id := _event_id(event)
	var token := str(event.device)+":"+id
	if not id.is_empty() and suppressed.has(token):
		if _released(event): suppressed.erase(token)
		return true
	if app.page!="gamepad": return false
	if not id.is_empty() and event.device==app.controller_device:
		var binding := PAD.event_binding(event)
		if not binding.is_empty(): last_input = PAD.binding_label(binding,app.controller_device)
	if waiting.is_empty() and not testing_inputs: return false
	if event is InputEventKey:
		if event.pressed and event.keycode==KEY_ESCAPE: cancel()
		return true
	# Mouse remains available for the visible cancel button.
	if id.is_empty(): return false
	if testing_inputs:
		if event is InputEventJoypadButton and event.pressed and event.button_index==JOY_BUTTON_B:
			suppressed[token] = true
			cancel()
		return true
	if event.device!=capture_device: return true
	if neutral_required.has(id):
		if _released(event): neutral_required.erase(id)
		return true
	if not neutral_required.is_empty(): return true
	var binding := PAD.event_binding(event)
	if binding.is_empty(): return true
	var action := waiting
	var exchanged := PAD.assign(app.profile.data,capture_device,action,binding)
	suppressed[token] = true
	PAD.apply(app.profile.data,capture_device)
	show(action)
	status.text = L10N.text("Commande enregistrée : %s") % L10N.text(ACTIONS[action])
	if not exchanged.is_empty():
		var labels: Array[String] = []
		for other in exchanged: labels.append(L10N.text(ACTIONS.get(other,other)))
		status.text += "  •  "+L10N.text("Affectations échangées avec : %s") % ", ".join(labels)
	app._save()
	return true

func _update_capture_notice() -> void:
	status.text = L10N.text("%s : appuyez sur un bouton ou une gâchette, ou inclinez un stick. Échap / Annuler (%d s).") % [L10N.text(ACTIONS[waiting]),ceili(seconds_left)]
	if not neutral_required.is_empty(): status.text = L10N.text("Relâchez les commandes maintenues, puis choisissez la nouvelle commande.")

func connection_changed(device: int, connected: bool) -> void:
	if not connected:
		for token in suppressed.keys():
			if str(token).begins_with(str(device)+":"): suppressed.erase(token)
	if app.page!="gamepad": return
	show()

func update(delta: float) -> void:
	if app.page!="gamepad" or not is_instance_valid(live): return
	if not waiting.is_empty():
		seconds_left -= delta
		if seconds_left<=0:
			cancel()
			status.text = L10N.text("Affectation annulée. Aucune commande modifiée.")
		else: _update_capture_notice()
	var device: int = app.controller_device
	if device not in Input.get_connected_joypads():
		live.text = L10N.text("En attente de connexion…")
		return
	live.text = L10N.text("Dernière entrée : %s\n\nStick gauche  X %+.2f  Y %+.2f\nStick droit     X %+.2f  Y %+.2f\nGâchettes      G %3d %%  D %3d %%") % [last_input,Input.get_joy_axis(device,JOY_AXIS_LEFT_X),Input.get_joy_axis(device,JOY_AXIS_LEFT_Y),Input.get_joy_axis(device,JOY_AXIS_RIGHT_X),Input.get_joy_axis(device,JOY_AXIS_RIGHT_Y),roundi(Input.get_joy_axis(device,JOY_AXIS_TRIGGER_LEFT)*100),roundi(Input.get_joy_axis(device,JOY_AXIS_TRIGGER_RIGHT)*100)]
