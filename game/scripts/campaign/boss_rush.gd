extends RefCounted
## An isolated, single-credit route. A result can only be claimed once per duel.
const ROUTE := [4,8,12,16,20,24,28,32]
var aircraft := 0
var cursor := 0
var score := 0
var lives := 3
var seconds := 0.0
var grazes := 0
var cleared := 0
var active := false
var stage_open := false
var last_won := false

func begin(selected_aircraft: int) -> void:
	aircraft = clampi(selected_aircraft,0,2)
	cursor = 0
	score = 0
	lives = 3
	seconds = 0
	grazes = 0
	cleared = 0
	active = true
	stage_open = true
	last_won = false

func mission_id() -> int:
	return ROUTE[cursor]

func accept(report: Dictionary) -> bool:
	if not active or not stage_open or int(report.get("mission",-1))!=mission_id(): return false
	stage_open = false
	score = maxi(score,int(report.get("score",score)))
	lives = clampi(int(report.get("lives",0)),0,9)
	seconds += maxf(0,float(report.get("seconds",0)))
	grazes += maxi(0,int(report.get("grazes",0)))
	last_won = bool(report.get("won",false)) and lives>0
	if last_won: cleared += 1
	if not last_won or cleared==ROUTE.size(): active = false
	return true

func advance() -> bool:
	if not active or stage_open or not last_won or cursor>=ROUTE.size()-1: return false
	cursor += 1
	stage_open = true
	last_won = false
	return true

func complete() -> bool:
	return cleared==ROUTE.size()

func record_key() -> String:
	return "rush:%d" % aircraft
