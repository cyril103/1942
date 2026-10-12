extends SceneTree
const L10N:=preload("res://scripts/campaign/localization.gd")
const DEBRIEF:=preload("res://scripts/campaign/debrief.gd")
var app: Control
var checks:=0
var failures: Array[String]=[]
var capture:=false
var output:=ProjectSettings.globalize_path("res://../renders/command-2.4")

func _initialize() -> void:
	capture="--capture" in OS.get_cmdline_user_args()
	_run.call_deferred()

func check(ok: bool, why: String) -> void:
	checks+=1
	if not ok:
		failures.append(why)
		push_error(why)

func geometry(context: String) -> void:
	var bounds:=Rect2(0,0,1920,1080)
	for node in app.design.get_children():
		if node is not Control: continue
		check(bounds.encloses(node.get_rect()),context+" contains "+str(node.name))
		if node is Label: check(node.get_minimum_size().y<=node.size.y+.2,context+" text fits "+str(node.name)+" "+node.text.left(30))
	for i in range(app.buttons.size()):
		for j in range(i+1,app.buttons.size()): check(not app.buttons[i].get_rect().intersects(app.buttons[j].get_rect()),context+" buttons separated")

func screenshot(name: String) -> void:
	if not capture: return
	for i in range(3): await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(name+".png"))==OK,"Capture "+name)

func fixture() -> Dictionary:
	return {"won":true,"mission":4,"score":15620,"mission_score":11620,"lives":3,"seconds":105.0,"grazes":18,"graze_score":450,"kills":46,"naval_kills":2,"deaths":0,"damage":1,"bonus":950,"grade":3,"power":"spread","rank":"A","best_chain":14,"secondary":true,"accuracy":.63,"flight_analysis":{"version":1,"interval":12.0,"elapsed":105.0,"samples":[{"seconds":0.0,"score":0},{"seconds":12.0,"score":1000},{"seconds":24.0,"score":1800},{"seconds":36.0,"score":3900},{"seconds":48.0,"score":4600},{"seconds":60.0,"score":6500},{"seconds":72.0,"score":6800},{"seconds":84.0,"score":7800},{"seconds":96.0,"score":9700},{"seconds":105.0,"score":10670}],"events":[{"seconds":20.0,"kind":"hit"},{"seconds":52.0,"kind":"bomb"},{"seconds":81.0,"kind":"boss"},{"seconds":98.0,"kind":"strike"}],"totals":{"score":10670,"kills":46,"damage":1,"grazes":18},"dropped_events":0}}

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	app=load("res://scenes/campaign.tscn").instantiate()
	app.testing=true
	app.profile.path="user://command-bridge-never-saved.json"
	root.add_child(app)
	current_scene=app
	app.profile.reset()
	app.profile.data.unlocked=14
	app.profile.data.next_mission=14
	for number in range(1,14): app.profile.data.records[str(number)]={"grade":3 if number%3==0 else 2,"score":10000,"rank":"S" if number%3==0 else "A","best_chain":20}
	var before: Dictionary=app.profile.data.duplicate(true)
	for code in ["fr","en"]:
		L10N.set_locale(code)
		app._prepare_missions()
		for dimensions in [Vector2i(1280,720),Vector2i(1920,1080),Vector2i(2560,1080)]:
			root.size=dimensions
			await process_frame
			for sector in range(8):
				app._show_missions(sector)
				await process_frame
				geometry(code+" map "+str(sector)+" "+str(dimensions))
				check(root.gui_get_focus_owner()==app.design.get_node("Sector_%d" % sector),"Selected sector retains keyboard focus")
				var sector_button: Button=app.design.get_node("Sector_%d" % ((sector+1)%8))
				check(sector_button.get_theme_stylebox("focus").border_color!=sector_button.get_theme_stylebox("normal").border_color,"Unselected sectors keep a distinct focus outline")
				for offset in range(4):
					var number:=sector*4+offset+1
					var button: Button=app.design.get_node("Operation_%02d" % number)
					check(button.disabled==(number>14),"Actual campaign locks mission "+str(number))
			app._show_missions(3)
			if dimensions==Vector2i(1920,1080): await screenshot(code+"-operations")
		check(app.profile.data==before,"Map inspection leaves campaign untouched")
		app._show_missions(2)
		app.design.get_node("Operation_09").pressed.emit()
		check(app.page=="briefing" and app.selected_mission==9,"Mission card opens real briefing")
		app._show_main()
		app._launch(4,"arcade")
		app.cockpit.flight.process_mode=Node.PROCESS_MODE_DISABLED
		app.profile.data.arcade_records["4:0"]=10000
		var report:=fixture()
		app._show_result(report)
		check(app.result_previous_best==10000,"Previous score captured before updating record")
		check(app.design.has_node("FlightAnalysisEntry"),"Results provide a flight analysis entry")
		app._show_result(report)
		check(app.result_previous_best==10000,"Duplicate results cannot overwrite previous comparison")
		for dimensions in [Vector2i(1280,720),Vector2i(1920,1080),Vector2i(2560,1080)]:
			root.size=dimensions
			await process_frame
			app._show_debrief()
			await process_frame
			geometry(code+" debrief "+str(dimensions))
			check(paused and app.director.paused,"Analysis preserves paused flight")
			if dimensions==Vector2i(1920,1080): await screenshot(code+"-analysis-fixture")
		app._draw_result(report)
		check(app.page=="result","Analysis returns to current result")
		app._show_main()
		before=app.profile.data.duplicate(true)
	var report:=fixture()
	check(DEBRIEF.next_rank(report)=="S","A rank offers S criteria")
	check(DEBRIEF.coaching(report).size()<=2,"Advice limited to two actionable priorities")
	report.won=false
	report.objective_failed=true
	report.ground_status={"main_met":false}
	check(DEBRIEF.coaching(report)[0].title==L10N.text("PRIORITÉ À LA MISSION"),"Missed raid objectives outrank score advice")
	report=fixture()
	report.damage=0
	report.best_chain=25
	report.rank="S"
	check(DEBRIEF.coaching(report)[0].title==L10N.text("UNE SORTIE DE MAÎTRISE"),"Clean mastery gets appropriate advanced advice")
	check(DEBRIEF.score_delta(report,15000).contains("-3380"),"Lower score comparison is signed accurately")
	check(L10N.catalogue_errors.is_empty(),"All new catalogues load without conflicts")
	app._dispose_run()
	app.music.stop()
	app.queue_free()
	await process_frame
	await create_timer(.2).timeout
	print("COMMAND BRIDGE: ",checks," checks, ",failures.size()," failures: ",failures)
	quit(0 if failures.is_empty() else 1)
