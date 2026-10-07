extends RefCounted
const ASSETS := "res://assets/campaign/carrier-ui/"
const GOLD := Color("e2c383")
const WHITE := Color("e6eceb")
const MUTED := Color("a8bcc4")
const PLANES := ["vanguard", "interceptor", "bulwark"]
const COMMANDS := preload("res://scripts/campaign/command_labels.gd")
const LOADOUT := preload("res://scripts/campaign/loadout.gd")
const RULES := preload("res://scripts/campaign/scoring_rules.gd")

func backdrop(app: Control, kind: String) -> void:
	app.background.texture = load(ASSETS+kind+".png")
	app.shade.color = Color(.015,.025,.035,.30)
	# Local opaque panels carry text; most of the room remains visible.
	var header := panel(app,Rect2(68,42,1758 if kind == "briefing" else 1190,153),.80)
	app.design.move_child(header,0)
	var transition := app.create_tween()
	app.design.modulate.a = .0
	transition.tween_property(app.design,"modulate:a",1.0,.22)

func panel(app: Control, rect: Rect2, opacity := .90, selected := false) -> Panel:
	var p := Panel.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.position = rect.position
	p.size = rect.size
	var style := StyleBoxFlat.new()
	style.bg_color = Color(.025,.055,.070,opacity)
	style.border_color = GOLD if selected else Color(.32,.42,.43,.7)
	style.set_border_width_all(2 if selected else 1)
	style.set_corner_radius_all(7)
	style.shadow_color = Color(0,0,0,.35)
	style.shadow_size = 12
	p.add_theme_stylebox_override("panel",style)
	app.design.add_child(p)
	return p

func image(app: Control, asset: String, rect: Rect2) -> TextureRect:
	var view := TextureRect.new()
	view.texture = load(ASSETS+asset)
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.position = rect.position
	view.size = rect.size
	app.design.add_child(view)
	return view

func text(app: Control, value: String, pos: Vector2, size: Vector2, pixels := 24, color := WHITE) -> void:
	app._label(value,pos,size,pixels,color)

func bar(app: Control, pos: Vector2, amount: float, color: Color) -> void:
	for i in range(8):
		var part := ColorRect.new()
		part.mouse_filter = Control.MOUSE_FILTER_IGNORE
		part.position = pos+Vector2(i*19,0)
		part.size = Vector2(15,6)
		part.color = color if i < roundi(amount*8) else Color("2b414b")
		app.design.add_child(part)

func named_text(app: Control, name: String, value: String, pos: Vector2, dimensions: Vector2, pixels := 24, color := WHITE) -> Label:
	var label: Label = app._label(value,pos,dimensions,pixels,color)
	label.name = name
	app._fit_label(label,dimensions.y,maxi(18,pixels-2))
	return label

func compact_button(app: Control, name: String, value: String, rect: Rect2, action: Callable, disabled := false) -> Button:
	var button: Button = app._button(value,rect.position,rect.size,action,disabled)
	button.name = name
	button.add_theme_font_size_override("font_size",22)
	for state in ["normal","hover","pressed","focus","disabled"]:
		var style := button.get_theme_stylebox(state).duplicate() as StyleBoxFlat
		style.content_margin_top = 6
		style.content_margin_bottom = 6
		button.add_theme_stylebox_override(state,style)
	return button

func _rank_name(rank: int) -> String:
	return ["0","I","II","III"][clampi(rank,0,3)]

func _upgrade_copy(app: Control, index: int) -> String:
	var rank: int = app.profile.data.upgrades[index]
	if index==0:
		var data: Dictionary = app.profile.data.duplicate(true)
		data.equipped_modules = []
		data.upgrades = [0,0,0]
		var base: Dictionary = LOADOUT.stats(data)
		data.upgrades[0] = rank
		var current: Dictionary = LOADOUT.stats(data)
		return "Dégâts ×%.2f  •  Débit ×%.2f\nRangs conservés ; aucun POW requis." % [float(current.projectile_damage)/float(base.projectile_damage),float(base.shot_interval)/float(current.shot_interval)]
	if index==1: return "+%d points de blindage acquis.\nProchain rang : +1 point." % rank if rank<3 else "+3 points de blindage acquis.\nProtection après impact inchangée."
	var baseline: Dictionary = app.profile.data.duplicate(true)
	baseline.equipped_modules = []
	baseline.upgrades = [0,0,0]
	baseline.upgrades[2] = rank
	var current: Dictionary = LOADOUT.stats(baseline)
	return "Charge : %.0f / destruction\nRecharge passive : %.1f / seconde" % [float(current.charge_kill),float(current.charge_passive)]

func _ability_copy(stats: Dictionary) -> String:
	var effect := "cadence ×%.2f" % float(stats.ability_rate_multiplier)
	if stats.ability_label=="Poursuite": effect = "vitesse ×%.2f • dégâts ×%.2f" % [float(stats.ability_speed_multiplier),float(stats.ability_damage_multiplier)]
	if stats.ability_label=="Bastion": effect = "protection • dégâts ×%.2f" % float(stats.ability_damage_multiplier)
	return "%s · %.1f s · %s" % [str(stats.ability_label).to_upper(),float(stats.ability_duration),effect]

func hangar(app: Control) -> void:
	backdrop(app,"hangar")
	panel(app,Rect2(1425,60,400,125),.85)
	text(app,"RÉSERVE DE L'ESCADRILLE",Vector2(1450,77),Vector2(350,30),22,GOLD)
	text(app,"%03d  PIÈCES" % app.profile.data.credits,Vector2(1450,111),Vector2(350,60),38)
	for i in range(3):
		var x := 94.0+i*580
		var selected: bool = app.profile.data.aircraft == i
		var aircraft: Dictionary = LOADOUT.aircraft(i)
		var stats: Dictionary = LOADOUT.stats(app.profile.data,i)
		panel(app,Rect2(x,270,550,415),.89,selected).name = "AircraftPanel_%d" % i
		named_text(app,"AircraftRole_%d" % i,"0%d  /  %s" % [i+1,str(aircraft.model_label).to_upper()],Vector2(x+24,286),Vector2(500,26),19,GOLD)
		named_text(app,"AircraftName_%d" % i,str(aircraft.label).to_upper()+"  /  "+str(aircraft.role).to_upper(),Vector2(x+24,315),Vector2(500,42),31)
		image(app,PLANES[i]+".png",Rect2(x+20,355,510,144))
		named_text(app,"AircraftStats_%d" % i,"VITESSE %.1f   •   BLINDAGE %d   •   FEU %.1f DPS" % [float(stats.speed),int(stats.max_health),float(stats.standard_dps)],Vector2(x+24,506),Vector2(500,29),22)
		named_text(app,"AircraftAmmo_%d" % i,"%.2f SALVES/S   •   %d BOMBES   •   LASER %.1f DPS" % [float(stats.shot_rate),int(stats.bombs),float(stats.sustained_laser_dps)],Vector2(x+24,540),Vector2(500,26),20,MUTED)
		named_text(app,"AircraftTradeoff_%d" % i,str(aircraft.tradeoff),Vector2(x+24,574),Vector2(500,45),22,MUTED)
		compact_button(app,"SelectAircraft_%d" % i,"EN SERVICE" if selected else "AFFECTER CET APPAREIL",Rect2(x+22,632,506,40),app._select_aircraft.bind(i))
	var equipped: Dictionary = LOADOUT.stats(app.profile.data)
	panel(app,Rect2(94,689,1730,38),.94).name = "HangarCommandPanel"
	var commands: Label = app._label("CAPACITÉ  %s (clavier / manette)  /  %s" % [COMMANDS.hint("strike"),_ability_copy(equipped)],Vector2(94,692),Vector2(1730,32),23,GOLD)
	commands.name = "HangarCommands"
	app._fit_label(commands,32,21)
	var names := ["ARMEMENT","BLINDAGE","CONDENSATEUR"]
	var icons := ["armament","armor","charge"]
	for i in range(3):
		var x := 94.0+i*580
		var rank: int = app.profile.data.upgrades[i]
		panel(app,Rect2(x,738,550,189),.94).name = "UpgradePanel_%d" % i
		image(app,icons[i]+".svg",Rect2(x+22,761,64,64))
		named_text(app,"UpgradeName_%d" % i,names[i]+"  /  "+_rank_name(rank)+" / III",Vector2(x+108,748),Vector2(415,35),27,GOLD)
		var copy := _upgrade_copy(app,i)
		if rank>0 and int(app.profile.data.unlocked)<LOADOUT.rank_required_mission(rank): copy = "Rang acquis conservé et actif.\n"+copy.get_slice("\n",0)
		named_text(app,"UpgradeDetails_%d" % i,copy,Vector2(x+108,790),Vector2(415,62),23,MUTED)
		var cost: int = app.profile.upgrade_cost(i)
		var required: int = app.profile.upgrade_required_mission(i)
		var caption := "RANG MAXIMUM" if rank>=3 else ("MISSION %02d  /  RANG %s" % [required,_rank_name(rank+1)] if int(app.profile.data.unlocked)<required else "RANG %s  /  %d PIÈCES" % [_rank_name(rank+1),cost])
		compact_button(app,"BuyUpgrade_%d" % i,caption,Rect2(x+22,871,506,42),app._buy.bind(i),not app.profile.can_buy_upgrade(i))
	app._button("RETOUR AU BRIEFING",Vector2(94,946),Vector2(420,55),app._show_briefing.bind(app.selected_mission)).name = "HangarBriefing"
	app._button("MODULES & ÉQUIPEMENT",Vector2(539,946),Vector2(510,55),app._show_modules).name = "HangarModules"
	app._button("ACCUEIL",Vector2(1074,946),Vector2(240,55),app._show_main)

func modules(app: Control) -> void:
	backdrop(app,"hangar")
	panel(app,Rect2(1425,60,400,125),.85)
	text(app,"RÉSERVE DE L'ESCADRILLE",Vector2(1450,77),Vector2(350,30),22,GOLD)
	text(app,"%03d  PIÈCES" % app.profile.data.credits,Vector2(1450,111),Vector2(350,60),38)
	var access := [5,13,17,25,29]
	var tabs := ["VISÉE","CELLULE","ÉNERGIE","SOUTE","CAPACITÉ"]
	for i in range(5):
		var selected: bool = app.module_group==i
		var button := compact_button(app,"ModuleTab_%d" % i,("◆  " if selected else "")+tabs[i]+"  /  M%02d" % access[i],Rect2(94+i*351,260,326,52),app._show_modules.bind(i))
		if selected: button.add_theme_color_override("font_color",WHITE)
	panel(app,Rect2(94,338,535,589),.94).name = "EquipmentPanel"
	named_text(app,"EquipmentTitle","APPAREIL ÉQUIPÉ",Vector2(118,355),Vector2(487,32),25,GOLD)
	image(app,PLANES[app.profile.data.aircraft]+".png",Rect2(115,399,490,126))
	var stats: Dictionary = LOADOUT.stats(app.profile.data)
	named_text(app,"EquipmentStats","%s  /  SANS POW\nVitesse %.1f  •  Blindage %d\nFeu %.1f DPS  •  %.2f salves/s\nLaser %.1f DPS  •  %d bombes" % [app.PROFILE.AIRCRAFT[app.profile.data.aircraft].to_upper(),float(stats.speed),int(stats.max_health),float(stats.standard_dps),float(stats.shot_rate),float(stats.sustained_laser_dps),int(stats.bombs)],Vector2(118,543),Vector2(487,140),25)
	var equipped: Array = app.profile.data.equipped_modules
	var slots: int = app.profile.module_slots()
	for slot in range(2):
		var y := 710+slot*102
		panel(app,Rect2(118,y,487,92),.90,slot<equipped.size()).name = "ModuleSlot_%d" % slot
		var label := "EMPLACEMENT %d  /  " % (slot+1)
		var detail := "VIDE — choisissez un module possédé."
		if slot>=slots: detail = "DISPONIBLE MISSION %02d" % (5 if slot==0 else 13)
		if slot<equipped.size():
			var module: Dictionary = LOADOUT.module_info(str(equipped[slot]))
			label += str(module.label).to_upper()
			detail = str(module.family_label)+" — module actif"
			compact_button(app,"RemoveModule_%d" % slot,"RETIRER",Rect2(463,y+46,123,32),app._equip_module.bind(str(module.id)))
		named_text(app,"ModuleSlotName_%d" % slot,label,Vector2(133,y+10),Vector2(452,28),22,GOLD if slot<slots else MUTED)
		named_text(app,"ModuleSlotState_%d" % slot,detail,Vector2(133,y+48),Vector2(319 if slot<equipped.size() else 452,29),20,MUTED)
	var candidates: Array = []
	for module in LOADOUT.modules():
		if int(module.required_mission)==access[app.module_group]: candidates.append(module)
	for i in range(candidates.size()):
		var module: Dictionary = candidates[i]
		var id := str(module.id)
		var x := 660+i*592
		var owned: bool = id in app.profile.data.owned_modules
		var active: bool = id in equipped
		var unlocked: bool = int(app.profile.data.unlocked)>=int(module.required_mission)
		panel(app,Rect2(x,338,565,589),.94,active).name = "ModulePanel_"+id
		image(app,"modules/"+id+".svg",Rect2(x+24,365,70,70)).name = "ModuleIcon_"+id
		named_text(app,"ModuleName_"+id,str(module.label).to_upper(),Vector2(x+115,367),Vector2(426,40),31,GOLD)
		named_text(app,"ModuleFamily_"+id,str(module.family_label).to_upper()+"  /  MISSION %02d" % int(module.required_mission),Vector2(x+24,457),Vector2(517,32),23,MUTED)
		named_text(app,"ModuleDescription_"+id,str(module.description),Vector2(x+24,516),Vector2(517,154),28)
		var instructions := "Un module par famille. Retirez d'abord\nle module de cette famille s'il est actif."
		if int(app.profile.data.unlocked)<5: instructions = "Premier emplacement : mission 05.\nAucun module requis pour décoller."
		elif slots<2: instructions = "Second emplacement : mission 13.\nAucun module requis pour décoller."
		named_text(app,"ModuleInstructions_"+id,instructions,Vector2(x+24,699),Vector2(517,70),23,MUTED)
		var purchase := "ACQUIS  /  CHANGEMENT GRATUIT" if owned else ("MISSION %02d REQUISE" % int(module.required_mission) if not unlocked else "ACQUÉRIR  /  %d PIÈCES" % int(module.cost))
		compact_button(app,"BuyModule_"+id,purchase,Rect2(x+24,806,517,44),app._buy_module.bind(id),not app.profile.can_buy_module(id))
		var equip_caption := "RETIRER DU SERVICE" if active else "ÉQUIPER CE MODULE"
		if owned and not active and not app.profile.can_equip_module(id): equip_caption = "LIBÉREZ UN EMPLACEMENT / FAMILLE"
		compact_button(app,"EquipModule_"+id,equip_caption,Rect2(x+24,866,517,44),app._equip_module.bind(id),not app.profile.can_equip_module(id))
	app._button("RETOUR AU HANGAR",Vector2(94,946),Vector2(420,55),app._show_hangar).name = "ModulesHangar"
	app._button("RETOUR AU BRIEFING",Vector2(539,946),Vector2(420,55),app._show_briefing.bind(app.selected_mission))

func briefing(app: Control, mission: Dictionary) -> void:
	backdrop(app,"briefing")
	panel(app,Rect2(94,290,1010,280),.81)
	var chart := preload("res://scripts/campaign/tactical_chart.gd").new()
	chart.name = "MissionChart"
	chart.position = Vector2(112,307)
	chart.size = Vector2(974,245)
	chart.sector = int(mission.sector)
	chart.boss = mission.boss != ""
	chart.ground = mission.get("ground_assault",false)
	app.design.add_child(chart)
	var order_panel := panel(app,Rect2(94,594,1010,314),.94)
	order_panel.name = "MissionOrderPanel"
	image(app,"objective.svg",Rect2(120,618,54,54))
	text(app,"ORDRE DE MISSION",Vector2(194,616),Vector2(840,35),26,GOLD)
	var orders: Label = app._label(mission.briefing,Vector2(194,668),Vector2(866,220),27,WHITE)
	orders.name = "MissionOrderText"
	var info_panel := panel(app,Rect2(1140,290,685,618),.93)
	info_panel.name = "MissionInfoPanel"
	image(app,"pilot.svg",Rect2(1164,308,38,38))
	text(app,"VOTRE APPAREIL  /  "+app.PROFILE.AIRCRAFT[app.profile.data.aircraft].to_upper(),Vector2(1214,308),Vector2(582,37),25,GOLD)
	image(app,PLANES[app.profile.data.aircraft]+".png",Rect2(1170,345,610,135))
	text(app,"DIFFICULTÉ  "+app.PROFILE.DIFFICULTIES[app.profile.data.difficulty].to_upper()+"   •   SECTEUR %02d" % (int(mission.sector)+1),Vector2(1170,491),Vector2(625,35),23,MUTED)
	image(app,"objective.svg",Rect2(1170,545,42,42))
	var primary := "Détruire le commandant du secteur." if mission.boss!="" else "Rejoindre le point de sortie en vie."
	if mission.objective=="ground": primary = "Détruire %d installations, puis revenir au porte-avions." % int(mission.quota)
	text(app,primary,Vector2(1230,545),Vector2(555,60),25)
	image(app,"medal.svg",Rect2(1170,615,42,42))
	var mastery := "Abattre %d adversaires." % int(mission.quota)
	if mission.objective == "strike": mastery = "Couler %d navires." % int(mission.quota)
	if mission.objective == "ground": mastery = "Détruire %d cibles terrestres." % int(mission.quota)
	if mission.boss != "": mastery = "Détruire le boss."
	text(app,"OR  /  Aucune vie perdue • %d impacts maximum" % RULES.GOLD_MAX_HITS,Vector2(1230,612),Vector2(555,32),23,GOLD)
	text(app,mastery,Vector2(1230,648),Vector2(555,32),23,MUTED)
	text(app,"BONUS : "+preload("res://scripts/campaign/operations.gd").objective_text(mission.get("secondary","formation")),Vector2(1170,687),Vector2(625,32),20,GOLD)
	text(app,"COMMANDES  /  CLAVIER · MANETTE",Vector2(1170,726),Vector2(625,27),19,GOLD)
	var commands: Label = app._label(COMMANDS.flight_guide(),Vector2(1170,759),Vector2(625,136),21,MUTED)
	commands.name = "FlightCommands"
	app._fit_label(commands,136,19)
	app._button("DÉCOLLER",Vector2(94,946),Vector2(420,55),app._launch.bind(int(mission.id)))
	app._button("HANGAR",Vector2(539,946),Vector2(270,55),app._show_hangar)
	app._button("CARTE DES MISSIONS",Vector2(834,946),Vector2(330,55),app._show_missions)
	app._button("GUIDE DE SCORE",Vector2(1189,946),Vector2(420,55),app._show_rules.bind("briefing")).name = "BriefingRules"

func scoring_guide(app: Control) -> void:
	backdrop(app,"briefing")
	panel(app,Rect2(94,286,1010,629),.96).name = "ScoreGuideMainPanel"
	panel(app,Rect2(1140,286,685,629),.96).name = "ScoreGuideChainPanel"
	var sections: PackedStringArray = RULES.guide().split("\n\n")
	named_text(app,"ScoreGuideMain",sections[0]+"\n\n"+sections[1],Vector2(123,310),Vector2(952,580),29)
	named_text(app,"ScoreGuideChain",sections[2],Vector2(1170,310),Vector2(625,580),29)

func scoring_criteria(app: Control, report: Dictionary) -> void:
	backdrop(app,"briefing")
	panel(app,Rect2(94,286,830,629),.96).name = "MedalCriteriaPanel"
	panel(app,Rect2(955,286,870,629),.96).name = "RankCriteriaPanel"
	image(app,"medal.svg",Rect2(122,310,60,60))
	named_text(app,"MedalCriteriaTitle","MÉDAILLE OR  /  EXIGENCES",Vector2(203,316),Vector2(685,43),32,GOLD)
	named_text(app,"MedalObtained","OBTENUE : "+["AUCUNE","BRONZE","ARGENT","OR"][int(report.get("grade",0))],Vector2(124,397),Vector2(762,40),29)
	named_text(app,"MedalCriteria",RULES.criteria_text(RULES.medal_checks(3,report)),Vector2(124,469),Vector2(762,333),29)
	image(app,"pilot.svg",Rect2(983,310,60,60))
	named_text(app,"RankCriteriaTitle","RANG S  /  EXIGENCES",Vector2(1064,316),Vector2(733,43),32,GOLD)
	named_text(app,"RankObtained","OBTENU : "+str(report.get("rank","D")),Vector2(985,397),Vector2(800,40),29)
	named_text(app,"RankCriteria",RULES.criteria_text(RULES.rank_checks("S",report)),Vector2(985,469),Vector2(800,333),29)
	var final_line: String = RULES.guide().split("\n")[-1]
	named_text(app,"CriteriaDifference",final_line,Vector2(124,831),Vector2(762,58),25,MUTED)
	named_text(app,"CriteriaMode","Aucun record ni récompense en entraînement." if app.play_mode=="practice" else ("Arcade : record de score uniquement." if app.play_mode=="arcade" else "Le quota principal et l'objectif secondaire sont distincts."),Vector2(985,831),Vector2(800,58),25,MUTED)
