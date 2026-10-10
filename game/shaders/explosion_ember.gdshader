shader_type spatial;
// Warm, tapered combustion fragments; deliberately distinct from cyan gunfire.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform float strength = 1.0;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float head = exp(-dot(p-vec2(0.0,-.3),p-vec2(0.0,-.3))*7.5);
	float taper = (1.0-smoothstep(-.6,1.0,p.y));
	float streak = exp(-p.x*p.x*18.0) * taper * smoothstep(-1.0,-.65,p.y);
	ALBEDO = mix(vec3(1.0,.23,.035),vec3(1.0,.79,.36),head);
	ALPHA = max(streak*.7,head)*strength;
}
