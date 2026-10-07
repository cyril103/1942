extends RefCounted
## Authored encounter preparation and shared raid objective metadata.
## Encounter mechanics, altitude gates and rendering remain with their actors.
const RAID_LAYOUTS := preload("res://scripts/campaign/raid_layouts.gd")
const ACTS := [
	["PATROUILLE DU LAGON", "INTERCEPTION", "BRISER LE BLOCUS", "RETOUR AU PONT"],
	["RECONNAISSANCE", "CHASSE AUX TORPILLEURS", "LE CONVOI", "SORTIE DU DÉTROIT"],
	["FRONT ORAGEUX", "CONTACTS DANS LA PLUIE", "ZONE DE TURBULENCE", "ÉCLAIRCIE"],
	["CÔTE DE JADE", "DÉFENSES CÔTIÈRES", "FRAPPE SUR LE PORT", "EXTRACTION"],
	["CENDRES VOLCANIQUES", "RAID À BASSE ALTITUDE", "BARRAGE NAVAL", "SORTIE DU CRATÈRE"],
	["PATROUILLE DU SOIR", "CHASSE AUX AS", "DERNIÈRE LUMIÈRE", "CAP AU LARGE"],
	["MER DE GLACE", "INTERCEPTION POLAIRE", "LIGNE DE DÉFENSE", "PASSAGE DU NORD"],
	["DERNIÈRE OFFENSIVE", "ESCORTE IMPÉRIALE", "BRISER LA CITADELLE", "L'AUBE DU PACIFIQUE"]
]
const RADIO := ["Tour : ciel dégagé. Gardez vos bombes pour les urgences.", "Contrôle : contacts rapides. Les chasseurs vont croiser votre route.", "Commandement : cible prioritaire en approche. Concentrez le feu.", "Tour : vous tenez le secteur. Préparez le retour au porte-avions."]
const RAID_TITLES := ["Opération Coupe-Circuit", "Les réservoirs de Mako", "Silence radar", "La piste de Jade", "Le dépôt des cendres", "Raid au crépuscule", "La station boréale", "L'arsenal impérial"]
const OCEAN_PLANS := [
	{"id": "coral-reading", "teaching": "Suivez les formations rouges pour obtenir un POW, puis déplacez-vous après les amorces de tir.", "roles": ["escort", "escort", "interceptor", "escort"], "kinds": ["zero", "zero", "hayabusa", "zero"], "patterns": [0, 1, 0, 1], "breathers": [[.26, 4.0]]},
	{"id": "convoy-priority", "teaching": "Pendant l'escorte, les bombardiers visent le convoi : interceptez-les avant de poursuivre les chasseurs.", "roles": ["escort", "gunner", "escort", "interceptor"], "kinds": ["zero", "zero", "hayabusa", "zero"], "patterns": [1, 0, 1, 0], "breathers": [[.26, 4.0], [.69, 3.0]]},
	{"id": "storm-prediction", "teaching": "Les intercepteurs anticipent votre mouvement ; changez d'axe après leur amorce, entre les passages latéraux.", "roles": ["interceptor", "escort", "interceptor", "gunner"], "kinds": ["hayabusa", "zero", "hayabusa", "zero"], "patterns": [0, 1, 1, 0], "breathers": [[.26, 4.0], [.52, 2.4]]},
	{"id": "jade-side-pairs", "teaching": "Deux vagues latérales précèdent les arrivées de face : traversez après leur passage, puis concentrez votre tir.", "roles": ["gunner", "escort", "interceptor", "escort"], "kinds": ["hayabusa", "hayabusa", "zero", "zero"], "patterns": [1, 0, 1, 0], "breathers": [[.26, 4.0], [.56, 3.6]]},
	{"id": "volcanic-pursuit", "teaching": "Poursuivez les cibles rapides dans leurs virages ; contre les intercepteurs, changez de direction après l'amorce.", "roles": ["interceptor", "gunner", "escort", "interceptor"], "kinds": ["hayabusa", "zero", "zero", "hayabusa"], "patterns": [0, 1, 0, 1], "breathers": [[.26, 4.0], [.62, 2.8]]},
	{"id": "dusk-locked-lanes", "teaching": "Les tireurs lents décalent leur visée et les intercepteurs la prédisent : quittez l'axe annoncé avant la rafale.", "roles": ["gunner", "interceptor", "gunner", "escort"], "kinds": ["zero", "hayabusa", "zero", "zero"], "patterns": [1, 0, 0, 1], "breathers": [[.26, 4.0], [.45, 3.0]]},
	{"id": "arctic-reserve", "teaching": "Gardez une bombe pour l'interception suivante et exploitez les intervalles entre vagues pour vous replacer.", "roles": ["escort", "gunner", "interceptor", "escort"], "kinds": ["zero", "zero", "hayabusa", "hayabusa"], "patterns": [0, 1, 1, 0], "breathers": [[.26, 4.0], [.70, 3.4]]},
	{"id": "final-combination", "teaching": "Alternez poursuite et déplacement entre les passages latéraux, les tireurs lents et les intercepteurs prédictifs.", "roles": ["interceptor", "gunner", "escort", "interceptor", "gunner", "escort"], "kinds": ["hayabusa", "zero", "hayabusa", "zero", "zero", "hayabusa"], "patterns": [0, 1, 1, 0, 0, 1], "breathers": [[.26, 4.0], [.49, 2.0], [.74, 2.4]]}
]
const BOSS_TEACHING := {
	"bomber": "Visez ses deux moteurs : chaque point faible réduit l'éventail central.",
	"destroyer": "Détruisez ses tourelles de flanc pour supprimer leurs tirs.",
	"squadron": "Neutralisez ses points faibles entre les renforcements de l'escadre.",
	"fortress": "Replacez-vous au changement de phase, puis attaquez les points faibles entre les balayages.",
	"battleship": "Concentrez le feu sur un flanc pour supprimer ses tirs, puis ouvrez le second.",
	"ace": "Suivez l'as pendant ses traversées ; ses points faibles réduisent l'éventail central.",
	"carrier": "Priorisez les points faibles du porte-avions ; ses renforts restent actifs.",
	"citadel": "Replacez-vous au changement de phase ; neutralisez les points faibles avant les balayages suivants."
}

static func prepare(source: Dictionary) -> Dictionary:
	# Existing ocean actors, quotas, boss kinds, HP and opening boss remain.
	# Author roles, entry kinds and recovery timing, using only
	# behavior already consumed by the current director/combat/boss scripts.
	# This function still copies its input, preserving the historical interface.
	var m := source.duplicate(true)
	if int(m.id) == 1:
		m.title = "Opération Brise-Lames"
		m.briefing = "Ouvrez la route de l’escadrille. Interceptez les chasseurs, éliminez les formations rouges puis neutralisez le bombardier de commandement. Ses moteurs sont ses points faibles."
		m.duration = 105
		m.boss = "bomber"
		m.boss_health_scale = .58
		m.events.append_array([{"time": 64.0, "kind": "naval", "pattern": 1}, {"time": 72.0, "kind": "red", "pattern": 0}, {"time": 81.0, "kind": "boss", "variant": "bomber"}])
	var sector := int(m.sector)
	m.acts = []
	for i in range(4):
		m.acts.append({"time": float(m.duration) * [0.0, .26, .55, .82][i], "title": ACTS[sector][i], "radio": RADIO[i]})
	var boundary := float(m.duration) * .26
	var shifted := 0
	for e in m.events:
		if e.kind in ["zero", "hayabusa"] and float(e.time) >= boundary and float(e.time) < boundary + 4:
			e.time = boundary + 4 + shifted * 2.2
			shifted += 1
		if e.kind in ["zero", "hayabusa"]:
			e.role = "interceptor" if int(e.get("pattern", 0)) % 3 == 0 else "escort"
			if int(m.id) > 4 and int(e.get("pattern", 0)) % 3 == 2:
				e.role = "gunner"
	m.events.sort_custom(func(a, b): return float(a.time) < float(b.time))
	m.secondary = ["formation", "bomber", "naval", "boss"][int(m.id - 1) % 4]
	m.secondary_target = 1 if m.secondary in ["formation", "boss"] else (2 if m.secondary == "naval" else 1)
	if int(m.id) in [6, 10, 14, 18, 22, 26, 30]:
		m.secondary = "convoy"
		m.secondary_target = 1
	if m.secondary == "naval" and not m.events.any(func(e): return e.kind == "naval"):
		m.events.append({"time": float(m.duration) * .55, "kind": "naval", "pattern": 1})
		m.events.sort_custom(func(a, b): return float(a.time) < float(b.time))
	if int(m.id) in [3, 7, 11, 15, 19, 23, 27, 31]:
		_prepare_ground_raid(m)
	else:
		_prepare_ocean_identity(m)
	return m

static func _prepare_ocean_identity(m: Dictionary) -> void:
	var sector := int(m.sector)
	var plan: Dictionary = OCEAN_PLANS[sector]
	m.teaching = str(plan.teaching)
	# A convoy-priority instruction is shown only when a convoy truly spawns.
	if sector == 1 and m.secondary != "convoy":
		m.teaching = "Interceptez le bombardier pendant ses traversées ; profitez des arrivées espacées pour ouvrir la route maritime."
	m.tactical_signature = str(plan.id) + " : " + str(m.teaching)
	m.boss_teaching = str(BOSS_TEACHING.get(str(m.boss), ""))
	m.overlay_warnings = []
	m.breathing_windows = []
	for authored in plan.breathers:
		var start := float(m.duration) * float(authored[0])
		m.breathing_windows.append({"start": start, "end": start + float(authored[1]), "scope": "standard_fighter_entries_only"})
	var wave_index := 0
	for event in m.events:
		if event.kind not in ["zero", "hayabusa"]:
			continue
		event.kind = plan.kinds[wave_index % plan.kinds.size()]
		event.role = plan.roles[wave_index % plan.roles.size()]
		# Only the two actual Zero parity profiles are claimed. Hayabusa patterns
		# do not currently alter paths; its kind and role are what change play.
		event.pattern = int(plan.patterns[wave_index % plan.patterns.size()])
		wave_index += 1
	if m.secondary == "convoy":
		# Director already spawns one bomber with the convoy. Reuse the existing
		# scheduled bomber inside its 32-second escort window, without adding one.
		# spawn_bomber's one-active-bomber cap can suppress this second request if
		# the first bomber survived: a firing threat already exists in that case.
		var pressure_at: float = float(m.duration) * .26 + float([8.0, 8.0, 9.0, 7.5, 10.0, 8.0, 9.0, 7.0][sector])
		for event in m.events:
			if event.kind == "bomber":
				event.time = pressure_at
				event.encounter_note = "Existing bomber request inside the real convoy escort window; bounded active cap preserved"
				break
		m.convoy_pressure_at = pressure_at
		if sector != 1:
			m.teaching += " En escorte, les bombardiers prennent le convoi pour cible."
		m.tactical_signature = str(plan.id) + " : " + str(m.teaching)
	m.events.sort_custom(func(a, b): return float(a.time) < float(b.time))
	var previous := -100.0
	for event in m.events:
		if event.kind not in ["zero", "hayabusa"]:
			continue
		var at := maxf(float(event.time), previous + 1.2)
		# Move the existing entry, never queue a burst at the end of a recovery.
		for window in m.breathing_windows:
			if at >= float(window.start) and at < float(window.end):
				at = float(window.end)
		event.time = at
		previous = at
		if at >= float(m.duration) - .5:
			m.overlay_warnings.append("Authored fighter entry exceeds its mission time budget")
	m.events.sort_custom(func(a, b): return float(a.time) < float(b.time))
	m.encounter_overlay = {"id": plan.id, "fighters": wave_index, "roles": plan.roles.duplicate(), "kinds": plan.kinds.duplicate(), "patterns": plan.patterns.duplicate()}
	m.briefing = str(m.briefing).strip_edges() + " " + str(m.teaching)
	if not str(m.boss_teaching).is_empty() and not str(m.briefing).contains(str(m.boss_teaching)):
		m.briefing += " " + str(m.boss_teaching)
	# Do not overwrite the real convoy act: director uses act_index==1 to spawn
	# the friendly vessel and its initial bomber, regardless of this radio text.
	for act_index in [0, 2]:
		m.acts[act_index].radio = "Contrôle : " + (str(m.teaching) if act_index == 0 else (str(m.boss_teaching) if not str(m.boss_teaching).is_empty() else str(m.teaching)))

static func _prepare_ground_raid(m: Dictionary) -> void:
	var sector := int(m.sector)
	var layout := RAID_LAYOUTS.layout_for_sector(sector)
	if layout.is_empty():
		push_error("Missing ground layout for sector %d" % sector)
		return
	m.ground_assault = true
	m.title = RAID_TITLES[sector]
	m.objective = "ground"
	m.raid_layout_id = str(layout.id)
	m.raid_layout_version = int(layout.version)
	m.raid_tactic = str(layout.signature)
	m.raid_learning = str(layout.learning)
	m.teaching = str(layout.learning)
	m.tactical_signature = str(layout.id) + " : " + str(layout.signature)
	m.ground_count = layout.targets.size()
	m.quota = int(layout.quota)
	m.priority_ids = layout.priority_ids.duplicate()
	m.radar_groups = layout.radar_groups.duplicate(true)
	m.ground_composition = {"battery": 0, "bunker": 0, "fuel": 0, "radar": 0, "runway": 0}
	m.mobile_count = 0
	for target in layout.targets:
		m.ground_composition[target.variant] += 1
		if bool(target.mobile):
			m.mobile_count += 1
	m.radar_count = int(m.ground_composition.radar)
	# Compatibility data only, never a substitute for the actual side objective.
	m.secondary_radar_target = int(layout.secondary_radar_target)
	m.secondary_spec = layout.secondary_spec.duplicate(true)
	m.secondary = str(m.secondary_spec.kind)
	m.secondary_target = int(m.secondary_spec.minimum)
	m.secondary_ids = m.secondary_spec.target_ids.duplicate()
	m.secondary_label = str(m.secondary_spec.label)
	m.primary_text = _primary_ground_text(layout)
	m.secondary_text = str(m.secondary_spec.label)
	m.radar_text = _radar_ground_text(layout)
	var priorities := _priority_clause(layout)
	m.briefing = "Survolez les patrouilles en mer, puis descendez sous les nuages : seule la DCA tire au sol. Objectif : %d installations%s. %s %s Rejoignez ensuite le porte-avions." % [int(layout.quota), priorities, str(layout.learning), m.radar_text]
	m.acts = [
		{"time": 0.0, "title": "APPROCHE MARITIME", "radio": "Contrôle : patrouilles ennemies entre vous et la côte. Ouvrez le passage !"},
		{"time": 12.0, "title": "DESCENTE TACTIQUE", "radio": "Leader : vol rasant, la DCA prend le relais. " + str(layout.learning)},
		{"time": float(m.duration) * .49, "title": str(layout.title).to_upper(), "radio": "Contrôle : " + str(layout.signature)},
		{"time": float(m.duration) - 17.0, "title": "EXTRACTION VERS LA MER", "radio": "Tour : reprenez de l'altitude. Des chasseurs couvrent le retour : forcez le passage vers le porte-avions !"}
	]
	# These are the same four real approach encounters as in phase 3. The raid
	# still owns the altitude gate; return interceptions remain director-driven.
	m.events = [
		{"time": 1.0, "kind": "zero", "pattern": sector, "role": "escort"},
		{"time": 4.5, "kind": "bomber", "pattern": 0},
		{"time": 6.0, "kind": "hayabusa", "pattern": sector + 1, "role": "interceptor"},
		{"time": 9.0, "kind": "zero", "pattern": sector + 2, "role": "escort"}
	]
	m.boss = ""

static func _priority_clause(layout: Dictionary) -> String:
	var required: Array = layout.priority_ids
	if required.is_empty():
		return ""
	var variants := {}
	var mobile_count := 0
	var tags := {}
	for target in layout.targets:
		if target.id not in required:
			continue
		variants[target.variant] = int(variants.get(target.variant, 0)) + 1
		tags[str(target.priority_tag)] = true
		if bool(target.mobile):
			mobile_count += 1
	if tags.has("command_bunker") and required.size() == 1:
		return ", dont le bunker de commandement"
	if tags.has("western_bastion") and tags.has("eastern_bastion") and required.size() == 2:
		return ", dont les bastions Est et Ouest"
	if mobile_count == required.size():
		return ", dont les %d DCA mobiles d'ouverture" % mobile_count
	var labels: Array[String] = []
	var names := {"battery": ["DCA", "DCA"], "bunker": ["bunker", "bunkers"], "fuel": ["dépôt", "dépôts"], "radar": ["radar", "radars"], "runway": ["hangar", "hangars"]}
	for variant in ["battery", "bunker", "fuel", "radar", "runway"]:
		var count := int(variants.get(variant, 0))
		if count == 1:
			labels.append("le %s prioritaire" % str(names[variant][0]))
		elif count > 1:
			labels.append("les %d %s prioritaires" % [count, str(names[variant][1])])
	return ", dont " + " et ".join(labels)

static func _primary_ground_text(layout: Dictionary) -> String:
	return "Détruire au moins %d installations%s, puis revenir au porte-avions." % [int(layout.quota), _priority_clause(layout)]

static func _radar_ground_text(layout: Dictionary) -> String:
	var global_scope := false
	for group in layout.radar_groups.values():
		global_scope = global_scope or bool(group.get("global", false))
	var seconds := ("%.1f" % float(RAID_LAYOUTS.JAM_SECONDS)).replace(".", ",").trim_suffix(",0")
	return ("Les radars brouillent toute la DCA pendant %s s." if global_scope else "Chaque radar brouille uniquement son réseau pendant %s s.") % seconds

static func primary_text(mission: Dictionary) -> String:
	if mission.get("ground_assault", false):
		return str(mission.get("primary_text", "Détruire les installations prioritaires et revenir au porte-avions."))
	return ""

static func secondary_text(mission: Dictionary) -> String:
	return objective_text(str(mission.get("secondary", "formation")), mission)

static func objective_text(kind: String, mission: Dictionary = {}) -> String:
	# The original one-argument API remains usable for all historical kinds.
	# A generic ground-layout label cannot honestly encode eight different goals;
	# new consumers pass mission or read mission.secondary_text instead.
	if kind == "ground_layout":
		return str(mission.get("secondary_label", "Accomplir l'objectif tactique du raid"))
	return {"formation": "Détruire une escadrille rouge complète", "bomber": "Intercepter un bombardier", "naval": "Couler deux navires", "boss": "Neutraliser les deux points faibles du boss", "convoy": "Protéger le convoi pendant 32 secondes", "radar": "Détruire les deux stations radar"}.get(kind, "")

# Implemented here: metadata/text from eight authored layouts;
# sector-specific roles, existing fighter kinds and recovery entry windows;
# convoy pressure using existing bomber requests; actual boss component advice.
# Ocean overlays do not increase quotas/HP or add events, except M01's existing
# phase 3 additions. Ground quotas are explicitly authored in the catalogue.
# It does not create aerial radar, a new boss phase or invulnerability.
# Actor/target mechanics, terrain and HUD consume these data elsewhere.
# No human difficulty/pleasure validation or frame-time result follows from
# this catalogue. No aerial radar network exists or is described by M09.
