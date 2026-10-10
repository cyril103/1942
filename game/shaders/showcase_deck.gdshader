shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

varying vec3 local_position;
void vertex() { local_position = VERTEX; }
void fragment() {
	vec2 p = local_position.xz;
	vec2 edge = abs(fract(p / vec2(2.4, 4.8)) - 0.5);
	float seam = smoothstep(0.493, 0.499, max(edge.x, edge.y));
	float grain = sin(p.x*4.0+sin(p.y*3.1))*.03;
	vec3 steel = mix(vec3(0.011,0.022,0.028), vec3(0.008,0.014,0.021), seam);
	steel *= 1.0 + grain;
	float stripe = (1.0 - smoothstep(0.025,0.055,abs(abs(p.x)-4.6))) * (1.0-smoothstep(7.5,8.0,abs(p.y)));
	float hatch = step(0.42,fract(p.y*0.72+p.x*0.72));
	float margin = smoothstep(4.95,5.0,abs(p.x))*(1.0-smoothstep(5.35,5.4,abs(p.x)));
	ALBEDO = mix(steel,vec3(0.65,0.48,0.20),max(stripe,margin*hatch)*0.72);
	METALLIC = 0.16;
	SPECULAR = 0.25;
	ROUGHNESS = 0.73 + seam * 0.2;
}
