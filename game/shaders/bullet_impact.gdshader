shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform float intensity = 1.0;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float core = exp(-r * r * 35.0);
	float rays = exp(-min(abs(p.x), abs(p.y)) * 55.0) * pow(max(0.0, 1.0 - r), 2.0);
	ALBEDO = mix(vec3(1.0, 0.35, 0.04), vec3(1.0, 0.97, 0.75), core);
	ALPHA = clamp(core + rays, 0.0, 1.0) * intensity;
}
