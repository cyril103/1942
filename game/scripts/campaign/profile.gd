extends RefCounted
## Profile data never contains objects or scripts. Invalid values are clamped on load.
const VERSION := 1
const DIFFICULTIES := ["Cadet", "Pilote", "As"]
const LOADOUT := preload("res://scripts/campaign/loadout.gd")
const AIRCRAFT := [LOADOUT.AIRCRAFT[0]["label"],LOADOUT.AIRCRAFT[1]["label"],LOADOUT.AIRCRAFT[2]["label"]]
var path := "user://pacific-campaign-v1.json"
var data: Dictionary
var last_error := OK
var _preserve_backup := false
var _unrecoverable_save := false

func _init() -> void:
	reset()

func reset() -> void:
	data = _default_data()
	last_error = OK
	_preserve_backup = false
	_unrecoverable_save = false

func _default_data() -> Dictionary:
	var defaults := {"version":VERSION,"unlocked":1,"next_mission":1,"completed":false,"pow_ready":false,"credits":0,"high_score":0,"aircraft":0,"difficulty":1,"upgrades":[0,0,0],"records":{},"settings":{"master":0.8,"music":0.35,"effects":0.8,"fullscreen":true,"shake":true,"flashes":true}}
	defaults.merge({"run_score":0,"run_lives":3,"power":"none","arcade_records":{},"bindings":{}})
	defaults.settings.merge({"quality":1,"fps":false,"vsync":true,"short_retry_intro":false})
	defaults.merge({"equipment_revision":LOADOUT.EQUIPMENT_REVISION,"owned_modules":[],"equipped_modules":[]})
	return defaults

func _is_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

func _valid_fields(source: Dictionary, numbers: Array, flags: Array = [], strings: Array = []) -> bool:
	for key in numbers:
		if source.has(key) and not _is_number(source[key]): return false
	for key in flags:
		if source.has(key) and source[key] is not bool: return false
	for key in strings:
		if source.has(key) and source[key] is not String: return false
	return true

func _bounded_int(value: Variant, minimum: int, maximum: int) -> int:
	# JSON numbers are floats; clamp before integer conversion to avoid overflow.
	return int(clampf(float(value),float(minimum),float(maximum)))

func _decode_candidate(parsed: Variant) -> Dictionary:
	if parsed is not Dictionary: return {}
	var source: Dictionary = parsed
	if not _is_number(source.get("version")) or source.version != VERSION: return {}
	if not _valid_fields(source,["unlocked","next_mission","credits","high_score","aircraft","difficulty","run_score","run_lives","equipment_revision"],["completed","pow_ready"],["power"]): return {}
	# JSON decodes integral numbers as floats; numeric equality is required here.
	if source.has("equipment_revision") and source.equipment_revision!=0 and source.equipment_revision!=LOADOUT.EQUIPMENT_REVISION: return {}
	for field in ["owned_modules","equipped_modules"]:
		if not source.has(field): continue
		if source[field] is not Array: return {}
		for value in source[field]:
			if value is not String: return {}
	for field in ["records","settings","bindings","arcade_records"]:
		if source.has(field) and source[field] is not Dictionary: return {}
	var upgrades: Variant = source.get("upgrades",[0,0,0])
	if upgrades is not Array or upgrades.size() != 3: return {}
	for value in upgrades:
		if not _is_number(value): return {}
	var records: Dictionary = source.get("records",{})
	for key in records:
		if not str(key).is_valid_int() or str(key).to_int()<1 or str(key).to_int()>32: continue
		if records[key] is not Dictionary or not _valid_fields(records[key],["score","grade","best_chain"],[],["rank"]): return {}
	var settings: Dictionary = source.get("settings",{})
	if not _valid_fields(settings,["master","music","effects","quality"],["fullscreen","shake","flashes","fps","vsync","short_retry_intro"]): return {}
	var bindings: Dictionary = source.get("bindings",{})
	var binding_names := ["move_left","move_right","move_up","move_down","fire","bomb","strike","focus_flight"]
	for key in bindings:
		if key in binding_names and not _is_number(bindings[key]): return {}
	var arcade_records: Dictionary = source.get("arcade_records",{})
	for key in arcade_records:
		if str(key).length()<32 and not _is_number(arcade_records[key]): return {}

	# Build and migrate off to the side. No rejected candidate changes the live profile.
	var decoded := _default_data()
	for key in ["unlocked","next_mission"]: decoded[key] = _bounded_int(source.get(key,1),1,32)
	decoded.next_mission = mini(decoded.next_mission,decoded.unlocked)
	decoded.completed = source.get("completed",false) and decoded.unlocked == 32
	decoded.pow_ready = source.get("pow_ready",false)
	decoded.credits = _bounded_int(source.get("credits",0),0,200)
	decoded.high_score = _bounded_int(source.get("high_score",0),0,99999999)
	decoded.aircraft = _bounded_int(source.get("aircraft",0),0,2)
	decoded.difficulty = _bounded_int(source.get("difficulty",1),0,2)
	for i in range(3): decoded.upgrades[i] = _bounded_int(upgrades[i],0,3)
	for key in records:
		if not str(key).is_valid_int() or str(key).to_int()<1 or str(key).to_int()>32: continue
		var old: Dictionary = records[key]
		var rank: String = old.get("rank","D")
		decoded.records[str(str(key).to_int())] = {"score":_bounded_int(old.get("score",0),0,99999999),"grade":_bounded_int(old.get("grade",0),0,3),"best_chain":_bounded_int(old.get("best_chain",0),0,99999),"rank":rank if rank in ["D","C","B","A","S"] else "D"}
	var legacy_total := 0
	for record in decoded.records.values(): legacy_total += int(record.score)
	decoded.run_score = _bounded_int(source.get("run_score",legacy_total),0,99999999)
	decoded.run_lives = _bounded_int(source.get("run_lives",3),1,9)
	decoded.power = source.get("power","spread" if decoded.pow_ready else "none")
	if decoded.power not in ["none","spread","laser","life"]: decoded.power = "none"
	decoded.high_score = maxi(decoded.high_score,decoded.run_score)
	for key in ["master","music","effects"]: decoded.settings[key] = clampf(float(settings.get(key,decoded.settings[key])),0,1)
	for key in ["fullscreen","shake","flashes"]: decoded.settings[key] = settings.get(key,true)
	decoded.settings.quality = _bounded_int(settings.get("quality",1),0,2)
	decoded.settings.fps = settings.get("fps",false)
	decoded.settings.vsync = settings.get("vsync",true)
	decoded.settings.short_retry_intro = settings.get("short_retry_intro",false)
	for key in bindings:
		if key in binding_names: decoded.bindings[key] = _bounded_int(bindings[key],1,0x7fffff)
	for key in arcade_records:
		if str(key).length()<32: decoded.arcade_records[key] = _bounded_int(arcade_records[key],0,99999999)
	for id in source.get("owned_modules",[]):
		if not LOADOUT.module_info(id).is_empty() and id not in decoded.owned_modules:
			decoded.owned_modules.append(id)
	decoded.equipped_modules = source.get("equipped_modules",[]).duplicate()
	decoded.equipped_modules = LOADOUT.equipped_modules(decoded)
	return decoded

func load_profile() -> bool:
	var existing_save := false
	for candidate in [path,path+".bak"]:
		if not FileAccess.file_exists(candidate): continue
		existing_save = true
		var parser := JSON.new()
		if parser.parse(FileAccess.get_file_as_string(candidate)) != OK: continue
		var decoded := _decode_candidate(parser.data)
		if decoded.is_empty(): continue
		data = decoded
		last_error = OK
		_preserve_backup = candidate != path
		_unrecoverable_save = false
		return true
	last_error = ERR_FILE_CORRUPT if existing_save else OK
	_unrecoverable_save = existing_save
	return false

func save() -> Error:
	# Keep unrecoverable files for manual repair instead of replacing them with defaults.
	# reset() is the explicit action that allows a fresh profile to replace them.
	if _unrecoverable_save:
		last_error = ERR_FILE_CORRUPT
		return last_error
	var file := FileAccess.open(path+".tmp",FileAccess.WRITE)
	if file == null:
		last_error = FileAccess.get_open_error()
		return last_error
	file.store_string(JSON.stringify(data,"\t"))
	file.flush()
	file.close()
	if FileAccess.file_exists(path) and not _preserve_backup:
		var backup_result := DirAccess.copy_absolute(path,path+".bak")
		if backup_result != OK:
			last_error = backup_result
			return last_error
	last_error = DirAccess.rename_absolute(path+".tmp",path)
	if last_error == OK: _preserve_backup = false
	return last_error

func record_victory(mission: int, score: int, grade: int) -> int:
	var key := str(mission)
	var old: Dictionary = data.records.get(key,{"score":0,"grade":-1})
	var earned := (2 if int(old.grade)<0 else 0) + maxi(0,grade-maxi(0,int(old.grade)))
	data.credits += earned
	data.records[key] = {"score":maxi(score,int(old.score)),"grade":maxi(grade,int(old.grade)),"rank":old.get("rank","D"),"best_chain":old.get("best_chain",0)}
	data.unlocked = maxi(data.unlocked,mini(32,mission+1))
	data.next_mission = maxi(data.next_mission,mini(32,mission+1))
	data.high_score = maxi(data.high_score,score)
	if mission == 32: data.completed = true
	return earned

func upgrade_cost(index: int) -> int:
	return LOADOUT.upgrade_cost(int(data.upgrades[index])+1) if index>=0 and index<3 else 0

func upgrade_required_mission(index: int) -> int:
	return LOADOUT.rank_required_mission(int(data.upgrades[index])+1) if index>=0 and index<3 else 0

func can_buy_upgrade(index: int) -> bool:
	if index<0 or index>=3 or int(data.upgrades[index])>=3: return false
	return int(data.unlocked)>=upgrade_required_mission(index) and int(data.credits)>=upgrade_cost(index)

func buy_upgrade(index: int) -> bool:
	if not can_buy_upgrade(index): return false
	var cost := upgrade_cost(index)
	var before := data.duplicate(true)
	data.credits -= cost
	data.upgrades[index] += 1
	if save() != OK:
		data = before
		return false
	return true

func module_slots() -> int:
	return LOADOUT.module_slots(data)

func can_buy_module(id: String) -> bool:
	var item := LOADOUT.module_info(id)
	if item.is_empty() or id in data.owned_modules: return false
	return int(data.unlocked)>=int(item.required_mission) and int(data.credits)>=int(item.cost)

func buy_module(id: String) -> bool:
	if not can_buy_module(id): return false
	var before := data.duplicate(true)
	data.credits -= int(LOADOUT.module_info(id).cost)
	data.owned_modules.append(id)
	if save() != OK:
		data = before
		return false
	return true

func can_equip_module(id: String) -> bool:
	if id not in data.owned_modules: return false
	if id in data.equipped_modules: return true
	var item := LOADOUT.module_info(id)
	if item.is_empty() or data.equipped_modules.size()>=module_slots(): return false
	for equipped in data.equipped_modules:
		if LOADOUT.module_info(equipped).get("family","")==item.family: return false
	return true

func equip_module(id: String) -> bool:
	if not can_equip_module(id): return false
	var before := data.duplicate(true)
	if id in data.equipped_modules: data.equipped_modules.erase(id)
	else: data.equipped_modules.append(id)
	if save() != OK:
		data = before
		return false
	return true
