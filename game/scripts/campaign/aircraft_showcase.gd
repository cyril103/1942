extends Control
## Real production aircraft, isolated lighting, bounded render target. No save or
## combat state is created by the showroom. Dragging changes presentation only.
const MODELS := ["res://assets/aircraft.glb","res://assets/player-fleet/p38.glb","res://assets/player-fleet/f4u.glb"]
static var _studio_sky: Sky
var aircraft_index := 0
var compact := false
var reduced_motion := false
var quality := 1
var viewport: SubViewport
var pivot: Node3D
var model: Node3D
var camera: Camera3D
var props: Array[Node3D] = []
var elapsed := 0.0
var yaw := -0.42
var pitch := 0.0
var zoom := 5.9
var dragging := false
var resting_height := 0.0
var _meshes := 0

func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE if compact else Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE if compact else Control.FOCUS_CLICK
	viewport = SubViewport.new()
	viewport.name = "AircraftStudio"
	viewport.own_world_3d = true
	viewport.transparent_bg = false
	viewport.msaa_3d = [Viewport.MSAA_DISABLED,Viewport.MSAA_2X,Viewport.MSAA_4X][clampi(quality,0,2)]
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var image := TextureRect.new()
	image.texture = viewport.get_texture()
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(image)
	var world := Node3D.new()
	viewport.add_child(world)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("0a1922")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("94b8d0")
	environment.ambient_light_energy = .55
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	if _studio_sky==null:
		_studio_sky = Sky.new()
		var atmosphere := ProceduralSkyMaterial.new()
		atmosphere.sky_top_color = Color("294866")
		atmosphere.sky_horizon_color = Color("d8e5e7")
		atmosphere.ground_horizon_color = Color("bd9c75")
		atmosphere.ground_bottom_color = Color("16222e")
		_studio_sky.sky_material = atmosphere
		_studio_sky.radiance_size = Sky.RADIANCE_SIZE_128
		_studio_sky.process_mode = Sky.PROCESS_MODE_QUALITY
	environment.sky = _studio_sky
	var holder := WorldEnvironment.new()
	holder.environment = environment
	world.add_child(holder)
	_light(world,Vector3(-.78,-.4,-.4),Color("ffe4b7"),1.6,true)
	_light(world,Vector3(-.40,2.5,.2),Color("89b5e0"),.45,false)
	_light(world,Vector3(.45,2.4,.0),Color("c8eaff"),.85,false)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.5 if compact else zoom
	camera.position = Vector3(6.0,3.2,14.0) if compact else Vector3(7.8,5.8,11.5)
	world.add_child(camera)
	camera.look_at(Vector3(0,.65,0))
	camera.current = true
	pivot = Node3D.new()
	world.add_child(pivot)
	model = (load(MODELS[clampi(aircraft_index,0,2)]) as PackedScene).instantiate()
	pivot.add_child(model)
	var bounds := _bounds(model)
	var factor := 7.1 / maxf(bounds.size.x,bounds.size.z)
	model.scale = Vector3.ONE * factor
	model.position = -bounds.get_center() * factor
	resting_height = bounds.size.y * factor * .5 + .28
	pivot.position.y = resting_height
	pivot.rotation.y = yaw
	if compact: camera.look_at(Vector3(0,resting_height,0))
	preload("res://scripts/campaign/materials.gd").enhance_aircraft(model)
	for prop_name in ["Propeller_L","Propeller_R","Propeller_Center"]:
		var prop := model.find_child(prop_name,true,false) as Node3D
		if prop!=null: props.append(prop)
	var deck := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(120,120)
	deck.mesh = plane
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/showcase_deck.gdshader")
	deck.material_override = material
	world.add_child(deck)
	# Finite lamps frame the aircraft and give its metal a coherent environment.
	for x in [-5.0,5.0]:
		for z in [-4.5,0.0,4.5]:
			var lamp := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(.08,.035,.9)
			lamp.mesh = box
			lamp.position = Vector3(x,.025,z)
			var lit := StandardMaterial3D.new()
			lit.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			lit.albedo_color = Color("a8c8d3")
			lamp.material_override = lit
			world.add_child(lamp)
	resized.connect(_resize)
	get_viewport().size_changed.connect(_resize)
	_resize()

func _light(world: Node3D, angle: Vector3, color: Color, energy: float, shadows: bool) -> void:
	var light := DirectionalLight3D.new()
	light.rotation = angle
	light.light_color = color
	light.light_energy = energy
	light.shadow_enabled = shadows and quality>0
	light.directional_shadow_max_distance = 28.0
	light.shadow_bias = .035
	world.add_child(light)

func _bounds(root_model: Node3D) -> AABB:
	var result := AABB()
	var initialized := false
	for item in root_model.find_children("*","MeshInstance3D",true,false):
		var mesh := item as MeshInstance3D
		if mesh.mesh==null: continue
		var transform_to_root := root_model.global_transform.affine_inverse()*mesh.global_transform
		var aabb := transform_to_root*mesh.get_aabb()
		result = result.merge(aabb) if initialized else aabb
		initialized = true
		_meshes += 1
	return result

func _resize() -> void:
	if viewport==null: return
	# Thumbnails stay small even on a high-DPI desktop; full inspection is 1080p.
	var pixels := size * get_global_transform().get_scale()
	var limit := 640.0 if compact else 1440.0
	var factor := minf(1.0,limit/maxf(pixels.x,1.0))
	viewport.size = Vector2i(maxi(2,roundi(pixels.x*factor)),maxi(2,roundi(pixels.y*factor)))

func _process(delta: float) -> void:
	if pivot==null or not is_visible_in_tree(): return
	elapsed += delta
	var drift := 0.0 if reduced_motion or dragging else sin(elapsed*.24)*(.035 if compact else .07)
	pivot.rotation = Vector3(pitch,yaw+drift,0)
	for prop in props:
		if not reduced_motion: prop.rotate_z(delta*2.6)

func set_view(index: int) -> void:
	yaw = [-.42,PI*.5,0.0][clampi(index,0,2)]
	pitch = 0
	camera.position = Vector3(0,16,.01) if index==2 else (Vector3(0,3.2,15) if index==1 else Vector3(7.8,5.8,11.5))
	camera.look_at(Vector3(0,.65,0))
	camera.size = zoom

func _gui_input(event: InputEvent) -> void:
	if compact: return
	if event is InputEventMouseButton:
		if event.button_index==MOUSE_BUTTON_LEFT:
			dragging = event.pressed
			if dragging: grab_focus()
			accept_event()
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			zoom = clampf(zoom+(-.4 if event.button_index==MOUSE_BUTTON_WHEEL_UP else .4),5.0,11.0)
			camera.size = zoom
			accept_event()
	elif event is InputEventMouseMotion and dragging:
		yaw += event.relative.x*.008
		pitch = clampf(pitch+event.relative.y*.004,-.25,.25)
		accept_event()

func _notification(what: int) -> void:
	if what==NOTIFICATION_VISIBILITY_CHANGED and viewport!=null:
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if is_visible_in_tree() else SubViewport.UPDATE_DISABLED
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT: dragging = false
