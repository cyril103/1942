extends SceneTree
## Authored visual inspection of production actors and scenery. Accelerated
## simulation is deliberately separate from the real-time performance replay.
const OUTPUT := "C:/ChatGPT/1942/renders/presentation-2.1"
const DT := 1.0/60.0
var app: Control
func _initialize() -> void: _run.call_deferred()
func silence(node: Node) -> void:
	if node is AudioStreamPlayer or node is AudioStreamPlayer3D: node.stop()
	for child in node.get_children(): silence(child)
func capture(label: String) -> void:
	for frame in range(6): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUTPUT.path_join(label+".png"))
func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	root.size = Vector2i(1920,1080)
	app = load("res://scenes/campaign.tscn").instantiate()
	app.testing = true
	app.profile.path = "user://presentation-21-never-saved.json"
	root.add_child(app)
	app.profile.reset()
	app.profile.data.unlocked = 32
	app.profile.data.settings.fullscreen = false
	app.profile.data.settings.shake = false
	app._show_main()
	await capture("00-accueil")
	for number in [4,8,12,16,20,24,28,32,19,27]:
		seed(1942)
		app.process_mode = Node.PROCESS_MODE_ALWAYS
		app.profile.data.aircraft = (number/4)%3
		var raid: bool = number in [19,27]
		app._launch(number,"campaign" if raid else "practice")
		var d: Node = app.director
		var flight: Node3D = app.cockpit.flight
		flight.get_node("Departure").finish_immediately()
		app.process_mode = Node.PROCESS_MODE_DISABLED
		app.cockpit.process_mode = Node.PROCESS_MODE_DISABLED
		d.player.invulnerable_time = 1000
		d.player.get_node("Hurtbox").collision_layer = 0
		var ticks := 37*60 if raid else 8*60
		for tick in range(ticks):
			d.combat._physics_process(DT)
			d.advance(DT)
			flight.get_node("Seascape")._physics_process(DT)
			flight.get_node("Clouds")._physics_process(DT)
			d.details._physics_process(DT)
			if tick%12==0: d.weapons._fire_salvo()
			d.weapons._physics_process(DT)
			if tick%60==0: await process_frame
		d.player.invulnerable_time = 0
		d.player.bank.show()
		flight.get_node("FleetFinish")._process(0)
		var hud: Control = app.cockpit.get_node("CampaignHUD")
		hud._process(0)
		hud.boss_intro_time = 0
		hud.queue_redraw()
		await capture("mission-%02d-%s" % [number,str(d.mission.biome)])
		silence(app)
		app._dispose_run()
		await process_frame
	app.process_mode = Node.PROCESS_MODE_ALWAYS
	app.music.stop()
	app.queue_free()
	await create_timer(.35).timeout
	print("PRESENTATION 2.1 CAPTURES COMPLETE")
	quit()
