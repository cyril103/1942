shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
varying float fade;
void vertex() { fade = INSTANCE_CUSTOM.r; }
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float edge = exp(-p.x*p.x*9.0) * (1.0-smoothstep(.3,1.0,abs(p.y)));
	ALBEDO = mix(COLOR.rgb,vec3(1.0,.96,.8),exp(-dot(p,p)*12.0)) * 1.2;
	ALPHA = edge*fade;
}
