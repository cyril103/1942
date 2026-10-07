extends SceneTree
## Exercise the actual menu callbacks and measured controls, using an isolated save.
const LOADOUT := preload("res://scripts/campaign/loadout.gd")
const FIXTURE := "user://loadout-ui-regression.json"
var app: Control
var checks := 0
var failures: Array[String] = []
var observations: Array[Dictionary] = []
var output_dir := "user://loadout-ui-review"

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output-dir="): output_dir = argument.trim_prefix("--output-dir=")
	DirAccess.make_dir_recursive_absolute(output_dir)
	_run.call_deferred()

func _cleanup() -> void:
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(FIXTURE+suffix): DirAccess.remove_absolute(FIXTURE+suffix)

func _button(name: String) -> Button:
	return app.design.get_node(name) as Button

func _label(name: String) -> Label:
	return app.design.get_node(name) as Label

func _press(name: String) -> void:
	var button := _button(name)
	check(not button.disabled,"Real menu action enabled: "+name)
	if not button.disabled: button.pressed.emit()

func _geometry(context: String) -> void:
	var canvas := Rect2(Vector2.ZERO,Vector2(1920,1080))
	for child in app.design.get_children():
		if child is not Control: continue
		check(canvas.encloses(child.get_rect()),context+" stays inside authored canvas: "+str(child.name))
		if child is Label:
			check(child.get_minimum_size().y<=child.size.y+.2,context+" has room for every wrapped line: "+str(child.name))
	for i in range(app.buttons.size()):
		var button: Button = app.buttons[i]
		for j in range(i+1,app.buttons.size()): check(not button.get_rect().intersects(app.buttons[j].get_rect()),context+" keeps menu actions distinct: "+button.name+" / "+app.buttons[j].name)
		check(button.get_combined_minimum_size().y<=button.size.y+.2,context+" keeps the complete button caption: "+button.name)
	for child in app.design.get_children():
		if child is not Label: continue
		var container_name := ""
		var child_name := str(child.name)
		if child_name.begins_with("Aircraft"): container_name = "AircraftPanel_"+child_name.get_slice("_",1)
		elif child_name.begins_with("Upgrade"): container_name = "UpgradePanel_"+child_name.get_slice("_",1)
		elif child_name.begins_with("Equipment"): container_name = "EquipmentPanel"
		elif child_name.begins_with("ModuleSlotName") or child_name.begins_with("ModuleSlotState"): container_name = "ModuleSlot_"+child_name.get_slice("_",1)
		elif child_name.begins_with("ModuleName_") or child_name.begins_with("ModuleFamily_") or child_name.begins_with("ModuleDescription_") or child_name.begins_with("ModuleInstructions_"): container_name = "ModulePanel_"+child_name.get_slice("_",1)
		if not container_name.is_empty(): check(app.design.get_node(container_name).get_rect().encloses(child.get_rect()),context+" text stays on its actual opaque panel: "+child_name)
	observations.append({"context":context,"physical_size":str(root.size),"page":app.page,"aircraft":app.profile.data.aircraft,"upgrades":app.profile.data.upgrades.duplicate(),"equipped":app.profile.data.equipped_modules.duplicate(),"controls":app.design.get_child_count()})

func _capture(name: String) -> void:
	if "--capture-ui" not in OS.get_cmdline_user_args(): return
	await create_timer(.30).timeout
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output_dir.path_join("loadout-"+name+".png"))==OK,"Save rendered loadout evidence: "+name)

func _resize(dimensions: Vector2i) -> void:
	root.size = dimensions
	await process_frame
	await process_frame
	check(app.size.is_equal_approx(root.get_visible_rect().size),"Actual application follows viewport "+str(dimensions))

func _assert_hangar_stats() -> void:
	for plane in range(3):
		var actual: Dictionary = LOADOUT.stats(app.profile.data,plane)
		var stats: String = _label("AircraftStats_%d" % plane).text
		var ammo: String = _label("AircraftAmmo_%d" % plane).text
		check(stats.contains("VITESSE %.1f" % float(actual.speed)) and stats.contains("BLINDAGE %d" % int(actual.max_health)) and stats.contains("FEU %.1f DPS" % float(actual.standard_dps)),"Hangar plane %d reflects calculated speed, armor and standard damage per second" % plane)
		check(ammo.contains("%.2f SALVES/S" % float(actual.shot_rate)) and ammo.contains("%d BOMBES" % int(actual.bombs)) and ammo.contains("LASER %.1f DPS" % float(actual.sustained_laser_dps)),"Hangar plane %d reflects calculated shot rate, bombs and laser damage per second" % plane)
		check(_label("AircraftTradeoff_%d" % plane).text==LOADOUT.aircraft(plane).tradeoff,"Hangar plane %d explains its authored tradeoff" % plane)
		check(not _button("SelectAircraft_%d" % plane).disabled,"Every aircraft remains available without spending credits")

func _assert_equipped_stats() -> void:
	var actual: Dictionary = LOADOUT.stats(app.profile.data)
	var display: String = _label("EquipmentStats").text
	check(display.contains("Vitesse %.1f" % float(actual.speed)) and display.contains("Blindage %d" % int(actual.max_health)) and display.contains("Feu %.1f DPS" % float(actual.standard_dps)),"Module screen shows actual installed aircraft statistics")
	check(display.contains("%.2f salves/s" % float(actual.shot_rate)) and display.contains("Laser %.1f DPS" % float(actual.sustained_laser_dps)) and display.contains("%d bombes" % int(actual.bombs)),"Module screen includes the installed cadence, laser and bomb count")

func _selection_focus() -> void:
	for plane in range(3):
		app.profile.reset()
		app.profile.data.aircraft = plane
		app._show_hangar()
		var assigned := _button("SelectAircraft_%d" % plane)
		check(root.gui_get_focus_owner()==assigned,"Hangar opens with focus on its assigned aircraft "+str(plane))
		assigned.pressed.emit()
		check(app.profile.data.aircraft==plane and root.gui_get_focus_owner()==_button("SelectAircraft_%d" % plane),"Activating the focused aircraft preserves the selection and focus "+str(plane))

func _upgrade_progression() -> void:
	app.profile.reset()
	app.profile.data.credits = 50
	app._show_hangar()
	_press("BuyUpgrade_0")
	check(app.profile.data.upgrades[0]==1 and app.profile.data.credits==48,"Rank I purchase actually spends two credits")
	check(_label("UpgradeDetails_0").text.contains("×1.25") and _label("UpgradeDetails_0").text.contains("×1.04"),"Rank I explains its precise damage and rate factors")
	check(_button("BuyUpgrade_0").disabled and _button("BuyUpgrade_0").text.contains("MISSION 09"),"Hangar explains the sector gate for rank II")
	app.profile.data.unlocked = 9
	app._show_hangar()
	_press("BuyUpgrade_0")
	check(app.profile.data.upgrades[0]==2 and app.profile.data.credits==44,"Rank II actual purchase spends four credits at mission 09")
	check(_label("UpgradeDetails_0").text.contains("×1.55") and _label("UpgradeDetails_0").text.contains("×1.08"),"Rank II explains its precise damage and rate factors")
	check(_button("BuyUpgrade_0").disabled and _button("BuyUpgrade_0").text.contains("MISSION 21"),"Hangar explains the late rank III gate")
	app.profile.data.unlocked = 21
	app._show_hangar()
	_press("BuyUpgrade_0")
	check(app.profile.data.upgrades[0]==3 and app.profile.data.credits==38,"Rank III actual purchase spends six credits at mission 21")
	check(_label("UpgradeDetails_0").text.contains("×1.90") and _label("UpgradeDetails_0").text.contains("×1.12") and not _label("UpgradeDetails_0").text.contains("doublés"),"Rank III explains the gradual curve, with no stale double-damage claim")
	check(_button("BuyUpgrade_0").disabled and _button("BuyUpgrade_0").text=="RANG MAXIMUM","Maximum rank cannot be purchased twice")
	# An already purchased legacy rank remains active even before a new gate.
	app.profile.data.unlocked = 1
	app._show_hangar()
	check(_label("UpgradeDetails_0").text.contains("Rang acquis conservé et actif"),"Legacy equipment clearly remains active before a new sector gate")
	_assert_hangar_stats()

func _module_progression() -> void:
	app.profile.reset()
	app.profile.data.credits = 6
	app._show_modules(0)
	check(_button("BuyModule_precision").disabled and _button("BuyModule_precision").text.contains("MISSION 05"),"First modules explain their mission 05 unlock")
	check(_label("ModuleSlotState_0").text.contains("MISSION 05") and _label("ModuleSlotState_1").text.contains("MISSION 13"),"Both equipment slots show their own unlock milestones")
	app.profile.data.unlocked = 5
	app._show_modules()
	_press("BuyModule_precision")
	check("precision" in app.profile.data.owned_modules and app.profile.data.equipped_modules.is_empty() and app.profile.data.credits==0,"Module purchase spends six credits and leaves installation explicit")
	check(root.gui_get_focus_owner()==_button("EquipModule_precision"),"After buying, keyboard focus moves to the available equip action")
	_press("EquipModule_precision")
	check(app.profile.data.equipped_modules==["precision"],"Actual equip callback installs precision in the available slot")
	_assert_equipped_stats()
	app.profile.data.credits = 6
	app._show_modules()
	_press("BuyModule_coverage")
	check(_button("EquipModule_coverage").disabled and app.profile.data.equipped_modules==["precision"],"A conflicting family cannot silently replace installed equipment")
	_press("RemoveModule_0")
	check(app.profile.data.equipped_modules.is_empty() and app.profile.data.credits==0,"Removing a module is free and clears the actual equipment slot")
	_press("EquipModule_coverage")
	check(app.profile.data.equipped_modules==["coverage"],"The alternative becomes available after an explicit removal")
	app.profile.data.unlocked = 13
	app.profile.data.credits = 18
	app._show_modules(1)
	_press("BuyModule_plates")
	_press("EquipModule_plates")
	check(app.profile.data.equipped_modules==["coverage","plates"],"Second slot can hold a different family at mission 13")
	_assert_equipped_stats()
	_press("BuyModule_agile")
	check(_button("EquipModule_agile").disabled,"A second airframe is unavailable while plates occupy that family")
	app.profile.data.unlocked = 17
	app._show_modules(2)
	_press("BuyModule_yield")
	check(_button("EquipModule_yield").disabled and app.profile.data.equipped_modules.size()==2,"A third family cannot bypass the two-slot limit")
	_press("RemoveModule_1")
	_press("EquipModule_yield")
	check(app.profile.data.equipped_modules==["coverage","yield"],"An explicit free slot allows the new systems module")
	_assert_equipped_stats()
	for group in range(3,5):
		app._show_modules(group)
		for child in app.design.get_children():
			if child is Button and str(child.name).begins_with("BuyModule_"): check(child.disabled and child.text.contains("MISSION"),"Later systems choices remain explained and gated")
	# Actual GUI navigation receives a key event; the active tab opens with focus.
	app._show_modules(3)
	check(root.gui_get_focus_owner()==_button("ModuleTab_3"),"Switching catalogue pages preserves focus on the selected tab")
	var key := InputEventKey.new()
	key.keycode = KEY_TAB
	key.pressed = true
	root.push_input(key)
	await process_frame
	check(root.gui_get_focus_owner() is Button and root.gui_get_focus_owner()!=_button("ModuleTab_3"),"Tab advances through the real workshop controls")
	var escape := InputEventAction.new()
	escape.action = "quit_game"
	escape.pressed = true
	app._input(escape)
	check(app.page=="hangar","Escape returns from the workshop to the actual hangar")

func _storage_failure() -> void:
	app.profile.reset()
	app.profile.data.unlocked = 5
	app.profile.data.credits = 6
	var path: String = app.profile.path
	app.profile.path = "user://loadout-ui-nonexistent-directory/profile.json"
	app._show_modules(0)
	_press("BuyModule_precision")
	check(app.profile.data.credits==6 and app.profile.data.owned_modules.is_empty(),"A failed UI purchase preserves actual credits and ownership")
	check(app.notice.text.contains("Achat annulé") and not app.notice.text.contains("ACQUIS"),"The UI describes a failed save without claiming a purchase")
	app.profile.path = path
	app.profile.last_error = OK

func _screens() -> void:
	for dimensions in [Vector2i(1280,720),Vector2i(1920,1080)]:
		await _resize(dimensions)
		app.profile.reset()
		app._show_hangar()
		await process_frame
		_assert_hangar_stats()
		_geometry("Initial hangar "+str(dimensions))
		await _capture("hangar-start-%d" % dimensions.y)
		app._show_modules(0)
		await process_frame
		_geometry("Initial workshop "+str(dimensions))
		await _capture("workshop-start-%d" % dimensions.y)
		app.profile.data.unlocked = 32
		app.profile.data.upgrades = [3,3,3]
		app.profile.data.credits = 80
		app.profile.data.owned_modules = []
		for module in LOADOUT.modules(): app.profile.data.owned_modules.append(module.id)
		app.profile.data.equipped_modules = ["precision","plates"]
		for plane in range(3):
			app._select_aircraft(plane)
			await process_frame
			_assert_hangar_stats()
			_geometry("Equipped hangar aircraft%d %s" % [plane,str(dimensions)])
			check(_label("HangarCommands").text.contains(LOADOUT.stats(app.profile.data).ability_label.to_upper()),"Hangar command reflects the selected aircraft's actual ability")
		await _capture("hangar-equipped-%d" % dimensions.y)
		for group in range(5):
			app._show_modules(group)
			await process_frame
			_assert_equipped_stats()
			_geometry("Workshop group%d %s" % [group,str(dimensions)])
			for module in LOADOUT.modules():
				if int(module.required_mission)!=[5,13,17,25,29][group]: continue
				check(_label("ModuleDescription_"+str(module.id)).text==module.description,"Every catalogue module retains its complete authored advantages and costs")
				var icon: TextureRect = app.design.get_node("ModuleIcon_"+str(module.id))
				check(is_instance_valid(icon.texture) and icon.texture.resource_path.ends_with("/modules/"+str(module.id)+".svg"),"Each catalogue module uses its own imported, recognizable icon")
			await _capture("workshop-group%d-%d" % [group,dimensions.y])
		# Long special-key bindings must still fit the shared hangar command area.
		for event in InputMap.action_get_events("strike"):
			if event is InputEventKey: InputMap.action_erase_event("strike",event)
		var special := InputEventKey.new()
		special.keycode = KEY_PRINT
		InputMap.action_add_event("strike",special)
		app._show_hangar()
		await process_frame
		check(_label("HangarCommands").text.contains("Impr. écran") and _label("HangarCommands").get_minimum_size().y<=_label("HangarCommands").size.y,"Special-key hangar command remains complete at "+str(dimensions))
		_geometry("Long-key hangar "+str(dimensions))

func _run() -> void:
	_cleanup()
	app = load("res://scenes/campaign.tscn").instantiate()
	app.testing = true
	app.profile.path = FIXTURE
	root.add_child(app)
	current_scene = app
	await process_frame
	_selection_focus()
	_upgrade_progression()
	await _module_progression()
	_storage_failure()
	await _screens()
	app._dispose_run()
	if is_instance_valid(app.music): app.music.stop()
	app.queue_free()
	await process_frame
	await create_timer(.2).timeout
	_cleanup()
	var report := {"checks":checks,"failures":failures,"screens":observations,"human_controller_check":"NOT_PERFORMED"}
	FileAccess.open("res://tests/loadout-ui-results.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("LOADOUT UI ",checks," checks, ",failures.size()," failures: ",failures)
	quit(0 if failures.is_empty() else 1)
