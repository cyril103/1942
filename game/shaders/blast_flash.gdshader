shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform float age = 0.0;
uniform float strength = .8;
uniform float variation = 0.0;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float angle = atan(p.y,p.x);
	float core = exp(-r*r*16.0)*exp(-age*35.0);
	float edge = .12+age*2.2+.014*sin(angle*7.0+variation);
	float fragments = .55+.45*sin(angle*9.0+variation)*sin(angle*5.0-variation);
	float wake = exp(-pow((r-edge)/.05,2.0))*.095*fragments*(1.0-smoothstep(.04,.27,age));
	ALBEDO = vec3(1.0,.59,.23);
	ALPHA = (core+wake)*strength*(1.0-smoothstep(.82,1.0,r));
}
