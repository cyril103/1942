shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform float age = 0.0;
void fragment() {
	float r = length(UV * 2.0 - 1.0);
	float core = exp(-r * r * 12.0) * exp(-age * 32.0);
	float ring_radius = 0.15 + age * 2.1;
	float ring = exp(-pow((r - ring_radius) / 0.045, 2.0)) * 0.12 * (1.0 - smoothstep(0.05, 0.32, age));
	ALBEDO = vec3(1.0, 0.65, 0.27);
	ALPHA = (core + ring) * (1.0 - smoothstep(0.9, 1.0, r));
}
