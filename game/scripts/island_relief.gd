extends RefCounted
## A small, cached height field follows the actual painted coast of each atlas.
## No land can grow outside the existing navigation rectangle. Water and lagoons
## remain at sea level; inland distance builds continuous ridges above beaches.
const CELL_SIZE := 128
const RELIEF_HEIGHT := 1.65
const SUBDIVISIONS := 56
## Alpha stores a signed shore distance: .5 at shore, positive toward water.
## RGB retains the existing relief/land/interior-distance contract.
const COAST_DISTANCE_PIXELS := 24.0
static var _cache: Dictionary = {}

static func texture_for(atlas: Texture2D) -> Texture2D:
	var key := atlas.resource_path if not atlas.resource_path.is_empty() else str(atlas.get_instance_id())
	if _cache.has(key): return _cache[key]
	var source := atlas.get_image()
	if source.is_compressed(): source.decompress()
	source.resize(CELL_SIZE*2,CELL_SIZE*2,Image.INTERPOLATE_LANCZOS)
	var field := Image.create(CELL_SIZE*2,CELL_SIZE*2,false,Image.FORMAT_RGBA8)
	for cell_y in range(2):
		for cell_x in range(2):
			_build_cell(source,field,Vector2i(cell_x,cell_y)*CELL_SIZE)
	field.generate_mipmaps()
	var texture := ImageTexture.create_from_image(field)
	_cache[key] = texture
	return texture

static func _build_cell(source: Image,field: Image,offset: Vector2i) -> void:
	var distances := PackedFloat32Array()
	var land := PackedFloat32Array()
	distances.resize(CELL_SIZE*CELL_SIZE)
	land.resize(distances.size())
	for y in range(CELL_SIZE):
		for x in range(CELL_SIZE):
			var color := source.get_pixel(x+offset.x,y+offset.y)
			var water := smoothstep(.02,.16,color.g-color.r)*smoothstep(.015,.09,color.b-color.r)
			var is_land := color.a>.72 and water<.42 and x>2 and y>2 and x<CELL_SIZE-3 and y<CELL_SIZE-3
			var i := y*CELL_SIZE+x
			land[i] = 1.0 if is_land else 0.0
			distances[i] = 1000.0 if is_land else 0.0
	# Chamfer distance keeps lagoons open and connects ridges without radial domes.
	for y in range(1,CELL_SIZE-1):
		for x in range(1,CELL_SIZE-1):
			var i := y*CELL_SIZE+x
			distances[i] = minf(distances[i],minf(distances[i-1]+1,minf(distances[i-CELL_SIZE]+1,minf(distances[i-CELL_SIZE-1],distances[i-CELL_SIZE+1])+1.4142)))
	for y in range(CELL_SIZE-2,0,-1):
		for x in range(CELL_SIZE-2,0,-1):
			var i := y*CELL_SIZE+x
			distances[i] = minf(distances[i],minf(distances[i+1]+1,minf(distances[i+CELL_SIZE]+1,minf(distances[i+CELL_SIZE-1],distances[i+CELL_SIZE+1])+1.4142)))
	# Tiny brown reef texels are not individual coastlines. A majority filter
	# suppresses those flecks before building the surf distance, while retaining
	# bays, lagoons and the outlines of small real rocks. Relief itself is unchanged.
	var shore_land := PackedFloat32Array()
	shore_land.resize(land.size())
	for y in range(1,CELL_SIZE-1):
		for x in range(1,CELL_SIZE-1):
			var neighbours := 0.0
			for dy in range(-1,2):
				for dx in range(-1,2): neighbours += land[(y+dy)*CELL_SIZE+x+dx]
			shore_land[y*CELL_SIZE+x] = 1.0 if neighbours>=5.0 else 0.0
	var distance_to_land := _coast_distance(shore_land,true)
	var distance_to_water := _coast_distance(shore_land,false)
	# Smooth only the signed coast, never the height or gameplay land channel.
	# A one-texel Gaussian removes square notches from the low-resolution mask
	# without adding texture memory, runtime fetches or growing tiny reef flecks.
	var signed_coast := PackedFloat32Array()
	signed_coast.resize(land.size())
	for i in range(land.size()):
		var signed_distance := distance_to_land[i]-distance_to_water[i]
		# The coast lies half way between the first wet and dry texel centres.
		signed_distance -= signf(signed_distance)*.5
		signed_coast[i] = clampf(signed_distance,-COAST_DISTANCE_PIXELS,COAST_DISTANCE_PIXELS)
	for y in range(CELL_SIZE):
		for x in range(CELL_SIZE):
			var i := y*CELL_SIZE+x
			var color := source.get_pixel(x+offset.x,y+offset.y)
			var distance := distances[i]
			var inland := smoothstep(0.0,15.0,distance)
			var ridges := .8+.12*sin(x*.18+y*.13)+.08*sin(x*.31-y*.22)
			var rock := 1.0-smoothstep(.02,.14,color.g-color.b)
			var height := clampf(inland*(.78+rock*.22)*ridges,0.0,1.0)
			var signed_distance := signed_coast[i]
			if x>0 and y>0 and x<CELL_SIZE-1 and y<CELL_SIZE-1:
				signed_distance = (signed_coast[i]*4.0 + (signed_coast[i-1]+signed_coast[i+1]+signed_coast[i-CELL_SIZE]+signed_coast[i+CELL_SIZE])*2.0 + signed_coast[i-CELL_SIZE-1]+signed_coast[i-CELL_SIZE+1]+signed_coast[i+CELL_SIZE-1]+signed_coast[i+CELL_SIZE+1])/16.0
			var coast := clampf(.5+signed_distance/(COAST_DISTANCE_PIXELS*2.0),0,1)
			field.set_pixel(x+offset.x,y+offset.y,Color(height,land[i],clampf(distance/15.0,0,1),coast))

static func _coast_distance(mask: PackedFloat32Array,to_land: bool) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	result.resize(mask.size())
	for i in range(mask.size()): result[i] = 0.0 if (mask[i]>.5)==to_land else 1000.0
	for y in range(1,CELL_SIZE-1):
		for x in range(1,CELL_SIZE-1):
			var i := y*CELL_SIZE+x
			result[i] = minf(result[i],minf(result[i-1]+1,minf(result[i-CELL_SIZE]+1,minf(result[i-CELL_SIZE-1],result[i-CELL_SIZE+1])+1.4142)))
	for y in range(CELL_SIZE-2,0,-1):
		for x in range(CELL_SIZE-2,0,-1):
			var i := y*CELL_SIZE+x
			result[i] = minf(result[i],minf(result[i+1]+1,minf(result[i+CELL_SIZE]+1,minf(result[i+CELL_SIZE-1],result[i+CELL_SIZE+1])+1.4142)))
	return result
