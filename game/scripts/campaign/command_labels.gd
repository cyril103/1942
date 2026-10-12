extends RefCounted
const L10N := preload("res://scripts/campaign/localization.gd")
const GAMEPAD := preload("res://scripts/campaign/gamepad_bindings.gd")
static var active_device: int = -1
## Shared display names for the actual flight bindings; menu navigation is separate.
const KEY_LABELS := {KEY_SPACE:"Espace",KEY_SHIFT:"Maj",KEY_ESCAPE:"Échap",KEY_ENTER:"Entrée",KEY_KP_ENTER:"Entrée pavé",KEY_LEFT:"←",KEY_RIGHT:"→",KEY_UP:"↑",KEY_DOWN:"↓",KEY_CTRL:"Ctrl",KEY_ALT:"Alt",KEY_CAPSLOCK:"Verr. maj.",KEY_BACKSPACE:"Retour arrière",KEY_PAGEUP:"Page préc.",KEY_PAGEDOWN:"Page suiv.",KEY_PRINT:"Impr. écran"}
const PAD_LABELS := {JOY_BUTTON_A:"A",JOY_BUTTON_B:"B",JOY_BUTTON_X:"X",JOY_BUTTON_Y:"Y",JOY_BUTTON_LEFT_SHOULDER:"LB",JOY_BUTTON_RIGHT_SHOULDER:"RB",JOY_BUTTON_START:"Start",JOY_BUTTON_BACK:"Select",JOY_BUTTON_DPAD_LEFT:"← croix",JOY_BUTTON_DPAD_RIGHT:"→ croix",JOY_BUTTON_DPAD_UP:"↑ croix",JOY_BUTTON_DPAD_DOWN:"↓ croix"}

static func keys(action: String) -> Array[String]:
	var labels: Array[String] = []
	for event in InputMap.action_get_events(action):
		if event is not InputEventKey: continue
		var code: int = event.keycode if event.keycode!=0 else event.physical_keycode
		var label: String = L10N.text(KEY_LABELS.get(code,OS.get_keycode_string(code)))
		if not labels.has(label): labels.append(label)
	return labels

static func keyboard(action: String) -> String:
	var labels := keys(action)
	return labels[0] if not labels.is_empty() else "—"

static func gamepad(action: String) -> String:
	var labels: Array[String] = []
	for event in InputMap.action_get_events(action):
		if event.device != -1 and active_device != -1 and event.device != active_device: continue
		if event is InputEventJoypadButton:
			labels.append(GAMEPAD.binding_label({"kind":"button","index":event.button_index},active_device))
		elif event is InputEventJoypadMotion:
			labels.append(GAMEPAD.binding_label({"kind":"axis","index":event.axis,"direction":-1 if event.axis_value<0 else 1},active_device))
	return " / ".join(labels) if not labels.is_empty() else "—"

static func hint(action: String) -> String:
	return keyboard(action)+" / "+gamepad(action)

static func movement() -> String:
	var left := keys("move_left")
	var right := keys("move_right")
	var up := keys("move_up")
	var down := keys("move_down")
	var alternatives: Array[String] = []
	if left.has("←") and right.has("→") and up.has("↑") and down.has("↓"): alternatives.append(L10N.text("Flèches"))
	if left.has("Q") and right.has("D") and up.has("Z") and down.has("S"): alternatives.append("ZQSD")
	if left.has("A") and right.has("D") and up.has("W") and down.has("S"): alternatives.append("WASD")
	if not alternatives.is_empty(): return " / ".join(alternatives)
	return L10N.text("G/D/H/B : %s / %s / %s / %s") % [",".join(left),",".join(right),",".join(up),",".join(down)]

static func pad_movement() -> String:
	var standard := GAMEPAD.defaults()
	var is_standard := true
	for action in ["move_left","move_right","move_up","move_down"]:
		var actual: Array[Dictionary] = []
		for event in InputMap.action_get_events(action):
			if event.device != -1 and active_device != -1 and event.device != active_device: continue
			if event is InputEventJoypadButton: actual.append({"kind":"button","index":event.button_index})
			elif event is InputEventJoypadMotion: actual.append({"kind":"axis","index":event.axis,"direction":-1 if event.axis_value<0 else 1})
		if actual.size()!=standard[action].size(): is_standard = false
		for binding in standard[action]:
			if binding not in actual: is_standard = false
	if is_standard: return L10N.text("Stick / croix")
	return L10N.text("G/D/H/B : %s / %s / %s / %s") % [gamepad("move_left"),gamepad("move_right"),gamepad("move_up"),gamepad("move_down")]

static func flight_guide() -> String:
	return L10N.text("PILOTER  %s   ·   %s\nTIR  %s   |   BOMBE  %s\nFRAPPE  %s   |   PRÉCISION  %s\nPAUSE  %s") % [movement(),pad_movement(),hint("fire"),hint("bomb"),hint("strike"),hint("focus_flight"),hint("quit_game")]
