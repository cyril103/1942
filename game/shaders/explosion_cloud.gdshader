shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never;
uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform float age = 0.0;
uniform float opacity = 1.0;
uniform float variation = 0.0;

vec4 cell_sample(float frame, vec2 uv) {
	vec2 tile = vec2(mod(frame, 2.0), floor(frame / 2.0));
	// Clamp well inside each cell; no sampling neighbouring smoke sprites.
	return texture(atlas, (tile + clamp(uv, vec2(0.006), vec2(0.994))) * 0.5);
}
void fragment() {
	float t = max(0.0, age);
	float frame = t < 0.17 ? t / 0.17 : (t < 0.75 ? 1.0 + (t - 0.17) / 0.58 : 2.0 + clamp((t - 0.75) / 1.4, 0.0, 1.0));
	float first = floor(frame);
	float blend = smoothstep(0.0, 1.0, fract(frame));
	vec2 drift = vec2(sin(UV.y * 12.0 + t * 1.6 + variation), cos(UV.x * 11.0 - t * 1.2 + variation)) * 0.009 * min(t, 1.0);
	vec4 a = cell_sample(first, UV + drift);
	vec4 b = cell_sample(min(first + 1.0, 3.0), UV - drift);
	float alpha = mix(a.a, b.a, blend);
	vec3 rgb = mix(a.rgb * a.a, b.rgb * b.a, blend) / max(alpha, 0.001);
	// The hot core decays into dark soot; preserve the source's orange fissures.
	float soot = smoothstep(0.7, 2.5, t);
	ALBEDO = rgb * mix(1.12, 0.50, soot);
	ALPHA = alpha * opacity * smoothstep(0.0, 0.035, t) * (1.0 - smoothstep(1.5, 3.3, t));
}
