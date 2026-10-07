extends RefCounted
const ASSETS := "res://assets/campaign/carrier-ui/"
const GOLD := Color("e2c383")
const WHITE := Color("e6eceb")
const MUTED := Color("a8bcc4")
const PLANES := ["vanguard", "interceptor", "bulwark"]
const COMMANDS := preload("res://scripts/campaign/command_labels.gd")

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

func hangar(app: Control) -> void:
	backdrop(app,"hangar")
	panel(app,Rect2(1425,60,400,125),.85)
	text(app,"RÉSERVE DE L'ESCADRILLE",Vector2(1450,77),Vector2(350,30),22,GOLD)
	text(app,"%03d  PIÈCES" % app.profile.data.credits,Vector2(1450,111),Vector2(350,60),38)
	var roles := ["POLYVALENT", "LOCKHEED P-38 LIGHTNING", "CHANCE VOUGHT F4U CORSAIR"]
	var speeds := [12.0,14.0,10.4]
	var intervals := [.105,.09,.12]
	for i in range(3):
		var x := 94.0+i*580
		var selected: bool = app.profile.data.aircraft == i
		panel(app,Rect2(x,285,550,382),.82,selected)
		text(app,"0%d  /  %s" % [i+1,roles[i]],Vector2(x+24,304),Vector2(420,28),19,GOLD)
		text(app,app.PROFILE.AIRCRAFT[i].to_upper(),Vector2(x+24,335),Vector2(490,48),36)
		image(app,PLANES[i]+".png",Rect2(x+20,371,510,180))
		var hull: int = [2,2,3][i]+int(app.profile.data.upgrades[1])
		var rate: float = 1.0/(intervals[i]*(1.0-.06*int(app.profile.data.upgrades[0])))
		text(app,"VITESSE  %.1f" % speeds[i],Vector2(x+24,546),Vector2(160,30),21)
		text(app,"BLINDAGE  %d" % hull,Vector2(x+205,546),Vector2(150,30),21)
		text(app,"TIR  %.1f/s" % rate,Vector2(x+380,546),Vector2(160,30),21)
		bar(app,Vector2(x+24,579),speeds[i]/14.0,Color("7fdce3"))
		bar(app,Vector2(x+205,579),float(hull)/6,GOLD)
		bar(app,Vector2(x+380,579),rate/14.0,Color("7fdce3"))
		app._button("EN SERVICE" if selected else "AFFECTER CET APPAREIL",Vector2(x+22,603),Vector2(506,38),app._select_aircraft.bind(i))
	var commands: Label = app._label("FRAPPE  %s (clavier / manette)  :  SURCHARGE (VANGUARD)  /  POURSUITE (P-38)  /  BASTION (CORSAIR)" % COMMANDS.hint("strike"),Vector2(94,680),Vector2(1730,34),23,GOLD)
	commands.name = "HangarCommands"
	var names := ["ARMEMENT","BLINDAGE","CONDENSATEUR"]
	var icons := ["armament","armor","charge"]
	var descriptions := ["Cadence accrue par rang.\nRang III : dégâts doublés.","+1 point de blindage par rang.\nEncaissez un impact de plus.","Recharge de frappe accélérée\nà chaque ennemi détruit."]
	for i in range(3):
		var x := 94.0+i*580
		var rank: int = app.profile.data.upgrades[i]
		panel(app,Rect2(x,726,550,193),.94)
		image(app,icons[i]+".svg",Rect2(x+22,751,64,64))
		text(app,names[i]+"  /  %d / 3" % rank,Vector2(x+108,742),Vector2(415,35),27,GOLD)
		text(app,descriptions[i],Vector2(x+108,781),Vector2(415,65),23,MUTED)
		var cost: int = app.profile.upgrade_cost(i)
		app._button("RANG MAXIMUM" if rank>=3 else "AMÉLIORER  /  %d PIÈCES" % cost,Vector2(x+22,861),Vector2(506,42),app._buy.bind(i),rank>=3 or app.profile.data.credits<cost)
	app._button("RETOUR AU BRIEFING",Vector2(94,946),Vector2(420,55),app._show_briefing.bind(app.selected_mission))
	app._button("ACCUEIL",Vector2(539,946),Vector2(240,55),app._show_main)

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
	text(app,"OR  /  Aucune vie perdue • 2 impacts maximum",Vector2(1230,612),Vector2(555,32),23,GOLD)
	text(app,mastery,Vector2(1230,648),Vector2(555,32),23,MUTED)
	text(app,"BONUS : "+preload("res://scripts/campaign/operations.gd").objective_text(mission.get("secondary","formation")),Vector2(1170,687),Vector2(625,32),20,GOLD)
	text(app,"COMMANDES  /  CLAVIER · MANETTE",Vector2(1170,726),Vector2(625,27),19,GOLD)
	var commands: Label = app._label(COMMANDS.flight_guide(),Vector2(1170,759),Vector2(625,136),21,MUTED)
	commands.name = "FlightCommands"
	app._fit_label(commands,136,19)
	app._button("DÉCOLLER",Vector2(94,946),Vector2(420,55),app._launch.bind(int(mission.id)))
	app._button("HANGAR",Vector2(539,946),Vector2(270,55),app._show_hangar)
	app._button("CARTE DES MISSIONS",Vector2(834,946),Vector2(330,55),app._show_missions)
