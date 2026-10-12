extends RefCounted
## Campaign navigation uses the real mission/record data. The chart is schematic.
const L10N := preload("res://scripts/campaign/localization.gd")
const UI := preload("res://scripts/campaign/carrier_menu.gd")
const GOLD := Color("e2c383")
const TEAL := Color("8fe2cd")
const MUTED := Color("9badb5")
const POINTS := [Vector2(140,450),Vector2(370,490),Vector2(615,450),Vector2(865,360),Vector2(810,210),Vector2(570,240),Vector2(315,165),Vector2(535,70)]

class Chart extends Control:
	var selected := 0
	var unlocked := 0
	var completed: Array[bool] = []
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		for x in range(0,int(size.x),48): draw_line(Vector2(x,0),Vector2(x,size.y),Color(.29,.55,.58,.10),1)
		for y in range(0,int(size.y),48): draw_line(Vector2(0,y),Vector2(size.x,y),Color(.29,.55,.58,.10),1)
		# Original vector islands, stable between openings and independent of RNG.
		for index in range(8):
			var center: Vector2 = POINTS[index]+Vector2(15,-4)
			for ring in range(3,0,-1):
				var polygon := PackedVector2Array()
				for vertex in range(25):
					var a := vertex*TAU/24
					var r := 1.0+.20*sin(a*3+index)+.13*cos(a*5-index)
					polygon.append(center+Vector2(cos(a)*50,sin(a)*30)*r*(1+ring*.33))
				draw_colored_polygon(polygon,Color(.10+ring*.006,.23+ring*.012,.22+ring*.010,.8))
				draw_polyline(polygon,Color(.37,.63,.55,.16),1,true)
		for index in range(1,8):
			var a: Vector2 = POINTS[index-1]
			var b: Vector2 = POINTS[index]
			var color := Color(.50,.78,.73,.55) if index<=unlocked else Color(.45,.54,.57,.27)
			draw_dashed_line(a,b,color,2,8,true)
		for index in range(8):
			var p: Vector2 = POINTS[index]
			var color := TEAL if completed[index] else (GOLD if index<=unlocked else MUTED.darkened(.4))
			draw_arc(p,45,0,TAU,64,Color(color,.30),1.4,true)
			if index==selected:
				draw_arc(p,53,0,TAU,64,Color(GOLD,.75),2,true)
				draw_line(p+Vector2(-64,0),p+Vector2(-54,0),GOLD,2)
				draw_line(p+Vector2(54,0),p+Vector2(64,0),GOLD,2)
		var compass := Vector2(size.x-53,56)
		draw_line(compass+Vector2(0,-18),compass+Vector2(0,18),Color(MUTED,.6),1)
		draw_line(compass+Vector2(-18,0),compass+Vector2(18,0),Color(MUTED,.6),1)
		draw_circle(compass,3,GOLD)

func build(app: Control, sector: int) -> void:
	var ui := UI.new()
	var records: Dictionary = app.profile.data.records
	var gold := 0
	var ranks := 0
	for record in records.values():
		if int(record.get("grade",0))==3: gold+=1
		if str(record.get("rank","D"))=="S": ranks+=1
	app._label(L10N.text("CAMPAGNE  %02d / 32   •   OR  %02d / 32   •   RANG S  %02d / 32") % [records.size(),gold,ranks],Vector2(94,246),Vector2(1600,36),24,GOLD)
	ui.panel(app,Rect2(94,300,1072,590),.92)
	ui.panel(app,Rect2(1200,300,600,590),.95)
	var chart := Chart.new()
	chart.name = "OperationChart"
	chart.position = Vector2(114,318)
	chart.size = Vector2(1032,550)
	chart.selected = sector
	chart.unlocked = (int(app.profile.data.unlocked)-1)/4
	for i in range(8):
		var done := true
		for mission in range(i*4+1,i*4+5):
			if not records.has(str(mission)): done=false
		chart.completed.append(done)
	app.design.add_child(chart)
	for i in range(8):
		var at: Vector2 = chart.position+POINTS[i]
		var region := str(app.missions[i*4].region).to_upper()
		var button: Button = app._button("%02d" % [i+1],at-Vector2(31,27),Vector2(62,54),app._show_missions.bind(i))
		button.name = "Sector_%d" % i
		button.tooltip_text = region
		button.add_theme_font_size_override("font_size",25)
		for state in ["normal","hover","pressed","focus","disabled"]:
			var style: StyleBoxFlat = button.get_theme_stylebox(state).duplicate()
			style.content_margin_left=4
			style.content_margin_right=4
			style.border_color=GOLD if i==sector else Color("47616b")
			style.bg_color=Color("293b3b") if i==sector else Color("0b202a")
			if state in ["hover","focus"]:
				style.border_color=TEAL
				style.set_border_width_all(3)
				style.bg_color=Color("244446")
			button.add_theme_stylebox_override(state,style)
		app._label(region,at+Vector2(-104,32),Vector2(208,28),20,TEAL if chart.completed[i] else MUTED).horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	var mission: Dictionary = app.missions[sector*4]
	app._label(L10N.text("SECTEUR %02d") % [sector+1],Vector2(1230,320),Vector2(530,30),22,GOLD)
	var title: Label = app._label(str(mission.region).to_upper(),Vector2(1230,359),Vector2(530,58),38,Color.WHITE,true)
	app._fit_label(title,58,28)
	for offset in range(4):
		var number := sector*4+offset+1
		var item: Dictionary = app.missions[number-1]
		var record: Dictionary = records.get(str(number),{})
		var locked := number>int(app.profile.data.unlocked)
		var state := L10N.text("VERROUILLÉE") if locked else L10N.text("À ACCOMPLIR")
		if not record.is_empty(): state=["—",L10N.text("BRONZE"),L10N.text("ARGENT"),L10N.text("OR")][int(record.get("grade",0))]+"  /  "+L10N.text("RANG %s") % str(record.get("rank","D"))
		if number==int(app.profile.data.next_mission) and not bool(app.profile.data.completed): state=L10N.text("PROCHAINE OPÉRATION")
		var button: Button = app._button("%02d   %s\n%s" % [number,item.title,state],Vector2(1230,437+offset*93),Vector2(540,80),app._show_briefing.bind(number),locked)
		button.name="Operation_%02d" % number
		button.add_theme_font_size_override("font_size",23)
		button.clip_text=true
		button.tooltip_text=str(item.title)+"\n"+state
		for style_name in ["normal","hover","pressed","focus","disabled"]:
			var style: StyleBoxFlat = button.get_theme_stylebox(style_name).duplicate()
			style.content_margin_left=14
			style.content_margin_right=14
			style.content_margin_top=6
			style.content_margin_bottom=6
			button.add_theme_stylebox_override(style_name,style)
	app._label(L10N.text("Sélectionnez un secteur, puis une mission.\nCarte schématique du théâtre d'opérations."),Vector2(1230,824),Vector2(530,52),21,MUTED)
	app._label(L10N.text("01 — 08  SECTEURS   /   LES MÉDAILLES ET RANGS SONT CONSERVÉS"),Vector2(114,902),Vector2(1450,30),20,MUTED)
	app._button(L10N.text("RETOUR"),Vector2(94,945),Vector2(280,55),app._show_main)
	app._button(L10N.text("REPRENDRE  /  MISSION %02d") % int(app.profile.data.next_mission),Vector2(1200,945),Vector2(600,55),app._show_briefing.bind(int(app.profile.data.next_mission)))
	app.design.get_node("Sector_%d" % sector).grab_focus()
