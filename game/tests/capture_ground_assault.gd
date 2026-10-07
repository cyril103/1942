extends SceneTree
var app: Control
func _initialize() -> void: _run.call_deferred()
func capture(label: String) -> void:
	for frame in range(5): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("C:/ChatGPT/1942/renders/assault-"+label+".png")
func _run() -> void:
	root.size = Vector2i(1920,1080)
	app = load("res://scenes/campaign.tscn").instantiate()
	app.testing = true
	root.add_child(app)
	current_scene = app
	await process_frame
	app.profile.reset()
	app.profile.data.unlocked = 32
	app._show_briefing(3)
	await capture("briefing")
	app._launch(3)
	var d = app.director
	var flight = app.cockpit.flight
	flight.get_node("Departure").finish_immediately()
	for name_text in ["Seascape","Clouds","Combat","Player","Weapons","Departure"]: flight.get_node(name_text).set_physics_process(false)
	d.set_physics_process(false)
	d.details.set_physics_process(false)
	d.player.invulnerable_time = 0
	d.player.get_node("Hurtbox").collision_layer = 0
	d.player.position = Vector3(-4,0,7)
	var dca_captured := false
	var extraction_captured := false
	for frame in range(60*95):
		d.combat._physics_process(1.0/60)
		d.advance(1.0/60)
		flight.get_node("Seascape")._physics_process(1.0/60)
		flight.get_node("Clouds")._physics_process(1.0/60)
		d.details._physics_process(1.0/60)
		if frame%120==0: await process_frame
		if frame==60*8: await capture("approche-aerienne")
		if not extraction_captured and d.extraction_wave_count>0 and d.elapsed>d.extraction_started_at+1.5:
			await capture("interception-retour")
			extraction_captured = true
		if not dca_captured and frame>60*27 and d.combat.lifetimes.count(0.0)<=d.combat.BULLET_CAPACITY-15:
			d.weapons._fire_salvo()
			d.weapons._physics_process(.04)
			await capture("dca")
			dca_captured = true
		if frame==60*20: await capture("cote")
		if frame==60*37:
			d.weapons._fire_salvo()
			d.weapons._physics_process(.07)
			await capture("combat")
			if "--palette-testing" in OS.get_cmdline_user_args():
				for gain in [.20,.30,.40]:
					d.assault.terrain.set_ocean_parameter("landscape_gain",gain)
					await capture("palette-"+str(gain))
				d.assault.terrain.set_ocean_parameter("landscape_gain",.30)
		if frame==60*44:
			for target in d.assault.contacts():
				if target.variant=="fuel": target.take_damage(100); break
			d.combat._update_effects(.2)
			await capture("explosion")
		if extraction_captured and frame>60*53: break
	app._show_main()
	app.music.stop()
	await process_frame
	quit()
