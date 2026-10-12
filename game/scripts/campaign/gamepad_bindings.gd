extends RefCounted
## Persist only plain values; device indices belong to the current session, not saves.
const L10N := preload("res://scripts/campaign/localization.gd")
const ACTIONS := ["move_left","move_right","move_up","move_down","fire","bomb","strike","focus_flight","quit_game"]
const DEFAULT_DEADZONE := 0.22
const CAPTURE_THRESHOLD := 0.65
const MIN_DEADZONE := 0.10
const MAX_DEADZONE := 0.45

static func defaults() -> Dictionary:
	return {
		"move_left":[{"kind":"button","index":JOY_BUTTON_DPAD_LEFT},{"kind":"axis","index":JOY_AXIS_LEFT_X,"direction":-1}],
		"move_right":[{"kind":"button","index":JOY_BUTTON_DPAD_RIGHT},{"kind":"axis","index":JOY_AXIS_LEFT_X,"direction":1}],
		"move_up":[{"kind":"button","index":JOY_BUTTON_DPAD_UP},{"kind":"axis","index":JOY_AXIS_LEFT_Y,"direction":-1}],
		"move_down":[{"kind":"button","index":JOY_BUTTON_DPAD_DOWN},{"kind":"axis","index":JOY_AXIS_LEFT_Y,"direction":1}],
		"fire":[{"kind":"button","index":JOY_BUTTON_A}],
		"bomb":[{"kind":"button","index":JOY_BUTTON_B}],
		"strike":[{"kind":"button","index":JOY_BUTTON_X}],
		"focus_flight":[{"kind":"button","index":JOY_BUTTON_LEFT_SHOULDER}],
		"quit_game":[{"kind":"button","index":JOY_BUTTON_START}]
	}

static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func sanitize_binding(value: Variant) -> Dictionary:
	if value is not Dictionary or not _number(value.get("index")): return {}
	var index_value := float(value.index)
	if index_value < 0 or index_value != floorf(index_value): return {}
	if value.get("kind") == "button" and index_value < JOY_BUTTON_MAX:
		return {"kind":"button","index":int(index_value)}
	if value.get("kind") == "axis" and index_value < JOY_AXIS_MAX:
		# JSON decodes integral values as floats; Array membership compares types.
		if not _number(value.get("direction")) or (float(value.direction)!=-1.0 and float(value.direction)!=1.0): return {}
		# Mapped triggers rest at zero and only have a positive travel range.
		if int(index_value) in [JOY_AXIS_TRIGGER_LEFT,JOY_AXIS_TRIGGER_RIGHT] and value.direction < 0: return {}
		return {"kind":"axis","index":int(index_value),"direction":int(value.direction)}
	return {}

static func _token(binding: Dictionary) -> String:
	return "%s:%d:%d" % [binding.kind,int(binding.index),int(binding.get("direction",0))]

static func _sanitize_profile(value: Dictionary) -> Dictionary:
	var clean := {"bindings":defaults(),"deadzone":DEFAULT_DEADZONE}
	if _number(value.get("deadzone")):
		clean.deadzone = clampf(float(value.deadzone),MIN_DEADZONE,MAX_DEADZONE)
	if value.get("bindings") is not Dictionary: return clean
	for action in ACTIONS:
		var entries: Variant = value.bindings.get(action)
		if entries is not Array or entries.is_empty() or entries.size()>16: continue
		var valid: Array[Dictionary] = []
		for entry in entries:
			var binding := sanitize_binding(entry)
			if not binding.is_empty() and binding not in valid: valid.append(binding)
		if not valid.is_empty(): clean.bindings[action] = valid
	# Corrupted collisions must never silently fire a bomb or leave a direction unbound.
	var used := {}
	for action in ACTIONS:
		for binding in clean.bindings[action]:
			var token := _token(binding)
			if used.has(token):
				clean.bindings = defaults()
				return clean
			used[token] = action
	return clean

static func sanitize_profiles(value: Variant) -> Dictionary:
	var clean := {}
	if value is not Dictionary: return clean
	for key in value:
		if clean.size()>=32: break
		if key is not String or key.is_empty() or key.length()>192 or value[key] is not Dictionary: continue
		clean[key] = _sanitize_profile(value[key])
	return clean

static func profile_key(device: int) -> String:
	if device < 0 or device not in Input.get_connected_joypads(): return "default"
	var guid := Input.get_joy_guid(device)
	var info := Input.get_joy_info(device)
	var vendor := int(info.get("vendor_id",0))
	var product := int(info.get("product_id",0))
	if not guid.is_empty():
		# Some Windows backends expose one shared XInput GUID; IDs distinguish models.
		return (guid+":%04x:%04x" % [vendor,product]) if vendor>0 or product>0 else guid
	var name := Input.get_joy_name(device)
	return "name:"+name.sha256_text() if not name.is_empty() else "default"

static func _profile(data: Dictionary, device: int) -> Dictionary:
	var profiles: Variant = data.get("gamepad_profiles",{})
	if profiles is Dictionary:
		var stored: Variant = profiles.get(profile_key(device),{})
		if stored is Dictionary: return _sanitize_profile(stored)
	return {"bindings":defaults(),"deadzone":DEFAULT_DEADZONE}

static func _store_profile(data: Dictionary, device: int, profile: Dictionary) -> void:
	data.gamepad_profiles = sanitize_profiles(data.get("gamepad_profiles",{}))
	data.gamepad_profiles[profile_key(device)] = profile

static func bindings_for(data: Dictionary, device: int) -> Dictionary:
	return _profile(data,device).bindings

static func deadzone_for(data: Dictionary, device: int) -> float:
	return float(_profile(data,device).deadzone)

static func set_deadzone(data: Dictionary, device: int, value: float) -> void:
	if not is_finite(value): return
	var profile := _profile(data,device)
	profile.deadzone = clampf(value,MIN_DEADZONE,MAX_DEADZONE)
	_store_profile(data,device,profile)

static func apply(data: Dictionary, device: int) -> void:
	var profile := _profile(data,device)
	for action in ACTIONS:
		if not InputMap.has_action(action): InputMap.add_action(action)
		# A held button may otherwise survive removal of its binding indefinitely.
		Input.action_release(action)
		for event in InputMap.action_get_events(action):
			if event is InputEventJoypadButton or event is InputEventJoypadMotion:
				InputMap.action_erase_event(action,event)
		InputMap.action_set_deadzone(action,float(profile.deadzone))
		for binding in profile.bindings[action]:
			var event: InputEvent
			if binding.kind == "button":
				var button := InputEventJoypadButton.new()
				button.button_index = int(binding.index)
				event = button
			else:
				var motion := InputEventJoypadMotion.new()
				motion.axis = int(binding.index)
				motion.axis_value = float(binding.direction)
				event = motion
			event.device = device
			InputMap.action_add_event(action,event)

static func assign(data: Dictionary, device: int, action: String, value: Dictionary) -> Array[String]:
	var changed: Array[String] = []
	var binding := sanitize_binding(value)
	if action not in ACTIONS or binding.is_empty(): return changed
	var profile := _profile(data,device)
	var previous: Array = profile.bindings[action].duplicate(true)
	if binding in previous: return changed
	# Exchange bindings rather than silently leaving the previous owner unusable.
	for other in ACTIONS:
		if other == action or binding not in profile.bindings[other]: continue
		var others: Array = profile.bindings[other]
		others.erase(binding)
		others.append_array(previous)
		changed.append(other)
	profile.bindings[action] = [binding]
	_store_profile(data,device,profile)
	return changed

static func reset(data: Dictionary, device: int) -> void:
	_store_profile(data,device,{"bindings":defaults(),"deadzone":DEFAULT_DEADZONE})

static func event_binding(event: InputEvent) -> Dictionary:
	if event is InputEventJoypadButton and event.pressed:
		return sanitize_binding({"kind":"button","index":event.button_index})
	if event is InputEventJoypadMotion and is_finite(event.axis_value) and absf(event.axis_value)>=CAPTURE_THRESHOLD:
		return sanitize_binding({"kind":"axis","index":event.axis,"direction":-1 if event.axis_value<0 else 1})
	return {}

static func device_name(device: int) -> String:
	if device < 0: return L10N.text("Aucune manette connectée")
	if device not in Input.get_connected_joypads(): return L10N.text("Manette %d") % (device+1)
	var name := Input.get_joy_name(device)
	var raw_name := str(Input.get_joy_info(device).get("raw_name",""))
	if not raw_name.is_empty() and (name.is_empty() or "xinput" in name.to_lower() or name.to_lower()=="gamepad"):
		name = raw_name
	return name if not name.is_empty() else L10N.text("Manette %d") % (device+1)

static func device_family(device: int = -1) -> String:
	if device < 0: return "xbox"
	if device not in Input.get_connected_joypads(): return "xbox"
	var info := Input.get_joy_info(device)
	var name := (Input.get_joy_name(device)+" "+str(info.get("raw_name",""))).to_lower()
	var vendor := int(info.get("vendor_id",0))
	if vendor == 0x054c or "playstation" in name or "dualshock" in name or "dualsense" in name or "ps4" in name or "ps5" in name: return "playstation"
	if vendor == 0x057e or "nintendo" in name or "switch" in name or "joy-con" in name: return "nintendo"
	if vendor == 0x045e or "xbox" in name or "xinput" in name: return "xbox"
	return "generic"

static func binding_label(value: Dictionary, device: int = -1) -> String:
	var binding := sanitize_binding(value)
	if binding.is_empty(): return "—"
	var family := device_family(device)
	var index := int(binding.index)
	if binding.kind == "button":
		var labels := {JOY_BUTTON_A:"A",JOY_BUTTON_B:"B",JOY_BUTTON_X:"X",JOY_BUTTON_Y:"Y",JOY_BUTTON_LEFT_SHOULDER:"LB",JOY_BUTTON_RIGHT_SHOULDER:"RB",JOY_BUTTON_START:"Start",JOY_BUTTON_BACK:"Select",JOY_BUTTON_LEFT_STICK:"LS",JOY_BUTTON_RIGHT_STICK:"RS",JOY_BUTTON_GUIDE:"Guide",JOY_BUTTON_DPAD_LEFT:"← croix",JOY_BUTTON_DPAD_RIGHT:"→ croix",JOY_BUTTON_DPAD_UP:"↑ croix",JOY_BUTTON_DPAD_DOWN:"↓ croix"}
		if family == "playstation":
			labels.merge({JOY_BUTTON_A:"×",JOY_BUTTON_B:"○",JOY_BUTTON_X:"□",JOY_BUTTON_Y:"△",JOY_BUTTON_LEFT_SHOULDER:"L1",JOY_BUTTON_RIGHT_SHOULDER:"R1",JOY_BUTTON_START:"Options",JOY_BUTTON_BACK:"Share",JOY_BUTTON_LEFT_STICK:"L3",JOY_BUTTON_RIGHT_STICK:"R3",JOY_BUTTON_GUIDE:"PS",JOY_BUTTON_TOUCHPAD:"Pavé tactile"},true)
		elif family == "nintendo":
			labels.merge({JOY_BUTTON_A:"B",JOY_BUTTON_B:"A",JOY_BUTTON_X:"Y",JOY_BUTTON_Y:"X",JOY_BUTTON_LEFT_SHOULDER:"L",JOY_BUTTON_RIGHT_SHOULDER:"R",JOY_BUTTON_START:"+",JOY_BUTTON_BACK:"−",JOY_BUTTON_GUIDE:"Home"},true)
		elif family == "generic" and not Input.is_joy_known(device):
			return L10N.text("Bouton %d") % (index+1)
		return L10N.text(labels[index]) if labels.has(index) else L10N.text("Bouton %d") % (index+1)
	var negative: bool = int(binding.direction)<0
	if index == JOY_AXIS_TRIGGER_LEFT:
		return "L2" if family=="playstation" else ("ZL" if family=="nintendo" else "LT")
	if index == JOY_AXIS_TRIGGER_RIGHT:
		return "R2" if family=="playstation" else ("ZR" if family=="nintendo" else "RT")
	if index in [JOY_AXIS_LEFT_X,JOY_AXIS_LEFT_Y,JOY_AXIS_RIGHT_X,JOY_AXIS_RIGHT_Y]:
		var arrow := ("←" if negative else "→") if index in [JOY_AXIS_LEFT_X,JOY_AXIS_RIGHT_X] else ("↑" if negative else "↓")
		return (L10N.text("Stick gauche %s") if index in [JOY_AXIS_LEFT_X,JOY_AXIS_LEFT_Y] else L10N.text("Stick droit %s")) % arrow
	return L10N.text("Axe %d %s") % [index+1,"−" if negative else "+"]

static func describe_bindings(data: Dictionary, device: int, action: String) -> String:
	var labels: Array[String] = []
	for binding in bindings_for(data,device).get(action,[]):
		labels.append(binding_label(binding,device))
	return " / ".join(labels) if not labels.is_empty() else "—"
