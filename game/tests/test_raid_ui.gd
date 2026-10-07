extends SceneTree
## Rendered presentation test. Result fixtures are not gameplay or quota proof.
const OPS := preload("res://scripts/campaign/operations.gd")
const RULES := preload("res://scripts/campaign/scoring_rules.gd")
const FIXTURE := "user://raid-ui-regression.json"
const RAIDS := [3,7,11,15,19,23,27,31]
var app: Control
var checks := 0
var failures: Array[String] = []
var observations: Array[Dictionary] = []
var output_dir := "user://raid-ui-review"

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
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

func _geometry(context: String) -> void:
	var canvas := Rect2(Vector2.ZERO,Vector2(1920,1080))
	for child in app.design.get_children():
		if child is not Control: continue
		check(canvas.encloses(child.get_rect()),context+" contains "+str(child.name))
		if child is Label:
			check(child.get_minimum_size().y<=child.size.y+.2,context+" fits all wrapped lines in "+str(child.name))
			for button in app.buttons:
				check(not child.get_rect().intersects(button.get_rect()),context+" separates "+str(child.name)+" from "+str(button.name))
	for i in range(app.buttons.size()):
		for j in range(i+1,app.buttons.size()):
			check(not app.buttons[i].get_rect().intersects(app.buttons[j].get_rect()),context+" separates actions")
	for pair in [["MissionOrderText","MissionOrderPanel"],["PrimaryMissionObjective","MissionInfoPanel"],["SecondaryMissionObjective","MissionInfoPanel"]]:
		if app.design.has_node(pair[0]):
			check(app.design.get_node(pair[1]).get_rect().encloses(app.design.get_node(pair[0]).get_rect()),context+" places text on its panel: "+pair[0])
	if app.design.has_node("ResultGroundObjective"):
		var objective: Label = app.design.get_node("ResultGroundObjective")
		var summary: Label = app.design.get_node("ResultSummary")
		check(not objective.get_rect().intersects(summary.get_rect()),context+" separates ground outcome and retry explanation")
		check(summary.get_rect().end.y<=665.0,context+" leaves room for the Arcade/practice mode line")

func _capture(name: String) -> void:
	if "--capture-ui" not in OS.get_cmdline_user_args(): return
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output_dir.path_join(name+".png"))==OK,"Capture "+name)

func _briefings() -> void:
	for number in range(1,33):
		app._show_briefing(number)
		await process_frame
		var mission: Dictionary = app.missions[number-1]
		var secondary: Label = app.design.get_node("SecondaryMissionObjective")
		check(secondary.text=="BONUS : "+OPS.objective_text(str(mission.secondary),mission),"M%02d explains its actual secondary objective" % number)
		if number in RAIDS:
			check(app.design.get_node("PrimaryMissionObjective").text==str(mission.primary_text),"M%02d explains its authored primary objective" % number)
		_geometry("Briefing M%02d %s" % [number,str(root.size)])
		observations.append({"page":"briefing","mission":number,"size":str(root.size),"secondary":secondary.text})
		if number in [19,27,31]: await _capture("briefing-m%02d-%d" % [number,root.size.y])

func _report(mission: Dictionary, won: bool, priorities_missed: bool) -> Dictionary:
	var quota := int(mission.quota)
	var priorities: Array = mission.get("priority_ids",[])
	var missed := 1 if priorities_missed and not priorities.is_empty() else 0
	var missing: Array = [str(priorities[0])] if missed>0 else []
	var kills := quota if won or missed>0 else quota-1
	var status := {"kills":kills,"quota":quota,"priority_total":priorities.size(),"priority_destroyed":priorities.size()-missed,"missing_priority_ids":missing,"escaped_priority_ids":missing,"main_met":won}
	var report := {"won":won,"objective_failed":not won,"score":15430,"mission_score":2000,"kills":28+kills,"naval_kills":2,"ground_kills":kills,"deaths":0,"damage":0,"bonus":1000,"lives":5,"power":"laser","best_chain":16,"accuracy":.62,"secondary":true,"objective_met":won,"ground_status":status}
	report.grade = RULES.medal(won,0,0,won)
	report.rank = RULES.rank(won,0,0,true,16)
	return report

func _results() -> void:
	for number in RAIDS:
		app._launch(number)
		app.cockpit.flight.process_mode = Node.PROCESS_MODE_DISABLED
		var mission: Dictionary = app.director.mission
		for mode in ["campaign","arcade","practice"]:
			app.play_mode = mode
			for outcome in [[true,false],[false,false],[false,true]]:
				var report := _report(mission,outcome[0],outcome[1])
				app._draw_result(report)
				await process_frame
				var label: Label = app.design.get_node("ResultGroundObjective")
				check(label.text.contains("%d / %d" % [int(report.ground_status.kills),int(mission.quota)]),"Ground result reports actual quota values")
				if not mission.get("priority_ids",[]).is_empty():
					check(label.text.contains("PRIORITÉS  %d / %d" % [int(report.ground_status.priority_destroyed),int(report.ground_status.priority_total)]),"Mandatory targets stay distinct from quota")
					if outcome[1]: check(label.text.contains("ÉCHAPPÉE"),"Escaped priority is explained even with a full quota")
				_geometry("Result M%02d %s %s %s" % [number,mode,str(outcome),str(root.size)])
				if number==31 and mode=="arcade" and outcome[1]: await _capture("result-m31-priority-missed-%d" % root.size.y)
		app._dispose_run()
		await process_frame
		await create_timer(.25).timeout
		app.play_mode = "campaign"

func _run() -> void:
	if DisplayServer.get_name()=="headless":
		push_error("UI inspection requires the real renderer")
		quit(2)
		return
	_cleanup()
	app = load("res://scenes/campaign.tscn").instantiate()
	app.testing = true
	app.profile.path = FIXTURE
	root.add_child(app)
	current_scene = app
	await process_frame
	app.profile.reset()
	app.profile.data.unlocked = 32
	app.profile.data.settings.fullscreen = false
	root.mode = Window.MODE_WINDOWED
	for dimensions in [Vector2i(1280,720),Vector2i(1920,1080)]:
		root.size = dimensions
		await process_frame
		await process_frame
		await _briefings()
		await _results()
	app._dispose_run()
	if is_instance_valid(app.music): app.music.stop()
	app.queue_free()
	await process_frame
	await create_timer(.25).timeout
	_cleanup()
	var file := FileAccess.open("res://tests/raid-ui-results.json",FileAccess.WRITE)
	if file==null: check(false,"Save UI evidence")
	else:
		file.store_string(JSON.stringify({"checks":checks,"failures":failures,"briefings":observations,"result_method":"Presentation fixtures; not a gameplay or human comprehension test","human_comprehension":"NOT_PERFORMED"},"\t"))
		file.close()
	print("RAID UI ",checks," checks; failures: ",failures)
	quit(0 if failures.is_empty() else 1)
