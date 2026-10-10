shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform float intensity = 1.0;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float core = exp(-r * r * 35.0);
	float angle = atan(p.y,p.x);
	float streak = pow(abs(cos(angle*3.0+.4)),18.0);
	float rays = streak*exp(-r*4.0)*smoothstep(.0,.09,r);
	float corona = exp(-r*r*9.0)*.24;
	ALBEDO = mix(vec3(1.0, 0.35, 0.04), vec3(1.0, 0.97, 0.75), core);
	ALPHA = clamp(core + rays + corona, 0.0, 1.0) * intensity;
}
