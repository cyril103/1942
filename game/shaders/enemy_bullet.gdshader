shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float core = exp(-r * r * 25.0);
	ALBEDO = mix(vec3(1.0, 0.08, 0.14), vec3(1.0, 0.9, 0.68), core);
	ALPHA = exp(-r * r * 5.0) * (1.0 - smoothstep(0.7, 1.0, r));
}
