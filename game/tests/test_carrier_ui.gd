extends SceneTree
var checks := 0
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)
func _initialize() -> void: _run.call_deferred()
func capture(app: Control, name: String) -> void:
	await create_timer(.35).timeout
	for button in app.buttons:
		check(button.position.x+button.size.x<=1920 and button.position.y+button.size.y<=1080,"Button inside canvas: "+button.text)
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("C:/ChatGPT/1942/renders/carrier-"+name+".png")
func _run() -> void:
	var app = load("res://scenes/campaign.tscn").instantiate()
	app.testing = true
	root.add_child(app)
	current_scene = app
	await process_frame
	app.profile.reset()
	app.profile.path = "user://carrier-ui-test.json"
	app.profile.data.unlocked = 32
	app.profile.data.credits = 20
	app._show_hangar()
	await capture(app,"hangar")
	check(app.buttons.size()==8,"Three aircraft, three upgrades, two navigation buttons")
	app.buttons[1].pressed.emit()
	check(app.profile.data.aircraft==1 and app.page=="hangar","Aircraft selection updates loadout")
	var credits: int = app.profile.data.credits
	app.buttons[3].pressed.emit()
	check(app.profile.data.upgrades[0]==1 and app.profile.data.credits<credits,"Upgrade purchase keeps its cost and effect")
	app._show_briefing(1)
	await capture(app,"briefing")
	check(app.page=="briefing" and app.buttons.size()==3,"Briefing exposes launch, hangar and mission map")
	app._show_briefing(32)
	await capture(app,"briefing-final")
	app.buttons[1].pressed.emit()
	check(app.page=="hangar" and app.selected_mission==32,"Hangar preserves the selected mission")
	app._show_main()
	check(app.background.texture.resource_path.ends_with("title-ocean.png"),"Leaving rooms restores menu background")
	app.music.stop()
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(app.profile.path+suffix): DirAccess.remove_absolute(app.profile.path+suffix)
	await create_timer(.2).timeout
	print("CARRIER UI: ",checks," checks; failures: ",failures)
	quit(0 if failures.is_empty() else 1)
