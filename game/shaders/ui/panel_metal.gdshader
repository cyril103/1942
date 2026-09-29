shader_type canvas_item;
render_mode unshaded;

void fragment() {
	vec3 metal = mix(vec3(0.085,0.085,0.063),texture(TEXTURE, UV).rgb,0.68);
	float light = 0.68 + 0.22 * (1.0-UV.y) + 0.10 * sin(UV.x*3.14159);
	float bevel = smoothstep(0.0, 0.025, min(UV.x, 1.0-UV.x));
	COLOR = vec4(metal * light * mix(0.55, 1.0, bevel), 1.0);
}
