extends SceneTree
## Pure catalogue/operation/geometry checks.
## Invocation: --headless --path game --script
## res://tests/test_raid_layouts.gd. No actors, weapons, audio or GPU scene here.
## These checks cannot prove quotas achievable, correct runtime colliders,
## animation quality, graphical quality, human difficulty or frame pacing.
const LAYOUTS := preload("res://scripts/campaign/raid_layouts.gd")
const OPERATIONS := preload("res://scripts/campaign/operations.gd")
const EXPECTED_COUNTS := [30, 32, 34, 36, 34, 32, 38, 40]
const EXPECTED_QUOTAS := [12, 14, 14, 16, 18, 20, 22, 26]
# Independent acceptance table: battery includes mobile, then bunker/fuel/radar/hangar/mobile.
const EXPECTED_COMPOSITION := [
	[18, 6, 3, 2, 1, 0], [18, 8, 4, 1, 1, 0],
	[18, 10, 2, 3, 1, 0], [22, 7, 2, 1, 4, 0],
	[22, 8, 2, 1, 1, 6], [16, 10, 2, 2, 2, 0],
	[20, 12, 2, 2, 2, 0], [22, 11, 3, 3, 1, 0]
]
const EXPECTED_PRIORITY_IDS := [
	[], [], ["storm/r01", "storm/r02"], ["jade/h01", "jade/h02", "jade/h03"],
	["volcanic/m01", "volcanic/m02"], ["dusk/k05", "dusk/k06"], [], ["final/command"]
]
const EXPECTED_SIDE_MINIMUM := [2, 3, 3, 4, 4, 2, 2, 3]
const EXPECTED_SIDE_TYPES := ["radar", "fuel", "radar", "runway", "mobile", "radar", "fuel", "radar"]
const EXPECTED_HEALTH_BONUS := [0, 0, 1, 1, 2, 2, 3, 3]
const EXPECTED_FOOTPRINT := {"battery": Vector2(2.8, 2.8), "bunker": Vector2(3.2, 2.5), "fuel": Vector2(3.3, 2.8), "radar": Vector2(2.6, 2.6), "runway": Vector2(4.0, 5.2)}
const DIMENSIONS := [[50.0, 13.0], [65.0, 18.5], [82.0, 24.0]]
# Actual legacy portrait allowance, minimum supported allowance, and the
# compact/wide boundary. Every case still uses both real and minimum length.
const COMPACT_DIMENSIONS := [[40.0, 7.0], [40.69136, 8.070370], [50.0, 12.999999]]
const MINIMUM_HALF_Z := [42.0, 48.0, 55.0, 60.0, 67.0, 74.0, 81.0, 90.0]
const CLEARANCE := .25
var checks := 0
var geometry_configurations := 0
var failures: Array[String] = []
var summaries: Array[Dictionary] = []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_check_geometry_helper()
	check(LAYOUTS.layout_for_sector(-1).is_empty(), "A negative sector cannot alias another raid")
	check(LAYOUTS.layout_for_sector(8).is_empty(), "Sector nine cannot alias the final raid")
	var sources: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/missions.json"))
	check(sources.size() == 32, "The source campaign still contains 32 missions")
	for sector in range(8):
		var source: Dictionary = sources[sector * 4 + 2]
		var snapshot := JSON.stringify(source)
		var mission := OPERATIONS.prepare(source)
		var layout := LAYOUTS.layout_for_sector(sector)
		check(JSON.stringify(source) == snapshot, "M%02d preparation leaves its input unchanged" % int(source.id))
		_check_catalogue(layout, mission, sector)
		var real_length := (float(mission.duration) - 43.0) * float(mission.scroll) * 1.18
		for dimensions in DIMENSIONS + COMPACT_DIMENSIONS:
			for length in [real_length, (MINIMUM_HALF_Z[sector] + 16.0) * 2.0]:
				var instantiated := LAYOUTS.instantiate_layout(mission, dimensions[0], length, dimensions[1])
				_check_geometry(instantiated, sector)
				_check_width_variant(instantiated, layout, sector)
		_check_dimension_guards(mission, sector)
		_check_copy_isolation(sector)
		summaries.append({"mission": int(mission.id), "targets": layout.targets.size(), "quota": int(mission.quota), "priorities": mission.priority_ids, "secondary": mission.secondary_label, "briefing_characters": str(mission.briefing).length()})
	_check_ocean_compatibility(sources)
	check(OPERATIONS.objective_text("ground_layout") == "Accomplir l'objectif tactique du raid", "The legacy one-argument API has an honest generic raid fallback")
	var report := {"scope": "Pure authored data and rectangle reservations only; no gameplay/render/human proof", "checks": checks, "geometry_configurations": geometry_configurations, "missions": summaries, "failures": failures}
	var output := FileAccess.open("user://phase4-raid-layout-results.json", FileAccess.WRITE)
	if output == null:
		check(false, "Cannot write the isolated layout result")
	else:
		output.store_string(JSON.stringify(report, "\t"))
	print("RAID LAYOUT TEST ", checks, " checks across ", geometry_configurations, " geometry configurations; ", failures.size(), " failures: ", failures)
	quit(0 if failures.is_empty() else 1)

func _check_catalogue(layout: Dictionary, mission: Dictionary, sector: int) -> void:
	var number := sector * 4 + 3
	check(int(layout.mission) == number and int(layout.sector) == sector, "M%02d uses its own authored sector" % number)
	check(layout.targets.size() == EXPECTED_COUNTS[sector], "M%02d has the agreed independent target count" % number)
	check(int(layout.quota) == EXPECTED_QUOTAS[sector] and int(mission.quota) == EXPECTED_QUOTAS[sector], "M%02d uses the explicit quota; finale remains 26" % number)
	check(int(mission.ground_count) == layout.targets.size(), "M%02d derives ground_count from real authored entries" % number)
	check(int(mission.quota) >= layout.priority_ids.size() and int(mission.quota) <= layout.targets.size(), "M%02d does not add priorities on top of the quota" % number)
	check(layout.priority_ids == EXPECTED_PRIORITY_IDS[sector] and mission.priority_ids == EXPECTED_PRIORITY_IDS[sector], "M%02d requires exactly the agreed stable priority IDs" % number)
	var counts := {"battery": 0, "bunker": 0, "fuel": 0, "radar": 0, "runway": 0, "mobile": 0}
	var ids := {}
	for target in layout.targets:
		check(not ids.has(target.id), "M%02d target ID is unique: %s" % [number, target.id])
		ids[target.id] = target
		check(str(target.id).begins_with(str(layout.id) + "/"), "M%02d target IDs include their sector" % number)
		check(EXPECTED_FOOTPRINT.has(target.variant), "M%02d uses an existing target variant" % number)
		check(target.footprint == EXPECTED_FOOTPRINT[target.variant], "M%02d reserves the published footprint for %s" % [number, target.id])
		check(is_finite(target.normalized.x) and is_finite(target.normalized.y) and absf(target.normalized.x) <= 1.0 and absf(target.normalized.y) <= 1.0, "M%02d has finite bounded normalized target coordinates" % number)
		check(int(target.health_bonus) == EXPECTED_HEALTH_BONUS[sector], "M%02d keeps the existing health increment without priority inflation" % number)
		check(float(target.defense_stagger) >= 0 and float(target.defense_stagger) <= .28, "M%02d keeps bounded deterministic recovery staggering" % number)
		check(bool(target.priority) == (target.id in layout.priority_ids), "M%02d priority metadata matches the objective IDs" % number)
		check(not bool(target.priority) or not str(target.priority_tag).is_empty(), "M%02d every priority has a readable tactical category" % number)
		counts[target.variant] += 1
		if bool(target.mobile):
			counts.mobile += 1
			check(target.variant == "battery" and layout.routes.has(target.mobile_route_id), "M%02d every mobile is a battery with an explicit road" % number)
	for i in range(6):
		var type: String = ["battery", "bunker", "fuel", "radar", "runway", "mobile"][i]
		check(int(counts[type]) == int(EXPECTED_COMPOSITION[sector][i]), "M%02d composition keeps %d %s" % [number, int(EXPECTED_COMPOSITION[sector][i]), type])
	check(mission.ground_composition.radar == counts.radar and mission.mobile_count == counts.mobile, "M%02d published radar/mobile counts describe its actual entries" % number)
	check(mission.secondary == "ground_layout" and mission.secondary_spec.kind == "ground_layout", "M%02d supplies the generic secondary event contract" % number)
	check(int(mission.secondary_target) == EXPECTED_SIDE_MINIMUM[sector], "M%02d side objective has its sector's required count" % number)
	check(int(layout.secondary_spec.minimum) <= layout.secondary_ids.size(), "M%02d side objective has enough actual eligible targets" % number)
	var secondary_ids := {}
	for id in layout.secondary_ids:
		check(ids.has(id) and not secondary_ids.has(id), "M%02d secondary refers to a unique real target" % number)
		secondary_ids[id] = true
		if ids.has(id):
			var expected_type: String = EXPECTED_SIDE_TYPES[sector]
			check(bool(ids[id].mobile) if expected_type == "mobile" else ids[id].variant == expected_type, "M%02d secondary selects the correct tactical target type" % number)
	_check_networks(layout, ids, number)
	_check_text(mission, sector)
	check(mission.events.size() == 4 and mission.boss == "" and mission.objective == "ground", "M%02d keeps the real four-event ocean approach and terrestrial objective" % number)
	for i in range(4):
		check(float(mission.events[i].time) == [1.0, 4.5, 6.0, 9.0][i] and mission.events[i].kind == ["zero", "bomber", "hayabusa", "zero"][i], "M%02d does not move approach aircraft into the low-flight phase" % number)
	check(mission.acts.size() == 4 and float(mission.acts[1].time) == 12.0, "M%02d preserves descent scheduling and four mission acts" % number)
	if sector == 4:
		var first: Dictionary = ids["volcanic/m01"]
		var second: Dictionary = ids["volcanic/m02"]
		var front_fixed := -1.0
		for target in layout.targets:
			if target.variant in ["battery", "bunker"] and not bool(target.mobile):
				front_fixed = maxf(front_fixed, target.normalized.y)
		check(first.normalized.y > second.normalized.y and second.normalized.y > front_fixed, "M19 teaches the two mobile priorities before its fixed shooting complexes")
		var half_z := (float(mission.duration) - 43.0) * float(mission.scroll) * 1.18 * .5 - 16.0
		var ground_scroll := float(mission.scroll) * 1.18
		check((first.normalized.y - second.normalized.y) * half_z / ground_scroll > 4.0 and (second.normalized.y - front_fixed) * half_z / ground_scroll > 4.0, "M19 authored opening spacings exceed four seconds of nominal scroll, without claiming a played tutorial")

func _check_networks(layout: Dictionary, ids: Dictionary, number: int) -> void:
	var defense_members := {}
	var radar_members := {}
	for group_id in layout.radar_groups:
		var group: Dictionary = layout.radar_groups[group_id]
		check(float(group.jam_seconds) == 6.0 and not group.radar_ids.is_empty(), "M%02d radar network has a real station and the agreed temporary duration" % number)
		check(bool(group.get("global", false)) == (number == 3), "M%02d global scope is reserved for the Corail tutorial" % number)
		for id in group.target_ids:
			check(ids.has(id) and not defense_members.has(id), "M%02d network references a unique real defense" % number)
			defense_members[id] = group_id
			if ids.has(id):
				check(ids[id].variant in ["battery", "bunker"] and ids[id].radar_group == group_id, "M%02d network membership agrees with its target data" % number)
		for id in group.radar_ids:
			check(ids.has(id) and not radar_members.has(id), "M%02d network references a unique real radar" % number)
			radar_members[id] = group_id
			if ids.has(id):
				check(ids[id].variant == "radar" and ids[id].radar_group == group_id, "M%02d radar belongs to the network it can actually disrupt" % number)
	for target in layout.targets:
		if target.variant in ["battery", "bunker"]:
			check(defense_members.has(target.id), "M%02d every defense has exactly one radar scope" % number)
		elif target.variant == "radar":
			check(radar_members.has(target.id), "M%02d every radar has exactly one network" % number)
		else:
			check(not defense_members.has(target.id), "M%02d fuel/hangars cannot be misreported as jammed guns" % number)
	if number == 11:
		check(layout.radar_groups.size() == 3, "M11 has three distinct nonoverlapping radar networks")
	if number in [23, 27]:
		check(layout.radar_groups.size() == 2, "M%02d has the two independent tactical complexes" % number)

func _check_text(mission: Dictionary, sector: int) -> void:
	var number := int(mission.id)
	var primary := OPERATIONS.primary_text(mission)
	var secondary := OPERATIONS.secondary_text(mission)
	check(primary == mission.primary_text and primary.contains(str(EXPECTED_QUOTAS[sector])), "M%02d primary text uses its actual total quota" % number)
	check(secondary == mission.secondary_spec.label and OPERATIONS.objective_text("ground_layout", mission) == secondary, "M%02d briefing/bonus text uses the real side objective" % number)
	check(str(mission.briefing).length() <= 460 and str(mission.briefing).length() > 120, "M%02d briefing has a bounded readable text budget; real font layout remains to verify" % number)
	for text_value in [mission.briefing, mission.primary_text, mission.secondary_text, mission.radar_text]:
		var value := str(text_value)
		check(not value.contains("res://") and not value.contains("\t") and not value.contains("{") and not value.contains("}"), "M%02d orders contain no resource path or raw data syntax" % number)
	check(str(mission.briefing).contains("sous les nuages") and str(mission.briefing).contains("porte-avions"), "M%02d orders describe descent and real carrier return" % number)
	check(str(mission.radar_text).contains("toute la DCA") if sector == 0 else str(mission.radar_text).contains("uniquement son réseau"), "M%02d briefing states the actual global/local radar scope" % number)
	if sector == 2:
		check(primary.contains("2 radars prioritaires"), "M11 names both required radars rather than a generic quota")
	if sector == 3:
		check(primary.contains("3 hangars prioritaires"), "M15 names its three required hangars")
	if sector == 4:
		check(primary.contains("2 DCA mobiles d'ouverture"), "M19 names both opening mobile priorities")
	if sector == 5:
		check(primary.contains("bastions Est et Ouest"), "M23 names its opposite required bastions")
	if sector == 7:
		check(primary.contains("bunker de commandement"), "M31 names the actual command target and keeps quota 26")

func _check_geometry(layout: Dictionary, sector: int) -> void:
	geometry_configurations += 1
	var label := "Sector %d geometry %d" % [sector, geometry_configurations]
	check(not layout.is_empty() and bool(layout.valid) and layout.warnings.is_empty(), label + " has admissible authored dimensions")
	check(not bool(layout.geometry_validated_in_game), label + " does not claim gameplay/render validation")
	var targets: Array = layout.targets
	var half_x := float(layout.bounds.half_x)
	var half_z := float(layout.bounds.half_z)
	for target in targets:
		var p: Vector3 = target.position
		check(is_finite(p.x) and is_finite(p.z) and p.y == 0.0, label + " target stays finite on the common collision plane")
		check(absf(p.x) <= half_x and absf(p.z) <= half_z, label + " target center stays in reachable bounds")
		check(absf(p.x) + target.footprint.x * .5 < float(layout.bounds.width) * .33 and absf(p.z) + target.footprint.y * .5 < float(layout.bounds.length) * .5 - 9.0, label + " full footprint remains on the flat plateau")
		check(is_equal_approx(p.x, target.normalized.x * half_x) and is_equal_approx(p.z, target.normalized.y * half_z), label + " world placement uses the single normalized transform")
		check(layout.target_by_id[target.id].position == p, label + " stable ID map refers to the same placement")
	for a in range(targets.size()):
		for b in range(a + 1, targets.size()):
			check(not targets[a].footprint_rect.grow(CLEARANCE * .5).intersects(targets[b].footprint_rect.grow(CLEARANCE * .5)), label + " target reservations do not overlap: " + targets[a].id + "/" + targets[b].id)
	for route_id in layout.routes:
		var route: Dictionary = layout.routes[route_id]
		check(float(route.width) > 0 and route.world_points.size() == route.points.size() and route.world_points.size() >= 2, label + " road has a positive total world width and a complete polyline")
		for i in range(route.world_points.size()):
			var point: Vector3 = route.world_points[i]
			check(point.y == 0.0 and absf(point.x) <= half_x and absf(point.z) <= half_z, label + " route waypoint is finite, bounded and on Y=0")
			check(point.is_equal_approx(Vector3(route.points[i].x * half_x, 0.0, route.points[i].y * half_z)), label + " terrain and mobile routes share the placement transform")
			if i == route.world_points.size() - 1:
				continue
			var from := Vector2(point.x, point.z)
			var next: Vector3 = route.world_points[i + 1]
			var to := Vector2(next.x, next.z)
			for target in targets:
				if bool(target.mobile):
					continue
				check(not _segment_intersects_rect(from, to, target.footprint_rect.grow(float(route.width) * .5 + CLEARANCE)), label + " road does not pass beneath " + target.id + ": " + str(route_id))
	for strip in layout.runways:
		check(strip.position.y == 0.0 and strip.world_half_extents.x > 0 and strip.world_half_extents.y > 0, label + " strip has a finite positive axis-aligned reservation")
		for target in targets:
			check(not strip.rect.grow(CLEARANCE).intersects(target.footprint_rect), label + " strip does not pass beneath " + target.id)
	for target in targets:
		if not bool(target.mobile):
			continue
		var route: Dictionary = layout.routes[target.mobile_route_id]
		check(route.world_points[0] == target.position and route.world_points.size() == 2, label + " mobile begins at its first waypoint and can reverse the same segment without teleport")
		check(float(route.width) * .5 >= target.footprint.length() * .5 + CLEARANCE, label + " mobile full square and clearance fit the road core, including its rounded end caps")
		var swept := _mobile_reservation(target, route)
		for other in targets:
			if not bool(other.mobile) or str(other.id) <= str(target.id):
				continue
			var other_route: Dictionary = layout.routes[other.mobile_route_id]
			check(not swept.grow(CLEARANCE * .5).intersects(_mobile_reservation(other, other_route).grow(CLEARANCE * .5)), label + " moving neighbors cannot overlap anywhere along either complete route: " + target.id + "/" + other.id)
		for other in targets:
			if bool(other.mobile):
				continue
			var expanded: Rect2 = other.footprint_rect.grow(CLEARANCE)
			expanded.position -= target.footprint * .5
			expanded.size += target.footprint
			var from: Vector3 = route.world_points[0]
			var to: Vector3 = route.world_points[1]
			check(not _segment_intersects_rect(Vector2(from.x, from.z), Vector2(to.x, to.z), expanded), label + " full moving footprint clears fixed building " + other.id)

func _check_width_variant(instantiated: Dictionary, authored: Dictionary, sector: int) -> void:
	var compact := float(instantiated.bounds.half_x) < 13.0
	check(instantiated.width_variant == ("compact" if compact else "wide"), "Sector %d selects the explicit layout for its measured low-camera allowance" % sector)
	check(instantiated.targets.size() == authored.targets.size() and int(instantiated.quota) == int(authored.quota), "Sector %d compact reflow preserves count and quota" % sector)
	check(instantiated.priority_ids == authored.priority_ids and instantiated.secondary_ids == authored.secondary_ids and instantiated.radar_groups == authored.radar_groups, "Sector %d compact reflow preserves all objective IDs and radar relationships" % sector)
	for target in instantiated.targets:
		var source: Dictionary = authored.targets.filter(func(t): return t.id == target.id)[0]
		check(target.variant == source.variant and target.rapid_fire == source.rapid_fire and target.health_bonus == source.health_bonus and target.mobile == source.mobile, "Sector %d reflow preserves actor behavior and health for %s" % [sector, target.id])
	if sector == 0:
		var depot: Vector3 = instantiated.target_by_id["coral/f01"].position
		var cannon: Vector3 = instantiated.target_by_id["coral/b10"].position
		check(is_equal_approx(depot.x, cannon.x) and depot.distance_to(cannon) > 3.05 and depot.distance_to(cannon) <= 5.5, "Corail demonstrates a real neighboring cannon inside the fuel reaction radius at every supported width")
	# Explicit compact placements are copies: no source catalogue mutation.
	check(LAYOUTS.layout_for_sector(sector).targets == authored.targets, "Sector %d compact instantiation leaves the wide authored catalogue unchanged" % sector)

func _mobile_reservation(target: Dictionary, route: Dictionary) -> Rect2:
	# Conservative swept rectangle for the authored two-point, straight routes.
	# The road radius also reserves visual heading changes at both endpoints.
	var a: Vector3 = route.world_points[0]
	var b: Vector3 = route.world_points[1]
	var radius := maxf(float(route.width) * .5, target.footprint.length() * .5)
	var minimum := Vector2(minf(a.x, b.x), minf(a.z, b.z)) - Vector2.ONE * radius
	var maximum := Vector2(maxf(a.x, b.x), maxf(a.z, b.z)) + Vector2.ONE * radius
	return Rect2(minimum, maximum - minimum)

func _check_dimension_guards(mission: Dictionary, sector: int) -> void:
	var valid_length: float = (float(MINIMUM_HALF_Z[sector]) + 16.0) * 2.0
	check(not bool(LAYOUTS.instantiate_layout(mission, 40.0, valid_length, 6.9).valid), "Sector %d rejects an allowance below the proven compact 7 m minimum" % sector)
	check(not bool(LAYOUTS.instantiate_layout(mission, 65.0, valid_length - 1.0, 18.5).valid), "Sector %d rejects a length below its authored spacing budget" % sector)
	var capped := LAYOUTS.instantiate_layout(mission, 65.0, valid_length, 40.0)
	check(is_equal_approx(float(capped.bounds.half_x), 65.0 * .33 - 2.3), "Sector %d caps requested target width to the actual flat plateau" % sector)
	var nonfinite := LAYOUTS.instantiate_layout(mission, NAN, valid_length, 18.5)
	check(not bool(nonfinite.valid) and not nonfinite.warnings.is_empty(), "Sector %d rejects non-finite geometry inputs explicitly" % sector)

func _check_copy_isolation(sector: int) -> void:
	var first := LAYOUTS.layout_for_sector(sector)
	var second := LAYOUTS.layout_for_sector(sector)
	var expected_id: String = second.targets[0].id
	first.targets[0].id = "mutated"
	first.routes.clear()
	first.priority_ids.append("invented")
	check(second.targets[0].id == expected_id and not second.routes.is_empty() and not second.priority_ids.has("invented"), "Sector %d returns independent authored dictionaries and arrays" % sector)
	check(LAYOUTS.layout_for_sector(sector).targets[0].id == expected_id, "Sector %d cannot mutate the persistent catalogue" % sector)

func _check_ocean_compatibility(sources: Array) -> void:
	var first := OPERATIONS.prepare(sources[0])
	check(first.boss == "bomber" and is_equal_approx(float(first.boss_health_scale), .58), "M01 retains the existing introductory command bomber")
	var sector_identities := {}
	for source in sources:
		var number := int(source.id)
		if number % 4 == 3:
			continue
		var snapshot := JSON.stringify(source)
		var mission := OPERATIONS.prepare(source)
		var repeated := OPERATIONS.prepare(source)
		check(JSON.stringify(source) == snapshot, "M%02d ocean overlay does not mutate the source" % number)
		check(JSON.stringify(mission) == JSON.stringify(repeated), "M%02d ocean overlay is deterministic from fresh source data" % number)
		check(int(mission.quota) == int(source.quota), "M%02d ocean identity does not inflate its quota" % number)
		check(int(mission.duration) == (105 if number == 1 else int(source.duration)), "M%02d ocean identity preserves its mission duration" % number)
		check(mission.boss == ("bomber" if number == 1 else source.boss), "M%02d uses its real existing boss kind" % number)
		check(not mission.get("ground_assault", false), "M%02d ocean identity does not introduce a new descent" % number)
		check(str(mission.briefing).contains(str(mission.teaching)) and not str(mission.teaching).contains("radar"), "M%02d visible teaching matches real aerial behaviors without an invented radar" % number)
		check(str(mission.briefing).length() <= 460, "M%02d ocean briefing fits the text budget; rendered wrapping remains to verify" % number)
		check(mission.overlay_warnings.is_empty(), "M%02d authored recovery windows stay within its time budget" % number)
		sector_identities[int(mission.sector)] = str(mission.encounter_overlay.id)
		var source_fighters: int = source.events.filter(func(e): return e.kind in ["zero", "hayabusa"]).size()
		var actual_fighters: int = mission.events.filter(func(e): return e.kind in ["zero", "hayabusa"]).size()
		check(source_fighters == actual_fighters and int(mission.encounter_overlay.fighters) == source_fighters, "M%02d changes fighter composition without adding a wave" % number)
		for kind in ["bomber", "naval", "red", "boss"]:
			var before: int = source.events.filter(func(e): return e.kind == kind).size()
			var after: int = mission.events.filter(func(e): return e.kind == kind).size()
			var existing_intro_addition := 1 if number == 1 and kind in ["naval", "red", "boss"] else 0
			check(after == before + existing_intro_addition, "M%02d preserves its existing %s event budget" % [number, kind])
		var previous_time := -100.0
		var fighter_time := -100.0
		var roles_used := {}
		for event in mission.events:
			check(float(event.time) >= previous_time and float(event.time) < float(mission.duration), "M%02d events stay ordered and before the mission deadline" % number)
			previous_time = float(event.time)
			if event.kind not in ["zero", "hayabusa"]:
				continue
			check(event.role in ["escort", "interceptor", "gunner"] and int(event.pattern) in [0, 1], "M%02d uses roles and pattern parities consumed by actual combat" % number)
			roles_used[event.role] = true
			check(float(event.time) - fighter_time >= 1.2 - .000001, "M%02d recovery cannot release several deferred fighter waves at once" % number)
			fighter_time = float(event.time)
			for window in mission.breathing_windows:
				check(not (float(event.time) >= float(window.start) and float(event.time) < float(window.end)), "M%02d standard fighter entry respects its explicit recovery window" % number)
		check(roles_used.has("escort") and roles_used.has("interceptor"), "M%02d combines normal and genuinely predictive attacks" % number)
		check(not roles_used.has("gunner") if int(mission.sector) == 0 else roles_used.has("gunner"), "M%02d introduces the real offset-aim gunner after the Corail sector" % number)
		if mission.secondary == "convoy":
			var convoy_at := float(mission.duration) * .26
			check(str(mission.teaching).contains("convoi"), "M%02d teaches the real protected vessel and its targeting threat" % number)
			check(float(mission.convoy_pressure_at) > convoy_at and float(mission.convoy_pressure_at) + 6.5 < convoy_at + 32.0, "M%02d existing bomber request can complete its ascent before the escort window closes" % number)
			check(mission.events.any(func(e): return e.kind == "bomber" and is_equal_approx(float(e.time), float(mission.convoy_pressure_at))), "M%02d schedules an existing bomber inside the real escort window, subject to the active cap" % number)
		if str(mission.boss) != "":
			check(not str(mission.boss_teaching).is_empty() and str(mission.briefing).contains(str(mission.boss_teaching)), "M%02d describes its existing destructible boss components" % number)
	var unique_identities := {}
	for identity in sector_identities.values():
		unique_identities[identity] = true
	check(sector_identities.size() == 8 and unique_identities.size() == 8, "All eight ocean sectors expose different authored encounter signatures")
	for number in [6, 10, 14, 18, 22, 26, 30]:
		var mission := OPERATIONS.prepare(sources[number - 1])
		check(mission.secondary == "convoy" and int(mission.secondary_target) == 1 and not mission.get("ground_assault", false), "M%02d retains its real ocean convoy objective without an extra descent" % number)
	check(not OPERATIONS.prepare(sources[16]).get("ground_assault", false), "M17 remains an ocean mission; mobile ground teaching begins in M19")
	var legacy := {"formation": "Détruire une escadrille rouge complète", "bomber": "Intercepter un bombardier", "naval": "Couler deux navires", "boss": "Neutraliser les deux points faibles du boss", "convoy": "Protéger le convoi pendant 32 secondes", "radar": "Détruire les deux stations radar"}
	for kind in legacy:
		check(OPERATIONS.objective_text(kind) == legacy[kind], "Historical objective_text remains compatible for " + str(kind))

func _segment_intersects_rect(from: Vector2, to: Vector2, rect: Rect2) -> bool:
	# Liang-Barsky slab intersection, with endpoints and tangencies included.
	var low := 0.0
	var high := 1.0
	var direction := to - from
	for axis in range(2):
		var origin: float = from[axis]
		var speed: float = direction[axis]
		var minimum: float = rect.position[axis]
		var maximum: float = rect.end[axis]
		if absf(speed) < .000001:
			if origin < minimum or origin > maximum:
				return false
			continue
		var enter := (minimum - origin) / speed
		var leave := (maximum - origin) / speed
		if enter > leave:
			var temporary := enter
			enter = leave
			leave = temporary
		low = maxf(low, enter)
		high = minf(high, leave)
		if low > high:
			return false
	return true

func _check_geometry_helper() -> void:
	var obstacle := Rect2(4, -1, 2, 2)
	check(_segment_intersects_rect(Vector2(0, 0), Vector2(10, 0), obstacle), "Reservation helper detects a road through a building")
	check(not _segment_intersects_rect(Vector2(0, 2), Vector2(10, 2), obstacle), "Reservation helper rejects a parallel clear road")
	check(_segment_intersects_rect(Vector2(5, .5), Vector2(5, .5), obstacle), "Reservation helper detects a stationary point inside a building")
	check(not _segment_intersects_rect(Vector2(1, .5), Vector2(1, .5), obstacle), "Reservation helper rejects a stationary point outside a building")
	check(_segment_intersects_rect(Vector2(0, 1), Vector2(10, 1), obstacle), "Reservation helper includes a tangent to the reserved margin")
