extends RefCounted
## Bounded, observational mission recorder. No profile or gameplay mutation.
const INTERVAL := 12.0
const MAX_BINS := 256
const MAX_EVENTS := 96
const METRICS := ["score","kills","damage","grazes"]
const EVENT_KINDS := ["hit","death","bomb","strike","boss"]
var elapsed := 0.0
var bins: Array[Dictionary] = []
var events: Array[Dictionary] = []
var dropped_events := 0
var totals := {"score":0,"kills":0,"damage":0,"grazes":0}

func capture(seconds: float, values: Dictionary) -> void:
	if not is_finite(seconds) or seconds<elapsed or seconds<0: return
	elapsed = seconds
	for key in METRICS:
		var value: Variant = values.get(key,totals[key])
		if (value is int or value is float) and is_finite(float(value)):
			totals[key] = maxi(int(totals[key]),maxi(0,int(value)))
	var row := totals.duplicate()
	row.seconds = elapsed
	var index := mini(MAX_BINS-1,int(floor(elapsed/INTERVAL)))
	if bins.is_empty() or int(bins.back().bin)<index:
		row.bin = index
		bins.append(row)
	else:
		row.bin = int(bins.back().bin)
		bins[bins.size()-1] = row

func mark(seconds: float, kind: String) -> void:
	if kind not in EVENT_KINDS or not is_finite(seconds) or seconds<0: return
	if events.size()>=MAX_EVENTS:
		dropped_events += 1
		return
	events.append({"seconds":seconds,"kind":kind})

func snapshot() -> Dictionary:
	var samples: Array[Dictionary] = [{"seconds":0.0,"score":0,"kills":0,"damage":0,"grazes":0}]
	for row in bins:
		var copy := row.duplicate()
		copy.erase("bin")
		if float(copy.seconds)>0 or copy.score>0 or copy.kills>0 or copy.damage>0 or copy.grazes>0:
			samples.append(copy)
	return {"version":1,"interval":INTERVAL,"elapsed":elapsed,"samples":samples,"events":events.duplicate(true),"totals":totals.duplicate(),"dropped_events":dropped_events}
