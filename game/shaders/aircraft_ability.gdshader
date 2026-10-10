shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform int mode = 0;
uniform float strength = 0.0;
void fragment() {
	vec2 p = UV*2.0-1.0;
	vec3 tint = vec3(.16,.66,1.0);
	float shape = 0.0;
	if (mode == 2) {
		// Broken armour facets, leaving the silhouette and hitbox readable.
		float hexagon = max(abs(p.x)*.866+abs(p.y)*.5,abs(p.y));
		float rim = exp(-pow((hexagon-.70)*65.0,2.0));
		float segments = smoothstep(.15,.35,abs(sin(atan(p.y,p.x)*3.0)));
		shape = rim*segments;
		tint = vec3(1.0,.70,.24);
	} else {
		float axis = abs(abs(p.x)-(.38+sin(p.y*9.0-TIME*8.0)*.025));
		float runners = exp(-axis*axis*2500.0);
		float tail = smoothstep(-.45,.1,p.y)*(1.0-smoothstep(.45,1.0,p.y));
		float packets = .45+.55*pow(.5+.5*sin(p.y*14.0-TIME*12.0),4.0);
		shape = runners*tail*packets;
		if (mode==1) tint = vec3(.52,.35,1.0);
	}
	ALBEDO = tint*shape;
	ALPHA = strength;
}
