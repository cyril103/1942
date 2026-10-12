extends SceneTree
## Run with the Godot console and --main-pack pointing to the exported executable.
## Release templates ignore --script; the editor runtime executes this probe.
## Tests are excluded from the release package; all production resources must come
## from the embedded pack, with no dependency on the source project directory.
var failures: Array[String] = []
var checks := 0
const FIXTURE := "user://localization-package-fixture.json"

func _initialize() -> void:
	print("LOCALIZATION RELEASE: starting external pack probe")
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func _run() -> void:
	check(not FileAccess.file_exists("res://tests/test_localization.gd"), "Running against the release pack with source tests excluded")
	var localization = load("res://scripts/campaign/localization.gd")
	check(localization != null, "Localization script exists in the embedded pack")
	if localization == null:
		quit(1)
		return
	localization.set_locale("en")
	check(localization.catalogue_errors.is_empty(), "Every English catalogue is shipped")
	check(localization.text("DÉCOLLER") == "TAKE OFF", "Packaged English catalogue is readable")
	var app = load("res://scenes/campaign.tscn").instantiate()
	app.testing = true
	app.profile.path = FIXTURE
	app.profile.data.settings.language = "en"
	check(app.profile.save() == OK, "Isolated English profile saves")
	root.add_child(app)
	await process_frame
	check(localization.locale == "en" and app.missions[0].title == "Operation Breakwater", "Release starts in saved English language")
	check(app.design.has_node("LanguageMenu"), "Release exposes the title-screen selector")
	app._show_settings(false)
	app.design.get_node("Language_fr").pressed.emit()
	check(localization.locale == "fr" and app.profile.data.settings.language == "fr", "Release switches to French")
	app.design.get_node("Language_en").pressed.emit()
	check(localization.locale == "en" and app.profile.data.settings.language == "en", "Release switches back to English")
	if is_instance_valid(app.music): app.music.stop()
	app.queue_free()
	await process_frame
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(FIXTURE + suffix): DirAccess.remove_absolute(FIXTURE + suffix)
	print("LOCALIZATION RELEASE: ", checks, " checks; failures: ", failures)
	quit(0 if failures.is_empty() else 1)
