extends RefCounted
## Shared display names for the actual flight bindings; menu navigation is separate.
const KEY_LABELS := {KEY_SPACE:"Espace",KEY_SHIFT:"Maj",KEY_ESCAPE:"Échap",KEY_ENTER:"Entrée",KEY_KP_ENTER:"Entrée pavé",KEY_LEFT:"←",KEY_RIGHT:"→",KEY_UP:"↑",KEY_DOWN:"↓",KEY_CTRL:"Ctrl",KEY_ALT:"Alt",KEY_CAPSLOCK:"Verr. maj.",KEY_BACKSPACE:"Retour arrière",KEY_PAGEUP:"Page préc.",KEY_PAGEDOWN:"Page suiv.",KEY_PRINT:"Impr. écran"}
const PAD_LABELS := {JOY_BUTTON_A:"A",JOY_BUTTON_B:"B",JOY_BUTTON_X:"X",JOY_BUTTON_Y:"Y",JOY_BUTTON_LEFT_SHOULDER:"LB",JOY_BUTTON_RIGHT_SHOULDER:"RB",JOY_BUTTON_START:"Start",JOY_BUTTON_BACK:"Select",JOY_BUTTON_DPAD_LEFT:"← croix",JOY_BUTTON_DPAD_RIGHT:"→ croix",JOY_BUTTON_DPAD_UP:"↑ croix",JOY_BUTTON_DPAD_DOWN:"↓ croix"}

static func keys(action: String) -> Array[String]:
	var labels: Array[String] = []
	for event in InputMap.action_get_events(action):
		if event is not InputEventKey: continue
		var code: int = event.keycode if event.keycode!=0 else event.physical_keycode
		var label: String = KEY_LABELS.get(code,OS.get_keycode_string(code))
		if not labels.has(label): labels.append(label)
	return labels

static func keyboard(action: String) -> String:
	var labels := keys(action)
	return labels[0] if not labels.is_empty() else "—"

static func gamepad(action: String) -> String:
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadButton: return PAD_LABELS.get(event.button_index,"Bouton %d" % (event.button_index+1))
	return "—"

static func hint(action: String) -> String:
	return keyboard(action)+" / "+gamepad(action)

static func movement() -> String:
	var left := keys("move_left")
	var right := keys("move_right")
	var up := keys("move_up")
	var down := keys("move_down")
	var alternatives: Array[String] = []
	if left.has("←") and right.has("→") and up.has("↑") and down.has("↓"): alternatives.append("Flèches")
	if left.has("Q") and right.has("D") and up.has("Z") and down.has("S"): alternatives.append("ZQSD")
	if left.has("A") and right.has("D") and up.has("W") and down.has("S"): alternatives.append("WASD")
	if not alternatives.is_empty(): return " / ".join(alternatives)
	return "G/D/H/B : %s / %s / %s / %s" % [",".join(left),",".join(right),",".join(up),",".join(down)]

static func pad_movement() -> String:
	for event in InputMap.action_get_events("move_left"):
		if event is InputEventJoypadMotion: return "Stick / croix"
	return "Croix directionnelle"

static func flight_guide() -> String:
	return "PILOTER  %s   ·   %s\nTIR  %s   |   BOMBE  %s\nFRAPPE  %s   |   PRÉCISION  %s\nPAUSE  %s" % [movement(),pad_movement(),hint("fire"),hint("bomb"),hint("strike"),hint("focus_flight"),hint("quit_game")]
