extends SceneTree
const MATERIALS := preload("res://scripts/campaign/materials.gd")
var checks := 0
var failures: Array[String] = []
class DirectorFixture extends Node:
	var combat: Node3D

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func _initialize() -> void: _run.call_deferred()

func _freeze(node: Node) -> void:
	node.set_physics_process(false)
	node.set_process(false)
	for child in node.get_children(): _freeze(child)

func _surfaces(model: Node3D) -> Array[Material]:
	var result: Array[Material] = []
	for mesh in model.find_children("*","MeshInstance3D",true,false):
		for surface in range(mesh.mesh.get_surface_count()): result.append(mesh.get_active_material(surface))
	return result

func _run() -> void:
	for path in ["res://assets/aircraft.glb","res://assets/player-fleet/p38.glb","res://assets/player-fleet/f4u.glb","res://assets/enemies/zero.glb"]:
		var model: Node3D = load(path).instantiate()
		root.add_child(model)
		var original := _surfaces(model)
		var count := model.find_children("*","MeshInstance3D",true,false).size()
		MATERIALS.enhance_aircraft(model)
		var improved := _surfaces(model)
		check(model.find_children("*","MeshInstance3D",true,false).size()==count,"Finishing preserves mesh count and silhouette: "+path)
		check(improved.any(func(material): return material is ShaderMaterial and material.shader==MATERIALS.PAINT),"Authored aircraft skin receives the cinematic PBR shader: "+path)
		MATERIALS.enhance_aircraft(model)
		check(_surfaces(model)==improved,"Repeated finishing is idempotent: "+path)
		check(original.all(func(material): return material is StandardMaterial3D),"Imported materials remain untouched: "+path)
		var untouched: Node3D = load(path).instantiate()
		check(_surfaces(untouched)==original,"A second import still has the original shared material resources: "+path)
		untouched.free()
		model.queue_free()
		await process_frame
	var scene: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	_freeze(scene)
	for biome in MATERIALS.PALETTES:
		MATERIALS.flight_lighting(scene,biome)
		check(scene.get_node("WorldEnvironment").environment.sky==MATERIALS.sky_cache[biome],"Biome reflection sky is applied: "+biome)
	check(MATERIALS.sky_cache.size()==8,"Exactly eight reusable reflection environments exist")
	var finish: Node3D = scene.get_node("FleetFinish")
	check(finish.batch.multimesh.instance_count==48,"Fleet shadows use one fixed 48-slot batch")
	check(scene.get_children().filter(func(child): return child.name=="FleetFinish").size()==1,"Changing lighting never duplicates the fleet runtime")
	scene.get_node("Departure").finish_immediately()
	finish._process(0)
	check(finish.batch.multimesh.visible_instance_count==1,"Active player casts one ocean shadow")
	var combat: Node3D = scene.get_node("Combat")
	combat.automatic_waves = false
	combat.spawn_wave()
	await process_frame
	finish._process(0)
	check(finish.actors.size()==5,"New production enemies join the fleet without changing their spawner")
	var actor: Area3D = combat.enemies[0]
	check(_surfaces(actor.visual).any(func(material): return material is ShaderMaterial and material.shader==MATERIALS.PAINT),"Spawned production enemy receives its finish after ready")
	var hp: float = actor.health
	MATERIALS.enhance_aircraft(actor.visual)
	check(actor.health==hp and actor.collision_layer==2,"Materials leave actor health and collision untouched")
	for enemy in combat.enemies: enemy.retire()
	await process_frame
	finish._process(0)
	check(finish.actors.size()==1 and finish.batch.multimesh.visible_instance_count==1,"Retired actors release shadow entries instead of accumulating")
	var naval := preload("res://scripts/campaign/enemy_naval.gd").new()
	combat.add_child(naval)
	await process_frame
	var hull_surfaces := _surfaces(naval.visual)
	check(hull_surfaces.any(func(material): return material is ShaderMaterial and material.shader==MATERIALS.HULL),"Production naval hull uses its separate weathered material")
	var hull_mesh := naval.visual.find_children("*","MeshInstance3D",true,false)[0] as MeshInstance3D
	check(hull_mesh.material_overlay==naval.hit_material,"Deferred enhancement preserves the naval hit overlay")
	naval.take_damage(1)
	naval.advance(.1,combat)
	check(_surfaces(naval.visual)==hull_surfaces,"A naval hit never resets the cinematic surfaces")
	check(finish.actors.size()==1,"Surface ships do not allocate aircraft shadow cards")
	naval.retire()
	var boss := preload("res://scripts/campaign/boss.gd").new()
	boss.kind = "bomber"
	boss.combat = combat
	combat.add_child(boss)
	await process_frame
	var boss_surfaces := _surfaces(boss.visual)
	var boss_mesh := boss.visual.find_children("*","MeshInstance3D",true,false)[0] as MeshInstance3D
	check(boss_mesh.material_overlay==boss.hit_material,"Deferred enhancement preserves the boss hit overlay")
	boss.collision_layer = 2
	boss.take_damage(boss.health)
	var fixture := DirectorFixture.new()
	fixture.combat = combat
	boss.advance(1,fixture)
	check(boss.dying and _surfaces(boss.visual)==boss_surfaces,"Boss destruction preserves base materials throughout the explosion sequence")
	boss.advance(2,fixture)
	fixture.free()
	await process_frame
	finish._process(0)
	check(finish.actors.size()==1,"A boss completing its death sequence releases its shadow card")
	scene.get_node("Player").controls_enabled = false
	finish._process(0)
	check(finish.batch.multimesh.visible_instance_count==0,"Ocean shadow is hidden during carrier choreography")
	scene.queue_free()
	current_scene = null
	await process_frame
	await create_timer(.15).timeout
	print("CINEMATIC FLEET: ",checks," checks; failures: ",failures)
	quit(0 if failures.is_empty() else 1)
