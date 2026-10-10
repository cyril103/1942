extends RefCounted
## Shared geometry for flight overlays and their ground-contact reservations.
## Presentation only: no actor state, input, timers or score are changed here.
const INTRO_SECONDS := 2.25
const IVORY := Color("f3ead7")
const AMBER := Color("efcd88")
const CYAN := Color("97dce5")
const INK := Color("071720")

static func chain_frame(play: Rect2, scale: float) -> Rect2:
	return Rect2(Vector2(12 * scale, play.position.y + 6 * scale), Vector2(220, 78) * scale)

static func boss_frame(viewport: Vector2, play: Rect2, scale: float) -> Rect2:
	var left := 248 * scale
	var right := viewport.x - 446 * scale
	var width := minf(760 * scale, maxf(180 * scale, right - left))
	var x := clampf((viewport.x - width) * .5, left, maxf(left, right - width))
	return Rect2(Vector2(x, play.position.y + 8 * scale), Vector2(width, 64 * scale))

static func intro_frame(viewport: Vector2, play: Rect2, scale: float) -> Rect2:
	var width := minf(690 * scale, viewport.x - 40 * scale)
	return Rect2(Vector2((viewport.x - width) * .5, play.position.y + 126 * scale), Vector2(width, 112 * scale))

static func fit(value: String, font: Font, pixels: int, width: float) -> String:
	if font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, pixels).x <= width:
		return value
	var result := value
	while not result.is_empty() and font.get_string_size(result + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, pixels).x > width:
		result = result.left(result.length() - 1)
	return result.strip_edges() + "…"
