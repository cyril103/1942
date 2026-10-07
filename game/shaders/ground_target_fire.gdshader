shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform float age = 0.0;
uniform float strength : hint_range(0.0, 1.0) = 1.0;
uniform int kind = 0;
float hash(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f*f*(3.0-2.0*f);
	return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1)),f.x),f.y);
}
void fragment() {
	vec2 p = UV*2.0-1.0;
	vec3 color;
	float alpha;
	if (kind == 1) {
		float radius = length(p);
		float ring = exp(-pow((radius-mix(0.76,0.28,strength))*22.0,2.0));
		float hot = exp(-radius*radius*30.0) * strength;
		color = mix(vec3(1.0,0.36,0.055),vec3(1.0,0.91,0.61),hot);
		alpha = (ring*0.7+hot)*strength;
	} else {
		float n = noise(p*3.5-vec2(age*0.15,age*0.68));
		float wisps = noise(p*8.0+vec2(-age*0.28,age*0.8));
		float density = 1.0-smoothstep(0.22,0.91,length(p*vec2(1.1,0.82))+(n-0.5)*0.32);
		float ember = exp(-dot(p+vec2(0.12,0.27),p+vec2(0.12,0.27))*12.0);
		ember *= smoothstep(0.23,0.75,n*0.65+wisps*0.35);
		color = mix(vec3(0.065,0.057,0.048)*(0.6+wisps*0.6),vec3(1.0,0.31,0.025),ember*1.3);
		color = mix(color,vec3(1.0,0.8,0.24),ember*ember*0.75);
		alpha = density*(0.38+n*0.40+ember*0.20)*strength;
	}
	ALBEDO = color;
	ALPHA = clamp(alpha,0.0,0.88);
}
