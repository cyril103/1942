extends "res://scripts/campaign/enemy_naval.gd"
## Friendly escort uses the same ocean-safe navigation as the carrier.
signal rescued
signal lost
var remaining := 32.0
var protection := 0.0

func _ready() -> void:
	super._ready()
	collision_layer = 4
	health = 6
	var marker := MeshInstance3D.new()
	marker.mesh = TorusMesh.new()
	marker.mesh.inner_radius = .55
	marker.mesh.outer_radius = .60
	marker.mesh.rings = 12
	marker.mesh.ring_segments = 16
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(.2,.8,.7)
	marker.material_override = mat
	marker.position.y = -.9
	add_child(marker)

func advance(delta: float, combat: Node) -> void:
	if not alive: return
	age += delta
	remaining = maxf(0,remaining-delta)
	protection = maxf(0,protection-delta)
	position.z -= delta*.16
	combat.navigate_naval(self)
	visual.rotation.z = sin(age)*.015
	hit_time = maxf(0,hit_time-delta)
	hit_material.set_shader_parameter("strength",hit_time/.08)
	if remaining<=0:
		rescued.emit()
		retire()

func take_damage(amount: int) -> void:
	if not alive or amount<=0 or protection>0: return
	health = maxi(0,health-amount)
	protection = .6
	hit_time = .08
	if health==0:
		lost.emit()
		retire()
