extends SceneTree
const RULES := preload("res://scripts/campaign/scoring_rules.gd")
const MASTERY := preload("res://scripts/campaign/mastery.gd")
var checks := 0
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	# Boundary expectations authored as cases, separate from implementation logic.
	var cases := [
		[true,0,0,true,16,true,"S",3],
		[true,0,1,true,16,true,"S",3],
		[true,0,2,true,16,true,"A",3],
		[true,0,3,true,16,true,"A",2],
		[true,0,0,true,15,true,"A",3],
		[true,0,0,false,16,true,"B",3],
		[true,1,0,true,16,true,"B",1],
		[true,2,0,true,16,true,"C",1],
		[true,0,0,true,16,false,"S",2],
		[true,0,0,false,0,false,"B",2],
		[false,0,0,true,16,true,"D",0],
		[false,1,1,false,15,false,"D",0]
	]
	for i in cases.size():
		var c: Array = cases[i]
		var report := {"won":c[0],"deaths":c[1],"damage":c[2],"secondary":c[3],"best_chain":c[4],"objective_met":c[5]}
		check(RULES.rank(c[0],c[1],c[2],c[3],c[4])==c[6],"Rank boundary case %d" % i)
		check(RULES.medal(c[0],c[1],c[2],c[5])==c[7],"Medal boundary case %d" % i)
		var actual_s := RULES.rank_checks("S",report)
		check(actual_s.size()==5,"S explains all five effective criteria")
		check(actual_s.all(func(row): return bool(row.passed))==(c[6]=="S"),"S explanation agrees with the award in case %d" % i)
		check(RULES.medal_checks(3,report).all(func(row): return bool(row.passed))==(c[7]==3),"Gold explanation agrees with the award in case %d" % i)
	var mastery = MASTERY.new()
	for n in range(7): mastery.kill(100)
	check(mastery.multiplier==1,"Seven kills have not reached the next multiplier")
	check(mastery.kill(100)==100 and mastery.multiplier==2,"Eighth kill grants the first multiplier bonus")
	mastery.advance(4.49)
	check(mastery.chain==8,"Chain stays open just before the deadline")
	mastery.advance(.01)
	check(mastery.chain==0 and mastery.multiplier==1,"Chain expires at its deadline")
	for n in range(40): mastery.kill(100)
	check(mastery.multiplier==5,"Multiplier stops at five after a long chain")
	mastery.hit()
	check(mastery.chain==0 and mastery.window==0 and mastery.cue=="CHAÎNE INTERROMPUE","Hit breaks the chain with an explicit cue")
	mastery.secondary_kind = "boss"
	mastery.secondary_target = 1
	check(mastery.objective("radar")==0,"Wrong objective cannot claim a secondary award")
	check(mastery.objective("boss")==2500 and mastery.objective("boss")==0,"Correct secondary award is idempotent")
	mastery.best_chain = 16
	check(mastery.rank(true,0,1)=="S" and mastery.rank(true,0,2)=="A","Actual mastery delegates the impact boundary to the shared rules")
	check(RULES.guide().contains("4.5") or RULES.guide().contains("4,5"),"Guide contains the actual chain duration")
	var report := {"checks":checks,"failures":failures}
	if not "--packaged" in OS.get_cmdline_user_args():
		FileAccess.open("res://tests/scoring-rules-results.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("SCORING RULES TEST ",checks," checks, ",failures.size()," failures: ",failures)
	quit(0 if failures.is_empty() else 1)
