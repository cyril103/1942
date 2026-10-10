extends SceneTree
## Authored inspection frames, separate from real-time performance measurements.
const OUTPUT := "C:/ChatGPT/1942/renders/atmosphere-2.2"
const DT := 1.0/60.0
var app: Control
var shore_only := false

func _initialize() -> void: _run.call_deferred()

func capture(label: String) -> void:
	for frame in range(6): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUTPUT.path_join(label+".png"))

func _run() -> void:
	shore_only = "--shore-only" in OS.get_cmdline_user_args()
	AudioServer.set_bus_mute(0,true)
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	root.size = Vector2i(1920,1080)
	app = load("res://scenes/campaign.tscn").instantiate()
	app.testing = true
	app.profile.path = "user://atmosphere-22-never-saved.json"
	root.add_child(app)
	app.profile.reset()
	app.profile.data.unlocked = 32
	app.profile.data.settings.fullscreen = false
	app.profile.data.settings.shake = false
	app._show_main()
	if not shore_only: await capture("00-accueil")
	for number in ([8] if shore_only else [4,8,12,16,20,24,28,32,19,27]):
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
		for tick in range(0 if shore_only else (37*60 if raid else 8*60)):
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
		if not shore_only: await capture("mission-%02d-%s" % [number,str(d.mission.biome)])
		if not shore_only and number in [4,8,32] and is_instance_valid(d.boss):
			d.boss._cancel_attack()
			d.boss._begin_attack(d)
			d.boss.advance(d.boss.warning_duration*.55,d)
			hud._process(0)
			hud.queue_redraw()
			await capture("boss-%02d-charge-sans-trajectoires" % number)
		if number==8:
			# A paused, enlarged production island at multiple wave phases.
			# Only framing and placement differ from a normal sortie.
			var sea: Node3D = flight.get_node("Seascape")
			flight.get_node("Clouds").hide()
			d.combat.hide()
			d.weapons.hide()
			d.player.hide()
			d.details.hide()
			flight.get_node("FleetFinish").hide()
			hud.hide()
			for island in sea.islands: island.hide()
			var island: MeshInstance3D = sea.islands[0]
			island.show()
			island.position = Vector3(0,-3,0)
			island.rotation.y = -.15
			island.mesh.size = Vector2(22,22)
			var atlas := preload("res://assets/environment/archipelago-atlas.png")
			island.material_override.set_shader_parameter("island_atlas",atlas)
			island.material_override.set_shader_parameter("relief_atlas",preload("res://scripts/island_relief.gd").texture_for(atlas))
			island.material_override.set_shader_parameter("atlas_cell",Vector2(1,0))
			island.material_override.set_shader_parameter("island_size",Vector2(22,22))
			island.material_override.set_shader_parameter("phase_offset",0.0)
			for phase in range(4):
				var value := float(phase)*.6
				sea.ocean_material.set_shader_parameter("wave_phase",value)
				island.material_override.set_shader_parameter("wave_phase",value)
				await capture("ressac-phase-%d" % phase)
		app._dispose_run()
		await process_frame
	app.process_mode = Node.PROCESS_MODE_ALWAYS
	app.music.stop()
	app.queue_free()
	await create_timer(.35).timeout
	print("ATMOSPHERE 2.2 CAPTURES COMPLETE; AUDIO MUTED")
	quit()
