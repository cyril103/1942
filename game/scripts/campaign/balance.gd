extends RefCounted
## Mission-based pressure, independent of purchased upgrades and saved progress.
static func settings(mission_id: int, difficulty: int) -> Dictionary:
	var progress := clampf(float(mission_id-1)/19.0,0.0,1.0)
	var mode := clampi(difficulty,0,2)
	return {
		"salvos": clampf(lerpf(1.0,3.0,progress)+[-0.2,0.0,0.2][mode],1.0,3.0),
		"interval": lerpf(1.9,1.0,progress)*[1.12,1.0,0.92][mode],
		"speed": lerpf(0.82,1.0,progress),
		"boss_fan": 3 if mission_id <= 4 else (5 if mission_id <= 8 else 7),
		"boss_ring": mission_id >= 9,
		"boss_flank": 1 if mission_id <= 4 else (2 if mission_id <= 8 else 4)
	}
