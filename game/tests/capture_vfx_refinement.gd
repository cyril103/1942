extends SceneTree
## Authored production-effect gallery; not a human playthrough.
var output := "C:/ChatGPT/1942/renders/sublime-vfx"
func _initialize() -> void: _run.call_deferred()
func freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children(): freeze(child)
func silence(node: Node) -> void:
	if node is AudioStreamPlayer or node is AudioStreamPlayer3D: node.stop()
	for child in node.get_children(): silence(child)
func capture(label: String) -> void:
	for frame in range(6): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label+".png"))
func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1920,1080)
	var app: Node = load("res://scenes/campaign.tscn").instantiate()
	app.testing = true
	app.profile.path = "user://vfx-refinement-capture.json"
	root.add_child(app)
	app.profile.reset()
	app.profile.data.settings.fullscreen = false
	app._launch(1)
	app.cockpit.flight.get_node("Departure").finish_immediately()
	freeze(app)
	var d: Node = app.director
	var c: Node = d.combat
	d.player.invulnerable_time = 0
	d.feedback_time = 0
	d.radio_time = 0
	for index in range(5):
		var effect: Node3D = c.effects[index]
		effect.scale = Vector3.ONE*effect.AIRCRAFT_EFFECT_SCALE*1.7
		effect.trigger(Vector3(-9+index*4.5,0,-2),float(index)*1.713)
		effect.advance([.07,.20,.43,.74,1.12][index])
		d.details.burst(Vector3(-9+index*4.5,0,-2))
	d.details._physics_process(.24)
	# Genuine pooled enemy rounds beneath the smoke gallery verify separation.
	for index in range(5):
		c._launch_enemy_round(Vector3(-9+index*4.5,.0,1.2),Vector3(-9+index*4.5,0,10),1)
	await capture("explosion-life-and-projectiles-1080")
	for effect in c.effects: effect.hide()
	d.details.enabled = false
	d.details._physics_process(2)
	c.clear_enemy_bullets()
	d.details.enabled = true
	d.details.reduced_flash = false
	d.player.bank.rotation.z = .45
	d.details.impact(d.player.position+Vector3(0,.2,-3),false)
	d.details._physics_process(.06)
	await capture("banking-condensation-and-impact-1080")
	d.profile.data.settings.flashes = false
	c.effects[0].trigger(Vector3(0,0,-2),.3)
	c.effects[0].advance(.07)
	await capture("explosion-reduced-flash-1080")
	silence(app)
	await create_timer(.25).timeout
	app._show_main()
	silence(app)
	await create_timer(.25).timeout
	app.queue_free()
	await create_timer(.25).timeout
	print("VFX captures: ",output)
	quit()
