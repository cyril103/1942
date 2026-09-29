shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never;
uniform float progress = 0.0;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float a = atan(p.y, p.x);
	float r = length(p);
	float edge = 0.65 + 0.09 * sin(a * 7.0 + progress * 4.0) + 0.055 * sin(a * 13.0);
	float cloud = 1.0 - smoothstep(edge * 0.5, edge, r);
	float heat = (1.0 - smoothstep(0.05, 0.65, progress)) * (1.0 - smoothstep(0.0, 0.6, r));
	vec3 fire = mix(vec3(0.95, 0.19, 0.025), vec3(1.0, 0.95, 0.65), heat);
	ALBEDO = mix(fire, vec3(0.10, 0.12, 0.14), smoothstep(0.18, 0.7, progress));
	ALPHA = cloud * (1.0 - smoothstep(0.35, 1.0, progress));
}
