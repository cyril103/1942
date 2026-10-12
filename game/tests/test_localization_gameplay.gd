extends SceneTree
## Run with Dummy audio. Compatibility rendering also inspects actual HUD draws.
const L10N := preload("res://scripts/campaign/localization.gd")
const BOSS := preload("res://scripts/campaign/boss.gd")
const PATTERNS := preload("res://scripts/campaign/boss_patterns.gd")
const BALANCE := preload("res://scripts/campaign/balance.gd")
const READABILITY := preload("res://scripts/campaign/readability_policy.gd")
var checks := 0
var failures: Array[String] = []
var app: Control
var output := ProjectSettings.globalize_path("res://").path_join("../renders/localization").simplify_path()
var completed_boss_checks := false
var completed_hud_source_checks := false
var completed_active_checks := false

class HudProbe extends "res://scripts/campaign/hud.gd":
	var drawn_text: Array[String] = []
	func text_at(value: String, _at: Vector2, _pixels: float, _color: Color, _width := -1.0) -> void:
		drawn_text.append(value)

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func _fields(object: Object, names: Array) -> Dictionary:
	var result := {}
	for name in names:
		var value: Variant = object.get(name)
		result[name] = value.duplicate(true) if value is Dictionary or value is Array else value
	return result

func _boss_checks() -> void:
	var balance := BALANCE.settings(32,1)
	var components: Array[float] = [30.0,30.0]
	for kind in BOSS.NAMES:
		var actor := BOSS.new()
		actor.kind = kind
		L10N.set_locale("fr")
		var french_name: String = BOSS.display_name(kind)
		L10N.set_locale("en")
		var english_name: String = BOSS.display_name(kind)
		check(english_name != french_name, "%s boss description is English" % kind)
		check(english_name.get_slice("•",0) == french_name.get_slice("•",0), "%s proper name is unchanged" % kind)
		# Six volleys exercise odd/even patterns and both alternating ring exits.
		for phase in range(3):
			for volley in range(1,7):
				L10N.set_locale("fr")
				var plan := PATTERNS.build(kind,phase,volley,Vector3(0,.22,-6),Vector3(2,0,8),7,balance,components)
				actor.phase = phase
				actor.volley = volley
				actor.attack_plan = plan.duplicate(true)
				actor.attack_label = plan.label
				actor.attack_hint = plan.hint
				actor.attack_state = "charging"
				actor.attack_progress = .43
				actor.telegraph = float(plan.warning)*.57
				var state := _fields(actor,["kind","phase","volley","attack_plan","attack_label","attack_hint","attack_state","attack_progress","telegraph","health","component_health"])
				var french: Dictionary = actor.presentation()
				L10N.set_locale("en")
				var english: Dictionary = actor.presentation()
				var context := "%s phase %d volley %d" % [kind,phase,volley]
				check(not str(english.label).is_empty() and english.label != french.label, context + " attack label translates")
				check(not str(english.hint).is_empty() and english.hint != french.hint, context + " evasion instruction translates")
				check(english.phase == phase and english.state == "charging" and english.progress == .43, context + " warning presentation retains its state")
				check(_fields(actor,state.keys()) == state, context + " cached attack survives language switch")
				check(PATTERNS.build(kind,phase,volley,Vector3(0,.22,-6),Vector3(2,0,8),7,balance,components) == plan, context + " trajectory and timing are language-independent")
				L10N.set_locale("fr")
				check(actor.presentation() == french, context + " French restores exactly")
		actor.free()
	var actor := BOSS.new()
	for message in [
		["arrival","APPROCHE","REPÉREZ LES DEUX POINTS FAIBLES","APPROACH"],
		["transition","RECONFIGURATION","REPLACEZ-VOUS AVANT LA PROCHAINE OFFENSIVE","RECONFIGURING"],
		["defeated","CIBLE NEUTRALISÉE","","TARGET DESTROYED"]
	]:
		actor.attack_state = message[0]
		actor.attack_label = message[1]
		actor.attack_hint = message[2]
		L10N.set_locale("en")
		check(actor.presentation().label == message[3], "Boss lifecycle cue: " + message[0])
		L10N.set_locale("fr")
		check(actor.presentation().label == message[1], "Boss lifecycle cue restores: " + message[0])
	actor.free()
	completed_boss_checks = true

func _layout_rules(layout: Dictionary) -> Dictionary:
	var result := layout.duplicate(true)
	for field in ["title","signature","learning"]: result.erase(field)
	for field in ["secondary","secondary_spec"]:
		if result.has(field): result[field].erase("label")
	for field in ["radars","radar_groups"]:
		for group in result.get(field,{}).values(): group.erase("label")
	return result

func _raid_state(director: Node) -> Dictionary:
	var raid: Node = director.assault
	var actors: Array = []
	for target in raid.targets:
		var state := _fields(target,["tactical_id","variant","position","health","max_health","alive","jammed","age","cooldown","warning_time","aim","salvo_remaining","salvo_time","mobile_phase","motion_intent","motion_index","motion_clock"])
		state.instance_id = target.get_instance_id()
		actors.append(state)
	var objective: Dictionary = raid.objective_status()
	objective.erase("secondary_label")
	return {
		"director_id":director.get_instance_id(), "raid_id":raid.get_instance_id(),
		"actors":actors, "layout":_layout_rules(raid.layout), "objective":objective,
		"raid":_fields(raid,["deployed","kills","radar_kills","escaped","position","low_flight","jam_remaining","network_jams","destroyed_ids","escaped_ids","secondary_destroyed_ids","supply_drops","next_supply_kill"]),
		"mission":_fields(director,["elapsed","event_index","act_index","active","paused","ability_time","charge","bombs","attacks_used","deaths","damage_taken","ring_time","extraction_started_at"]),
		"combat":_fields(director.combat,["score","kills","remaining_lives","next_power_kind","pow_spawn_count"]),
		"player":_fields(director.player,["position","health","alive","controls_enabled","speed","invulnerable_time"]),
		"weapons":_fields(director.weapons,["power_type","shot_interval","projectile_damage","laser_interval_multiplier","shots_fired","hits_landed"]),
		"mastery":_fields(director.mastery,["chain","best_chain","multiplier","window","bonus_score","secondary_kind","secondary_progress","secondary_complete","grazes","graze_score"]),
		"pickup":_fields(director.combat.pickup,["position","power_kind","active","age","burst_time","collected_count","previous_relative"])
	}

func _hud_source_checks() -> void:
	# Every direct string argument bypassing L10N must be intentionally shared
	# between languages. This catches a new raw label even in headless CI.
	var source := FileAccess.get_file_as_string("res://scripts/campaign/hud.gd")
	var direct := RegEx.new()
	direct.compile('text_at\\("([^"\\n]*)"')
	var shared := ["%08d","%s  %s / %s","%d FPS","GAME OVER","×%d","PHASE  %02d / 03"]
	for found in direct.search_all(source):
		check(found.get_string(1) in shared, "HUD direct label is localized or language-neutral: " + found.get_string(1))
	L10N.set_locale("en")
	check(READABILITY.label_for({"variant":"battery","mobile":true,"priority":true}) == "MOBILE AA · PRIORITY", "Ground contact labels are English before layout measurement")
	check(READABILITY.label_for({"variant":"radar","priority_tag":"western_radar","priority":true}) == "WEST RADAR · PRIORITY", "Named priority marker is English")
	completed_hud_source_checks = true

func _inspect_hud(probe: Control, code: String) -> void:
	probe.drawn_text.clear()
	probe.queue_redraw()
	for frame in range(3): await process_frame
	if probe.drawn_text.is_empty() and DisplayServer.get_name() == "headless":
		return # Dummy renderer does not guarantee CanvasItem draw notifications.
	check(not probe.drawn_text.is_empty(), "HUD draw captured in " + code)
	var text := "\n".join(probe.drawn_text)
	if code == "en":
		for required in ["TOTAL SCORE","LIVES","ARMOR","GROUND TARGETS","ABILITY ACTIVE","OVERDRIVE"]:
			check(required in text, "English flight HUD contains " + required)
		for forbidden in ["BLINDAGE","VIES","BOMBES","CAPACITÉ","CIBLES AU SOL","PRIORITÉS","CHAÎNE","FRÔLEMENT","RÉSEAU","SURCHARGE"]:
			check(forbidden not in text, "English flight HUD has no stale " + forbidden)
	else:
		check("SCORE TOTAL" in text and "CAPACITÉ ACTIVE" in text, "French HUD restores during active ability")

func _capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	DirAccess.make_dir_recursive_absolute(output)
	app.menu.hide()
	var hud: Control = app.cockpit.get_node("CampaignHUD")
	hud._update_jam_status()
	hud.queue_redraw()
	for frame in range(3): await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(name+".png")) == OK, "Actual English HUD screenshot: " + name)

func _active_raid_checks() -> void:
	app = load("res://scenes/campaign.tscn").instantiate()
	app.testing = true
	# A unique nonexistent path guarantees this test cannot load or save a pilot's run.
	app.profile.path = "user://localization-gameplay-%d.json" % Time.get_ticks_usec()
	root.size = Vector2i(1920,1080)
	root.add_child(app)
	current_scene = app
	await process_frame
	app.profile.data.unlocked = 32
	app.profile.data.aircraft = 0
	app._set_language("fr")
	app._launch(11)
	var director: Node = app.director
	check(is_instance_valid(director), "Real mission 11 launched")
	if not is_instance_valid(director): return
	app.cockpit.flight.process_mode = Node.PROCESS_MODE_DISABLED
	app.cockpit.flight.get_node("Departure").finish_immediately()
	director.charge = 100.0
	check(director.use_strike() and director.ability_time > 0, "Actual aircraft ability is active before pause")
	director.elapsed = 12.0
	var raid: Node = director.assault
	check(is_instance_valid(raid), "Mission has a real ground-assault actor")
	if not is_instance_valid(raid): return
	raid.advance(0.0)
	# Runtime IDs include their sector prefix. Read the real network membership
	# instead of assuming that an authored short ID is also the actor lookup key.
	var groups: Dictionary = raid.layout.get("radar_groups",{})
	var western_group: Dictionary = groups.get("west",{})
	var western_radars: Array = western_group.get("radar_ids",[])
	var western_members: Array = western_group.get("target_ids",[])
	var eastern_members: Array = groups.get("east",{}).get("target_ids",[])
	var has_members := not western_radars.is_empty() and not western_members.is_empty() and not eastern_members.is_empty()
	check(has_members, "Authored west/east networks expose full radar and defense IDs")
	if not has_members: return
	var radar: Area3D = raid.target_by_id(str(western_radars[0]))
	var western_defense: Area3D = raid.target_by_id(str(western_members[0]))
	var eastern_defense: Area3D = raid.target_by_id(str(eastern_members[0]))
	var has_actors := is_instance_valid(radar) and is_instance_valid(western_defense) and is_instance_valid(eastern_defense)
	check(has_actors, "Canonical network IDs resolve to actual live raid actors")
	if not has_actors: return
	# Position the authored western radar in view, then destroy the actual actor.
	raid.position.z = -radar.position.z
	raid.low_flight = 1.0
	raid._apply_flight_view()
	radar.take_damage(radar.max_health)
	check(raid.deployed and not radar.alive and raid.kills == 1, "Authored radar destruction updates a deployed raid")
	check(float(raid.network_jams.get("west",0.0))>0 and raid.jam_status().size()==1, "Western network is actively jammed")
	check(western_defense.jammed and not eastern_defense.jammed, "Local jam leaves eastern defense active")
	director.combat.pickup.activate(Vector3(3,0,2),director.player,"spread")
	check(director.combat.pickup.active and director.combat.pickup.label.text == "MULTI", "Existing French POW is in flight")
	app._show_pause()
	app._show_settings(true)
	var probe := HudProbe.new()
	probe.cockpit = app.cockpit
	probe.director = director
	app.cockpit.add_child(probe)
	probe.set_process(false)
	var before := _raid_state(director)
	var english_groups := {"west":"Western Network","east":"Eastern Network","south":"Rear Network"}
	var french_groups := {"west":"Réseau Ouest","east":"Réseau Est","south":"Réseau arrière"}
	for code in ["en","fr","en","fr"]:
		app._set_language(code)
		check(paused and director.paused and app.settings_from_pause, "Flight remains paused after selecting " + code)
		check(_raid_state(director) == before, "All live actors, network timers, objectives, ability and POW survive " + code)
		for network in english_groups:
			check(raid.layout.radar_groups[network].label == (english_groups[network] if code=="en" else french_groups[network]), "Cached " + network + " label changes to " + code)
		check(director.equipment.ability_label == ("Overdrive" if code=="en" else "Surcharge"), "Active ability name changes to " + code)
		check(director.combat.pickup.label.text == ("SPREAD" if code=="en" else "MULTI"), "Existing POW label changes to " + code)
		var hud: Control = app.cockpit.get_node("CampaignHUD")
		hud._update_jam_status()
		check(hud.jam_badge.visible, "Active jam badge remains visible in " + code)
		check(hud.jam_label.text.begins_with("WESTERN NETWORK JAMMED" if code=="en" else "RÉSEAU OUEST BROUILLÉ"), "Visible jam badge uses refreshed network name in " + code)
		check(director.radio.is_empty() and director.feedback.is_empty(), "Formatted transient messages cannot retain the previous language")
		await _inspect_hud(probe,code)
		check(_raid_state(director) == before, "Rendering after language switch cannot advance the paused sortie")
	probe.hide()
	app._set_language("en")
	await _capture("en-raid-jam-hud")
	app._dispose_run()
	# A deterministic real boss in a telegraphed phase, using the normal HUD.
	app._launch(4,"practice")
	director = app.director
	check(is_instance_valid(director), "Real boss practice mission launched")
	if not is_instance_valid(director): return
	app.cockpit.flight.process_mode = Node.PROCESS_MODE_DISABLED
	var boss: Area3D = director.boss
	check(is_instance_valid(boss), "Practice mission contains its actual boss actor")
	if not is_instance_valid(boss): return
	boss.age = 4.2
	boss.position = Vector3(0,0,-6.3)
	boss.phase = 1
	boss.health = boss.max_health*.62
	boss._begin_attack(director)
	app._show_pause()
	var hud: Control = app.cockpit.get_node("CampaignHUD")
	hud.boss_identity = boss.get_instance_id()
	hud.boss_intro_time = 1.7
	hud.boss_health_trail = .62
	check(boss.presentation().hint == "MOVE ASIDE AFTER LOCK-ON", "Actual boss warning uses English in flight")
	await _capture("en-boss-hud")
	completed_active_checks = true

func _run() -> void:
	_boss_checks()
	_hud_source_checks()
	await _active_raid_checks()
	# A GDScript runtime error can abort a coroutine without throwing into its
	# caller. Stage sentinels make that an explicit test failure, never a pass.
	check(completed_boss_checks, "Boss localization checks reached their final assertion")
	check(completed_hud_source_checks, "HUD source checks reached their final assertion")
	check(completed_active_checks, "Active raid and boss checks reached their final assertion")
	if is_instance_valid(app):
		app._dispose_run()
		if is_instance_valid(app.music): app.music.stop()
		app.queue_free()
		await process_frame
	L10N.set_locale("fr")
	print("LOCALIZATION GAMEPLAY: ",checks," checks; failures: ",failures)
	quit(0 if failures.is_empty() else 1)
