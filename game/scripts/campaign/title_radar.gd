extends Control
## Lightweight vector chart, drawn over the existing original ocean illustration.
var clock := 0.0
var reduced_motion := false
const GOLD := Color("dfc58b")

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta: float) -> void:
	if not is_visible_in_tree(): return
	clock += delta
	queue_redraw()

func _draw() -> void:
	var center := size*.5
	var radius := minf(size.x,size.y)*.43
	for index in range(1,5):
		draw_arc(center,radius*index/4.0,0,TAU,96,Color(.73,.82,.77,.14),1.0,true)
	draw_line(center-Vector2(radius+18,0),center+Vector2(radius+18,0),Color(.73,.82,.77,.15),1,true)
	draw_line(center-Vector2(0,radius+18),center+Vector2(0,radius+18),Color(.73,.82,.77,.15),1,true)
	var angle := -.8 if reduced_motion else clock*.18
	for index in range(14):
		var a := angle-index*.014
		draw_line(center,center+Vector2(cos(a),sin(a))*radius,Color(.5,.84,.79,(1-index/14.0)*.14),2,true)
	var previous := Vector2.ZERO
	for index in range(8):
		var a := -2.4+index*.57
		var at := center+Vector2(cos(a),sin(a))*radius*(.48+.25*sin(index*1.8))
		if index>0: draw_line(previous,at,Color(.87,.77,.55,.32),1.2,true)
		draw_circle(at,3,GOLD)
		draw_arc(at,8,0,TAU,20,Color(.87,.77,.55,.45),1,true)
		previous = at
	for index in range(48):
		var a := index*TAU/48
		var unit := Vector2(cos(a),sin(a))
		draw_line(center+unit*(radius+8),center+unit*(radius+(18 if index%4==0 else 12)),Color(.8,.84,.77,.32),1,true)
