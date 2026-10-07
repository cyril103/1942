extends Control
var sector := 0
var boss := false
var ground := false
var mission: Dictionary = {}
var layout: Dictionary = {}
var clock := 0.0
const FONT := preload("res://assets/ui/fonts/BarlowCondensed-Medium.ttf")
const RAID_GOLD := Color("e2c383")
const RAID_INK := Color("a8c7c8")
const RAID_BLUE := Color("78c9db")
const RAID_MOBILE := Color("87dcc7")
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ground and not layout.is_empty(): set_process(false)
	queue_redraw()
func _process(delta: float) -> void:
	clock += delta
	queue_redraw()

func map_point(authored: Vector2) -> Vector2:
	# Positions follow the available map area; glyphs and marker circles retain
	# their size so a shorter briefing chart stays legible instead of squashed.
	return Vector2(authored.x*size.x/974.0,50.0+authored.y*maxf(1.0,size.y-88.0)/300.0)

func _draw() -> void:
	if ground and not layout.is_empty():
		_draw_raid()
		return
	var ink := Color("99babc")
	for x in range(0,int(size.x),48): draw_line(Vector2(x,0),Vector2(x,size.y),Color(.32,.53,.55,.14))
	for y in range(0,int(size.y),48): draw_line(Vector2(0,y),Vector2(size.x,y),Color(.32,.53,.55,.14))
	for island in range(4):
		var center := Vector2(180+island*190,160+sin(island*2.0+sector)*65)
		var points := PackedVector2Array()
		for i in range(72):
			var angle := i*TAU/72
			var radius := 42+10*sin(angle*3+sector+island)+5*cos(angle*5-island)+3*sin(angle*9+sector)
			points.append(map_point(center+Vector2(cos(angle)*1.55,sin(angle)*.8).rotated(island*.7)*radius))
		draw_colored_polygon(points,Color(.25,.39,.37,.65))
		points.append(points[0])
		draw_polyline(points,Color(.72,.72,.51,.65),1.5,true)
	var route := PackedVector2Array([Vector2(70,270),Vector2(320,240),Vector2(490,90),Vector2(710,70),Vector2(900,210)])
	for i in range(route.size()): route[i] = map_point(route[i])
	if ground:
		var coast := PackedVector2Array([Vector2(290,40),Vector2(370,20),Vector2(720,35),Vector2(780,130),Vector2(725,210),Vector2(510,255),Vector2(350,205)])
		for i in range(coast.size()): coast[i] = map_point(coast[i])
		draw_colored_polygon(coast,Color(.29,.38,.25,.8))
		coast.append(coast[0])
		draw_polyline(coast,Color(.81,.76,.48,.7),2,true)
		for at in [Vector2(415,133),Vector2(585,97),Vector2(650,158)]:
			var point := map_point(at)
			draw_rect(Rect2(point-Vector2(13,8),Vector2(26,16)),Color(.85,.46,.29,.9),false,2)
			draw_arc(point,24,0,TAU,24,Color(.85,.46,.29,.55),1,true)
	for i in range(route.size()-1): draw_dashed_line(route[i],route[i+1],Color("e2c383"),2,9,true)
	for i in range(route.size()):
		draw_circle(route[i],5,Color("e2c383"))
		draw_arc(route[i],12,0,TAU,32,ink,1,true)
		var labels := ["DÉPART","DESCENTE","RADARS","BASE AU SOL","RETOUR"] if ground else ["DÉPART","PATROUILLE","CONTACTS","INTERCEPTION","BOSS" if boss else "RETOUR"]
		draw_string(FONT,route[i]+Vector2(16,-14),labels[i],HORIZONTAL_ALIGNMENT_LEFT,-1,18,ink)
	var progress := fmod(clock*.17,4.0)
	var at := route[int(progress)].lerp(route[mini(4,int(progress)+1)],fmod(progress,1.0))
	draw_circle(at,4,Color.WHITE)
	draw_arc(at,10+fmod(clock*10,14),0,TAU,32,Color(.75,.9,.9,.35),1,true)
	draw_string(FONT,Vector2(15,25),"SCHÉMA TACTIQUE  /  SECTEUR %02d" % (sector+1),HORIZONTAL_ALIGNMENT_LEFT,-1,22,Color("e2c383"))
	draw_string(FONT,Vector2(15,size.y-12),"ITINÉRAIRE INDICATIF • NON À L'ÉCHELLE",HORIZONTAL_ALIGNMENT_LEFT,-1,16,ink)

func _raid_field() -> Rect2:
	# The long raid axis runs left to right in this wide briefing card. Only
	# presentation is rotated: the shared normalized positions are read unchanged.
	return Rect2(26,63,maxf(180.0,size.x-284.0),maxf(68.0,size.y-127.0))

func _raid_point(normalized: Vector2) -> Vector2:
	var field := _raid_field()
	return field.position+Vector2((1.0-normalized.y)*.5*field.size.x,(normalized.x+1.0)*.5*field.size.y)

func _raid_marker(at: Vector2, kind: String, color: Color, index := 0) -> void:
	if kind=="radar":
		draw_circle(at,3.0,color)
		draw_line(at+Vector2(0,2),at+Vector2(0,8),color,1.5,true)
		for radius in [6.0,10.0]: draw_arc(at,radius,PI*1.14,PI*1.86,16,Color(color,.75),1.2,true)
	elif kind=="mobile":
		draw_rect(Rect2(at-Vector2(6,3),Vector2(12,6)),color,false,1.4)
		draw_line(at+Vector2(-3,-4),at+Vector2(5,-6),color,1.4,true)
		for side in [-1.0,1.0]: draw_line(at+Vector2(-4,side*5),at+Vector2(4,side*5),color,1.4,true)
	else:
		var diamond := PackedVector2Array([at+Vector2(0,-8),at+Vector2(8,0),at+Vector2(0,8),at+Vector2(-8,0),at+Vector2(0,-8)])
		draw_colored_polygon(PackedVector2Array([diamond[0],diamond[1],diamond[2],diamond[3]]),Color(.06,.12,.13,.95))
		draw_polyline(diamond,color,1.7,true)
		if index>0: draw_string(FONT,at+Vector2(-3,4),str(index),HORIZONTAL_ALIGNMENT_LEFT,-1,12,color)

func _draw_raid() -> void:
	var field := _raid_field()
	var legend_x := field.end.x+28.0
	var legend_width := maxf(80.0,size.x-legend_x-14.0)
	for x in range(0,int(size.x),48): draw_line(Vector2(x,0),Vector2(x,size.y),Color(.32,.53,.55,.07))
	for y in range(0,int(size.y),48): draw_line(Vector2(0,y),Vector2(size.x,y),Color(.32,.53,.55,.07))
	draw_string(FONT,Vector2(15,25),"PLAN DE RAID  /  "+str(layout.get("title","SECTEUR %02d" % (sector+1))),HORIZONTAL_ALIGNMENT_LEFT,field.size.x,21,RAID_GOLD)
	draw_string(FONT,Vector2(field.position.x,field.position.y-10),"ENTRÉE",HORIZONTAL_ALIGNMENT_LEFT,120,13,RAID_INK)
	draw_string(FONT,Vector2(field.end.x-68,field.position.y-10),"EXTRACTION",HORIZONTAL_ALIGNMENT_LEFT,80,13,RAID_INK)
	# A schematic coastal envelope rather than another imaginary island route.
	var outline := PackedVector2Array([
		field.position+Vector2(5,9),field.position+Vector2(18,0),
		Vector2(field.end.x-14,field.position.y),field.end-Vector2(0,field.size.y-12),
		field.end-Vector2(3,8),field.end-Vector2(17,0),
		Vector2(field.position.x+15,field.end.y),Vector2(field.position.x,field.end.y-13)
	])
	draw_colored_polygon(outline,Color(.20,.30,.25,.75))
	outline.append(outline[0])
	draw_polyline(outline,Color(.61,.66,.48,.65),1.2,true)
	var routes: Dictionary = layout.get("routes",{})
	for route_id in routes:
		var route: Dictionary = routes[route_id]
		var points := PackedVector2Array()
		for normalized in route.get("points",[]): points.append(_raid_point(normalized))
		if points.size()<2: continue
		var mobile_path := str(route.get("usage",""))=="mobile"
		draw_polyline(points,Color(RAID_MOBILE,.52) if mobile_path else Color(.62,.72,.69,.35),2.4 if mobile_path else 1.2,true)
		if mobile_path:
			for endpoint in [points[0],points[-1]]: draw_circle(endpoint,2.1,Color(RAID_MOBILE,.7))
	for strip in layout.get("runways",[]):
		var center: Vector2 = _raid_point(strip.center)
		var length := maxf(12.0,float(strip.half_length)*field.size.x)
		var rect := Rect2(center-Vector2(length*.5,4),Vector2(length,8))
		draw_rect(rect,Color(.10,.19,.20,.96))
		draw_rect(rect,Color(.73,.76,.67,.75),false,1.2)
		draw_dashed_line(center-Vector2(length*.43,0),center+Vector2(length*.43,0),Color(.83,.86,.76,.8),1,4,true)
	var priorities: Array = layout.get("priority_ids",[])
	for target in layout.get("targets",[]):
		var at: Vector2 = _raid_point(target.normalized)
		if str(target.variant)=="radar": _raid_marker(at,"radar",RAID_BLUE)
		elif bool(target.get("mobile",false)): _raid_marker(at,"mobile",RAID_MOBILE)
		if priorities.has(target.id):
			# Offset the numbered priority halo slightly from its radar/truck glyph.
			var marker := at+Vector2(0,-12) if target.variant=="radar" or bool(target.get("mobile",false)) else at
			_raid_marker(marker,"priority",RAID_GOLD,priorities.find(target.id)+1)
	# Exact group labels and scope come from the same catalogue as the real guns.
	draw_string(FONT,Vector2(legend_x,25),"GUIDAGE RADAR",HORIZONTAL_ALIGNMENT_LEFT,legend_width,18,RAID_INK)
	var groups: Dictionary = layout.get("radar_groups",{})
	var row := 0
	for network_id in groups:
		var group: Dictionary = groups[network_id]
		var y := 62.0+row*36.0
		_raid_marker(Vector2(legend_x+7,y+2),"radar",RAID_BLUE)
		draw_string(FONT,Vector2(legend_x+25,y),str(group.get("label",network_id)),HORIZONTAL_ALIGNMENT_LEFT,legend_width-25,17,RAID_INK)
		draw_string(FONT,Vector2(legend_x+25,y+15),"GLOBAL" if bool(group.get("global",false)) else "LOCAL",HORIZONTAL_ALIGNMENT_LEFT,legend_width-25,12,Color(.50,.68,.70,.95))
		row += 1
	var key_y := size.y-43.0
	_raid_marker(Vector2(27,key_y-5),"radar",RAID_BLUE)
	draw_string(FONT,Vector2(44,key_y),"RADAR",HORIZONTAL_ALIGNMENT_LEFT,72,14,RAID_INK)
	_raid_marker(Vector2(146,key_y-5),"priority",RAID_GOLD)
	draw_string(FONT,Vector2(164,key_y),"PRIORITÉ",HORIZONTAL_ALIGNMENT_LEFT,92,14,RAID_INK)
	_raid_marker(Vector2(289,key_y-5),"mobile",RAID_MOBILE)
	draw_string(FONT,Vector2(307,key_y),"DCA MOBILE",HORIZONTAL_ALIGNMENT_LEFT,110,14,RAID_INK)
	draw_line(Vector2(446,key_y-5),Vector2(466,key_y-5),Color(.65,.74,.69,.65),1.4,true)
	draw_string(FONT,Vector2(475,key_y),"ROUTES / PISTES",HORIZONTAL_ALIGNMENT_LEFT,170,14,RAID_INK)
	draw_string(FONT,Vector2(15,size.y-12),"PLAN SECTORIEL INDICATIF • NON À L'ÉCHELLE • LES AUTRES DÉFENSES NE SONT PAS REPRÉSENTÉES",HORIZONTAL_ALIGNMENT_LEFT,size.x-30,13,RAID_INK)
