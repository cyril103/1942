extends SceneTree
## Flight HUD integration: finite overlays, safe geometry and no gameplay mutation.
const PRESENTATION := preload("res://scripts/campaign/hud_presentation.gd")
const FONT := preload("res://assets/ui/fonts/BarlowCondensed-Medium.ttf")
var failures: Array[String] = []
var checks := 0

func _initialize() -> void: _run.call_deferred()
func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message); push_error(message)
func freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children(): freeze(child)
func silence(node: Node) -> void:
	if node is AudioStreamPlayer or node is AudioStreamPlayer3D: node.stop()
	for child in node.get_children(): silence(child)

func _run() -> void:
	for viewport in [Vector2(1280,720),Vector2(1920,1080),Vector2(1280,1024),Vector2(2560,1080)]:
		var u: float = viewport.y/1080.0
		var play := Rect2(Vector2(0,64*u),Vector2(viewport.x,viewport.y-108*u))
		var chain := PRESENTATION.chain_frame(play,u)
		var boss := PRESENTATION.boss_frame(viewport,play,u)
		var intro := PRESENTATION.intro_frame(viewport,play,u)
		var objective := Rect2(viewport.x-430*u,play.position.y+6*u,410*u,60*u)
		check(play.encloses(chain) and play.encloses(boss) and play.encloses(intro),"All presentation panels stay inside flight at "+str(viewport))
		check(not boss.intersects(chain) and not boss.intersects(objective),"Boss status avoids combo and objectives at "+str(viewport))
		check(intro.end.y<play.position.y+play.size.y*.4,"Boss introduction leaves lower flight area clear at "+str(viewport))
		for caption in ["ÉVENTAIL CROISÉ  /  PASSEZ ENTRE LES SALVES","FRÔLEMENT  +12  / CHARGE +","DERNIÈRE OFFENSIVE / CHERCHEZ LE COULOIR OUVERT"]:
			var pixels := maxi(12,int(17*u))
			var width: float = boss.size.x-20*u
			var fitted := PRESENTATION.fit(caption,FONT,pixels,width)
			check(FONT.get_string_size(fitted,HORIZONTAL_ALIGNMENT_LEFT,-1,pixels).x<=width,"Actual font fits caption at "+str(viewport))
	var app: Node = load("res://scenes/campaign.tscn").instantiate()
	app.testing = true
	app.profile.path = "user://hud-presentation-fixture.json"
	root.add_child(app)
	app.profile.reset()
	app.profile.data.settings.fullscreen = false
	app._launch(1)
	app.cockpit.flight.get_node("Departure").finish_immediately()
	freeze(app)
	var director: Node = app.director
	director._spawn_boss("bomber")
	var hud: Control = app.cockpit.get_node("CampaignHUD")
	hud._process(.016)
	check(hud.boss_intro_time>2,"New boss starts its finite introduction")
	var health: float = director.boss.health
	var age: float = director.boss.age
	var score: int = director.combat.score
	var charge: float = director.charge
	var controls: bool = director.player.controls_enabled
	for i in range(180): hud._process(1.0/60.0)
	check(hud.boss_intro_time==0,"Boss introduction expires without advancing the encounter")
	check(director.boss.age==age and director.boss.health==health,"HUD never changes boss timing or health")
	check(director.combat.score==score and director.charge==charge,"HUD never awards points or charge")
	check(director.player.controls_enabled==controls,"Introduction never blocks player controls")
	hud._process(.016)
	check(hud.boss_intro_time==0,"Same encounter cannot restart the introduction")
	director.profile.data.settings.flashes = false
	director.profile.data.settings.shake = false
	director.mastery.multiplier = 3
	hud._process(.016)
	check(hud.last_multiplier==3,"Reduced effects still reports the current multiplier")
	check(hud._boss_alert_feedback(),"Arrival uses one boss announcement instead of two competing panels")
	silence(app)
	# Audio playback releases asynchronously even when the actor tree is frozen.
	# Let the mixer relinquish streams before destroying either flight or menu.
	await create_timer(.25).timeout
	app._show_main()
	await process_frame
	silence(app)
	await create_timer(.25).timeout
	app.queue_free()
	await process_frame
	await create_timer(.25).timeout
	print("HUD PRESENTATION: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
