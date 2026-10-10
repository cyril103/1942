extends Node3D
## One bounded shadow batch; material work happens once when an actor spawns.
const CAPACITY := 48
var enhance: Callable
var batch: MultiMeshInstance3D
var actors: Array[Dictionary] = []
var combat: Node3D
var player: Node3D
var sea: Node3D
var sun: DirectionalLight3D

func _ready() -> void:
	combat = get_parent().get_node("Combat")
	player = get_parent().get_node("Player")
	sea = get_parent().get_node("Seascape")
	sun = get_parent().get_node("KeyLight")
	batch = MultiMeshInstance3D.new()
	batch.name = "AircraftOceanShadows"
	batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/fleet_shadow.gdshader")
	plane.material = material
	var instances := MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	instances.use_colors = true
	instances.mesh = plane
	instances.instance_count = CAPACITY
	instances.visible_instance_count = 0
	batch.multimesh = instances
	add_child(batch)
	_track(player,player.get_node("Bank"))
	combat.child_entered_tree.connect(_actor_entered)
	for child in combat.get_children(): _actor_entered(child)

func _actor_entered(actor: Node) -> void:
	if actor is Area3D: _finish_actor.call_deferred(actor.get_instance_id())

func _finish_actor(identity: int) -> void:
	var actor := instance_from_id(identity) as Node3D
	if not is_instance_valid(actor) or actor.is_queued_for_deletion(): return
	var visual: Node3D = actor.get("visual") as Node3D
	if not is_instance_valid(visual): return
	if enhance.is_valid(): enhance.call(visual)
	# Hulls sit in the water and use their own wake. Only aircraft cast these cards.
	if visual.position.y< -1.0: return
	_track(actor,visual)

func _track(actor: Node3D, visual: Node3D) -> void:
	for entry in actors:
		if entry.actor==actor: return
	if actors.size()>=CAPACITY:
		actors = actors.filter(func(entry): return is_instance_valid(entry.actor))
	if actors.size()>=CAPACITY: return
	var bounds := AABB()
	var initialized := false
	var inverse := actor.global_transform.affine_inverse()
	for child in visual.find_children("*","MeshInstance3D",true,false):
		if child.mesh==null or child.material_override!=null: continue
		var extent: AABB = inverse*child.global_transform*child.get_aabb()
		bounds = bounds.merge(extent) if initialized else extent
		initialized = true
	if not initialized: return
	# The departure temporarily scales the player's bank to .68 on the deck.
	var takeoff_scale := maxf(.1,visual.scale.x) if actor==player else 1.0
	actors.append({"actor":actor,"visual":visual,"width":clampf(bounds.size.x/takeoff_scale,1,9),"depth":clampf(bounds.size.z/takeoff_scale,1,7)})

func _process(_delta: float) -> void:
	if not is_instance_valid(sea.ocean): return
	var used := 0
	var water: float = sea.ocean.global_position.y+.055
	var light_ray := -sun.global_basis.z
	var light_offset := Vector2(light_ray.x,light_ray.z)/maxf(.3,-light_ray.y)
	# A raid landmass lies above its ocean. Hide cards there rather than projecting
	# an ocean shadow through the plateau or the carrier deck.
	var above_land: bool = is_instance_valid(combat.campaign_driver) and is_instance_valid(combat.campaign_driver.assault) and combat.campaign_driver.assault.low_flight>.015
	for entry in actors:
		if not is_instance_valid(entry.actor) or not is_instance_valid(entry.visual): continue
		var actor: Node3D = entry.actor
		var visual: Node3D = entry.visual
		if not actor.is_visible_in_tree() or not visual.is_visible_in_tree() or actor.is_queued_for_deletion(): continue
		if above_land: continue
		if actor==player and not player.controls_enabled: continue
		var altitude := maxf(.1,visual.global_position.y-water)
		var offset := light_offset*minf(altitude,6)*.24
		var location := Vector3(actor.global_position.x+offset.x,water,actor.global_position.z+offset.y)
		var heading := actor.global_rotation.y+(0.0 if actor==player else PI)
		var spread := 1.08+altitude*.025
		var pose := Transform3D(Basis(Vector3.UP,heading).scaled(Vector3(entry.width*spread,1,entry.depth*spread)),location)
		batch.multimesh.set_instance_transform(used,pose)
		batch.multimesh.set_instance_color(used,Color(1,1,1,clampf(1.1-altitude*.055,.35,1.0)))
		used += 1
		if used>=CAPACITY: break
	batch.multimesh.visible_instance_count = used
	actors = actors.filter(func(entry): return is_instance_valid(entry.actor))
