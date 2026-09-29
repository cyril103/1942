shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float width = mix(0.12, 0.50, smoothstep(-1.0, 0.65, -p.y));
	float glow = exp(-pow(p.x / width, 2.0) * 2.0);
	float ends = smoothstep(-1.0, -0.7, p.y) * (1.0 - smoothstep(0.6, 1.0, p.y));
	float core = exp(-p.x * p.x * 160.0);
	ALBEDO = mix(vec3(1.0, 0.25, 0.035), vec3(1.0, 0.94, 0.62), core);
	ALPHA = glow * ends;
}
