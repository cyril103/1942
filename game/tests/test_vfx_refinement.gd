extends SceneTree
## Regression guard for fixed VFX budgets, accessibility and pooled expiry.
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: _run.call_deferred()
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message); push_error(message)
func freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children(): freeze(child)
func silence(node: Node) -> void:
	if node is AudioStreamPlayer or node is AudioStreamPlayer3D: node.stop()
	for child in node.get_children(): silence(child)
func _run() -> void:
	var app: Node = load("res://scenes/campaign.tscn").instantiate()
	app.testing = true
	app.profile.path = "user://vfx-refinement-fixture.json"
	root.add_child(app)
	app.profile.reset()
	app.profile.data.settings.fullscreen = false
	app._launch(1)
	app.cockpit.flight.get_node("Departure").finish_immediately()
	freeze(app)
	var d: Node = app.director
	var c: Node = d.combat
	var count := c.get_child_count()
	for i in range(128): c._explode(Vector3.ZERO,1,false)
	check(c.effects.size()==c.EFFECT_CAPACITY and c.get_child_count()==count,"Dense explosions never grow the actor tree")
	for effect in c.effects:
		check(effect.get_child_count()==28,"Each explosion retains its 28 reusable meshes")
	var effect: Node = c.effects[0]
	d.profile.data.settings.flashes = true
	effect.trigger(Vector3.ZERO,.3)
	effect.advance(.2)
	var full_flash: float = effect.flash.material_override.get_shader_parameter("strength")
	check(effect.clouds.all(func(cloud): return cloud.visible),"Full explosion reveals all five rising lobes")
	var coordinates := {}
	for cloud in effect.clouds: coordinates[str(cloud.position)] = true
	check(coordinates.size()==5,"Explosion smoke has five distinct spatial lobes")
	d.profile.data.settings.flashes = false
	effect.trigger(Vector3.ZERO,.3)
	effect.advance(.2)
	check(effect.reduced_flash and float(effect.flash.material_override.get_shader_parameter("strength"))<full_flash*.4,"Reduced flash setting suppresses local detonation brightness")
	check(effect.clouds.all(func(cloud): return cloud.visible),"Reduced flashes preserve readable smoke and destruction feedback")
	effect.advance(.8)
	check(effect.visible and not effect.flash.visible,"Smoke remains after the brief ignition flash")
	effect.advance(.5)
	check(not effect.visible,"Smoke expires within the existing explosion lifetime")
	var details: Node = d.details
	var detail_nodes := details.get_child_count()
	for i in range(64):
		details.hit_cooldown = 0
		details.impact(Vector3.ZERO,i%2==0)
		details.burst(Vector3.ZERO)
	check(details.get_child_count()==detail_nodes and details.spark_lives.size()==96 and details.lifetimes.size()==64,"Impacts and fragments remain bounded under overload")
	details.reduced_flash = true
	details._physics_process(.02)
	check(float(details.spark_material.get_shader_parameter("strength"))<.5,"Reduced flashes also apply to pooled hit sparks")
	details.enabled = false
	details._physics_process(2)
	check(not details.visible and details.spark_lives.count(0.0)==96 and details.lifetimes.count(0.0)==64,"Hidden quality effects drain their pools instead of leaving stale particles")
	var cloud_shader := FileAccess.get_file_as_string("res://shaders/cumulus.gdshader")
	check(cloud_shader.count("texture(")+cloud_shader.count("textureLod(")==2,"Cloud refinement retains the two-sample shader budget")
	check(c.score==0 and d.player.health==d.player.max_health,"Visual fixtures never change health or score")
	silence(app)
	await create_timer(.25).timeout
	app._show_main()
	silence(app)
	await create_timer(.25).timeout
	app.queue_free()
	await create_timer(.25).timeout
	print("VFX REFINEMENT: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
