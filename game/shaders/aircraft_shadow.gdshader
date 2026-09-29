shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform float opacity = 0.23;
uniform float softness = 0.06;

float silhouette(vec2 p, vec2 radius) {
	return 1.0 - smoothstep(1.0 - softness, 1.0 + softness * 3.0, length(p / radius));
}

void fragment() {
	vec2 p = UV - 0.5;
	float wings = silhouette(p - vec2(0.0, -0.055), vec2(0.43, 0.085));
	float fuselage = silhouette(p, vec2(0.063, 0.41));
	float tail = silhouette(p - vec2(0.0, 0.30), vec2(0.16, 0.045));
	ALBEDO = vec3(0.004, 0.014, 0.02);
	ALPHA = max(wings, max(fuselage, tail)) * opacity;
}
