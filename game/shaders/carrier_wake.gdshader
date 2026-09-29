shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform float wave_phase = 0.0;

void fragment() {
	float x = abs(UV.x - 0.5);
	float width = 0.06 + UV.y * 0.33;
	float edge = exp(-pow((x - width) / 0.027, 2.0));
	float center = exp(-pow(x / (0.07 + UV.y * 0.10), 2.0)) * 0.36;
	float breakup = 0.57 + 0.23 * sin(UV.y * 97.0 - wave_phase * 3.0)
		* sin(UV.x * 131.0 + UV.y * 83.0);
	float fade = smoothstep(0.0, 0.09, UV.y) * (1.0 - smoothstep(0.25, 1.0, UV.y));
	ALBEDO = vec3(0.48, 0.75, 0.78);
	ALPHA = (edge + center) * breakup * fade * 0.21;
}
