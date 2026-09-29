shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform sampler2D carrier_texture : source_color, filter_linear_mipmap, repeat_disable;

void fragment() {
	vec4 ship = texture(carrier_texture, UV);
	ALBEDO = ship.rgb * 0.94;
	ALPHA = smoothstep(0.02, 0.98, ship.a);
}
