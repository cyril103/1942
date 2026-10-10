extends RefCounted
## One source for scoring decisions and the explanations shown to the pilot.
const CHAIN_SECONDS := 4.5
const CHAIN_STEP := 8
const MAX_MULTIPLIER := 5
const SECONDARY_BONUS := 2500
const S_MAX_HITS := 1
const S_CHAIN := 16
const GOLD_MAX_HITS := 2

static func _criterion(label: String, passed: bool) -> Dictionary:
	return {"label":label,"passed":passed}

static func _all_passed(criteria: Array) -> bool:
	for criterion in criteria:
		if not criterion.passed: return false
	return true

static func rank_checks(target: String, report: Dictionary) -> Array:
	var rows := [_criterion("Victoire",bool(report.get("won",false)))]
	var deaths := int(report.get("deaths",0))
	match target:
		"S":
			rows.append(_criterion("Aucune vie perdue",deaths==0))
			rows.append(_criterion("Au plus %d impact" % S_MAX_HITS,int(report.get("damage",0))<=S_MAX_HITS))
			rows.append(_criterion("Objectif secondaire accompli",bool(report.get("secondary",false))))
			rows.append(_criterion("Meilleure chaîne d'au moins %d" % S_CHAIN,int(report.get("best_chain",0))>=S_CHAIN))
		"A":
			rows.append(_criterion("Aucune vie perdue",deaths==0))
			rows.append(_criterion("Objectif secondaire accompli",bool(report.get("secondary",false))))
		"B": rows.append(_criterion("Au plus une vie perdue",deaths<=1))
		"C": pass
		_: return [_criterion("Défaite",not bool(report.get("won",false)))]
	return rows

static func medal_checks(target: int, report: Dictionary) -> Array:
	var rows := [_criterion("Victoire",bool(report.get("won",false)))]
	if target>=2: rows.append(_criterion("Aucune vie perdue",int(report.get("deaths",0))==0))
	if target>=3:
		rows.append(_criterion("Au plus %d impacts" % GOLD_MAX_HITS,int(report.get("damage",0))<=GOLD_MAX_HITS))
		rows.append(_criterion("Objectif principal accompli",bool(report.get("objective_met",false))))
	return rows

static func rank(won: bool, deaths: int, damage: int, secondary: bool, best_chain: int) -> String:
	var report := {"won":won,"deaths":deaths,"damage":damage,"secondary":secondary,"best_chain":best_chain}
	for target in ["S","A","B","C"]:
		if _all_passed(rank_checks(target,report)): return target
	return "D"

static func medal(won: bool, deaths: int, damage: int, objective_met: bool) -> int:
	var report := {"won":won,"deaths":deaths,"damage":damage,"objective_met":objective_met}
	for target in [3,2,1]:
		if _all_passed(medal_checks(target,report)): return target
	return 0

static func chain_multiplier(chain: int) -> int:
	return mini(MAX_MULTIPLIER,1+chain/CHAIN_STEP)

static func criteria_text(rows: Array) -> String:
	var text := ""
	for row in rows:
		text += ("✓ " if row.passed else "À atteindre : ")+str(row.label)+"\n"
	return text.strip_edges()

static func guide() -> String:
	return "MÉDAILLE — RÉCOMPENSE DE CAMPAGNE\nBronze : victoire. Argent : victoire sans vie perdue.\nOr : victoire, aucune vie perdue, au plus %d impacts et objectif principal accompli.\n\nRANG — MAÎTRISE DU PILOTAGE\nS : victoire, aucune vie perdue, au plus %d impact, objectif secondaire et chaîne ≥ %d.\nA : victoire sans vie perdue avec l'objectif secondaire.\nB : victoire avec au plus une vie perdue. C : autre victoire. D : défaite.\n\nCHAÎNE — SCORE EN COMBAT\nDétruire à nouveau en %.1f secondes maintient la chaîne.\nMultiplicateur +1 tous les %d ennemis, jusqu'à ×%d. Un impact rompt la chaîne.\nObjectif secondaire : +%d points, une seule fois.\nVague parfaite : +100 par chasseur (+800 pour huit).\nEscadrille rouge complète : +1000 et un POW.\nUn avion échappé annule le bonus de vague.\nLa médaille et le rang évaluent des critères différents." % [GOLD_MAX_HITS,S_MAX_HITS,S_CHAIN,CHAIN_SECONDS,CHAIN_STEP,MAX_MULTIPLIER,SECONDARY_BONUS]
