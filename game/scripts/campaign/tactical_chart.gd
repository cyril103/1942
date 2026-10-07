extends Control
var sector := 0
var boss := false
var ground := false
var clock := 0.0
const FONT := preload("res://assets/ui/fonts/BarlowCondensed-Medium.ttf")
func _ready() -> void: mouse_filter = Control.MOUSE_FILTER_IGNORE
func _process(delta: float) -> void:
	clock += delta
	queue_redraw()
func _draw() -> void:
	var ink := Color("99babc")
	for x in range(0,int(size.x),48): draw_line(Vector2(x,0),Vector2(x,size.y),Color(.32,.53,.55,.14))
	for y in range(0,int(size.y),48): draw_line(Vector2(0,y),Vector2(size.x,y),Color(.32,.53,.55,.14))
	for island in range(4):
		var center := Vector2(180+island*190,160+sin(island*2.0+sector)*65)
		var points := PackedVector2Array()
		for i in range(72):
			var angle := i*TAU/72
			var radius := 42+10*sin(angle*3+sector+island)+5*cos(angle*5-island)+3*sin(angle*9+sector)
			points.append(center+Vector2(cos(angle)*1.55,sin(angle)*.8).rotated(island*.7)*radius)
		draw_colored_polygon(points,Color(.25,.39,.37,.65))
		points.append(points[0])
		draw_polyline(points,Color(.72,.72,.51,.65),1.5,true)
	var route := PackedVector2Array([Vector2(70,270),Vector2(320,240),Vector2(490,90),Vector2(710,70),Vector2(900,210)])
	if ground:
		var coast := PackedVector2Array([Vector2(290,40),Vector2(370,20),Vector2(720,35),Vector2(780,130),Vector2(725,210),Vector2(510,255),Vector2(350,205)])
		draw_colored_polygon(coast,Color(.29,.38,.25,.8))
		coast.append(coast[0])
		draw_polyline(coast,Color(.81,.76,.48,.7),2,true)
		for at in [Vector2(415,133),Vector2(585,97),Vector2(650,158)]:
			draw_rect(Rect2(at-Vector2(13,8),Vector2(26,16)),Color(.85,.46,.29,.9),false,2)
			draw_arc(at,24,0,TAU,24,Color(.85,.46,.29,.55),1,true)
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
