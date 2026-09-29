shader_type canvas_item;
render_mode unshaded;
float hash(vec2 p) {return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
void fragment() {
	vec4 ink = COLOR;
	float grain = hash(floor(FRAGCOORD.xy));
	float fleck = hash(floor(FRAGCOORD.xy*0.35));
	ink.a *= (grain > 0.91 && fleck > 0.70) ? 0.08 : 1.0;
	ink.rgb *= 0.88 + grain*0.12;
	COLOR = ink;
}
