shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform sampler2D rock_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform bool textured = false;
uniform bool snowy = false;
varying vec3 stone_position;
void vertex() { stone_position = VERTEX; }
void fragment() {
	vec2 p = stone_position.xz;
	float grain = fract(sin(dot(floor(p*70.0),vec2(12.9898,78.233)))*43758.5453);
	grain = mix(grain,.5,smoothstep(.35,1.0,max(fwidth(p.x),fwidth(p.y))*70.0));
	vec3 stone = textured ? texture(rock_texture,p*1.35).rgb : vec3(.18,.19,.145);
	float strata = .86+.14*sin(p.x*17.0+p.y*12.0+stone_position.y*9.0);
	ALBEDO = stone * strata * (.84+grain*.16) * (snowy ? .46 : .30);
	ROUGHNESS = .97;
	SPECULAR = .08;
}
