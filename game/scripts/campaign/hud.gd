extends Control
## Thin mission/boss banner; persistent flight data lives in the side instruments.
var cockpit: Control
var director: Node
var elapsed := 0.0
var weather: ColorRect
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
	weather.position = cockpit.play_rect.position
	weather.size = cockpit.play_rect.size
	queue_redraw()
func _draw() -> void:
	if not is_instance_valid(director): return
	var r: Rect2 = cockpit.play_rect
	var unit := r.size.y/1080.0
	var font_size := maxi(12,int(24*unit))
	var bar := Rect2(r.position,Vector2(r.size.x,38*unit))
	draw_rect(bar,Color(0.01,0.035,0.045,0.84))
	draw_string(FONT,bar.position+Vector2(14,27)*unit,"%02d / 32  •  %s" % [director.mission.id,director.mission.title.to_upper()],HORIZONTAL_ALIGNMENT_LEFT,bar.size.x-20,font_size,Color("e4cf9d"))
	var progress := clampf(director.elapsed/float(director.mission.duration),0,1)
	draw_rect(Rect2(bar.position+Vector2(0,bar.size.y),Vector2(bar.size.x*progress,2*unit)),Color("cfaa5d"))
	if is_instance_valid(director.boss) and director.boss.alive:
		var boss = director.boss
		var health_bar := Rect2(r.position+Vector2(30,76)*unit,Vector2(r.size.x-60*unit,9*unit))
		draw_rect(health_bar,Color("202c31"))
		draw_rect(Rect2(health_bar.position,Vector2(health_bar.size.x*float(boss.health)/boss.max_health,health_bar.size.y)),Color("ec7757"))
		draw_string(FONT,health_bar.position-Vector2(0,9)*unit,boss.NAMES[boss.kind].to_upper(),HORIZONTAL_ALIGNMENT_LEFT,health_bar.size.x,maxi(12,int(20*unit)),Color("efc9b4"))
	if director.feedback_time > 0:
		var alpha := minf(1,director.feedback_time)
		var pos := r.position+Vector2(0,r.size.y*0.17)
		var text_size := maxi(14,int(26*unit))
		var text: String = director.feedback
		var width := FONT.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,text_size).x
		pos.x += maxf(10*unit,(r.size.x-width)*0.5)
		draw_rect(Rect2(Vector2(r.position.x,pos.y-28*unit),Vector2(r.size.x,42*unit)),Color(0.02,0.03,0.025,alpha*.78))
		draw_string(FONT,pos,text,HORIZONTAL_ALIGNMENT_LEFT,r.size.x-20*unit,text_size,Color(1,.87,.57,alpha))
	# Small focus marker reveals the actual vulnerable centre while precision flight is held.
	if Input.is_action_pressed("focus_flight") and director.player.alive:
		var p: Vector2 = cockpit.combat.camera.unproject_position(director.player.global_position)+r.position
		draw_circle(p,3.0*unit,Color(1,.93,.65,.9))
		draw_arc(p,6.0*unit,0,TAU,24,Color(0,0,0,.7),1.5*unit,true)
