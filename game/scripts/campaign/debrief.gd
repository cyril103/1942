extends RefCounted
## Explain observed results, never invent accuracy/kill attribution or alter rewards.
const L10N := preload("res://scripts/campaign/localization.gd")
const RULES := preload("res://scripts/campaign/scoring_rules.gd")

static func coaching(report: Dictionary) -> Array[Dictionary]:
	var advice: Array[Dictionary] = []
	var ground: Dictionary = report.get("ground_status",{})
	if bool(report.get("objective_failed",false)) or (not ground.is_empty() and not bool(ground.get("main_met",true))):
		advice.append({"title":L10N.text("PRIORITÉ À LA MISSION"),"body":L10N.text("Le quota et les cibles prioritaires doivent être accomplis ensemble. Repérez les objectifs dans le briefing et attaquez-les avant leur sortie de l'écran.") if not ground.is_empty() else L10N.text("Repérez le quota demandé dans le briefing. Concentrez vos tirs sur les cibles de l'objectif avant le retour au porte-avions.")})
	if int(report.get("damage",0))>RULES.S_MAX_HITS or int(report.get("deaths",0))>0:
		advice.append({"title":L10N.text("OUVRIR UNE ISSUE"),"body":L10N.text("Relâchez les grands déplacements avec le vol de précision. Une bombe efface les projectiles et offre une brève protection : utilisez-la avant d'être encerclé.")})
	if not bool(report.get("secondary",false)):
		advice.append({"title":L10N.text("CHASSER LE RANG A"),"body":L10N.text("L'objectif secondaire est nécessaire aux rangs A et S. Consultez sa condition au briefing ; un score élevé seul ne le remplace pas.")})
	if int(report.get("best_chain",0))<RULES.S_CHAIN:
		advice.append({"title":L10N.text("RELIER LES DESTRUCTIONS"),"body":L10N.text("Une destruction en moins de 4,5 secondes prolonge la chaîne. Visez une chaîne de 16 pour le rang S et gardez une cible accessible pour le passage suivant.")})
	if advice.is_empty():
		if bool(report.get("won",false)):
			advice.append({"title":L10N.text("UNE SORTIE DE MAÎTRISE"),"body":L10N.text("Les conditions du rang S sont réunies. Affinez votre route pour conserver une longue chaîne ; les frôlements ajoutent des points sans prolonger celle-ci.")})
		else:
			advice.append({"title":L10N.text("PRIORITÉ À LA MISSION"),"body":L10N.text("Repérez le quota demandé dans le briefing. Concentrez vos tirs sur les cibles de l'objectif avant le retour au porte-avions.")})
	return advice.slice(0,2)

static func next_rank(report: Dictionary) -> String:
	var rank := str(report.get("rank","D"))
	return {"D":"C","C":"B","B":"A","A":"S","S":"S"}.get(rank,"C")

static func time_text(seconds: float) -> String:
	var value := maxi(0,int(seconds))
	return "%02d:%02d" % [value/60,value%60]

static func score_delta(report: Dictionary, previous: int) -> String:
	if previous<=0: return L10N.text("AUCUN RECORD PRÉCÉDENT")
	var delta := int(report.get("mission_score",report.get("score",0)))-previous
	return L10N.text("ÉCART AU RECORD PRÉCÉDENT  %s%d") % ["+" if delta>=0 else "",delta]
