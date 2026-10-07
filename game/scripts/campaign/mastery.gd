extends RefCounted
## Deterministic scoring, independent from frame rate and campaign persistence.
var chain := 0
var best_chain := 0
var multiplier := 1
var window := 0.0
var bonus_score := 0
var secondary_progress := 0
var secondary_target := 1
var secondary_kind := "formation"
var secondary_complete := false
var cue := ""
var cue_time := 0.0

func advance(delta: float) -> void:
	window = maxf(0,window-delta)
	cue_time = maxf(0,cue_time-delta)
	if window<=0:
		chain = 0
		multiplier = 1

func kill(base: int) -> int:
	chain += 1
	best_chain = maxi(chain,best_chain)
	window = 4.5
	multiplier = mini(5,1+chain/8)
	var extra := base*(multiplier-1)
	bonus_score += extra
	return extra

func hit() -> void:
	chain = 0
	multiplier = 1
	window = 0
	cue = "CHAÎNE INTERROMPUE"
	cue_time = 1.5

func objective(kind: String) -> int:
	if secondary_complete or kind!=secondary_kind: return 0
	secondary_progress += 1
	if secondary_progress<secondary_target: return 0
	secondary_complete = true
	cue = "OBJECTIF SECONDAIRE  +2500"
	cue_time = 4
	bonus_score += 2500
	return 2500

func rank(won: bool, deaths: int, damage: int) -> String:
	if not won: return "D"
	if deaths==0 and damage<=1 and secondary_complete and best_chain>=16: return "S"
	if deaths==0 and secondary_complete: return "A"
	return "B" if deaths<=1 else "C"
