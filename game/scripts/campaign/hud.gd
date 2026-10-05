extends Control
## Compact flight HUD, damage feedback and life-cycle transitions.
var cockpit: Control
var director: Node
var elapsed := 0.0
var weather: ColorRect
var armor_trail := 1.0
var armor_hold := 0.0
var previous_armor := 1.0
const FONT := preload("res://assets/ui/fonts/BarlowCondensed-Medium.ttf")
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	weather = ColorRect.new()
	weather.mouse_filter = Control.MOUSE_FILTER_IGNORE
	weather.show_behind_parent = true
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/campaign_weather.gdshader")
	material.set_shader_parameter("weather_kind",{"storm":1,"arctic":2,"volcanic":3}.get(director.mission.biome,0))
	material.set_shader_parameter("strength",0.8 if director.mission.biome in ["storm","arctic","volcanic"] else 0.35)
	weather.material = material
	add_child(weather)
func _process(delta: float) -> void:
	elapsed += delta
	var armor := float(director.player.health)/maxi(1,director.player.max_health)
	if armor < previous_armor: armor_hold = .4
	if armor > previous_armor: armor_trail = armor
	previous_armor = armor
	armor_hold = maxf(0,armor_hold-delta)
	if armor_hold <= 0: armor_trail = move_toward(armor_trail,armor,delta*.8)
	weather.position = cockpit.play_rect.position
	weather.size = cockpit.play_rect.size
	queue_redraw()
func _draw() -> void:
	if not is_instance_valid(director): return
	var r: Rect2 = cockpit.play_rect
	var u := cockpit.size.y/1080.0
	var w := cockpit.size.x
	var c = director.combat
	var gold := Color("efcd88")
	draw_rect(Rect2(0,0,w,64*u),Color("071720"))
	draw_line(Vector2(0,63*u),Vector2(w,63*u),Color("68756c"),u)
	text_at("%02d / 32  •  %s" % [director.mission.id,director.mission.region.to_upper()],Vector2(20*u,24*u),20*u,gold,w*.30)
	text_at(director.mission.title,Vector2(20*u,50*u),25*u,Color.WHITE,w*.30)
	text_at("SCORE TOTAL",Vector2(w*.33,22*u),17*u,gold)
	text_at("%08d" % c.score,Vector2(w*.33,51*u),30*u,Color.WHITE)
	text_at("RECORD",Vector2(w*.52,22*u),17*u,gold)
	text_at("%08d" % cockpit.high_score,Vector2(w*.52,51*u),30*u,Color.WHITE)
	text_at("VIES  %d" % c.remaining_lives,Vector2(w*.72,41*u),26*u,Color("8bf0b8"))
	var hp: int = director.player.health
	var maximum: int = director.player.max_health
	var armor_color := Color("86edce") if hp > 1 else Color("ff9965")
	text_at("BLINDAGE  %d / %d" % [hp,maximum],Vector2(w*.84,24*u),20*u,armor_color)
	var armor_rect := Rect2(w*.84,34*u,w*.145,16*u)
	draw_rect(armor_rect,Color("243a46"))
	draw_rect(Rect2(armor_rect.position,Vector2(armor_rect.size.x*armor_trail,armor_rect.size.y)),Color("e3a469"))
	draw_rect(Rect2(armor_rect.position,Vector2(armor_rect.size.x*float(hp)/maxi(1,maximum),armor_rect.size.y)),armor_color)
	for segment in range(1,maximum):
		var x := armor_rect.position.x+armor_rect.size.x*segment/maximum
		draw_line(Vector2(x,armor_rect.position.y),Vector2(x,armor_rect.end.y),Color("071720"),3*u)
	var bottom := cockpit.size.y-44*u
	draw_rect(Rect2(0,bottom,w,44*u),Color("071720"))
	var power: String = director.weapons.power_type
	if power != "none":
		draw_texture_rect(load("res://assets/campaign/icons/"+power+".svg"),Rect2(14*u,bottom+5*u,34*u,34*u),false)
	text_at({"none":"TIR STANDARD","spread":"MULTI-TIR","laser":"LASER","life":"VIE +1  •  STANDARD"}[power],Vector2(60*u,bottom+29*u),24*u,Color.WHITE)
	text_at("BOMBES  %d  / X" % director.bombs,Vector2(w*.32,bottom+29*u),23*u,gold)
	text_at("FRAPPE  %d%%  / C" % int(director.charge),Vector2(w*.51,bottom+29*u),23*u,Color("95ecff"))
	var charge_rect := Rect2(w*.69,bottom+17*u,w*.12,10*u)
	draw_rect(charge_rect,Color("233f4b"))
	draw_rect(Rect2(charge_rect.position,Vector2(charge_rect.size.x*director.charge/100.0,charge_rect.size.y)),Color("68dced"))
	text_at("MAJ PRÉCISION  •  ÉCHAP PAUSE",Vector2(w*.84,bottom+28*u),18*u,Color("9aadb8"),w*.15)
	var progress := clampf(director.elapsed/float(director.mission.duration),0,1)
	draw_rect(Rect2(r.position,Vector2(r.size.x*progress,2*u)),gold)
	if is_instance_valid(director.boss) and director.boss.alive:
		var boss = director.boss
		var boss_bar := Rect2(Vector2(w*.25,r.position.y+34*u),Vector2(w*.5,7*u))
		draw_rect(boss_bar,Color("202c31"))
		draw_rect(Rect2(boss_bar.position,Vector2(boss_bar.size.x*float(boss.health)/boss.max_health,boss_bar.size.y)),Color("ec7757"))
		text_at(boss.NAMES[boss.kind].to_upper(),boss_bar.position-Vector2(0,8*u),20*u,Color("efc9b4"),boss_bar.size.x)
	if director.feedback_time > 0:
		var alpha := minf(1,director.feedback_time)
		var value: String = director.feedback
		var font_size := maxi(14,int(26*u))
		var width := minf(w-40*u,FONT.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x+40*u)
		var pos := Vector2((w-width)*.5,r.position.y+75*u)
		draw_rect(Rect2(pos,Vector2(width,40*u)),Color(.02,.03,.04,.78*alpha))
		text_at(value,pos+Vector2(20,28)*u,font_size,Color(1,.87,.57,alpha),width-40*u)
	if director.player.alive and director.player.controls_enabled and director.player.invulnerable_time > 0:
		var protected_at: Vector2 = cockpit.combat.camera.unproject_position(director.player.global_position)+r.position
		var protection := clampf(director.player.invulnerable_time/4.0,0,1)
		draw_arc(protected_at,45*u,-PI*.5,-PI*.5+TAU*protection,64,Color(.45,.9,1,.65),2*u,true)
	if c.respawn_time > 0 or c.game_over:
		var center := r.get_center()
		var box := Rect2(center-Vector2(290,72)*u,Vector2(580,144)*u)
		draw_rect(box,Color(.015,.035,.05,.88))
		draw_line(box.position,box.position+Vector2(box.size.x,0),gold,2*u)
		text_at("GAME OVER" if c.game_over else "RENFORT EN APPROCHE",box.position+Vector2(30,52)*u,38*u,Color.WHITE)
		var message := "Toutes les vies sont épuisées" if c.game_over else "Retour dans %.1f s  •  %d vies restantes" % [c.respawn_time,c.remaining_lives]
		text_at(message,box.position+Vector2(30,99)*u,24*u,gold)
	if Input.is_action_pressed("focus_flight") and director.player.alive:
		var p: Vector2 = cockpit.combat.camera.unproject_position(director.player.global_position)+r.position
		draw_circle(p,3*u,Color(1,.93,.65,.9))
		draw_arc(p,6*u,0,TAU,24,Color(0,0,0,.7),1.5*u,true)

func text_at(value: String, at: Vector2, pixels: float, color: Color, width := -1.0) -> void:
	draw_string(FONT,at+Vector2(1,1),value,HORIZONTAL_ALIGNMENT_LEFT,width,maxi(12,int(pixels)),Color(0,0,0,.8))
	draw_string(FONT,at,value,HORIZONTAL_ALIGNMENT_LEFT,width,maxi(12,int(pixels)),color)
