extends RefCounted
const L10N := preload("res://scripts/campaign/localization.gd")
const DATA := preload("res://scripts/campaign/debrief.gd")
const RULES := preload("res://scripts/campaign/scoring_rules.gd")
const UI := preload("res://scripts/campaign/carrier_menu.gd")
const GOLD := Color("e2c383")
const TEAL := Color("8fe2cd")
const MUTED := Color("9badb5")

class Timeline extends Control:
	var analysis: Dictionary = {}
	func _ready() -> void: mouse_filter=Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var samples: Array = analysis.get("samples",[])
		if samples.size()<2: return
		var maximum := maxf(1,float(analysis.get("totals",{}).get("score",0)))
		var duration := maxf(1,float(analysis.get("elapsed",1)))
		var usable := size-Vector2(0,28)
		for i in range(5):
			var y:=usable.y*i/4.0
			draw_line(Vector2(0,y),Vector2(usable.x,y),Color(.48,.64,.68,.18),1)
		var points:=PackedVector2Array()
		for sample in samples:
			points.append(Vector2(clampf(float(sample.seconds)/duration,0,1)*usable.x,(1-clampf(float(sample.score)/maximum,0,1))*usable.y))
		var fill:=points.duplicate()
		fill.append(Vector2(points[-1].x,usable.y))
		fill.append(Vector2(points[0].x,usable.y))
		if points[-1].x>points[0].x: draw_colored_polygon(fill,Color(.32,.73,.66,.12))
		draw_polyline(points,TEAL,2.5,true)
		for event in analysis.get("events",[]):
			var x:=clampf(float(event.seconds)/duration,0,1)*usable.x
			var kind:=str(event.kind)
			if kind in ["hit","death"]:
				var color:=Color("ff997f")
				draw_line(Vector2(x,usable.y+8),Vector2(x,usable.y+21),color,2)
				if kind=="death": draw_line(Vector2(x-4,usable.y+10),Vector2(x+4,usable.y+18),color,2)
			elif kind in ["bomb","strike"]:
				draw_circle(Vector2(x,usable.y+14),4,GOLD)
			elif kind=="boss":
				draw_line(Vector2(x,0),Vector2(x,usable.y),Color(GOLD,.5),1)

func build(app: Control, report: Dictionary, previous: int) -> void:
	var ui:=UI.new()
	ui.panel(app,Rect2(94,270,1080,345),.94)
	ui.panel(app,Rect2(1206,270,594,612),.94)
	app._label(L10N.text("TRAJECTOIRE DU SCORE"),Vector2(122,289),Vector2(650,38),27,GOLD)
	var analysis: Dictionary=report.get("flight_analysis",{})
	app._label("%d PTS" % int(analysis.get("totals",{}).get("score",0)),Vector2(804,295),Vector2(340,32),23,TEAL).horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	var chart:=Timeline.new()
	chart.name="FlightTimeline"
	chart.position=Vector2(126,352)
	chart.size=Vector2(1018,183)
	chart.analysis=analysis
	app.design.add_child(chart)
	var elapsed:=float(analysis.get("elapsed",report.get("seconds",0)))
	app._label("00:00",Vector2(126,543),Vector2(100,30),21,MUTED)
	app._label(DATA.time_text(elapsed),Vector2(1044,543),Vector2(100,30),21,MUTED).horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	app._label(L10N.text("TRAIT CORAIL : IMPACT   •   POINT OR : BOMBE / CAPACITÉ   •   LIGNE OR : BOSS"),Vector2(126,578),Vector2(1018,28),20,MUTED)
	if analysis.get("samples",[]).size()<2:
		app._label(L10N.text("La chronologie apparaît après une sortie de combat."),Vector2(152,407),Vector2(940,64),29,MUTED)
	var metrics := [
		[L10N.text("TEMPS EN COMBAT"),DATA.time_text(elapsed)],
		[L10N.text("MEILLEURE CHAÎNE"),str(report.get("best_chain",0))],
		[L10N.text("IMPACTS / VIES PERDUES"),"%d / %d" % [report.get("damage",0),report.get("deaths",0)]],
		[L10N.text("FRÔLEMENTS"),str(report.get("grazes",0))]
	]
	for i in range(4):
		var x:=94+i*278
		ui.panel(app,Rect2(x,639,246,107),.93)
		app._label(metrics[i][0],Vector2(x+16,651),Vector2(218,30),20,MUTED)
		app._label(metrics[i][1],Vector2(x+16,683),Vector2(218,52),38,TEAL)
	var comparison:=DATA.score_delta(report,previous) if app.play_mode in ["campaign","arcade"] else L10N.text("ANALYSE DE CE DUEL  /  AUCUN RECORD DE MISSION")
	app._label(comparison,Vector2(94,774),Vector2(1078,42),26,GOLD)
	app._label(L10N.text("La courbe décrit le combat, avant le bonus de fin.\nLes conseils ne modifient ni vos points, ni votre équipement."),Vector2(94,826),Vector2(1078,56),23,MUTED)
	var target:=DATA.next_rank(report)
	app._label(L10N.text("CAP SUR LE RANG %s") % target,Vector2(1234,292),Vector2(534,48),32,GOLD)
	var y:=354.0
	for row in RULES.rank_checks(target,report):
		var label: Label=app._label(("✓  " if row.passed else "○  ")+str(row.label),Vector2(1234,y),Vector2(534,41),25,TEAL if row.passed else MUTED)
		app._fit_label(label,41,21)
		y+=43
	# Keep advice below the rank checklist even when the S rank has five rows.
	y=maxf(590,y+18)
	for item in DATA.coaching(report):
		app._label(item.title,Vector2(1234,y),Vector2(534,30),23,GOLD)
		var label: Label=app._label(item.body,Vector2(1234,y+35),Vector2(534,92),24,Color("dae5e7"))
		app._fit_label(label,92,21)
		y+=142
	app._button(L10N.text("RETOUR AU BILAN"),Vector2(94,939),Vector2(470,60),app._draw_result.bind(report))
	app._button(L10N.text("MÉDAILLE & RANG  /  DÉTAILS"),Vector2(590,939),Vector2(584,60),app._show_criteria)
	app._focus_first()
