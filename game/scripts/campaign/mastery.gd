extends RefCounted
## Deterministic scoring, independent from frame rate and campaign persistence.
const RULES := preload("res://scripts/campaign/scoring_rules.gd")
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
	window = RULES.CHAIN_SECONDS
	multiplier = RULES.chain_multiplier(chain)
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
	cue = "OBJECTIF SECONDAIRE  +%d" % RULES.SECONDARY_BONUS
	cue_time = 4
	bonus_score += RULES.SECONDARY_BONUS
	return RULES.SECONDARY_BONUS

func rank(won: bool, deaths: int, damage: int) -> String:
	return RULES.rank(won,deaths,damage,secondary_complete,best_chain)
