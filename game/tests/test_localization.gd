extends SceneTree
## Real menu, save migration and paused-flight checks. Always use Dummy audio.
const L10N := preload("res://scripts/campaign/localization.gd")
const PROFILE := preload("res://scripts/campaign/profile.gd")
const OPERATIONS := preload("res://scripts/campaign/operations.gd")
const LOADOUT := preload("res://scripts/campaign/loadout.gd")
const COMMANDS := preload("res://scripts/campaign/command_labels.gd")
const FIXTURE := "user://localization-regression.json"
var checks := 0
var failures: Array[String] = []
var app: Control
var captures := false
var output := ProjectSettings.globalize_path("res://").path_join("../renders/localization").simplify_path()

func _initialize() -> void:
	captures = "--capture" in OS.get_cmdline_user_args()
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func _profile_checks() -> void:
	var profile := PROFILE.new()
	check(profile.data.settings.language == "fr", "New profiles retain French by default")
	profile.data.credits = 17
	profile.data.unlocked = 23
	profile.data.run_score = 12560
	profile.data.settings.erase("language")
	var legacy: Dictionary = profile._decode_candidate(profile.data)
	check(legacy.settings.language == "fr" and legacy.run_score == 12560 and legacy.unlocked == 23, "Legacy saves migrate language without changing progress")
	for value in ["en", "en-GB", "en_US", "fr-FR", "invalid", 42, null, {}]:
		profile.data.settings.language = value
		var decoded: Dictionary = profile._decode_candidate(profile.data)
		check(not decoded.is_empty() and decoded.credits == 17 and decoded.settings.language == L10N.normalize(value), "Invalid or regional preference safely normalizes: " + str(value))
	profile.data.settings.language = "en"
	profile.path = FIXTURE
	check(profile.save() == OK, "English preference saves")
	var restored := PROFILE.new()
	restored.path = FIXTURE
	check(restored.load_profile() and restored.data.settings.language == "en" and restored.data.run_score == 12560, "English preference and campaign survive restart")

func _mechanics(value: Variant) -> Variant:
	# Display text may change. All dictionary keys, numbers, flags and collection
	# sizes must stay identical. Stable gameplay IDs get an additional check below.
	if value is Dictionary:
		var result := {}
		for key in value: result[key] = _mechanics(value[key])
		return result
	if value is Array:
		var result := []
		for item in value: result.append(_mechanics(item))
		return result
	return "<text>" if value is String else value

func _content_checks() -> void:
	var source: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/missions.json"))
	L10N.set_locale("fr")
	var french: Array = []
	for mission in source: french.append(OPERATIONS.prepare(mission))
	var equipment_fr: Dictionary = LOADOUT.stats(PROFILE.new().data)
	L10N.set_locale("en")
	check(L10N.catalogue_errors.is_empty(), "All shipped catalogues load without conflict")
	check(L10N.entries().size() > 400, "Complete game catalogue is available")
	check(L10N.text("UNREGISTERED_TEST_MESSAGE") == "UNREGISTERED_TEST_MESSAGE", "Missing translations fall back to readable source")
	for i in range(source.size()):
		var english: Dictionary = OPERATIONS.prepare(source[i])
		check(_mechanics(english) == _mechanics(french[i]), "Language leaves mission %02d mechanics intact" % (i + 1))
		for key in ["id", "objective", "biome", "boss", "secondary"]:
			check(english[key] == french[i][key], "Mission %02d keeps stable %s" % [i + 1, key])
		check(english.briefing != french[i].briefing and english.title != french[i].title, "Mission %02d title and briefing have English copy" % (i + 1))
		for act in english.acts: check(not str(act.radio).begins_with("Contrôle :"), "Mission %02d radio is localized" % (i + 1))
	check(_mechanics(LOADOUT.stats(PROFILE.new().data)) == _mechanics(equipment_fr), "Translation cannot change equipment statistics")
	check(LOADOUT.module_info("precision").label == "Precision", "Equipment uses translated display name and stable id")

func _capture(name: String) -> void:
	if not captures: return
	for i in range(3): await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(name + ".png")) == OK, "Screenshot: " + name)

func _inspect_briefings(code: String) -> void:
	for number in range(1, 33):
		app._show_briefing(number)
		await process_frame
		var orders: Label = app.design.get_node("MissionOrderText")
		var panel: Panel = app.design.get_node("MissionOrderPanel")
		check(panel.get_rect().encloses(orders.get_rect()), "%s mission %02d briefing fits its panel" % [code, number])
		check(orders.get_minimum_size().y <= orders.size.y + .1, "%s mission %02d all briefing lines fit" % [code, number])
		check(root.gui_get_focus_owner() != null and root.gui_get_focus_owner().text == L10N.text("DÉCOLLER"), "%s mission %02d launch has keyboard focus" % [code, number])

func _app_checks() -> void:
	app = load("res://scenes/campaign.tscn").instantiate()
	app.testing = true
	app.profile.path = FIXTURE
	root.add_child(app)
	current_scene = app
	await process_frame
	check(L10N.locale == "en" and app.missions[0].title == L10N.text("Opération Brise-Lames"), "Startup applies saved language before building mission data")
	check(COMMANDS.keyboard("fire") == "Space", "Key hints use localized names")
	app.design.get_node("LanguageMenu").pressed.emit()
	check(L10N.locale == "fr" and app.page == "main", "Title-screen language button switches to French")
	app.design.get_node("LanguageMenu").pressed.emit()
	check(L10N.locale == "en" and app.page == "main", "Title-screen language button switches back to English")
	app.profile.data.unlocked = 32
	app.profile.data.credits = 30
	for code in ["fr", "en"]:
		app._show_settings(false)
		var language_button: Button = app.design.get_node("Language_" + code)
		language_button.grab_focus()
		language_button.pressed.emit()
		await process_frame
		check(L10N.locale == code and app.profile.data.settings.language == code, "Options selects " + code)
		check(root.gui_get_focus_owner() != null and root.gui_get_focus_owner().name == "Language_" + code, "Language switch retains focus on the chosen language")
		await _capture(code + "-settings")
		app._show_main()
		await _capture(code + "-main")
		app._show_hangar()
		await _capture(code + "-hangar")
		app._show_pilot_guide()
		await _capture(code + "-guide")
		app._show_boss_rush()
		await _capture(code + "-boss-rush")
		for dimensions in [Vector2i(1280,720), Vector2i(1920,1080)]:
			root.size = dimensions
			await process_frame
			await _inspect_briefings(code)
		app._show_briefing(3)
		await _capture(code + "-raid-briefing")
	app._show_main()
	app._launch(3)
	app.cockpit.flight.process_mode = Node.PROCESS_MODE_DISABLED
	app.director.player.health = 1
	app.director.charge = 57.0
	app.cockpit.combat.score = 12345
	app._show_pause()
	var live_director: Node = app.director
	var live_raid: Node = app.director.assault
	var clock_before: float = app.director.elapsed
	var campaign_before: Dictionary = app.profile.data.duplicate(true)
	campaign_before.erase("settings")
	for code in ["fr", "en", "fr", "en"]:
		app._show_settings(true)
		app._set_language(code)
		await process_frame
		check(paused and app.settings_from_pause, "Changing language preserves pause")
		check(app.director == live_director and app.director.assault == live_raid, "Changing language preserves the actual flight and raid")
		check(app.director.elapsed == clock_before and app.director.charge == 57.0 and app.director.player.health == 1 and app.cockpit.combat.score == 12345, "Changing language leaves mission clock, health, charge and score intact")
		check(app.director.mission.title == app.missions[2].title, "Live mission receives translated briefing and objectives")
		var campaign_after: Dictionary = app.profile.data.duplicate(true)
		campaign_after.erase("settings")
		check(campaign_before == campaign_after, "Language changes do not mutate campaign progress")
	app._show_pause()
	await _capture("en-pause")
	app._show_main()
	await process_frame
	app._show_settings(false)
	app.testing = false
	app._set_language("fr")
	app._set_language("en")
	app.testing = true
	var restored := PROFILE.new()
	restored.path = FIXTURE
	check(restored.load_profile() and restored.data.settings.language == "en", "Real options callback persists language")
	app._dispose_run()
	if is_instance_valid(app.music): app.music.stop()
	app.queue_free()
	await process_frame

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	_profile_checks()
	_content_checks()
	await _app_checks()
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(FIXTURE + suffix): DirAccess.remove_absolute(FIXTURE + suffix)
	L10N.set_locale("fr")
	print("LOCALIZATION: ", checks, " checks; failures: ", failures)
	quit(0 if failures.is_empty() else 1)
