extends SceneTree
## Isolated regression for malformed profiles, migration and backup preservation.
const PROFILE = preload("res://scripts/campaign/profile.gd")
var failures: Array[String] = []
var checks := 0
var fixture: String

func _initialize() -> void:
	fixture = "user://profile-recovery-test-%d.json" % OS.get_process_id()
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func _write(path: String, content: String) -> void:
	var file := FileAccess.open(path,FileAccess.WRITE)
	check(file != null,"Fixture can be written: "+path)
	if file == null: return
	file.store_string(content)
	file.close()

func _clean() -> void:
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(fixture+suffix): DirAccess.remove_absolute(fixture+suffix)

func _profile():
	var profile = PROFILE.new()
	profile.path = fixture
	return profile

func _good() -> Dictionary:
	var good: Dictionary = PROFILE.new().data.duplicate(true)
	good.unlocked = 17
	good.next_mission = 17
	good.run_score = 12345
	good.high_score = 12345
	good.upgrades = [1,2,3]
	good.records = {"16":{"score":12345,"grade":2,"best_chain":24,"rank":"A"}}
	return good

func _fallback(label: String, primary: String) -> void:
	_clean()
	_write(fixture,primary)
	var backup := JSON.stringify(_good())
	_write(fixture+".bak",backup)
	var profile = _profile()
	check(profile.load_profile(),label+": backup loads")
	check(profile.data.unlocked==17 and profile.data.next_mission==17 and profile.data.run_score==12345,label+": backup progress survives")
	check(profile.data.upgrades==[1,2,3] and profile.data.records["16"].best_chain==24,label+": no partial primary fields survive")
	check(profile.last_error==OK,label+": recovered profile is writable")
	profile.data.run_score = 12346
	check(profile.save()==OK,label+": repaired primary saves")
	check(FileAccess.get_file_as_string(fixture+".bak")==backup,label+": valid backup survives first repair")
	var restored = _profile()
	check(restored.load_profile() and restored.data.run_score==12346,label+": repaired primary reloads")
	profile.data.run_score = 12347
	check(profile.save()==OK,label+": subsequent save succeeds")
	var previous: Variant = JSON.parse_string(FileAccess.get_file_as_string(fixture+".bak"))
	check(previous is Dictionary and previous.get("run_score")==12346,label+": subsequent backup tracks last complete save")

func _run() -> void:
	# Each of these previously raised a script error before reaching the backup.
	var malformed := [
		["version",{}],
		["unlocked",{}],
		["high_score",[]],
		["upgrades",[{},0,0]],
		["settings",{"music":{},"master":.8,"effects":.8}],
		["records",{"1":{"score":[],"grade":1}}]
	]
	for spec in malformed:
		var primary := _good()
		primary[spec[0]] = spec[1]
		_fallback("Malformed "+str(spec[0]),JSON.stringify(primary))
	_fallback("Invalid JSON","{broken")
	_fallback("Missing version",JSON.stringify({"unlocked":32,"run_score":90000}))
	_fallback("Unsupported version",JSON.stringify({"version":2,"unlocked":32}))
	_fallback("Non-object root",JSON.stringify([1,2,3]))
	for replacement in [{"upgrades":[0,0]},{"completed":"true"},{"bindings":{"fire":{}}},{"arcade_records":{"1-0-1":[]}},{"settings":[]},{"records":{"17":{"rank":{}}}}]:
		var primary := _good()
		primary.merge(replacement,true)
		_fallback("Invalid schema "+JSON.stringify(replacement),JSON.stringify(primary))

	# Optional fields in version 1 are migrated, rather than requiring a new format.
	_clean()
	var legacy := {"version":1,"unlocked":3,"next_mission":3,"pow_ready":true,"records":{"1":{"score":400,"grade":1},"2":{"score":600,"grade":2}}}
	_write(fixture,JSON.stringify(legacy))
	var profile = _profile()
	check(profile.load_profile(),"Legacy version 1 profile loads")
	check(profile.data.run_score==1000 and profile.data.high_score==1000 and profile.data.power=="spread","Legacy score and POW migrate")
	check(profile.data.settings.quality==1 and profile.data.settings.vsync and profile.data.upgrades==[0,0,0],"Missing optional fields retain defaults")
	check(profile.data.records["1"].rank=="D" and profile.data.records["2"].best_chain==0,"Legacy records gain rank and chain defaults")

	# Numeric values retain the old clamp behavior, including very large JSON numbers.
	var extremes := _good()
	extremes.merge({"unlocked":1e30,"next_mission":1e30,"completed":true,"credits":-50,"high_score":1e30,"aircraft":99,"difficulty":-2,"run_score":-10,"run_lives":1e30,"upgrades":[-1,2.9,1e30],"power":"unknown","settings":{"master":-1,"music":2,"effects":.5,"quality":99},"bindings":{"fire":1e30,"move_left":-1},"arcade_records":{"classic":1e30},"records":{"1":{"score":1e30,"grade":-5,"best_chain":1e30,"rank":"unknown"},"33":{"score":500},"unknown":{}}},true)
	_write(fixture,JSON.stringify(extremes))
	check(profile.load_profile(),"Out-of-range numeric profile remains recoverable")
	check(profile.data.unlocked==32 and profile.data.next_mission==32 and profile.data.completed,"Mission bounds clamp")
	check(profile.data.credits==0 and profile.data.high_score==99999999 and profile.data.run_score==0,"Score and credit bounds clamp before conversion")
	check(profile.data.aircraft==2 and profile.data.difficulty==0 and profile.data.run_lives==9 and profile.data.upgrades==[0,2,3],"Aircraft, lives and upgrades clamp")
	check(profile.data.power=="none" and profile.data.records.size()==1 and profile.data.records["1"]=={"score":99999999,"grade":0,"best_chain":99999,"rank":"D"},"Unknown powers/ranks and invalid record keys retain safe fallbacks")
	check(profile.data.settings.master==0 and profile.data.settings.music==1 and profile.data.settings.effects==.5 and profile.data.settings.quality==2,"Settings numeric bounds clamp")
	check(profile.data.bindings.fire==0x7fffff and profile.data.bindings.move_left==1 and profile.data.arcade_records.classic==99999999,"Binding and arcade record bounds clamp")
	_write(fixture,JSON.stringify({"version":1,"unlocked":2,"next_mission":19,"completed":true}))
	check(profile.load_profile() and profile.data.next_mission==2 and not profile.data.completed,"Next mission and completion cannot exceed unlocked progress")

	# Both invalid files leave in-memory state and disk data intact, including on save.
	var before: Dictionary = profile.data.duplicate(true)
	var invalid_primary := JSON.stringify({"version":1,"unlocked":{}})
	var invalid_backup := "{bad backup"
	_write(fixture,invalid_primary)
	_write(fixture+".bak",invalid_backup)
	check(not profile.load_profile() and profile.last_error==ERR_FILE_CORRUPT,"Two invalid candidates report failure")
	check(profile.data==before,"Two invalid candidates do not mutate an already loaded profile")
	check(profile.save()==ERR_FILE_CORRUPT,"Unrecoverable files cannot be overwritten by incidental saves")
	check(FileAccess.get_file_as_string(fixture)==invalid_primary and FileAccess.get_file_as_string(fixture+".bak")==invalid_backup and not FileAccess.file_exists(fixture+".tmp"),"Unrecoverable primary and backup remain byte-for-byte intact")
	var fresh = _profile()
	var defaults: Dictionary = fresh.data.duplicate(true)
	check(not fresh.load_profile() and fresh.data==defaults and fresh.save()==ERR_FILE_CORRUPT,"Fresh instance retains usable defaults without overwriting invalid files")
	# A repaired file is accepted on a subsequent load and releases the write guard.
	_write(fixture+".bak",JSON.stringify(_good()))
	check(fresh.load_profile() and fresh.save()==OK,"External backup repair restores normal saving")

	_clean()
	var empty = _profile()
	check(not empty.load_profile() and empty.last_error==OK,"Missing files are a normal first launch")
	check(empty.save()==OK,"First launch can save a fresh profile")
	_clean()
	print("PROFILE RECOVERY TEST ",checks," checks, ",failures.size()," failures: ",failures)
	quit(0 if failures.is_empty() else 1)
