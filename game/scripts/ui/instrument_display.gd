extends Control
## Recessed seven-segment instrument. Text is live, not baked into the texture.
const DIGITS = preload("res://assets/ui/fonts/DSEG7Classic-Regular.ttf")
var value := "000000"
var font_size := 54
var glass: ColorRect

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	glass = ColorRect.new()
	glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glass.position = Vector2(7, 7)
	glass.size = size - Vector2(14, 14)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/ui/instrument_glass.gdshader")
	mat.set_shader_parameter("dimensions", glass.size)
	glass.material = mat
	add_child(glass)

func set_value(next: String) -> void:
	if next != value:
		value = next
		queue_redraw()

func _draw() -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = Color("080a08")
	box.border_color = Color("6c6247")
	box.set_border_width_all(2)
	box.set_corner_radius_all(12)
	box.shadow_color = Color(0,0,0,0.8)
	box.shadow_size = 6
	box.shadow_offset = Vector2(1,3)
	draw_style_box(box, Rect2(Vector2.ZERO,size))
	draw_line(Vector2(12,size.y-4),Vector2(size.x-12,size.y-4),Color("22251b"),2,true)
	var text_width := DIGITS.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
	var pos := Vector2((size.x-text_width)*0.5, (size.y-DIGITS.get_height(font_size))*0.5+DIGITS.get_ascent(font_size))
	var ghost := ""
	for character in value:
		ghost += character if character == ":" or character == " " else "8"
	draw_string(DIGITS,pos,ghost,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,Color(0.24,0.13,0.055,0.32))
	draw_string_outline(DIGITS,pos,value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,10,Color(1,0.19,0.015,0.045))
	draw_string_outline(DIGITS,pos,value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,5,Color(1,0.28,0.01,0.12))
	draw_string_outline(DIGITS,pos,value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,2,Color(1,0.42,0.025,0.45))
	draw_string(DIGITS,pos,value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,Color("ffba4c"))
