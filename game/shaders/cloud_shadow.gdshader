shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform sampler2D cloud_atlas : filter_linear_mipmap, repeat_disable;
uniform vec2 atlas_cell = vec2(0.0);
uniform float opacity = 0.17;
void fragment() {
	vec2 uv = (atlas_cell+clamp(UV,vec2(.006),vec2(.994)))*.5;
	float density = textureLod(cloud_atlas,uv,4.5).a;
	vec2 edge = min(UV,1.0-UV);
	ALBEDO = vec3(.008,.018,.033);
	ALPHA = density*opacity*smoothstep(.02,.09,min(edge.x,edge.y));
}
