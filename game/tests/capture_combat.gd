extends SceneTree
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	scene.get_node("Departure").finish_immediately()
	var combat = scene.get_node("Combat")
	var player = scene.get_node("Player")
	for node_name in ["Combat", "Weapons", "Seascape", "Player"]:
		scene.get_node(node_name).set_physics_process(false)
	player.position.x = -7.0
	player.get_node("Hurtbox").collision_layer = 0
	var previous := 0
	var times := [2.8, 3.3, 4.8, 6.6]
	for index in range(times.size()):
		var target: int = roundi(times[index] * 60)
		for tick in range(target - previous):
			combat._physics_process(1.0 / 60.0)
			scene.get_node("Seascape")._physics_process(1.0 / 60.0)
		previous = target
		for frame in range(8): await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../renders/combat-%02d.png" % index))
	player.take_damage(1)
	combat._physics_process(0.12)
	for frame in range(8): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../renders/combat-defeat.png"))
	quit()
