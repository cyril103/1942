extends RefCounted
## PHASE 5 CANDIDATE ONLY. Pure presentation policy, never actor mutation.
## Input rows are already projected, visible live ground contacts.
const MAX_CONTEXT_LABELS := 4
const CATALOG_PERSISTENT_LABEL_BOUND := 4
const FOCUS_HALF_WIDTH := 28.0
const FOCUS_FORWARD_REACH := 450.0
const LABELS := {"fuel": "CARBURANT", "radar": "RADAR", "battery": "DCA", "bunker": "BUNKER", "runway": "HANGAR"}
const PRIORITY_LABELS := {
	"western_radar": "RADAR OUEST", "eastern_radar": "RADAR EST",
	"western_hangar": "HANGAR OUEST", "eastern_hangar": "HANGAR EST",
	"tutorial_mobile": "DCA MOBILE", "western_bastion": "BASTION OUEST",
	"eastern_bastion": "BASTION EST", "command_bunker": "COMMANDEMENT"
}

static func focus_target_id(rows: Array[Dictionary], player_screen: Vector2, enabled: bool, scale: float = 1.0) -> String:
	if not enabled or not player_screen.is_finite():
		return ""
	var u := maxf(.01, scale) if is_finite(scale) else 1.0
	var selected := ""
	var best_score := INF
	for row in rows:
		if not bool(row.get("visible", true)) or not bool(row.get("alive", true)):
			continue
		var point: Vector2 = row.get("screen_position", Vector2.ZERO)
		if not point.is_finite():
			continue
		var forward := player_screen.y - point.y
		var lateral := absf(point.x - player_screen.x)
		if forward < 0 or forward > FOCUS_FORWARD_REACH * u or lateral > FOCUS_HALF_WIDTH * u:
			continue
		var score := lateral * 4.0 + forward * .2
		var id := str(row.get("id", ""))
		if score < best_score or (is_equal_approx(score, best_score) and id < selected):
			best_score = score
			selected = id
	return selected

static func label_for(row: Dictionary) -> String:
	var variant := str(row.get("variant", "battery"))
	var priority := bool(row.get("priority", false))
	var label := str(PRIORITY_LABELS.get(str(row.get("priority_tag", "")), LABELS.get(variant, "CIBLE")))
	if bool(row.get("mobile", false)) and variant == "battery":
		label = "DCA MOBILE"
	elif bool(row.get("rapid_fire", false)) and variant == "battery":
		label = "DCA RAPIDE"
	return label + " · PRIORITÉ" if priority else label

static func select(rows: Array[Dictionary], player_screen: Vector2, focus_enabled: bool, scale: float = 1.0) -> Array[Dictionary]:
	# Persist radars/priorities. Other labels are contextual and limited; all
	# imminent firing frames remain visible even if their text budget is full.
	var focus_id := focus_target_id(rows, player_screen, focus_enabled, scale)
	var result: Array[Dictionary] = []
	var contextual: Array[Dictionary] = []
	for raw in rows:
		if not bool(raw.get("visible", true)) or not bool(raw.get("alive", true)):
			continue
		var point: Vector2 = raw.get("screen_position", Vector2.ZERO)
		if not point.is_finite():
			continue
		var row: Dictionary = raw.duplicate(true)
		var id := str(row.get("id", ""))
		var health := float(row.get("health", 1.0))
		var maximum := float(row.get("max_health", 1.0))
		row.persistent = str(row.get("variant", "")) == "radar" or bool(row.get("priority", false))
		row.fire_warning = float(row.get("warning_time", 0.0)) > 0.0 or int(row.get("salvo_remaining", 0)) > 0
		row.damaged = maximum > 0.0 and health >= 0.0 and health < maximum
		row.focused = not focus_id.is_empty() and id == focus_id
		row.motion_hint = bool(row.get("mobile", false)) and bool(row.get("motion_announced", false))
		row.frame_visible = row.persistent or row.fire_warning or row.damaged or row.focused
		row.health_visible = row.damaged
		row.label_visible = row.persistent
		row.label = label_for(row)
		row.attention_rank = 0 if row.fire_warning else (1 if row.damaged else 2)
		row.attention_distance = point.distance_squared_to(player_screen)
		result.append(row)
		if not row.persistent and row.frame_visible:
			contextual.append(row)
	contextual.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.attention_rank) != int(b.attention_rank):
			return int(a.attention_rank) < int(b.attention_rank)
		if not is_equal_approx(float(a.attention_distance), float(b.attention_distance)):
			return float(a.attention_distance) < float(b.attention_distance)
		return str(a.id) < str(b.id))
	for index in range(mini(MAX_CONTEXT_LABELS, contextual.size())):
		contextual[index].label_visible = true
	return result

static func marker_frame(projected: Rect2, play_rect: Rect2, persistent: bool, scale: float = 1.0) -> Rect2:
	var u := maxf(.01, scale)
	var safe := play_rect.grow(-6.0 * u)
	if safe.size.x <= 0 or safe.size.y <= 0:
		return Rect2()
	var clipped := projected.abs().intersection(safe)
	if clipped.size.x > 0 and clipped.size.y > 0:
		return clipped
	if not persistent:
		return Rect2()
	# A reported priority/radar beyond the edge keeps a bounded edge marker.
	# Its label can be placed inside the play area; no score/command overlap.
	var size := Vector2.ONE * minf(14.0 * u, minf(safe.size.x, safe.size.y))
	var center := projected.get_center()
	var at := Vector2(clampf(center.x - size.x * .5, safe.position.x, safe.end.x - size.x), clampf(center.y - size.y * .5, safe.position.y, safe.end.y - size.y))
	return Rect2(at, size)

static func health_bar(frame: Rect2, play_rect: Rect2, scale: float = 1.0) -> Rect2:
	var u := maxf(.01, scale)
	var safe := play_rect.grow(-6.0 * u)
	var height := minf(3.0 * u, maxf(0, safe.size.y))
	var width := minf(frame.size.x, maxf(0, safe.size.x))
	var y := frame.position.y - 7.0 * u
	if y < safe.position.y:
		y = frame.position.y + 2.0 * u
	return Rect2(Vector2(clampf(frame.position.x, safe.position.x, safe.end.x - width), clampf(y, safe.position.y, safe.end.y - height)), Vector2(width, height))

static func motion_hint_geometry(from: Vector2, to: Vector2, play_rect: Rect2, scale: float = 1.0) -> Dictionary:
	# Pure geometry, shared by drawing and bounds checks. The arrow and the
	# antialiased dashes stay inside the same gameplay rectangle as labels.
	var u := maxf(.01, scale)
	var safe := play_rect.grow(-10 * u)
	var segments: Array[PackedVector2Array] = []
	if safe.size.x <= 0 or safe.size.y <= 0 or not from.is_finite() or not to.is_finite():
		return {"segments": segments, "arrow": PackedVector2Array(), "line_width": 1.4 * u}
	from = Vector2(clampf(from.x, safe.position.x, safe.end.x), clampf(from.y, safe.position.y, safe.end.y))
	to = Vector2(clampf(to.x, safe.position.x, safe.end.x), clampf(to.y, safe.position.y, safe.end.y))
	var delta := to - from
	if delta.length() < 6 * u:
		return {"segments": segments, "arrow": PackedVector2Array(), "line_width": 1.4 * u}
	var direction := delta.normalized()
	var perpendicular := Vector2(-direction.y, direction.x)
	var dashes := mini(8, maxi(1, ceili(delta.length() / maxf(1, 20 * u))))
	for index in range(dashes):
		segments.append(PackedVector2Array([from.lerp(to, float(index) / dashes), from.lerp(to, (float(index) + .55) / dashes)]))
	var arrow := PackedVector2Array([to, to - direction * 7 * u + perpendicular * 3.5 * u, to - direction * 7 * u - perpendicular * 3.5 * u])
	return {"segments": segments, "arrow": arrow, "line_width": 1.4 * u}

static func label_placement(frame: Rect2, value: String, font: Font, play_rect: Rect2, scale: float = 1.0, occupied: Array[Rect2] = []) -> Dictionary:
	# Measure the actual font, including ascent/descent and text_at's 1px shadow.
	# The whole string stays inside play_rect; never clip a priority suffix.
	var u := maxf(.01, scale)
	var safe := play_rect.grow(-6.0 * u)
	var pixels := maxi(12, int(15 * u))
	var glyph_width := font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, pixels).x
	var ascent := font.get_ascent(pixels)
	var descent := font.get_descent(pixels)
	var size := Vector2(ceilf(glyph_width) + 2.0, ceilf(ascent + descent) + 2.0)
	var fits := size.x <= safe.size.x and size.y <= safe.size.y
	if not fits:
		return {"valid": false, "reason": "Label cannot fit the available play area", "text": value, "font_size": pixels}
	var candidates: Array[Vector2] = [
		Vector2(frame.position.x, frame.end.y + 4 * u),
		Vector2(frame.position.x, frame.position.y - size.y - 4 * u),
		Vector2(frame.end.x + 4 * u, frame.get_center().y - size.y * .5),
		Vector2(frame.position.x - size.x - 4 * u, frame.get_center().y - size.y * .5)
	]
	# Additional edge slots preserve required labels if the nearby slots are busy.
	# Prefer the nearest free edge of an actual panel, instead of jumping to
	# the opposite end of the screen when the four local slots are occupied.
	for obstacle in occupied:
		var gap := 4.0 * u
		candidates.append(Vector2(frame.position.x, obstacle.end.y + gap))
		candidates.append(Vector2(frame.position.x, obstacle.position.y - size.y - gap))
		candidates.append(Vector2(obstacle.end.x + gap, frame.get_center().y - size.y * .5))
		candidates.append(Vector2(obstacle.position.x - size.x - gap, frame.get_center().y - size.y * .5))
	for index in range(4):
		candidates.append(Vector2(safe.position.x, safe.position.y + index * (size.y + 4 * u)))
		candidates.append(Vector2(safe.end.x - size.x, safe.position.y + index * (size.y + 4 * u)))
		candidates.append(Vector2(safe.position.x, safe.end.y - size.y - index * (size.y + 4 * u)))
		candidates.append(Vector2(safe.end.x - size.x, safe.end.y - size.y - index * (size.y + 4 * u)))
	var best := Rect2()
	var best_overlaps := 2147483647
	var best_distance := INF
	for requested in candidates:
		var at := Vector2(clampf(requested.x, safe.position.x, safe.end.x - size.x), clampf(requested.y, safe.position.y, safe.end.y - size.y))
		var rect := Rect2(at, size)
		var overlaps := 0
		for other in occupied:
			if rect.grow(2 * u).intersects(other):
				overlaps += 1
		var distance := rect.get_center().distance_squared_to(frame.get_center())
		if overlaps < best_overlaps or (overlaps == best_overlaps and distance < best_distance):
			best = rect
			best_overlaps = overlaps
			best_distance = distance
	return {"valid": true, "text": value, "font_size": pixels, "rect": best, "baseline": best.position + Vector2(1, ascent + 1), "glyph_width": glyph_width, "overlaps": best_overlaps}

static func label_link(frame: Rect2, label: Rect2, play_rect: Rect2, scale: float = 1.0, occupied: Array[Rect2] = []) -> Array[PackedVector2Array]:
	# Solid, unadorned association line: deliberately unlike a mobile route.
	# Remove portions beneath panels/text, including antialiasing clearance.
	var segments: Array[PackedVector2Array] = []
	var u := maxf(.01, scale)
	var safe := play_rect.grow(-3.0 * u)
	if safe.size.x <= 0 or safe.size.y <= 0: return segments
	var target := label.get_center()
	var from := Vector2(clampf(target.x, frame.position.x, frame.end.x), clampf(target.y, frame.position.y, frame.end.y))
	var to := Vector2(clampf(from.x, label.position.x, label.end.x), clampf(from.y, label.position.y, label.end.y))
	from = from.clamp(safe.position, safe.end)
	to = to.clamp(safe.position, safe.end)
	if from.distance_to(to) <= 24.0 * u: return segments
	var delta := to - from
	var intervals: Array[Vector2] = [Vector2(0, 1)]
	for raw in occupied:
		var obstacle := raw.grow(2.0 * u)
		var enter := 0.0
		var leave := 1.0
		var intersects := true
		for axis in range(2):
			if absf(delta[axis]) < .00001:
				if from[axis] < obstacle.position[axis] or from[axis] > obstacle.end[axis]: intersects = false
			else:
				var a := (obstacle.position[axis] - from[axis]) / delta[axis]
				var b := (obstacle.end[axis] - from[axis]) / delta[axis]
				enter = maxf(enter, minf(a, b))
				leave = minf(leave, maxf(a, b))
		if not intersects or enter >= leave: continue
		var remaining: Array[Vector2] = []
		for interval in intervals:
			if leave <= interval.x or enter >= interval.y:
				remaining.append(interval)
			else:
				if enter > interval.x: remaining.append(Vector2(interval.x, enter))
				if leave < interval.y: remaining.append(Vector2(leave, interval.y))
		intervals = remaining
	for interval in intervals:
		if (interval.y - interval.x) * delta.length() > 2.0 * u:
			segments.append(PackedVector2Array([from + delta * interval.x, from + delta * interval.y]))
	return segments
