extends RefCounted
## Single equipment catalogue shared by profile, hangar and actual combat.
## These functions are pure: they never mutate a save or charge the player.
const EQUIPMENT_REVISION := 1
const DAMAGE_RANKS := [1.0,1.25,1.55,1.9]
const RATE_RANKS := [1.0,1.04,1.08,1.12]
const UPGRADE_COSTS := [2,4,6]
const UPGRADE_MISSIONS := [1,9,21]
const BASE_LASER_INTERVAL := .100
const BASE_LASER_DAMAGE := 3.0
const AIRCRAFT := [
	{"id":"vanguard","label":"Vanguard","role":"Feu soutenu","description":"Le meilleur débit de feu, une mobilité et un blindage équilibrés.","tradeoff":"Plus puissant en tir continu ; moins agile que le P-38, moins robuste que le Corsair.","speed":12.0,"max_health":2,"bombs":2,"shot_interval":.090,"ability_label":"Surcharge","ability_description":"Cadence ×1,50 pendant 5 s ; frappe ciblée.","ability_duration":5.0,"ability_speed_multiplier":1.0,"ability_damage_multiplier":1.0,"ability_rate_multiplier":1.5,"strike_damage":25.0,"strike_focused":true},
	{"id":"interceptor","label":"Interceptor","role":"Mobilité","description":"P-38 Lightning : vitesse accrue, canons espacés pour conserver une couverture équitable.","tradeoff":"Vitesse +16,7 % et DPS −10 % face au Vanguard ; même blindage et même hitbox.","speed":14.0,"max_health":2,"bombs":2,"shot_interval":.100,"ability_label":"Poursuite","ability_description":"Vitesse ×1,30 et dégâts ×1,35 pendant 4 s ; frappe ciblée.","ability_duration":4.0,"ability_speed_multiplier":1.3,"ability_damage_multiplier":1.35,"ability_rate_multiplier":1.0,"strike_damage":45.0,"strike_focused":true},
	{"id":"bulwark","label":"Bulwark","role":"Résistance","description":"F4U Corsair : un point de blindage et une bombe supplémentaires.","tradeoff":"Plus robuste ; vitesse −13,3 % et DPS −18,2 % face au Vanguard.","speed":10.4,"max_health":3,"bombs":3,"shot_interval":.110,"ability_label":"Bastion","ability_description":"Protection et dégâts ×1,20 pendant 3,5 s ; frappe large.","ability_duration":3.5,"ability_speed_multiplier":1.0,"ability_damage_multiplier":1.2,"ability_rate_multiplier":1.0,"strike_damage":85.0,"strike_focused":false}
]
const MODULES := [
	{"id":"precision","label":"Précision","family":"aim","family_label":"Visée","cost":6,"required_mission":5,"description":"Débit +10 % ; éventail et largeur laser −20 %. L'écartement du tir standard reste identique.","modifiers":{"rate":1.1,"spread":.8,"laser_width":.8}},
	{"id":"coverage","label":"Couverture","family":"aim","family_label":"Visée","cost":6,"required_mission":5,"description":"Éventail et largeur laser +30 % ; débit −10 %.","modifiers":{"rate":.9,"spread":1.3,"laser_width":1.3}},
	{"id":"plates","label":"Plaques","family":"airframe","family_label":"Cellule","cost":6,"required_mission":13,"description":"Blindage +1 ; vitesse −8 %.","modifiers":{"max_health":1,"speed":.92}},
	{"id":"agile","label":"Aile vive","family":"airframe","family_label":"Cellule","cost":6,"required_mission":13,"description":"Vitesse +8 % ; protection après impact −25 %.","modifiers":{"speed":1.08,"hit_invulnerability":.75}},
	{"id":"yield","label":"Rendement","family":"systems","family_label":"Systèmes","cost":6,"required_mission":17,"description":"Charge par destruction +20 % ; recharge passive −25 %.","modifiers":{"charge_kill":1.2,"charge_passive":.75}},
	{"id":"reserve","label":"Réserve","family":"systems","family_label":"Systèmes","cost":6,"required_mission":17,"description":"Recharge passive +40 % ; charge par destruction −20 %.","modifiers":{"charge_passive":1.4,"charge_kill":.8}},
	{"id":"payload","label":"Soute","family":"systems","family_label":"Systèmes","cost":6,"required_mission":25,"description":"Une bombe supplémentaire ; temps de recharge de frappe −12 %.","modifiers":{"bombs":1,"charge_time":.88}},
	{"id":"prepared","label":"Préparation","family":"systems","family_label":"Systèmes","cost":6,"required_mission":25,"description":"Charge initiale +25 ; une bombe en moins.","modifiers":{"initial_charge":25.0,"bombs":-1}},
	{"id":"endurance","label":"Endurance","family":"systems","family_label":"Systèmes","cost":6,"required_mission":29,"description":"Durée de capacité +25 % ; dégâts de frappe −20 %.","modifiers":{"ability_duration":1.25,"strike_damage":.8}},
	{"id":"impact","label":"Impact","family":"systems","family_label":"Systèmes","cost":6,"required_mission":29,"description":"Dégâts de frappe +20 % ; durée de capacité −25 %.","modifiers":{"strike_damage":1.2,"ability_duration":.75}}
]

static func aircraft(index: int) -> Dictionary:
	var bounded := clampi(index,0,AIRCRAFT.size()-1)
	var result: Dictionary = AIRCRAFT[bounded].duplicate(true)
	result.name = result.label
	result.model_label = ["Chasseur polyvalent","Lockheed P-38 Lightning","Chance Vought F4U Corsair"][bounded]
	return result

static func modules() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in MODULES:
		var item: Dictionary = entry.duplicate(true)
		item.name = item.label
		item.unlock_mission = item.required_mission
		result.append(item)
	return result

static func module_info(id: String) -> Dictionary:
	for entry in modules():
		if entry.id == id: return entry
	return {}

static func rank_required_mission(rank: int) -> int:
	return UPGRADE_MISSIONS[rank-1] if rank>=1 and rank<=3 else 0

static func upgrade_cost(rank: int) -> int:
	return UPGRADE_COSTS[rank-1] if rank>=1 and rank<=3 else 0

static func module_slots(data: Dictionary) -> int:
	var unlocked := int(data.get("unlocked",1))
	return 2 if unlocked>=13 else (1 if unlocked>=5 else 0)

static func equipped_modules(data: Dictionary) -> Array[String]:
	# The same bounded selection is used during decode and in combat. A malformed
	# direct caller cannot stack unknown, unowned or mutually exclusive modules.
	var result: Array[String] = []
	var families: Array[String] = []
	var owned: Array = data.get("owned_modules",[])
	for id in data.get("equipped_modules",[]):
		if id is not String or id not in owned or id in result: continue
		var item := module_info(id)
		if item.is_empty() or item.family in families: continue
		if result.size()>=module_slots(data): break
		result.append(id)
		families.append(item.family)
	return result

static func stats(data: Dictionary, aircraft_index: int = -1) -> Dictionary:
	var plane := aircraft(int(data.get("aircraft",0)) if aircraft_index<0 else aircraft_index)
	var upgrades: Array = data.get("upgrades",[0,0,0])
	var armament := clampi(int(upgrades[0]),0,3)
	var armor := clampi(int(upgrades[1]),0,3)
	var capacitor := clampi(int(upgrades[2]),0,3)
	var result := {
		"speed":float(plane.speed),"max_health":int(plane.max_health)+armor,
		"bombs":int(plane.bombs),"shot_interval":float(plane.shot_interval),
		"projectile_damage":float(DAMAGE_RANKS[armament]),
		"laser_interval_multiplier":float(plane.shot_interval)/.090,
		"spread_multiplier":1.0,"laser_width_multiplier":1.0,
		"hit_invulnerability_multiplier":1.0,
		"ability_duration":float(plane.ability_duration),
		"ability_speed_multiplier":float(plane.ability_speed_multiplier),
		"ability_damage_multiplier":float(plane.ability_damage_multiplier),
		"ability_rate_multiplier":float(plane.ability_rate_multiplier),
		"strike_damage":float(plane.strike_damage),"strike_focused":bool(plane.strike_focused),
		"charge_kill":5.0+capacitor,"charge_passive":1.8,"initial_charge":0.0,
		"ability_label":str(plane.ability_label)
	}
	var rate := float(RATE_RANKS[armament])
	for id in equipped_modules(data):
		var mod: Dictionary = module_info(id).modifiers
		rate *= float(mod.get("rate",1.0))
		result.speed *= float(mod.get("speed",1.0))
		result.max_health += int(mod.get("max_health",0))
		result.bombs += int(mod.get("bombs",0))
		result.spread_multiplier *= float(mod.get("spread",1.0))
		result.laser_width_multiplier *= float(mod.get("laser_width",1.0))
		result.hit_invulnerability_multiplier *= float(mod.get("hit_invulnerability",1.0))
		result.charge_kill *= float(mod.get("charge_kill",1.0))/float(mod.get("charge_time",1.0))
		result.charge_passive *= float(mod.get("charge_passive",1.0))/float(mod.get("charge_time",1.0))
		result.initial_charge += float(mod.get("initial_charge",0.0))
		result.ability_duration *= float(mod.get("ability_duration",1.0))
		result.strike_damage *= float(mod.get("strike_damage",1.0))
	result.shot_interval /= rate
	result.laser_interval_multiplier /= rate
	result.shot_rate = 1.0/result.shot_interval
	result.standard_dps = 2.0*result.projectile_damage/result.shot_interval
	result.sustained_laser_dps = BASE_LASER_DAMAGE*result.projectile_damage/(BASE_LASER_INTERVAL*result.laser_interval_multiplier)
	return result
