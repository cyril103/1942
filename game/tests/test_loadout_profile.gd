extends SceneTree
## Pure/headless checks of real purchases, persistence and equipment calculations.
## Campaign viability and the human play matrix are intentionally separate gates.
const PROFILE := preload("res://scripts/campaign/profile.gd")
const LOADOUT := preload("res://scripts/campaign/loadout.gd")
var checks := 0
var failures: Array[String] = []
var economy: Array[Dictionary] = []
var fixture := ""

func _initialize() -> void:
	fixture = "user://loadout-profile-test-%d.json" % OS.get_process_id()
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func near(actual: float, expected: float, message: String) -> void:
	check(absf(actual-expected)<.00001,message+" (%f vs %f)" % [actual,expected])

func clean() -> void:
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(fixture+suffix): DirAccess.remove_absolute(fixture+suffix)

func fresh():
	var profile = PROFILE.new()
	profile.path = fixture
	return profile

func write_json(path: String, value: Variant) -> void:
	var file := FileAccess.open(path,FileAccess.WRITE)
	check(file!=null,"Fixture opens for writing")
	if file!=null: file.store_string(JSON.stringify(value)); file.close()

func test_catalogue() -> void:
	var modules := LOADOUT.modules()
	check(modules.size()==10,"Ten authored modules")
	var ids: Array[String] = []
	for item in modules:
		check(item.id not in ids,"Module ids unique: "+item.id)
		ids.append(item.id)
		check(item.cost==6 and item.family in ["aim","airframe","systems"],"Module price and exclusion family: "+item.id)
		check(item.description.length()>20,"Every compromise is described: "+item.id)
	check(ids==["precision","coverage","plates","agile","yield","reserve","payload","prepared","endurance","impact"],"Catalogue preserves stable save identifiers")
	modules[0].modifiers.rate = 99.0
	near(float(LOADOUT.module_info("precision").modifiers.rate),1.1,"Mutating a UI copy does not change catalogue")
	var plane := LOADOUT.aircraft(0)
	plane.speed = 1000
	near(float(LOADOUT.aircraft(0).speed),12.0,"Aircraft returned by value")
	check(LOADOUT.module_info("unknown").is_empty(),"Unknown module is unavailable")
	check(LOADOUT.rank_required_mission(1)==1 and LOADOUT.rank_required_mission(2)==9 and LOADOUT.rank_required_mission(3)==21,"Three authored rank gates")
	check(LOADOUT.module_slots({"unlocked":4})==0 and LOADOUT.module_slots({"unlocked":5})==1 and LOADOUT.module_slots({"unlocked":12})==1 and LOADOUT.module_slots({"unlocked":13})==2,"Slot gates at missions 5 and 13")

func test_purchases() -> void:
	clean()
	var profile = fresh()
	profile.data.credits = 200
	for index in range(3):
		check(profile.can_buy_upgrade(index) and profile.buy_upgrade(index),"Initial rank I is purchasable for option %d" % index)
		check(profile.upgrade_required_mission(index)==9 and not profile.can_buy_upgrade(index) and not profile.buy_upgrade(index),"Rank II cannot be bought before sector 3 for option %d" % index)
	var early: Dictionary = profile.data.duplicate(true)
	for id in ["unknown","precision","plates","endurance"]:
		check(not profile.can_buy_module(id) and not profile.buy_module(id),"Unavailable module cannot be purchased: "+id)
	check(profile.data==early,"Rejected purchases do not spend or mutate profile")
	profile.record_victory(8,2000,1)
	for index in range(3):
		check(profile.buy_upgrade(index),"Actual victory unlocks rank II for option %d" % index)
		check(profile.upgrade_required_mission(index)==21 and not profile.buy_upgrade(index),"Rank III remains gated for option %d" % index)
	profile.record_victory(20,3000,1)
	for index in range(3):
		check(profile.buy_upgrade(index) and profile.upgrade_cost(index)==0 and not profile.buy_upgrade(index),"Rank III caps at three for option %d" % index)
	check(not profile.buy_upgrade(-1) and not profile.buy_upgrade(3) and profile.upgrade_cost(-1)==0,"Invalid upgrade index is safely rejected")
	check(profile.buy_module("precision") and profile.equip_module("precision"),"Buying does not prevent explicit equip")
	check(not profile.buy_module("precision"),"Owned module cannot be purchased twice")
	check(profile.buy_module("coverage") and not profile.can_equip_module("coverage") and not profile.equip_module("coverage"),"Same-family choice cannot replace equipped precision silently")
	check(profile.buy_module("plates") and profile.equip_module("plates"),"Second slot supports a different family")
	check(profile.buy_module("yield") and not profile.equip_module("yield"),"Third module cannot exceed two slots")
	check(profile.data.equipped_modules==["precision","plates"],"Rejected equip preserves both explicit choices")
	check(profile.equip_module("precision") and profile.equip_module("coverage"),"Toggle deselects and lets player explicitly switch aim module")
	check(profile.data.equipped_modules==["plates","coverage"],"Chosen family replacement is explicit")
	var credits: int = profile.data.credits
	check(profile.equip_module("coverage") and profile.equip_module("yield") and profile.data.credits==credits,"Free between-mission equipment change")
	var reloaded = fresh()
	check(reloaded.load_profile() and reloaded.data==profile.data,"Actual equipped choices round-trip through save")
	var before: Dictionary = profile.data.duplicate(true)
	profile.path = "user://missing-loadout-directory-%d/save.json" % OS.get_process_id()
	check(not profile.equip_module("yield") and profile.data==before,"Failed equipment save rolls back memory")
	profile.data.unlocked = 32
	before = profile.data.duplicate(true)
	check(not profile.buy_module("impact") and profile.data==before,"Failed module purchase save rolls back money and ownership")
	profile.data.upgrades = [0,0,0]
	before = profile.data.duplicate(true)
	check(not profile.buy_upgrade(0) and profile.data==before,"Failed upgrade purchase save rolls back rank and money")
	profile.path = fixture
	clean()

func test_module_access() -> void:
	# Exercising each exact gate with actual purchases catches price or profile
	# checks drifting independently from the catalogue used by the hangar.
	for entry in LOADOUT.modules():
		clean()
		var profile = fresh()
		profile.data.credits = 6
		profile.data.unlocked = entry.required_mission-1
		check(not profile.buy_module(entry.id) and profile.data.credits==6,"Module unavailable one mission before gate: "+entry.id)
		profile.record_victory(entry.required_mission-1,500,1)
		check(profile.buy_module(entry.id) and profile.data.credits==3,"Actual victory unlocks module: "+entry.id)
		check(profile.data.equipped_modules.is_empty(),"Purchase does not silently equip: "+entry.id)
		check(profile.equip_module(entry.id),"Available owned module equips: "+entry.id)
		var reloaded = fresh()
		check(reloaded.load_profile() and reloaded.data.equipped_modules==[entry.id],"Module access survives reload: "+entry.id)
	clean()

func test_medal_improvements() -> void:
	clean()
	var profile = fresh()
	check(profile.record_victory(1,1000,1)==3,"Bronze pays first clear plus first medal")
	check(profile.record_victory(1,2000,2)==1,"Silver improvement adds one credit")
	check(profile.record_victory(1,3000,3)==1,"Gold improvement adds one credit")
	check(profile.data.credits==5 and profile.data.records["1"].grade==3,"Improving medals equals one original gold reward")
	check(profile.buy_upgrade(0),"A medal reward can fund an actual upgrade")
	var balance: int = profile.data.credits
	check(profile.record_victory(1,4000,3)==0 and profile.record_victory(1,5000,1)==0 and profile.data.credits==balance,"Higher score and lower medal cannot farm money")
	check(profile.data.records["1"].score==5000 and profile.data.records["1"].grade==3,"Score progression preserves highest medal")
	check(profile.save()==OK,"Improved medal and purchase persist")
	var reloaded = fresh()
	check(reloaded.load_profile() and reloaded.data.credits==balance and reloaded.record_victory(1,6000,3)==0,"Reload cannot repay a first-clear award")
	clean()

func simulate_economy(name: String, grades: Array, expected_income: int) -> void:
	clean()
	var profile = fresh()
	var income := 0
	var spent := 0
	var milestones: Array[Dictionary] = []
	for mission in range(1,33):
		var grade: int = grades[(mission-1)%grades.size()]
		var earned: int = profile.record_victory(mission,mission*1000,grade)
		income += earned
		check(earned==2+grade,"%s mission %02d first-clear reward is real" % [name,mission])
		var unchanged: Dictionary = profile.data.duplicate(true)
		check(profile.record_victory(mission,mission*1000,grade)==0 and profile.data==unchanged,"%s mission %02d replay cannot finance equipment" % [name,mission])
		for index in range(3):
			while profile.can_buy_upgrade(index):
				var cost: int = profile.upgrade_cost(index)
				check(profile.buy_upgrade(index),"%s mission %02d actual upgrade purchase" % [name,mission])
				spent += cost
		for entry in LOADOUT.modules():
			if profile.can_buy_module(entry.id):
				check(profile.buy_module(entry.id),"%s mission %02d actual module purchase %s" % [name,mission,entry.id])
				spent += entry.cost
		check(profile.data.credits==income-spent and profile.data.credits>=0,"%s mission %02d ledger never becomes negative" % [name,mission])
		if mission in [4,8,12,16,20,24,28,32]:
			milestones.append({"after_mission":mission,"income":income,"spent":spent,"credits":profile.data.credits,"upgrades":profile.data.upgrades.duplicate(),"owned_modules":profile.data.owned_modules.duplicate()})
	check(income==expected_income,"%s campaign reward total" % name)
	check(spent==96 and profile.data.upgrades==[3,3,3] and profile.data.owned_modules.size()==10,"%s all choices are eventually affordable without replay farming" % name)
	check(profile.data.completed and profile.data.unlocked==32,"%s actual campaign victories preserve completion" % name)
	var remaining: int = profile.data.credits
	for mission in range(1,33):
		check(profile.record_victory(mission,mission*1000,grades[(mission-1)%grades.size()])==0,"%s full replay mission %02d cannot farm rewards" % [name,mission])
	check(profile.data.credits==remaining,"%s full replay leaves credits unchanged" % name)
	check(profile.save()==OK,"%s completed equipment saves" % name)
	var reloaded = fresh()
	check(reloaded.load_profile() and reloaded.data==profile.data,"%s actual purchase ledger round-trip" % name)
	economy.append({"medal_profile":name,"income":income,"spent":spent,"remaining":profile.data.credits,"milestones":milestones})
	clean()

func test_migrations() -> void:
	clean()
	var old = fresh()
	old.data.merge({"unlocked":3,"next_mission":3,"credits":27,"upgrades":[3,2,3],"run_score":12400,"high_score":19500,"run_lives":5,"pow_ready":true,"power":"laser","aircraft":1,"difficulty":2,"records":{"1":{"score":1200,"grade":3,"rank":"A","best_chain":17}},"bindings":{"fire":4194306},"arcade_records":{"1-1-2":7300}},true)
	old.data.settings.music = .42
	var legacy: Dictionary = old.data.duplicate(true)
	for key in ["equipment_revision","owned_modules","equipped_modules"]: legacy.erase(key)
	write_json(fixture,legacy)
	var migrated = fresh()
	check(migrated.load_profile(),"Legacy equipment-less profile loads")
	check(migrated.data.equipment_revision==1 and migrated.data.owned_modules.is_empty() and migrated.data.equipped_modules.is_empty(),"Independent revision adds empty module inventory")
	for key in legacy:
		check(migrated.data[key]==legacy[key],"Legacy field preserved: "+key)
	near(float(LOADOUT.stats(migrated.data).projectile_damage),1.9,"Legacy rank III remains active below the new sector gate")
	check(not migrated.can_buy_upgrade(1),"Legacy rank II can be used but next rank still gated")
	for reload_count in range(2):
		check(migrated.save()==OK,"Migration save %d" % reload_count)
		var next = fresh()
		check(next.load_profile() and next.data==migrated.data and next.data.credits==27,"Migration reload %d does not refund or reset anything" % reload_count)
		migrated = next
	# Optional partial equipment fields may be from an interrupted older rollout.
	for fields in [{"equipment_revision":0},{"owned_modules":["precision"]},{"equipped_modules":["precision"]},{"equipment_revision":1,"owned_modules":["precision"],"equipped_modules":[]}]:
		var partial: Dictionary = legacy.duplicate(true)
		partial.merge(fields,true)
		write_json(fixture,partial)
		check(migrated.load_profile() and migrated.data.equipment_revision==1 and migrated.data.upgrades==[3,2,3] and migrated.data.credits==27,"Partial revision preserves legacy progress: "+JSON.stringify(fields))
	var complete: Dictionary = old.data.duplicate(true)
	complete.unlocked = 32
	complete.next_mission = 32
	complete.owned_modules = ["precision","plates","reserve"]
	complete.equipped_modules = ["precision","plates"]
	var malformed_candidates := [{"equipment_revision":{}},{"equipment_revision":2},{"owned_modules":{}},{"owned_modules":["precision",2]},{"equipped_modules":"precision"},{"equipped_modules":[{}]}]
	for invalid_option in ["true",1,[],null]:
		var settings: Dictionary = complete.settings.duplicate(true)
		settings.short_retry_intro = invalid_option
		malformed_candidates.append({"settings":settings})
	for malformed in malformed_candidates:
		clean()
		var bad: Dictionary = complete.duplicate(true)
		bad.credits = 199
		bad.merge(malformed,true)
		write_json(fixture,bad)
		write_json(fixture+".bak",complete)
		var backup_text := FileAccess.get_file_as_string(fixture+".bak")
		var recovered = fresh()
		check(recovered.load_profile() and recovered.data.credits==27 and recovered.data.upgrades==[3,2,3] and recovered.data.equipped_modules==["precision","plates"],"Wrong equipment types reject entire candidate and recover backup: "+JSON.stringify(malformed))
		check(recovered.save()==OK and FileAccess.get_file_as_string(fixture+".bak")==backup_text,"Repair preserves valid equipment backup")
		for reload_count in range(2):
			var next = fresh()
			check(next.load_profile() and next.data==recovered.data,"Recovered equipment survives reload %d" % reload_count)
	# Semantic unknown identifiers are harmless; malformed types above are atomic.
	var semantic: Dictionary = complete.duplicate(true)
	semantic.owned_modules = ["unknown","precision","precision","coverage","plates","reserve"]
	semantic.equipped_modules = ["unknown","precision","coverage","plates","reserve","precision"]
	write_json(fixture,semantic)
	check(migrated.load_profile() and migrated.data.owned_modules==["precision","coverage","plates","reserve"] and migrated.data.equipped_modules==["precision","plates"],"Decode removes unknown/duplicate ids, excludes same family and caps slots")
	semantic.unlocked = 5
	semantic.next_mission = 5
	write_json(fixture,semantic)
	check(migrated.load_profile() and migrated.data.equipped_modules==["precision"] and migrated.data.owned_modules.size()==4,"Lower slot capacity preserves ownership but limits equipped effects")
	clean()

func test_stats() -> void:
	var profile = fresh()
	var speeds := [12.0,14.0,10.4]
	var intervals := [.090,.100,.110]
	var damages := [1.0,1.25,1.55,1.9]
	var dps_factors := [1.0,1.3,1.674,2.128]
	for aircraft in range(3):
		profile.data.aircraft = aircraft
		for rank in range(4):
			profile.data.upgrades = [rank,rank,rank]
			var stats := LOADOUT.stats(profile.data)
			near(stats.speed,speeds[aircraft],"Aircraft mobility does not drift with armament")
			near(stats.projectile_damage,damages[rank],"Authored fractional damage rank %d" % rank)
			near(stats.standard_dps,2.0/intervals[aircraft]*dps_factors[rank],"Smooth actual standard output aircraft %d rank %d" % [aircraft,rank])
			near(stats.sustained_laser_dps,2.7/intervals[aircraft]*dps_factors[rank],"Laser gets every armament rank aircraft %d rank %d" % [aircraft,rank])
			check(stats.max_health==([2,2,3][aircraft]+rank) and stats.bombs==[2,2,3][aircraft],"Authored armor and bomb tradeoffs")
			near(stats.charge_kill,5.0+rank,"Capacitor rank applied once")
			near(stats.charge_passive,1.8,"Capacitor keeps passive base charge")
			var next_dps: float = LOADOUT.stats({"aircraft":aircraft,"upgrades":[mini(3,rank+1),0,0]}).standard_dps
			check(next_dps/stats.standard_dps<=1.300001,"No rank doubles fire output")
	profile.data.unlocked = 32
	profile.data.upgrades = [0,0,0]
	profile.data.owned_modules = LOADOUT.modules().map(func(item): return item.id)
	profile.data.aircraft = 0
	var base := LOADOUT.stats(profile.data)
	for id in profile.data.owned_modules:
		profile.data.equipped_modules = [id]
		var stats := LOADOUT.stats(profile.data)
		match id:
			"precision":
				near(stats.standard_dps,24.44444444,"Precision fire gain")
				near(stats.spread_multiplier,.8,"Precision narrows real spread")
				near(stats.laser_width_multiplier,.8,"Precision narrows real laser")
			"coverage":
				near(stats.standard_dps,20.0,"Coverage fire sacrifice")
				near(stats.spread_multiplier,1.3,"Coverage widens real spread")
				near(stats.laser_width_multiplier,1.3,"Coverage widens real laser")
			"plates":
				check(stats.max_health==3,"Plates add one armor")
				near(stats.speed,11.04,"Plates mobility cost")
			"agile":
				near(stats.speed,12.96,"Agile mobility gain")
				near(stats.hit_invulnerability_multiplier,.75,"Agile vulnerability cost")
			"yield":
				near(stats.charge_kill,6.0,"Yield charge per kill gain")
				near(stats.charge_passive,1.35,"Yield passive recharge cost")
			"reserve":
				near(stats.charge_kill,4.0,"Reserve kill charge cost")
				near(stats.charge_passive,2.52,"Reserve passive gain")
			"payload":
				check(stats.bombs==3,"Payload extra bomb")
				near(stats.charge_kill,5.0/.88,"Payload shortens active recharge time")
				near(stats.charge_passive,1.8/.88,"Payload shortens passive recharge time")
			"prepared":
				check(stats.bombs==1 and stats.initial_charge==25.0,"Prepared trades a bomb for immediate charge")
			"endurance":
				near(stats.ability_duration,6.25,"Endurance duration gain")
				near(stats.strike_damage,20.0,"Endurance initial impact cost")
			"impact":
				near(stats.ability_duration,3.75,"Impact duration cost")
				near(stats.strike_damage,30.0,"Impact initial damage gain")
		near(stats.projectile_damage,base.projectile_damage,"Modules never quietly add permanent damage")
	profile.data.equipped_modules = ["precision","plates"]
	var combined := LOADOUT.stats(profile.data)
	near(combined.standard_dps,24.44444444,"Different module families combine fire effects")
	near(combined.speed,11.04,"Different module families combine mobility effects")
	check(combined.max_health==3,"Different module families combine armor effects")
	var immutable: Dictionary = profile.data.duplicate(true)
	var corsair := LOADOUT.stats(profile.data,2)
	check(profile.data==immutable and corsair.bombs==3 and corsair.max_health==4,"Hangar comparison override cannot mutate selected aircraft")
	profile.data.equipped_modules = ["precision","coverage","plates","reserve","unknown"]
	check(LOADOUT.stats(profile.data)==combined,"Direct combat stats cannot stack competing or over-capacity modules")
	for aircraft in range(3):
		profile.data.equipped_modules = []
		var stats := LOADOUT.stats(profile.data,aircraft)
		near(stats.ability_duration,[5.0,4.0,3.5][aircraft],"Distinct ability durations")
		near(stats.ability_rate_multiplier,[1.5,1.0,1.0][aircraft],"Distinct ability rate multiplier")
		near(stats.ability_speed_multiplier,[1.0,1.3,1.0][aircraft],"Distinct ability speed multiplier")
		near(stats.ability_damage_multiplier,[1.0,1.35,1.2][aircraft],"Damage ability works as a multiplier for all weapons")
		near(stats.strike_damage,[25.0,45.0,85.0][aircraft],"Distinct strike impact preserved")
		check(stats.strike_focused==(aircraft!=2),"Corsair retains wide strike identity")

func test_all_legal_builds() -> void:
	var data: Dictionary = fresh().data.duplicate(true)
	data.unlocked = 32
	data.owned_modules = LOADOUT.modules().map(func(item): return item.id)
	var builds: Array[Array] = [[]]
	for first in LOADOUT.modules():
		builds.append([first.id])
		for second in LOADOUT.modules():
			if first.id<second.id and first.family!=second.family:
				builds.append([first.id,second.id])
	check(builds.size()==39,"Exactly 39 legal none/single/pair selections across three families")
	for aircraft in range(3):
		data.aircraft = aircraft
		for armament in range(4):
			for build in builds:
				data.equipped_modules = build
				data.upgrades = [armament,0,0]
				var reference := LOADOUT.stats(data)
				for armor in range(4):
					for capacitor in range(4):
						data.upgrades = [armament,armor,capacitor]
						var stats := LOADOUT.stats(data)
						var label := "Aircraft %d ranks %s %s" % [aircraft,str(data.upgrades),str(build)]
						check(LOADOUT.equipped_modules(data)==build,label+": valid selection retained")
						check(stats.max_health>=2 and stats.bombs>=1 and stats.bombs<=4,label+": armor and bomb capacity remain valid")
						check(stats.speed>9.0 and stats.speed<16.0 and stats.shot_interval>.06,label+": base maneuver and fire budgets remain bounded")
						check(stats.projectile_damage>=1.0 and stats.projectile_damage<=1.9 and stats.charge_kill>0 and stats.charge_passive>0,label+": no permanent damage stacking or stalled charge")
						near(stats.standard_dps/stats.sustained_laser_dps,2.0/2.7,label+": laser and cannon progression remain proportionate")
						check(stats.projectile_damage==reference.projectile_damage and stats.shot_interval==reference.shot_interval and stats.laser_interval_multiplier==reference.laser_interval_multiplier,label+": armor and capacitor cannot change weapon rank")
						check(stats.max_health==reference.max_health+armor and stats.speed==reference.speed,label+": only armor rank changes hull, without changing mobility")
						near(stats.charge_kill,reference.charge_kill*(5.0+capacitor)/5.0,label+": capacitor rank affects kill charge independently")
						check(stats.charge_passive==reference.charge_passive and stats.ability_duration==reference.ability_duration,label+": permanent ranks do not silently change passive recharge or ability duration")

func _run() -> void:
	test_catalogue()
	test_purchases()
	test_module_access()
	test_medal_improvements()
	simulate_economy("bronze",[1],96)
	simulate_economy("argent",[2],128)
	simulate_economy("or",[3],160)
	simulate_economy("mixte",[1,2,3,2],128)
	test_migrations()
	test_stats()
	test_all_legal_builds()
	clean()
	var report := {"checks":checks,"failures":failures,"economy":economy,"equipment_configurations":7488,"configuration_scope":"3 aircraft x 64 independent upgrade triples x 39 legal module selections; repeated assertions, not human playthroughs","human_viability":"NOT_TESTED"}
	var output := FileAccess.open("res://tests/loadout-profile-results.json",FileAccess.WRITE)
	if output!=null: output.store_string(JSON.stringify(report,"\t")); output.close()
	print("LOADOUT PROFILE TEST ",checks," checks, ",failures.size()," failures: ",failures)
	quit(0 if failures.is_empty() else 1)
