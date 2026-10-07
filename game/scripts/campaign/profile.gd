extends RefCounted
## Profile data never contains objects or scripts. Invalid values are clamped on load.
const VERSION := 1
const DIFFICULTIES := ["Cadet", "Pilote", "As"]
const AIRCRAFT := ["Vanguard", "Interceptor", "Bulwark"]
var path := "user://pacific-campaign-v1.json"
var data: Dictionary
var last_error := OK

func _init() -> void:
	reset()

func reset() -> void:
	data = {"version":VERSION,"unlocked":1,"next_mission":1,"completed":false,"pow_ready":false,"credits":0,"high_score":0,"aircraft":0,"difficulty":1,"upgrades":[0,0,0],"records":{},"settings":{"master":0.8,"music":0.35,"effects":0.8,"fullscreen":true,"shake":true,"flashes":true}}
	data.merge({"run_score":0,"run_lives":3,"power":"none","arcade_records":{},"bindings":{}})
	data.settings.merge({"quality":1,"fps":false,"vsync":true})

func load_profile() -> bool:
	for candidate in [path,path+".bak"]:
		if not FileAccess.file_exists(candidate): continue
		var parser := JSON.new()
		if parser.parse(FileAccess.get_file_as_string(candidate)) != OK: continue
		var parsed = parser.data
		if parsed is not Dictionary or int(parsed.get("version",0)) != VERSION: continue
		reset()
		for key in ["unlocked","next_mission"]: data[key] = clampi(int(parsed.get(key,1)),1,32)
		data.next_mission = mini(data.next_mission,data.unlocked)
		data.completed = bool(parsed.get("completed",false)) and data.unlocked == 32
		data.pow_ready = bool(parsed.get("pow_ready",false))
		data.credits = clampi(int(parsed.get("credits",0)),0,200)
		data.high_score = clampi(int(parsed.get("high_score",0)),0,99999999)
		data.aircraft = clampi(int(parsed.get("aircraft",0)),0,2)
		data.difficulty = clampi(int(parsed.get("difficulty",1)),0,2)
		var upgrades = parsed.get("upgrades",[])
		if upgrades is Array and upgrades.size() == 3:
			for i in range(3): data.upgrades[i] = clampi(int(upgrades[i]),0,3)
		var records = parsed.get("records",{})
		if records is Dictionary:
			for key in records:
				if int(key)<1 or int(key)>32 or records[key] is not Dictionary: continue
				data.records[str(key)] = {"score":clampi(int(records[key].get("score",0)),0,99999999),"grade":clampi(int(records[key].get("grade",0)),0,3)}
		for key in data.records:
			var old: Dictionary = records[key]
			data.records[key].best_chain = clampi(int(old.get("best_chain",0)),0,99999)
			var rank := str(old.get("rank","D"))
			data.records[key].rank = rank if rank in ["D","C","B","A","S"] else "D"
		var settings = parsed.get("settings",{})
		var legacy_total := 0
		for record in data.records.values(): legacy_total += int(record.score)
		data.run_score = clampi(int(parsed.get("run_score",legacy_total)),0,99999999)
		data.run_lives = clampi(int(parsed.get("run_lives",3)),1,9)
		data.power = str(parsed.get("power","spread" if data.pow_ready else "none"))
		if data.power not in ["none","spread","laser","life"]: data.power = "none"
		data.high_score = maxi(data.high_score,data.run_score)
		if settings is Dictionary:
			for key in ["master","music","effects"]: data.settings[key] = clampf(float(settings.get(key,data.settings[key])),0,1)
			for key in ["fullscreen","shake","flashes"]: data.settings[key] = bool(settings.get(key,true))
		data.settings.quality = clampi(int(settings.get("quality",1)),0,2) if settings is Dictionary else 1
		if settings is Dictionary:
			data.settings.fps = bool(settings.get("fps",false))
			data.settings.vsync = bool(settings.get("vsync",true))
		for field in ["bindings","arcade_records"]:
			var saved = parsed.get(field,{})
			if saved is Dictionary:
				for key in saved:
					if field=="bindings" and key in ["move_left","move_right","move_up","move_down","fire","bomb","strike","focus_flight"] and (saved[key] is float or saved[key] is int):
						data.bindings[key] = clampi(int(saved[key]),1,0x7fffff)
					elif field=="arcade_records" and str(key).length()<32 and (saved[key] is int or saved[key] is float): data.arcade_records[key] = clampi(int(saved[key]),0,99999999)
		return true
	return false

func save() -> Error:
	var file := FileAccess.open(path+".tmp",FileAccess.WRITE)
	if file == null:
		last_error = FileAccess.get_open_error()
		return last_error
	file.store_string(JSON.stringify(data,"\t"))
	file.flush()
	file.close()
	if FileAccess.file_exists(path):
		var backup_result := DirAccess.copy_absolute(path,path+".bak")
		if backup_result != OK:
			last_error = backup_result
			return last_error
	last_error = DirAccess.rename_absolute(path+".tmp",path)
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
	return 2+int(data.upgrades[index])*2

func buy_upgrade(index: int) -> bool:
	if index<0 or index>2 or int(data.upgrades[index])>=3: return false
	var cost := upgrade_cost(index)
	if data.credits < cost: return false
	var before := data.duplicate(true)
	data.credits -= cost
	data.upgrades[index] += 1
	if save() != OK:
		data = before
		return false
	return true
