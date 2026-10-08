shader_type spatial;
// PHASE 5 CANDIDATE. Existing 0.28 x 1.05 m tracer quad and additive shape.
// Only green energy increases; alpha, speed, rays, damage and lifetime unchanged.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float ends = smoothstep(-1.0, -.62, p.y) * (1.0 - smoothstep(.65, 1.0, p.y));
	float tail = mix(.23, .66, 1.0 - smoothstep(-.5, 1.0, p.y));
	float halo = exp(-pow(p.x / tail, 2.0) * 2.0);
	float core = 1.0 - smoothstep(.12, .30, abs(p.x));
	ALBEDO = vec3(.08, .68, 1.0) * halo * .8 + vec3(.8, 1.0, 1.0) * core * 1.3;
	ALPHA = ends;
}
