extends SceneTree
## A synthetic coastline separates the real land/water interface from the
## atlas alpha boundary and exercises bays, small rocks and isolated reef flecks.
const RELIEF := preload("res://scripts/island_relief.gd")
var checks := 0
var failures: Array[String] = []
func check(ok: bool,message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)
func shore_px(field: Image,x: int,y: int) -> float:
	return (field.get_pixel(x,y).a-.5)*RELIEF.COAST_DISTANCE_PIXELS*2.0
func _initialize() -> void:
	var source := Image.create(256,256,false,Image.FORMAT_RGBA8)
	var field := Image.create(256,256,false,Image.FORMAT_RGBA8)
	var sea := Color(.06,.43,.54,1.0)
	var forest := Color(.18,.42,.07,1.0)
	source.fill(sea)
	source.fill_rect(Rect2i(32,32,64,64),forest)
	# Open a long bay from the north into the island.
	source.fill_rect(Rect2i(56,30,17,48),sea)
	# Preserve a genuine offshore rock but suppress one isolated brown reef pixel.
	source.fill_rect(Rect2i(107,62,5,5),Color(.38,.34,.29,1))
	source.set_pixel(8,64,Color(.23,.20,.13,1))
	RELIEF._build_cell(source,field,Vector2i.ZERO)
	check(source.get_pixel(26,64).a==source.get_pixel(40,64).a,"Fixture has no alpha boundary at its shore")
	check(shore_px(field,30,64)>0 and shore_px(field,34,64)<0,"Distance follows wet/dry interface rather than sprite opacity")
	var quantization := RELIEF.COAST_DISTANCE_PIXELS*2.0/255.0
	check(absf(shore_px(field,31,64)-.5)<=quantization and absf(shore_px(field,32,64)+.5)<=quantization,"Zero lies halfway between wet and dry pixel centres within one encoded step")
	var monotonic := true
	var previous := shore_px(field,20,64)
	for x in range(21,44):
		var next := shore_px(field,x,64)
		monotonic = monotonic and next<previous+.001
		previous = next
	check(monotonic,"Incoming foam can traverse the straight coastline continuously")
	check(shore_px(field,64,64)>6 and shore_px(field,53,64)<0,"Concave bay keeps its own water and coast")
	check(shore_px(field,64,82)<0,"Land behind the bay stays inland")
	check(shore_px(field,109,64)<0 and shore_px(field,114,64)>0,"Small offshore rocks retain their own surrounding surf")
	check(shore_px(field,8,64)>20,"Isolated reef pigment cannot manufacture a ring of foam")
	check(field.get_pixel(8,64).g>.5,"Reef filtering does not alter the existing relief land channel")
	check(field.get_pixel(64,64).r==0 and field.get_pixel(22,64).r==0,"Bay and open water remain geometrically flat")
	check(field.get_pixel(44,64).r>.1,"Inland terrain retains raised geometry")
	check(is_equal_approx(shore_px(field,3,3),RELIEF.COAST_DISTANCE_PIXELS),"Far water saturates safely outside the surf reach")
	# Land in the next atlas quadrant must never create a false coast in this cell.
	source.fill_rect(Rect2i(128,0,128,128),forest)
	RELIEF._build_cell(source,field,Vector2i.ZERO)
	check(shore_px(field,125,20)>20,"Neighbouring atlas quadrants cannot leak shoreline distance")
	var shader := load("res://shaders/island.gdshader") as Shader
	var names: Array[String] = []
	for uniform in shader.get_shader_uniform_list(): names.append(str(uniform.name))
	check(names.has("relief_atlas") and names.has("wave_phase"),"Production shader compiles its shared surf and signed-distance inputs")
	print("SHORE DISTANCE: ",checks," checks; failures: ",failures)
	quit(0 if failures.is_empty() else 1)
