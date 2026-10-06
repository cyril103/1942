shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform sampler2D cloud_atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform vec2 atlas_cell = vec2(0.0);
uniform vec3 cloud_tint : source_color = vec3(1.0);
uniform float opacity = 0.72;
uniform float phase = 0.0;
uniform float evolution = 0.0;

void fragment() {
	// Two texture taps: baked multiple-scattering light plus a soft density rim.
	// Erosion stays inside the padded cell, so neighboring clouds never leak in.
	vec2 wind = vec2(sin(UV.y*15.0+evolution+phase),cos(UV.x*12.0-evolution*.7+phase));
	vec2 uv = clamp(UV+wind*0.006,vec2(.006),vec2(.994));
	vec2 atlas_uv = (atlas_cell+uv)*.5;
	vec4 vapor = texture(cloud_atlas,atlas_uv);
	float soft_density = textureLod(cloud_atlas,atlas_uv,2.5).a;
	float rim = max(0.0,soft_density-vapor.a);
	vec2 edge = min(UV,1.0-UV);
	float padding = smoothstep(.01,.055,min(edge.x,edge.y));
	ALBEDO = (vapor.rgb+rim*.15)*cloud_tint;
	ALPHA = clamp(vapor.a*opacity*(.97+.03*sin(evolution*.5+phase)),0.0,.84)*padding;
}
