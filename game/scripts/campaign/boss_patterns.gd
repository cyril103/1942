extends RefCounted
## Deterministic attack plans: the warning and the released rounds share one snapshot.
## Counts follow campaign balance; difficulty still scales speed/cadence in Combat.
const MAX_ROUNDS := 18
const MAX_BURST_TIME := .6

static func _round(rounds: Array[Dictionary], at: Vector3, angle: float, speed: float, delay := 0.0, component := -1) -> void:
	if rounds.size() >= MAX_ROUNDS: return
	rounds.append({"origin":at,"direction":Vector3(sin(angle),0,cos(angle)),"speed":speed,"delay":clampf(delay,0,MAX_BURST_TIME),"component":component})

static func _fan(rounds: Array[Dictionary], origin: Vector3, angle: float, count: int, spacing: float, speed: float, stagger := 0.0) -> void:
	for i in range(count):
		_round(rounds,origin,angle+(i-(count-1)*.5)*spacing,speed,i*stagger)

static func _ring(rounds: Array[Dictionary], origin: Vector3, gap: float, speed: float, lost: int) -> void:
	# Twelve spokes minus the two nearest the locked escape direction. The
	# neighbouring spokes are 90 degrees apart, leaving a real forward exit.
	for i in range(1,11):
		if lost>0 and (i==5 or (lost==2 and i==6)): continue
		_round(rounds,origin,(i+.5)*TAU/12.0+gap,speed)

static func _comb(rounds: Array[Dictionary], origin: Vector3, count: int, gap_index: int, width: float, speed: float, stagger := 0.0) -> void:
	for i in range(count+1):
		if i==gap_index: continue
		var x := (float(i)/count-.5)*width
		_round(rounds,origin+Vector3(x,0,0),0,speed,absf(i-gap_index)*stagger)

static func build(kind: String, phase: int, volley: int, origin: Vector3, target: Vector3, sector: int, balance: Dictionary, components: Array[float]) -> Dictionary:
	phase = clampi(phase,0,2)
	var lost := (1 if components[0]<=0 else 0)+(1 if components[1]<=0 else 0)
	var count := maxi(1,mini(3+phase*2,int(balance.boss_fan))-lost)
	var speed := 6.2+sector*.25
	var aim := atan2(target.x-origin.x,maxf(1.0,target.z-origin.z))
	var alternate := 1.0 if volley%2==0 else -1.0
	var ring: bool = phase==2 and volley%3==0 and bool(balance.boss_ring)
	var rounds: Array[Dictionary] = []
	var label := "ÉVENTAIL KESTREL"
	var hint := "DÉCALEZ-VOUS APRÈS LE VERROUILLAGE"
	var warning := .75
	match kind:
		"bomber":
			if ring:
				label = "ROUE BRISÉE"
				hint = "REJOIGNEZ L'OUVERTURE DE L'ANNEAU"
				warning = 1.0
				_ring(rounds,origin,clampf(aim,-.55,.55),speed*.82,lost)
			elif volley%2==0 and phase>0:
				label = "PEIGNE D'ACIER"
				hint = "GLISSEZ ENTRE LES COLONNES"
				for i in range(count):
					_round(rounds,origin+Vector3((i-(count-1)*.5)*.9,0,0),aim*.35,speed*.9)
			else:
				_fan(rounds,origin,aim,count,.16,speed)
		"destroyer":
			label = "BORDÉES KUROGANE"
			hint = "LAISSEZ PASSER LA BORDÉE, PUIS TRAVERSEZ"
			warning = .9
			if volley%2==0:
				label = "CHENAL OUVERT"
				hint = "LE CENTRE DU MOTIF RESTE OUVERT"
				for i in range(count):
					var side := -1.0 if i%2==0 else 1.0
					_round(rounds,origin+Vector3(side*.85,0,1.4),side*(.24+floorf(i/2.0)*.15),speed*.86,floorf(i/2.0)*.08)
			else:
				_fan(rounds,origin+Vector3(alternate*.75,0,1.5),aim,count,.19,speed*.9,.07)
			if phase>0:
				for side_index in range(2):
					if components[side_index]<=0: continue
					var side := -1.0 if side_index==0 else 1.0
					for i in range(mini(2+phase,int(balance.boss_flank))):
						_round(rounds,origin+Vector3(side*.85,0,2),side*(.28+i*.23),speed*.8,.13*side_index+.05*i,side_index)
		"squadron":
			label = "CROISEMENT RAIDEN" if volley%2==0 else "ESCADRE EN CHEVRON"
			hint = "QUITTEZ LE POINT DE CROISEMENT"
			warning = .85
			for i in range(count):
				var wing := float(i%3-1)
				var at := origin+Vector3(wing*2.15,0,-absf(wing)*.85)
				var angle := atan2(target.x-at.x,target.z-at.z) if volley%2==0 else aim+wing*.21+(floorf(i/3.0)-phase*.25)*.11
				_round(rounds,at,angle,speed*(.9+absf(wing)*.06),float(i%3)*.12)
		"fortress":
			label = "FAUX TENRYU"
			hint = "PASSEZ DERRIÈRE LE BALAYAGE"
			warning = .95
			if ring:
				label = "ORBITE TENRYU"
				hint = "L'ANNEAU CONSERVE UNE BRÈCHE"
				_ring(rounds,origin,alternate*.4,speed*.78,lost)
			else:
				for i in range(count):
					var offset := (i-(count-1)*.5)*.2
					_round(rounds,origin+Vector3(alternate*1.25,0,0),aim+offset+alternate*.24,speed*.9,float(i if alternate>0 else count-1-i)*.065)
		"battleship":
			label = "PINCE ONYX" if volley%2==0 else "ARTILLERIE ÉCHELONNÉE"
			hint = "TRAVERSEZ ENTRE LES DEUX BATTERIES"
			warning = 1.0
			for i in range(count):
				var side := -1.0 if i%2==0 else 1.0
				var at := origin+Vector3(side*.8,0,1.8)
				var angle := atan2(target.x+side*2.6-at.x,maxf(2.0,target.z-at.z)) if volley%2==0 else aim+side*(.12+floorf(i/2.0)*.16)
				_round(rounds,at,angle,speed*.88,floorf(i/2.0)*.12)
			if phase>0:
				for side_index in range(2):
					if components[side_index]<=0: continue
					var side := -1.0 if side_index==0 else 1.0
					for i in range(mini(2+phase,int(balance.boss_flank))):
						_round(rounds,origin+Vector3(side*.9,0,2),side*(.48+i*.2),speed*.72,.2+.08*i,side_index)
		"ace":
			label = "DUEL AKAI" if volley%2==0 else "REPRISE ÉCARLATE"
			hint = "CASSER LA VISÉE D'UN PAS LATÉRAL"
			warning = .7
			for i in range(count):
				_round(rounds,origin,aim+alternate*(i-(count-1)*.5)*.085,speed*1.12,i*.065)
			if phase>0:
				for side_index in range(2):
					if components[side_index]<=0: continue
					var side := -1.0 if side_index==0 else 1.0
					_round(rounds,origin+Vector3(side*.7,0,0),aim,speed*1.25,.2,side_index)
		"carrier":
			label = "PONT FRACTURÉ"
			hint = "SUIVEZ LA BRÈCHE ENTRE LES COLONNES"
			warning = .95
			var gap_index := clampi(int(round((target.x-origin.x+4.0)/8.0*count)),0,count)
			_comb(rounds,origin+Vector3(0,0,1.8),count,gap_index,8.0,speed*.84,.05)
			if ring:
				label = "ENVELOPPE SHIRO"
				hint = "L'ANNEAU S'OUVRE VERS VOTRE POSITION"
				rounds.clear()
				_ring(rounds,origin,clampf(aim,-.5,.5),speed*.76,lost)
		"citadel":
			warning = 1.05
			if ring:
				label = "AUBE ROUGE"
				hint = "OUVERTURE DE L'ANNEAU À DROITE" if alternate>0 else "OUVERTURE DE L'ANNEAU À GAUCHE"
				_ring(rounds,origin,alternate*.55,speed*.88,lost)
			elif volley%2==0:
				label = "REMPART DISJOINT"
				hint = "LA PORTE ALTERNE À CHAQUE SALVE"
				# Count actual combs, excluding the rings that replace every sixth volley.
				var gates_so_far := volley/2
				if phase==2 and bool(balance.boss_ring): gates_so_far -= volley/6
				var gate_side := 1 if gates_so_far%2==0 else -1
				_comb(rounds,origin,count,clampi(count/2+gate_side,0,count),10.0,speed*.87,.065)
			else:
				label = "JUGEMENT DAWNBREAKER"
				hint = "DÉCALEZ-VOUS HORS DU DOUBLE ÉVENTAIL"
				for i in range(count):
					var side := -1.0 if i%2==0 else 1.0
					_round(rounds,origin+Vector3(side*1.8,0,-.6),aim+side*(.18+floorf(i/2.0)*.13),speed,.08*(i%3))
	rounds.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return float(a.delay)<float(b.delay))
	return {"label":label,"hint":hint,"warning":warning,"rounds":rounds}
