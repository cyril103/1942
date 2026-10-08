extends SceneTree
## PHASE 5 CANDIDATE. Policy, real font metrics, and source safety checks only.
## This does not prove shader compilation, human recognition, or frame timing.
const POLICY := preload("res://scripts/campaign/readability_policy.gd")
const LAYOUTS := preload("res://scripts/campaign/raid_layouts.gd")
const FONT := preload("res://assets/ui/fonts/BarlowCondensed-Medium.ttf")
const APP_PATH := "res://scripts/campaign/app.gd"
const HUD_PATH := "res://scripts/campaign/hud.gd"
const BASELINE := "res://tests/readability-physics-baseline.json"
const OUTPUT := "user://raid-readability-candidate-results.json"
var checks := 0
var failures: Array[String] = []
var observations: Array[Dictionary] = []
var app_script: Script
var hud_script: Script
var production_scripts_ready := false
var reservation_fixture_attempts := 0
var reservation_fixtures_completed := 0
var rectangle_suite_completed := false
var source_safety_completed := false
const EXPECTED_RESERVATION_FIXTURES := 3
const EXPECTED_MECHANICS_PATHS := ["res://scripts/combat.gd", "res://scripts/weapons.gd", "res://scripts/campaign/ground_target.gd", "res://scripts/campaign/ground_assault.gd"]
const EXPECTED_AUDIO_IDS := {
	"res://scripts/weapons.gd": ["weapons-bind-laser", "weapons-salvo-signature", "weapons-power-signature", "weapons-stop-all", "weapons-laser-state", "weapons-restore-idle-stop", "weapons-restore-playing-start"],
	"res://scripts/campaign/ground_assault.gd": ["ground-assault-entry-cue"]
}

class RaidPanels extends Node:
	var layout := {"priority_ids": ["fixture-priority"]}

class DirectorPanels extends Node:
	var radio_time := 1.0
	var boss: Node
	var feedback_time := 1.0
	var feedback := "FRAPPE CONFIRMÉE  /  OBJECTIF TERRESTRE ACCOMPLI"
	var ability_time := 3.5
	var combat: Node

class CombatPanels extends Node:
	var respawn_time := 1.0
	var game_over := false

class BossPanel extends Node:
	var alive := true

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
		push_error(description)

func _initialize() -> void:
	_run.call_deferred()

func _probe_production_scripts() -> void:
	# Loading an invalid dependency can leave a Script resource that has no
	# usable constructor. Do not call new() until can_instantiate is true.
	production_scripts_ready = false
	var usable := 0
	for path in [APP_PATH, HUD_PATH]:
		var resource: Script = load(path) as Script
		check(is_instance_valid(resource), "Production Script resource loads: " + path)
		var can_construct: bool = is_instance_valid(resource) and resource.can_instantiate()
		check(can_construct, "Production Script can_instantiate: " + path)
		if path == APP_PATH: app_script = resource
		else: hud_script = resource
		if not can_construct: continue
		# new is the GDScript factory, not a native Script API method. Keep its
		# dispatch/result Variant so a failed constructor cannot abort a typed
		# assignment before our explicit validity assertion.
		var factory: Variant = resource
		var instance: Variant = factory.new()
		var control_constructed: bool = is_instance_valid(instance) and instance is Control
		check(control_constructed, "Production Script creates a real Control without running _ready: " + path)
		if control_constructed:
			usable += 1
		if is_instance_valid(instance) and instance is Node:
			instance.free()
	production_scripts_ready = usable == 2
	observations.append({"scope": "production App/HUD load and constructor preflight", "usable_scripts": usable,
		"ready": production_scripts_ready, "scene_tree_ready_or_rendering": false})

func _free_fixture_nodes(nodes: Array[Node]) -> void:
	for node in nodes:
		if is_instance_valid(node): node.free()

func _row(id: String, at := Vector2(500, 350)) -> Dictionary:
	return {"id": id, "variant": "battery", "alive": true, "visible": true,
		"screen_position": at, "priority": false, "priority_tag": "", "mobile": false,
		"rapid_fire": false, "warning_time": 0.0, "salvo_remaining": 0,
		"health": 10.0, "max_health": 10.0, "motion_announced": false}

func _truth_table() -> void:
	var cases := 0
	for radar in [false, true]:
		for priority in [false, true]:
			for health in [-1.0, 0.0, 8.0, 10.0, 11.0]:
				for warning in [-.1, 0.0, .00001, .65]:
					for salvo in [-1, 0, 1, 4]:
						for mobile in [false, true]:
							for announced in [false, true]:
								var row := _row("truth")
								row.variant = "radar" if radar else "battery"
								row.priority = priority
								row.health = health
								row.warning_time = warning
								row.salvo_remaining = salvo
								row.mobile = mobile
								row.motion_announced = announced
								var rows: Array[Dictionary] = [row]
								var original: Array[Dictionary] = rows.duplicate(true)
								var records := POLICY.select(rows, Vector2(500, 500), false)
								var context := "Truth case %d" % cases
								check(records.size() == 1, context + " retains the live contact")
								if records.size() != 1: continue
								var actual: Dictionary = records[0]
								var persistent: bool = radar or priority
								var dangerous: bool = float(warning) > 0 or int(salvo) > 0
								var damaged: bool = float(health) >= 0 and float(health) < 10
								check(bool(actual.persistent) == persistent, context + " preserves radars and priorities")
								check(bool(actual.fire_warning) == dangerous, context + " preserves imminent and active salvos")
								check(bool(actual.damaged) == damaged, context + " identifies damage without inventing it")
								check(bool(actual.frame_visible) == (persistent or dangerous or damaged), context + " applies frame hierarchy")
								check(bool(actual.label_visible) == (persistent or dangerous or damaged), context + " applies the single-contact label hierarchy")
								check(bool(actual.health_visible) == damaged, context + " displays health only when damaged")
								check(bool(actual.motion_hint) == (mobile and announced), context + " distinguishes motion from firing")
								check(not bool(actual.focused), context + " does not invent focused flight")
								check(rows == original, context + " never writes actor snapshot data")
								check(actual.warning_time == warning and actual.salvo_remaining == salvo and actual.health == health, context + " never changes timers, salvo counts, or health")
								cases += 1
	for state in ["alive", "visible"]:
		var row := _row("excluded")
		row[state] = false
		var rows: Array[Dictionary] = [row]
		check(POLICY.select(rows, Vector2(500, 500), true).is_empty(), "Hidden or dead contact has no marker: " + state)
	var invalid: Array[Dictionary] = [_row("nonfinite", Vector2(INF, 10))]
	check(POLICY.select(invalid, Vector2(500, 500), true).is_empty(), "Invalid projection has no unbounded marker")
	observations.append({"scope": "presentation truth table", "cases": cases})

func _focus() -> void:
	var rows: Array[Dictionary] = [
		_row("zeta", Vector2(500, 350)), _row("alpha", Vector2(500, 350)),
		_row("aft", Vector2(500, 510)), _row("wide", Vector2(529, 490)),
		_row("far", Vector2(500, 49))]
	check(POLICY.focus_target_id(rows, Vector2(500, 500), true) == "alpha", "Focus has one stable ID tie breaker")
	rows.reverse()
	check(POLICY.focus_target_id(rows, Vector2(500, 500), true) == "alpha", "Focus is independent of contact iteration order")
	check(POLICY.focus_target_id(rows, Vector2(500, 500), false).is_empty(), "Focus requires the actual focus input")
	check(POLICY.focus_target_id(rows, Vector2(INF, 500), true).is_empty(), "Invalid player projection cannot create focus")
	var selected := POLICY.select(rows, Vector2(500, 500), true)
	var focused := 0
	for record in selected:
		if record.focused:
			focused += 1
			check(str(record.id) == "alpha" and record.frame_visible and record.label_visible, "Focused contact receives a readable marker")
	check(focused == 1, "Focused flight highlights exactly one contact")
	for u in [2.0 / 3.0, 1.0]:
		var scaled: Array[Dictionary] = [_row("inside", Vector2(500, 500) + Vector2(27, -449) * u), _row("outside", Vector2(500, 500) + Vector2(29, -10) * u)]
		check(POLICY.focus_target_id(scaled, Vector2(500, 500), true, u) == "inside", "Focus corridor respects actual viewport scale %.3f" % u)

func _crowd_budget() -> void:
	var rows: Array[Dictionary] = []
	for index in range(40):
		var row := _row("crowd-%02d" % index, Vector2(500 + index * 2, 400 - index * 3))
		row.variant = "radar" if index < 2 else "battery"
		row.priority = index in [2, 3]
		row.warning_time = .65
		row.salvo_remaining = 4
		row.health = 8.0
		row.mobile = index in range(10, 16)
		row.motion_announced = row.mobile
		rows.append(row)
	var original: Array[Dictionary] = rows.duplicate(true)
	var records := POLICY.select(rows, Vector2(500, 500), false)
	var labels := 0
	var context_labels := 0
	var motions := 0
	for record in records:
		check(record.frame_visible and record.fire_warning, "Crowd warning frame remains visible: " + str(record.id))
		if record.label_visible:
			labels += 1
			if not record.persistent: context_labels += 1
		if record.persistent: check(record.label_visible, "Required crowd label is not suppressed: " + str(record.id))
		if record.motion_hint: motions += 1
	check(records.size() == 40, "The text budget never drops a live warning contact")
	check(labels == 8 and context_labels == POLICY.MAX_CONTEXT_LABELS, "At most four optional texts accompany four required labels")
	check(motions == 6, "Each announced mobile movement keeps its distinct corridor")
	check(rows == original, "Crowd selection leaves all warning and salvo values unchanged")
	var ranked: Array[Dictionary] = [_row("damaged", Vector2(500, 499)), _row("firing-far", Vector2(700, 100)), _row("firing-near", Vector2(600, 450)), _row("firing-middle", Vector2(650, 400)), _row("firing-last", Vector2(750, 90))]
	ranked[0].health = 9
	for index in range(1, ranked.size()): ranked[index].warning_time = .1
	var ranking := POLICY.select(ranked, Vector2(500, 500), false)
	for record in ranking:
		check(bool(record.label_visible) == str(record.id).begins_with("firing"), "All four imminent warnings precede the closer damaged label: " + str(record.id))
	observations.append({"scope": "worst authored contact count", "contacts": records.size(), "labels": labels, "warning_frames": 40, "motion_hints": motions})

func _catalogue() -> Array[String]:
	var labels: Array[String] = []
	for sector in range(8):
		var layout: Dictionary = LAYOUTS.layout_for_sector(sector)
		var rows: Array[Dictionary] = []
		var persistent := 0
		for target in layout.targets:
			var row := _row(str(target.id))
			for key in ["variant", "priority", "priority_tag", "rapid_fire", "mobile"]: row[key] = target[key]
			rows.append(row)
			if str(target.variant) == "radar" or bool(target.priority): persistent += 1
			var text := POLICY.label_for(row)
			if text not in labels: labels.append(text)
		var selected := POLICY.select(rows, Vector2(500, 500), false)
		var required_texts := 0
		for record in selected:
			if record.label_visible: required_texts += 1
			check(bool(record.frame_visible) == bool(record.persistent), "Idle catalogue only marks required targets S%d %s" % [sector + 1, str(record.id)])
		check(required_texts == persistent, "Every actual radar and priority has an idle label S%d" % (sector + 1))
		check(persistent <= POLICY.CATALOG_PERSISTENT_LABEL_BOUND, "Actual catalogue respects the four-required-label budget S%d" % (sector + 1))
		check(rows.size() <= 40, "Actual authored contact bound remains forty S%d" % (sector + 1))
		observations.append({"scope": "actual sector label bound", "sector": sector + 1, "contacts": rows.size(), "persistent": persistent})
	check("COMMANDEMENT · PRIORITÉ" in labels, "Bounds cases include the longest actual command priority text")
	return labels

func _point_bounds(points: PackedVector2Array) -> Rect2:
	var result := Rect2(points[0], Vector2.ZERO)
	for point in points: result = result.expand(point)
	return result

func _actual_panel_reservations(viewport: Vector2, play: Rect2, u: float, labels: Array[String]) -> bool:
	# Invoke the actual HUD helper, using its real Control rectangle types.
	# No flight scene, actor simulation, _ready(), or rendering is requested.
	reservation_fixture_attempts += 1
	var can_construct: bool = production_scripts_ready and is_instance_valid(hud_script) and hud_script.can_instantiate()
	check(can_construct, "Reservation fixture requires an instantiable production HUD %s" % str(viewport))
	if not can_construct: return false
	var factory: Variant = hud_script
	var hud: Variant = factory.new()
	var hud_constructed: bool = is_instance_valid(hud) and hud is Control
	check(hud_constructed, "Reservation fixture creates its real HUD Control %s" % str(viewport))
	if not hud_constructed: return false
	check(hud.has_method("_ground_label_reservations"), "Reservation fixture has the real production reservation method %s" % str(viewport))
	if not hud.has_method("_ground_label_reservations"):
		hud.free()
		return false
	var cockpit := Control.new()
	var director := DirectorPanels.new()
	var boss := BossPanel.new()
	var combat := CombatPanels.new()
	var raid := RaidPanels.new()
	var badge := PanelContainer.new()
	var allocated: Array[Node] = [hud, cockpit, director, boss, combat, raid, badge]
	var fixtures_constructed := true
	for node in allocated:
		var valid := is_instance_valid(node)
		check(valid, "Every reservation fixture node was constructed %s" % str(viewport))
		fixtures_constructed = fixtures_constructed and valid
	if not fixtures_constructed:
		_free_fixture_nodes(allocated)
		return false
	cockpit.size = viewport
	director.boss = boss
	director.combat = combat
	hud.cockpit = cockpit
	hud.director = director
	hud.jam_badge = badge
	hud.jam_badge.position = Vector2(play.get_center().x - 150 * u, play.position.y + 12 * u)
	hud.jam_badge.size = Vector2(300, 40) * u
	# A runtime error in the helper can return null. Use Variant until its shape
	# is checked so this fixture refuses to silently skip the rectangle checks.
	var raw_panels: Variant = hud._ground_label_reservations(raid, play, u)
	check(raw_panels is Array, "Reservation method returned an actual rectangle array %s" % str(viewport))
	if raw_panels is not Array:
		_free_fixture_nodes(allocated)
		return false
	var panels: Array[Rect2] = []
	for panel in raw_panels:
		check(panel is Rect2, "Reservation array contains an actual Rect2 %s" % str(viewport))
		if panel is not Rect2:
			_free_fixture_nodes(allocated)
			return false
		panels.append(panel)
	check(panels.size() == 9, "Actual HUD reserves ground, chain, objective, jam, radio, boss, feedback, ability, and reinforcement rectangles %s" % str(viewport))
	for panel in panels:
		check(play.encloses(panel), "Entire actual overlay panel remains inside the gameplay rectangle %s %s" % [str(viewport), str(panel)])
		check(panel.position.y >= play.position.y and panel.end.y <= play.end.y, "Actual panel has no overlap with the score or command bands %s" % str(viewport))
	var reinforcement := Rect2(play.get_center() - Vector2(290, 72) * u, Vector2(580, 144) * u)
	check(panels.has(reinforcement), "The full real reinforcement panel is reserved %s" % str(viewport))
	combat.respawn_time = 0
	combat.game_over = true
	var game_over_panels: Variant = hud._ground_label_reservations(raid, play, u)
	check(game_over_panels is Array, "Game Over reservation invocation must return its real rectangle array %s" % str(viewport))
	if game_over_panels is not Array:
		_free_fixture_nodes(allocated)
		return false
	check(game_over_panels.has(reinforcement), "Game Over reserves the same complete real panel with no reinforcement timer %s" % str(viewport))
	combat.game_over = false
	director.feedback_time = 0
	director.ability_time = 0
	var inactive_panels: Variant = hud._ground_label_reservations(raid, play, u)
	check(inactive_panels is Array, "Inactive overlay reservation invocation must return its real rectangle array %s" % str(viewport))
	if inactive_panels is not Array:
		_free_fixture_nodes(allocated)
		return false
	check(inactive_panels.size() == 6, "Inactive feedback, ability, reinforcement, and Game Over do not reserve stale space %s" % str(viewport))
	# Exercise the complete active-panel set below; only the actor snapshots are
	# changed, and none of these fixtures run a flight scene or a rendering pass.
	director.feedback_time = 1
	director.ability_time = 3.5
	combat.respawn_time = 1
	var frames: Array[Rect2] = [
		Rect2(play.position + Vector2(15, 80) * u, Vector2(90, 50) * u),
		Rect2(Vector2(play.end.x - 60 * u, play.end.y - 10 * u), Vector2(100, 70) * u),
		Rect2(play.get_center(), Vector2(100, 70) * u)]
	for projected in frames:
		var frame := POLICY.marker_frame(projected, play, true, u)
		var occupied: Array[Rect2] = panels.duplicate()
		for value in labels:
			var placed: Dictionary = POLICY.label_placement(frame, value, FONT, play, u, occupied)
			check(placed.valid and play.encloses(placed.rect), "Complete actual-font label remains in play around actual HUD panels %s %s" % [str(viewport), value])
			if placed.valid:
				# A deliberately overcrowded fixture may report overlap; it must
				# never escape the gameplay rectangle to obtain a free slot.
				var count := 0
				for other in occupied:
					if placed.rect.grow(2 * u).intersects(other): count += 1
				check(count == int(placed.overlaps), "Panel overlap reporting matches the actual measured rectangles")
				occupied.append(placed.rect)
	_free_fixture_nodes(allocated)
	observations.append({"scope": "actual HUD reservation helper with Control rectangles and real font", "viewport": str(viewport), "panels": panels.size(), "runtime_projection": false})
	# This sentinel is written only after every existing fixture assertion ran.
	# _run checks the exact count even if GDScript aborts this helper mid-call.
	reservation_fixtures_completed += 1
	return true

func _rectangles(labels: Array[String]) -> void:
	for viewport in [Vector2(1280, 720), Vector2(1920, 1080), Vector2(960, 1080)]:
		var u: float = viewport.y / 1080.0
		# Same compact-cockpit geometry as the actual gameplay viewport.
		var play := Rect2(Vector2(0, 64 * u), Vector2(viewport.x, viewport.y - 108 * u))
		var score := Rect2(Vector2.ZERO, Vector2(viewport.x, play.position.y))
		var commands := Rect2(Vector2(0, play.end.y), Vector2(viewport.x, viewport.y - play.end.y))
		var fixture_completed: Variant = _actual_panel_reservations(viewport, play, u, labels)
		check(fixture_completed == true, "Reservation fixture must complete every assertion %s" % str(viewport))
		var shape := Vector2(100, 70) * u
		var projections: Array[Rect2] = [
			Rect2(play.position - shape * .5, shape),
			Rect2(Vector2(play.end.x - shape.x * .5, play.position.y - shape.y * .5), shape),
			Rect2(play.end - shape * .5, shape),
			Rect2(Vector2(play.position.x - shape.x * .5, play.end.y - shape.y * .5), shape),
			Rect2(play.get_center() - shape * .5, shape),
			Rect2(Vector2(play.get_center().x, play.end.y - 3 * u), shape),
			Rect2(play.position - shape * 3, shape),
			Rect2(play.end + shape * 2, shape),
			Rect2(play.get_center() - shape * .5, -shape)]
		var labelled := 0
		for persistent in [false, true]:
			for projected in projections:
				var frame := POLICY.marker_frame(projected, play, persistent, u)
				if frame.size.x <= 0 or frame.size.y <= 0:
					check(not persistent, "Reported priority/radar keeps a bounded edge marker %s" % str(viewport))
					continue
				var description := "Whole bounds %s %s" % [str(viewport), str(projected)]
				# Include the entire thickest warning frame and antialias margin.
				check(play.encloses(frame.grow(.95 * u + 1.0)), description + " contains frame, stroke, and antialias margin")
				check(not frame.intersects(score) and not frame.intersects(commands), description + " separates frame from both permanent bands")
				var bar := POLICY.health_bar(frame, play, u)
				check(play.encloses(bar), description + " contains the entire health bar")
				check(not bar.intersects(score) and not bar.intersects(commands), description + " separates health bar from both permanent bands")
				for value in labels:
					var placement: Dictionary = POLICY.label_placement(frame, value, FONT, play, u)
					check(bool(placement.valid), description + " fits the whole actual label " + value)
					if not placement.valid: continue
					var rect: Rect2 = placement.rect
					var pixels := int(placement.font_size)
					var ascent := FONT.get_ascent(pixels)
					var descent := FONT.get_descent(pixels)
					var width := FONT.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, pixels).x
					var baseline: Vector2 = placement.baseline
					var text_bounds := Rect2(baseline - Vector2(0, ascent), Vector2(width, ascent + descent))
					var shadow_bounds := Rect2(text_bounds.position + Vector2.ONE, text_bounds.size)
					check(play.encloses(rect), description + " contains the measured rectangle " + value)
					# Only font-metric arithmetic gets 0.05px float tolerance. The
					# real play rectangle and both permanent bands get no growth.
					check(rect.grow(.05).encloses(text_bounds) and rect.grow(.05).encloses(shadow_bounds), description + " contains font ascent/descent, full advance width, and 1px shadow " + value)
					check(not rect.intersects(score) and not rect.intersects(commands), description + " keeps the complete text out of both permanent bands " + value)
					check(is_equal_approx(float(placement.glyph_width), width), description + " draws the complete string without truncating the priority suffix " + value)
					labelled += 1
		var blocked_frame := POLICY.marker_frame(Rect2(play.position + Vector2(25, 35) * u, shape), play, true, u)
		var panels: Array[Rect2] = [Rect2(play.position, Vector2(320, 150) * u), Rect2(Vector2(play.end.x - 430 * u, play.position.y), Vector2(430, 80) * u)]
		var moved: Dictionary = POLICY.label_placement(blocked_frame, "COMMANDEMENT · PRIORITÉ", FONT, play, u, panels)
		check(moved.valid and int(moved.overlaps) == 0, "Required text finds a free measured slot around overlay panels %s" % str(viewport))
		if moved.valid:
			for panel in panels: check(not panel.intersects(moved.rect), "Required text avoids the entire panel %s" % str(viewport))
			check(moved.rect.get_center().distance_to(blocked_frame.get_center()) < 320 * u, "Corner priority stays near its target instead of jumping to bottom of screen")
			var link: Array[PackedVector2Array] = POLICY.label_link(blocked_frame, moved.rect, play, u, panels)
			# A panel may cover the whole short connection at this corner. Never
			# draw across it just to manufacture a visible segment.
			for segment in link:
				for step in range(21):
					var point: Vector2 = segment[0].lerp(segment[1], float(step) / 20.0)
					var footprint := Rect2(point - Vector2.ONE * u, Vector2.ONE * 2 * u)
					check(play.encloses(footprint), "Association line including stroke remains inside gameplay")
					for panel in panels: check(not panel.intersects(footprint), "Association line never draws through reserved panels")
		var adjacent := Rect2(blocked_frame.position + Vector2(0, blocked_frame.size.y + 4 * u), Vector2(80, 20) * u)
		check(POLICY.label_link(blocked_frame, adjacent, play, u).is_empty(), "Adjacent label needs no additional association line")
		var link_origin := Rect2(play.get_center() - Vector2(200, 0) * u, Vector2(30, 30) * u)
		var link_label := Rect2(play.get_center() + Vector2(150, 0) * u, Vector2(90, 25) * u)
		var link_blockers: Array[Rect2] = [Rect2(play.get_center() - Vector2(20, 20) * u, Vector2(40, 80) * u)]
		var split_link := POLICY.label_link(link_origin, link_label, play, u, link_blockers)
		check(split_link.size() == 2, "A distant label connection survives on both sides of an obstructing panel")
		for segment in split_link:
			for step in range(21):
				var at: Vector2 = segment[0].lerp(segment[1], float(step) / 20.0)
				check(not link_blockers[0].has_point(at), "Connection is clipped around intermediate panel")
		var full: Array[Rect2] = [play]
		var crowded: Dictionary = POLICY.label_placement(blocked_frame, "RADAR · PRIORITÉ", FONT, play, u, full)
		check(crowded.valid and int(crowded.overlaps) > 0 and play.encloses(crowded.rect), "Impossible interior clearance is reported, never pushes required text into score/commands %s" % str(viewport))
		var tiny: Dictionary = POLICY.label_placement(blocked_frame, "COMMANDEMENT · PRIORITÉ", FONT, Rect2(Vector2.ZERO, Vector2(20, 20)), u)
		check(not tiny.valid, "Insufficient text area fails explicitly instead of truncating priority text")
		var points: Array[Vector2] = [play.position - Vector2(500, 500), play.end + Vector2(500, 500), play.get_center(), Vector2(play.end.x + 500, play.position.y - 500), Vector2(play.position.x - 500, play.end.y + 500)]
		for from in points:
			for to in points:
				var geometry: Dictionary = POLICY.motion_hint_geometry(from, to, play, u)
				check(geometry.segments.size() <= 8, "Motion corridor never exceeds eight dashes %s" % str(viewport))
				for segment in geometry.segments:
					check(play.encloses(_point_bounds(segment).grow(float(geometry.line_width) * .5 + 1.0)), "Entire mobile dash remains outside the permanent bands %s" % str(viewport))
				if geometry.arrow.size() >= 3:
					check(play.encloses(_point_bounds(geometry.arrow)), "Entire mobile arrow remains outside the permanent bands %s" % str(viewport))
		observations.append({"scope": "real Barlow font and complete marker bounds", "viewport": str(viewport), "labels_measured": labelled})
	rectangle_suite_completed = true

func _canonical_shader(path: String) -> String:
	var source := FileAccess.get_file_as_string(path).replace("\r\n", "\n")
	var lines: Array[String] = []
	for line in source.split("\n"):
		lines.append(line.get_slice("//", 0))
	return "".join(lines).replace(" ", "").replace("\t", "").replace("\r", "").replace("\n", "")

func _reverse_reviewed_audio(source: String, path: String, changes: Array) -> Dictionary:
	# The mechanics baseline remains the reviewed phase 4 source. Reverse only
	# the enumerated audio substitutions, requiring each exact installed block
	# once. Do not ignore whole functions, lines by keyword, or arbitrary diffs.
	var expected_ids: Array = EXPECTED_AUDIO_IDS.get(path, [])
	var seen: Dictionary = {}
	var valid := true
	for value in changes:
		check(value is Dictionary, "Every reviewed audio transformation has a dictionary schema")
		if value is not Dictionary: return {"valid": false, "source": source, "applied": seen.size()}
		var row: Dictionary = value
		var shape_valid: bool = row.get("id") is String and row.get("path") is String and row.get("installed_literal") is String and row.get("phase4_literal") is String
		check(shape_valid, "Reviewed audio transformation contains exact string literals")
		if not shape_valid: return {"valid": false, "source": source, "applied": seen.size()}
		var id: String = row.id
		var target_path: String = row.path
		var permitted_ids: Array = EXPECTED_AUDIO_IDS.get(target_path, [])
		var known: bool = id in permitted_ids
		check(known, "Reviewed audio transformation belongs to the fixed eight-hook inventory: " + id)
		if not known: return {"valid": false, "source": source, "applied": seen.size()}
		if target_path != path: continue
		var installed: String = row.installed_literal
		var historical: String = row.phase4_literal
		var unique: bool = not seen.has(id)
		var exact_once: bool = not installed.is_empty() and source.count(installed) == 1
		var expected_once: bool = row.get("expected_installed_occurrences") == 1
		check(unique, "Exactly one baseline entry for reviewed audio transformation: " + id)
		check(expected_once, "Reviewed audio transformation only permits exactly one occurrence: " + id)
		check(exact_once, "Installed reviewed audio literal occurs exactly once: " + id)
		if not unique or not exact_once or not expected_once:
			valid = false
			continue
		seen[id] = true
		source = source.replace(installed, historical)
	for id in expected_ids:
		var applied: bool = seen.has(id)
		check(applied, "Every expected audio transformation was applied, with no missing hook: " + str(id))
		valid = valid and applied
	check(seen.size() == expected_ids.size(), "Reviewed audio inventory has no unaccounted transformation for " + path)
	return {"valid": valid, "source": source, "applied": seen.size()}

func _source_safety() -> void:
	check(FileAccess.file_exists(BASELINE), "Reviewed source safety baseline accompanies the candidate")
	if not FileAccess.file_exists(BASELINE): return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(BASELINE))
	check(parsed is Dictionary, "Source safety baseline has an atomic dictionary schema")
	if parsed is not Dictionary: return
	var baseline: Dictionary = parsed
	var mechanics_files: Variant = baseline.get("files")
	check(mechanics_files is Dictionary, "Reviewed source safety baseline retains its complete mechanics file inventory")
	if mechanics_files is not Dictionary: return
	check(mechanics_files.size() == EXPECTED_MECHANICS_PATHS.size(), "Source safety checks all four original mechanics files")
	for path in EXPECTED_MECHANICS_PATHS:
		check(mechanics_files.has(path), "Original mechanics file cannot be omitted from the baseline: " + path)
	var audio_changes: Variant = baseline.get("allowed_audio_changes")
	check(audio_changes is Array, "Reviewed source safety baseline includes the exact audio normalization inventory")
	if audio_changes is not Array: return
	check(audio_changes.size() == 8, "Audio normalization inventory contains exactly seven Weapons hooks and one raid-entry cue")
	var allowed: Array = baseline.get("allowed_presentation_lines", [])
	for path in baseline.get("files", {}):
		var source := FileAccess.get_file_as_string(str(path)).replace("\r\n", "\n")
		check(not source.is_empty(), "Source safety file exists: " + str(path))
		var restored: Variant = _reverse_reviewed_audio(source, str(path), audio_changes)
		var restored_shape: bool = restored is Dictionary and restored.get("source") is String and restored.get("valid") == true
		check(restored_shape, "Reviewed audio normalization completed before comparing phase 4 mechanics: " + str(path))
		if not restored_shape: continue
		source = restored.source
		var retained: Array[String] = []
		var removed := 0
		var occurrences := {}
		for line in source.split("\n"):
			var stripped: String = line.strip_edges()
			if str(path) == "res://scripts/campaign/ground_target.gd" and stripped in allowed:
				removed += 1
				occurrences[stripped] = int(occurrences.get(stripped, 0)) + 1
			else:
				retained.append(line)
		var normalized := "\n".join(retained).strip_edges()
		check(normalized.sha256_text() == str(baseline.files[path]), "Physics source stays byte-identical after only the eight exact audio reversals and two reviewed presentation writes: " + str(path))
		if str(path) == "res://scripts/campaign/ground_target.gd":
			check(removed == 2, "Motion shader hook is installed atomically with its reset")
			for approved in allowed: check(int(occurrences.get(approved, 0)) == 1, "Exactly one approved presentation write: " + str(approved))
	var hostile := _canonical_shader("res://shaders/enemy_bullet.gdshader")
	for token in ["blend_premul_alpha", "unshaded", "depth_draw_never", "floatcore=1.0-smoothstep(.19,.28,r);", "floatbody=1.0-smoothstep(.66,.75,r);", "ALPHA=body;", "color*body", "halo*(1.0-shell)"]:
		check(token in hostile, "Hostile shader preserves body/core opacity and a single coherent halo: " + token)
	for token in ["sampler", "texture(", "TIME", "VERTEX", "for(", "while(", "next_pass"]:
		check(token not in hostile, "Hostile shader adds no extra sampler, animation, geometry, loop, or pass: " + token)
	check(hostile.count("voidfragment()") == 1 and hostile.count("exp(") == 1, "Hostile shader keeps one fragment function and the original one exponential")
	var friendly := _canonical_shader("res://shaders/tracer.gdshader")
	for token in ["blend_add", "smoothstep(-1.0,-.62,p.y)", "smoothstep(.65,1.0,p.y)", "smoothstep(.12,.30,abs(p.x))", "ALPHA=ends;"]:
		check(token in friendly, "Player tracer preserves its elongated geometry and alpha silhouette: " + token)
	for token in ["sampler", "texture(", "TIME", "VERTEX", "for(", "while(", "next_pass"]:
		check(token not in friendly, "Player tracer adds no new rendering stage: " + token)
	var fire_path := "res://shaders/ground_target_fire.gdshader"
	var fire_source := FileAccess.get_file_as_string(fire_path).replace("\r\n", "\n")
	var fire := _canonical_shader(fire_path)
	check("if(kind==2)" in fire and "elseif(kind==1)" in fire and "color=vec3(.70,.77,1.0);" in fire, "Mobile movement uses a distinct pale dashed shader branch")
	var firing_start := fire_source.find("float radius = length(p);")
	check(firing_start >= 0, "Original fire warning branch is retained")
	if firing_start >= 0:
		var tail := fire_source.substr(firing_start).strip_edges()
		check(tail.sha256_text() == str(baseline.get("unchanged_fire_shader_tail_sha256", "")), "Firing warning and damage smoke shader code remain exactly unchanged")
	var hud := FileAccess.get_file_as_string("res://scripts/campaign/hud.gd")
	for token in ["READABILITY.marker_frame(", "READABILITY.health_bar(", "READABILITY.label_placement(", "READABILITY.motion_hint_geometry(", "label.baseline", "label.glyph_width", "_ground_label_reservations("]:
		check(token in hud, "HUD draws the same complete geometry measured by the test: " + token)
	var helpers_at := hud.find("func _draw_ground_contacts(")
	var helpers_end: int = hud.find("func key_name(", helpers_at) if helpers_at >= 0 else -1
	check(helpers_at >= 0 and helpers_end > helpers_at, "Readability hook scope is explicit")
	if helpers_at >= 0 and helpers_end > helpers_at:
		var helpers := hud.substr(helpers_at, helpers_end - helpers_at)
		for token in ["take_damage(", "fire_enemy(", "Input.action_press(", "Input.action_release(", ".warning_time =", ".salvo_remaining =", ".health =", ".position =", "Node.new(", "Label.new("]:
			check(token not in helpers, "Presentation helpers do not mutate mechanics or create persistent label nodes: " + token)
	var cockpit := _canonical_shader("res://scripts/ui/cockpit.gd")
	check("play_rect=Rect2(Vector2(0,64*ui_scale),Vector2(size.x,size.y-108*ui_scale))" in cockpit, "Measured bounds match the real compact cockpit gameplay rectangle")
	observations.append({"scope": "strict unchanged mechanics source and shader structural budget", "files": baseline.get("files", {}).size(), "source_normalization": baseline.get("normalization", "")})
	# Set only after the complete source/shader checks. An unexpected runtime
	# abort must propagate through _run instead of leaving a false green report.
	source_safety_completed = true

func _finish() -> void:
	var report := {"checks": checks, "failures": failures, "passed": failures.is_empty(),
		"production_scripts_ready": production_scripts_ready, "reservation_fixture_attempts": reservation_fixture_attempts,
		"reservation_fixtures_completed": reservation_fixtures_completed, "expected_reservation_fixtures": EXPECTED_RESERVATION_FIXTURES,
		"rectangle_suite_completed": rectangle_suite_completed,
		"source_safety_completed": source_safety_completed,
		"scope": "Pure presentation policy, actual font metric rectangles, and reviewed source safety only",
		"limitations": ["No shader compilation proof", "No rendered pixel/occlusion proof", "No frame timing or performance proof", "No human threat recognition proof"],
		"observations": observations}
	var output := FileAccess.open(OUTPUT, FileAccess.WRITE)
	if output != null:
		output.store_string(JSON.stringify(report, "\t"))
		output.close()
	else:
		check(false, "Result file can be written")
	print("Raid readability candidate: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _run() -> void:
	_probe_production_scripts()
	check(production_scripts_ready, "Both production App/HUD constructors must complete before any fixture can claim success")
	if not production_scripts_ready:
		_finish()
		return
	_truth_table()
	_focus()
	_crowd_budget()
	var labels := _catalogue()
	_rectangles(labels)
	_source_safety()
	check(reservation_fixture_attempts == EXPECTED_RESERVATION_FIXTURES, "Every planned reservation fixture was attempted; aborted callers cannot silently skip a viewport")
	check(reservation_fixtures_completed == EXPECTED_RESERVATION_FIXTURES, "Every planned reservation fixture completed all assertions; runtime aborts cannot produce a green report")
	check(rectangle_suite_completed, "The complete bounds suite must finish; completed reservations alone do not prove its remaining assertions ran")
	check(source_safety_completed, "The complete source-safety suite must finish; runtime aborts cannot skip mechanics/shader checks")
	_finish()
