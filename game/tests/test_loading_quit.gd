extends SceneTree
var app: Node
var requested := false
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	app = load("res://scenes/campaign.tscn").instantiate()
	app.testing = true
	app.prepare_in_tests = true
	app.profile.path = "user://loading-quit-fixture.json"
	root.add_child(app)
	app.profile.reset()
	app.profile.data.unlocked = 32
	app.profile.data.settings.fullscreen = false
	app._launch(19)
	await create_timer(30).timeout
	push_error("Closing while preparing did not exit")
	quit(1)
func _process(_delta: float) -> bool:
	if not requested and is_instance_valid(app) and app.preparing and is_instance_valid(app.cockpit):
		requested = true
		print("LOADING QUIT: invoking normal close while render preparation is active")
		app._quit()
	return false
