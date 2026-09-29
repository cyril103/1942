extends Control
## Resolution-independent cockpit artwork; textures contain no baked text.
const LABEL_FONT = preload("res://assets/ui/fonts/BarlowCondensed-Medium.ttf")
const TITLE_FONT = preload("res://assets/ui/fonts/BlackOpsOne-Regular.ttf")
const DISPLAY = preload("res://scripts/ui/instrument_display.gd")
const CREAM := Color("d9c59a")
const DIM := Color("8c8065")
const BRASS := Color("736448")
const RADAR := Rect2(62,472,431,330)
var dashboard: Control
var right_side := false
var displays: Array[Control] = []
var radar_surface: ColorRect
var elapsed := 0.0
var dial_bank := 0.0

func _ready() -> void:
	size = Vector2(555,1080)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var metal := TextureRect.new()
	metal.texture = preload("res://assets/ui/cockpit-metal.png")
	metal.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	metal.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	metal.size = size
	metal.show_behind_parent = true
	metal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/ui/panel_metal.gdshader")
	metal.material = material
	add_child(metal)
	if right_side:
		_display(Rect2(333,55,158,85),2,55)
		_display(Rect2(333,182,158,85),2,55)
		_display(Rect2(133,336,290,85),5,51)
		radar_surface = ColorRect.new()
		radar_surface.position = RADAR.position
		radar_surface.size = RADAR.size
		radar_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
		radar_surface.show_behind_parent = true
		var radar_material := ShaderMaterial.new()
		radar_material.shader = preload("res://shaders/ui/radar.gdshader")
		radar_material.set_shader_parameter("island_atlas",preload("res://assets/environment/islands-atlas.png"))
		radar_surface.material = radar_material
		add_child(radar_surface)
	else:
		_display(Rect2(65,442,425,95),6,55)
		_display(Rect2(65,610,425,95),6,55)
		var title := Label.new()
		title.text = "1942"
		title.position = Vector2(55,91)
		title.size = Vector2(445,145)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.add_theme_font_override("font",TITLE_FONT)
		title.add_theme_font_size_override("font_size",130)
		title.add_theme_color_override("font_color",CREAM)
		title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var paint := ShaderMaterial.new()
		paint.shader = preload("res://shaders/ui/stencil_paint.gdshader")
		title.material = paint
		add_child(title)

func _display(rect: Rect2, count: int, font_size: int) -> void:
	var instrument := DISPLAY.new()
	instrument.position = rect.position
	instrument.size = rect.size
	instrument.value = "0".repeat(count)
	instrument.font_size = font_size
	add_child(instrument)
	displays.append(instrument)

func refresh(delta: float) -> void:
	elapsed = fposmod(elapsed+delta,TAU*20.0)
	var combat = dashboard.combat
	if right_side:
		displays[0].set_value("%02d" % mini(combat.wave_count,99))
		displays[1].set_value("%02d" % mini(combat.kills,99))
		var seconds := ceili(maxf(0,combat.next_wave))
		displays[2].set_value("%02d:%02d" % [seconds/60,seconds%60] if combat.started and not combat.game_over else "--:--")
		radar_surface.material.set_shader_parameter("sweep",elapsed*0.75)
		_update_chart()
		dial_bank = lerpf(dial_bank,dashboard.player.bank.rotation.z,1.0-exp(-delta*7.0))
	else:
		displays[0].set_value("%06d" % mini(combat.score,999999))
		displays[1].set_value("%06d" % mini(dashboard.high_score,999999))
	queue_redraw()

func _update_chart() -> void:
	var camera: Camera3D = dashboard.flight.get_node("Camera")
	var viewport_size := Vector2(dashboard.viewport.size)
	var world_a := camera.project_position(Vector2.ZERO,camera.position.y)
	var world_b := camera.project_position(viewport_size,camera.position.y)
	radar_surface.material.set_shader_parameter("world_size",Vector2(absf(world_b.x-world_a.x),absf(world_b.z-world_a.z)))
	var data := PackedVector4Array()
	var details := PackedVector2Array()
	for island in dashboard.flight.get_node("Seascape").islands:
		var uv := camera.unproject_position(island.global_position)/viewport_size
		data.append(Vector4(uv.x,uv.y,island.mesh.size.x,island.mesh.size.y))
		details.append(Vector2(island.rotation.y,float(island.get_meta("variant"))))
	radar_surface.material.set_shader_parameter("island_data",data)
	radar_surface.material.set_shader_parameter("island_details",details)

func _text(text: String, at: Vector2, font_size: int, color := CREAM, title := false, centered := false) -> void:
	var font: Font = TITLE_FONT if title else LABEL_FONT
	var pos := at
	if centered: pos.x -= font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x*0.5
	draw_string(font,pos+Vector2(1,2),text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,Color(0,0,0,0.7))
	draw_string(font,pos,text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,color)

func _frame(rect: Rect2, filled := false) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.04,0.045,0.034,0.48) if filled else Color.TRANSPARENT
	box.border_color = BRASS
	box.set_border_width_all(1)
	box.set_corner_radius_all(12)
	box.shadow_color = Color(0,0,0,0.75)
	box.shadow_size = 5 if filled else 0
	box.shadow_offset = Vector2(2,3)
	draw_style_box(box,rect)
	draw_line(rect.position+Vector2(12,3),Vector2(rect.end.x-12,rect.position.y+3),Color(0.6,0.54,0.4,0.22),1,true)

func _rivet(pos: Vector2) -> void:
	draw_circle(pos+Vector2(1,3),12,Color(0,0,0,0.8))
	draw_circle(pos,10,Color("867250"))
	draw_circle(pos,8,Color("27271c"))
	draw_arc(pos,8,-PI,-0.3,20,Color("b7a077"),2,true)
	draw_line(pos+Vector2(-4,3),pos+Vector2(4,-3),Color("050806"),3,true)
	draw_line(pos+Vector2(-4,4),pos+Vector2(4,-2),Color("a08d64"),1,true)

func _plane(center: Vector2, radius: float, color: Color, angle := 0.0) -> void:
	var points := PackedVector2Array()
	for point in [Vector2(0,-1),Vector2(.11,-.72),Vector2(.11,-.24),Vector2(.85,-.18),Vector2(1,-.05),Vector2(.96,.13),Vector2(.1,.21),Vector2(.1,.72),Vector2(.4,.8),Vector2(.4,.94),Vector2(0,.9),Vector2(-.4,.94),Vector2(-.4,.8),Vector2(-.1,.72),Vector2(-.1,.21),Vector2(-.96,.13),Vector2(-1,-.05),Vector2(-.85,-.18),Vector2(-.11,-.24),Vector2(-.11,-.72)]:
		points.append(center+(point*radius).rotated(angle))
	draw_colored_polygon(points,color)

func _star(center: Vector2, radius: float) -> void:
	var points := PackedVector2Array()
	for i in range(10):
		points.append(center+Vector2.from_angle(-PI*.5+i*PI/5.0)*radius*(1.0 if i%2==0 else 0.42))
	draw_colored_polygon(points,CREAM)

func _draw() -> void:
	_frame(Rect2(15,14,525,1052))
	_frame(Rect2(23,22,509,1036))
	for point in [Vector2(34,34),Vector2(521,34),Vector2(34,1046),Vector2(521,1046)]: _rivet(point)
	var rail_x := 548.0 if not right_side else 6.0
	draw_line(Vector2(rail_x,0),Vector2(rail_x,1080),Color("b09a65"),3,true)
	draw_line(Vector2(rail_x-4,0),Vector2(rail_x-4,1080),Color("090c09"),3,true)
	if right_side: _draw_right()
	else: _draw_left()

func _draw_left() -> void:
	for side in [-1,1]:
		for stripe in range(3):
			var width := 92-stripe*14
			var x: float = 277+side*52
			if side<0: x -= width
			draw_rect(Rect2(x,262+stripe*14,width,8),CREAM)
	draw_arc(Vector2(277,285),50,0,TAU,80,CREAM,2,true)
	_star(Vector2(277,285),39)
	_text("P A C I F I C   T H E A T E R",Vector2(277,360),23,CREAM,false,true)
	_frame(Rect2(36,386,483,435),true)
	for point in [Vector2(50,400),Vector2(505,400),Vector2(50,807),Vector2(505,807)]: _rivet(point)
	_text("S C O R E",Vector2(72,428),28)
	_text("H I G H   S C O R E",Vector2(72,593),28)
	_text("V I E S",Vector2(72,770),27)
	for i in range(3):
		_plane(Vector2(266+i*80,763),26,CREAM if i<dashboard.combat.remaining_lives else Color("3c3d30"))
	_text("ESCADRILLE  01",Vector2(277,881),26,DIM,false,true)
	draw_line(Vector2(108,905),Vector2(447,905),Color("514b37"),1,true)
	var status := "PRÊT AU DÉCOLLAGE"
	var lamp := Color("e7a947")
	if dashboard.combat.game_over:
		status = "MISSION TERMINÉE"
		lamp = Color("fa5b37")
	elif dashboard.combat.respawn_time > 0:
		status = "RENFORT EN APPROCHE"
	elif dashboard.combat.started:
		status = "EN OPÉRATION"
		lamp = Color("9cae72")
	draw_circle(Vector2(105,944),9,Color("080b08"))
	draw_circle(Vector2(105,944),5,lamp)
	_text(status,Vector2(132,952),25,CREAM)
	_text("U.S. ARMY AIR FORCES",Vector2(277,1014),19,DIM,false,true)

func _draw_right() -> void:
	_text("V A G U E",Vector2(70,106),29)
	draw_line(Vector2(64,158),Vector2(490,158),BRASS,1,true)
	_text("A B A T T U S",Vector2(70,234),29)
	draw_line(Vector2(64,285),Vector2(490,285),BRASS,1,true)
	_text("PROCHAINE VAGUE",Vector2(277,321),27,CREAM,false,true)
	_frame(Rect2(42,441,471,388))
	_text("R A D A R   /   S E C T E U R  0 1",Vector2(277,464),21,CREAM,false,true)
	draw_rect(RADAR.grow(2),BRASS,false,2)
	_draw_contacts()
	_text("N",Vector2(277,494),18,DIM,false,true)
	_text("S",Vector2(277,795),18,DIM,false,true)
	_text("O",Vector2(76,643),18,DIM)
	_text("E",Vector2(474,643),18,DIM)
	_draw_dial(Vector2(145,934))
	_key("ESPACE","TIR",Vector2(265,872))
	_key("R","REJOUER",Vector2(265,925))
	_key("ÉCHAP","QUITTER",Vector2(265,978))
	_text("PACIFIC  /  1942",Vector2(277,1042),18,DIM,false,true)

func _key(key: String, caption: String, pos: Vector2) -> void:
	draw_rect(Rect2(pos,Vector2(98,34)),Color(0.03,0.04,0.03,0.65))
	draw_rect(Rect2(pos,Vector2(98,34)),DIM,false,1)
	_text(key,pos+Vector2(49,25),22,CREAM,false,true)
	_text(caption,pos+Vector2(115,25),21,CREAM)

func _draw_dial(center: Vector2) -> void:
	draw_circle(center+Vector2(2,4),89,Color("070907"))
	draw_circle(center,85,BRASS)
	draw_circle(center,81,Color("090e0b"))
	draw_arc(center,77,PI,TAU,80,Color("b09b70"),1,true)
	for i in range(48):
		var angle := i*TAU/48.0
		var outer := center+Vector2.from_angle(angle)*71
		var inner := center+Vector2.from_angle(angle)*(62 if i%4==0 else 67)
		draw_line(inner,outer,CREAM,1.5,true)
	draw_line(center+Vector2(-50,0),center+Vector2(50,0),Color("665c43"),1,true)
	_plane(center,38,CREAM,-dial_bank)
	_text("INCLINAISON",center+Vector2(0,52),16,DIM,false,true)

func _draw_contacts() -> void:
	var camera: Camera3D = dashboard.flight.get_node("Camera")
	var viewport_size := Vector2(dashboard.viewport.size)
	var inner := RADAR.grow(-24)
	# Contact positions use the actual gameplay camera, including barrel-roll motion.
	for enemy in dashboard.combat.enemies:
		if not is_instance_valid(enemy) or not enemy.alive: continue
		var uv := camera.unproject_position(enemy.global_position)/viewport_size
		if uv.x<0 or uv.x>1 or uv.y<0 or uv.y>1: continue
		var point := inner.position+uv*inner.size
		draw_circle(point,8,Color(1,0.18,0.06,0.07))
		draw_circle(point,5,Color(1,0.28,0.09,0.23))
		draw_circle(point,2.5,Color("ffae6b"))
	if dashboard.player.alive:
		var uv := camera.unproject_position(dashboard.player.global_position)/viewport_size
		uv = uv.clamp(Vector2.ZERO,Vector2.ONE)
		_plane(inner.position+uv*inner.size,9,CREAM)
