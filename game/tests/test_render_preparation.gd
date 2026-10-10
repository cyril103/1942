extends SceneTree
var checks := 0
var failures: Array[String] = []
var app: Control
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok: failures.append(text); push_error(text)
func _run() -> void:
	app = load("res://scenes/campaign.tscn").instantiate()
	app.testing = true
	app.prepare_in_tests = true
	app.profile.path = "user://render-preparation-fixture.json"
	root.add_child(app)
	app.profile.reset()
	app.profile.data.unlocked = 32
	app.profile.data.settings.fullscreen = false
	for index in range(3):
		var mission: int = [1,19,4][index]
		app.profile.data.settings.quality = index
		var profile_before: Dictionary = app.profile.data.duplicate(true)
		await app._launch(mission)
		check(app.page=="playing" and not app.preparing,"Preparation returns control for mission %d" % mission)
		check(app.last_preparation_count>40,"Representative meshes, effects and text are drawn")
		check(app.cockpit.flight.get_node("Departure").elapsed==0.0,"Takeoff clock stayed frozen during preparation")
		check(app.director.elapsed==0.0 and app.cockpit.combat.score==0,"Mission and score did not advance during preparation")
		check(app.cockpit.combat.enemies.is_empty() and app.cockpit.combat.bombers.is_empty(),"Preparation did not register enemy waves")
		check(app.profile.data==profile_before,"Preparing graphics never changes campaign progress or preferences")
		check(app.director.combat.get_radar_contacts().is_empty(),"Temporary actors are absent from radar")
		await process_frame
		check(app.find_child("MissionPreparation",true,false)==null,"Loading cover is released")
		check(app.cockpit.flight.find_children("*","Node3D",true,false).all(func(node): return node.get_script()!=preload("res://scripts/campaign/render_preparation.gd")),"Temporary render nodes are freed")
		await physics_frame
		await physics_frame
		check(app.cockpit.flight.get_node("Departure").elapsed>0,"Takeoff resumes normally")
		app._dispose_run()
		app.music.stop()
		await create_timer(.35).timeout
	app.queue_free()
	await process_frame
	print("RENDER PREPARATION: ",checks," checks, ",failures.size()," failures: ",failures)
	quit(0 if failures.is_empty() else 1)
