shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform float age = 0.0;
uniform float strength = 1.0;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float line = (1.0-smoothstep(.01,.04,abs(abs(p.y)-.85))) * (1.0-smoothstep(.58,.95,abs(p.x)));
	float wings = (1.0-smoothstep(.02,.065,abs(abs(p.y)+abs(p.x)*1.5-1.44))) * smoothstep(.64,.76,abs(p.x));
	float sweep = exp(-pow((p.x - (age*2.0-1.0))*8.0,2.0));
	ALBEDO = vec3(1.0,.66,.18) * (line+wings)*(.65+sweep*.6);
	ALPHA = strength;
}
