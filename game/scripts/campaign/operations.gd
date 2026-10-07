extends RefCounted
## Authored pacing overlays: preserved encounter schedules, deliberate breathing windows.
const ACTS := [
	["PATROUILLE DU LAGON","INTERCEPTION","BRISER LE BLOCUS","RETOUR AU PONT"],
	["RECONNAISSANCE","CHASSE AUX TORPILLEURS","LE CONVOI","SORTIE DU DÉTROIT"],
	["FRONT ORAGEUX","CONTACTS DANS LA PLUIE","ZONE DE TURBULENCE","ÉCLAIRCIE"],
	["CÔTE DE JADE","DÉFENSES CÔTIÈRES","FRAPPE SUR LE PORT","EXTRACTION"],
	["CENDRES VOLCANIQUES","RAID À BASSE ALTITUDE","BARRAGE NAVAL","SORTIE DU CRATÈRE"],
	["PATROUILLE DU SOIR","CHASSE AUX AS","DERNIÈRE LUMIÈRE","CAP AU LARGE"],
	["MER DE GLACE","INTERCEPTION POLAIRE","LIGNE DE DÉFENSE","PASSAGE DU NORD"],
	["DERNIÈRE OFFENSIVE","ESCORTE IMPÉRIALE","BRISER LA CITADELLE","L'AUBE DU PACIFIQUE"]]
const RADIO := ["Tour : ciel dégagé. Gardez vos bombes pour les urgences.","Contrôle : contacts rapides. Les chasseurs vont croiser votre route.","Commandement : cible prioritaire en approche. Concentrez le feu.","Tour : vous tenez le secteur. Préparez le retour au porte-avions."]

static func prepare(source: Dictionary) -> Dictionary:
	var m := source.duplicate(true)
	if int(m.id)==1:
		m.title = "Opération Brise-Lames"
		m.briefing = "Ouvrez la route de l’escadrille. Interceptez les chasseurs, éliminez les formations rouges puis neutralisez le bombardier de commandement. Ses moteurs sont ses points faibles."
		m.duration = 105
		m.boss = "bomber"
		m.boss_health_scale = .58
		m.events.append_array([{"time":64.0,"kind":"naval","pattern":1},{"time":72.0,"kind":"red","pattern":0},{"time":81.0,"kind":"boss","variant":"bomber"}])
	var sector := int(m.sector)
	m.acts = []
	for i in range(4):
		m.acts.append({"time":float(m.duration)*[0.0,.26,.55,.82][i],"title":ACTS[sector][i],"radio":RADIO[i]})
	# Deliberate four-second breath at the first act transition; no burst on resume.
	var boundary := float(m.duration)*.26
	var shifted := 0
	for e in m.events:
		if e.kind in ["zero","hayabusa"] and float(e.time)>=boundary and float(e.time)<boundary+4:
			e.time = boundary+4+shifted*2.2
			shifted += 1
		if e.kind in ["zero","hayabusa"]:
			e.role = "interceptor" if int(e.get("pattern",0))%3==0 else "escort"
			if int(m.id)>4 and int(e.get("pattern",0))%3==2: e.role = "gunner"
	m.events.sort_custom(func(a,b): return float(a.time)<float(b.time))
	m.secondary = ["formation","bomber","naval","boss"][int(m.id-1)%4]
	m.secondary_target = 1 if m.secondary in ["formation","boss"] else (2 if m.secondary=="naval" else 1)
	if int(m.id) in [6,10,14,18,22,26,30]:
		m.secondary = "convoy"
		m.secondary_target = 1
	if m.secondary=="naval" and not m.events.any(func(e): return e.kind=="naval"):
		m.events.append({"time":float(m.duration)*.55,"kind":"naval","pattern":1})
		m.events.sort_custom(func(a,b): return float(a.time)<float(b.time))
	if int(m.id) in [3,7,11,15,19,23,27,31]: _prepare_ground_raid(m)
	return m

static func _prepare_ground_raid(m: Dictionary) -> void:
	var sector := int(m.sector)
	m.ground_assault = true
	m.title = ["Opération Coupe-Circuit","Les réservoirs de Mako","Silence radar","La piste de Jade","Le dépôt des cendres","Raid au crépuscule","La station boréale","L'arsenal impérial"][sector]
	m.objective = "ground"
	m.quota = 12+sector*2
	m.ground_count = 30+mini(sector,3)*5
	m.secondary = "radar"
	m.secondary_target = 2
	m.briefing = "Traversez les patrouilles au-dessus de l'océan, puis plongez sous les nuages : les chasseurs restent en altitude. Détruisez au moins %d installations sous le feu croisé des canons rapides et des bunkers. Les radars brouillent la DCA pendant 6 secondes ; les dépôts fragilisent les défenses voisines. Des POW récompensent vos destructions. Rejoignez ensuite le porte-avions." % int(m.quota)
	m.acts = [
		{"time":0.0,"title":"APPROCHE MARITIME","radio":"Contrôle : patrouilles ennemies entre vous et la côte. Ouvrez le passage !"},
		{"time":12.0,"title":"DESCENTE TACTIQUE","radio":"Leader : cap sur la côte. À la descente, laissez les chasseurs en altitude. Attention au feu croisé de la DCA !"},
		{"time":float(m.duration)*.49,"title":"FRAPPER LES INSTALLATIONS","radio":"Contrôle : neutralisez les radars pour couper le guidage de la DCA. Visez les dépôts groupés."},
		{"time":float(m.duration)-17.0,"title":"EXTRACTION VERS LA MER","radio":"Tour : reprenez de l'altitude. Des chasseurs couvrent le retour : forcez le passage vers le porte-avions !"}]
	# A short aerial approach, then the altitude gate hands the battle to the DCA.
	# The director schedules a fresh interception once the return climb is over;
	# no missed approach event is held over for the ground phase or the landing.
	m.events = [
		{"time":1.0,"kind":"zero","pattern":sector,"role":"escort"},
		{"time":4.5,"kind":"bomber","pattern":0},
		{"time":6.0,"kind":"hayabusa","pattern":sector+1,"role":"interceptor"},
		{"time":9.0,"kind":"zero","pattern":sector+2,"role":"escort"}]
	m.boss = ""

static func objective_text(kind: String) -> String:
	return {"formation":"Détruire une escadrille rouge complète","bomber":"Intercepter un bombardier","naval":"Couler deux navires","boss":"Neutraliser les deux points faibles du boss","convoy":"Protéger le convoi pendant 32 secondes","radar":"Détruire les deux stations radar"}.get(kind,"")
