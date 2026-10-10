shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform float strength = .9;
varying float fade;
void vertex() { fade = INSTANCE_CUSTOM.r; }
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float tail = (1.0-smoothstep(-.6,1.0,p.y))*smoothstep(-1.0,-.5,p.y);
	float edge = exp(-p.x*p.x*13.0)*tail;
	float core = exp(-dot(p-vec2(0.0,-.24),p-vec2(0.0,-.24))*16.0);
	ALBEDO = mix(COLOR.rgb,vec3(1.0,.95,.78),core*.8);
	ALPHA = max(edge,core)*fade*strength;
}
