shader_type canvas_item;
render_mode unshaded;
uniform vec2 dimensions = vec2(440.0, 88.0);
void fragment() {
	float scan = 0.013 * (0.5+0.5*sin(UV.y*dimensions.y*3.14159));
	float reflection = pow(max(0.0, 1.0-UV.y*2.8), 4.0)*0.08;
	float edge = 1.0-smoothstep(0.0, 0.055, min(min(UV.x,1.0-UV.x),min(UV.y,1.0-UV.y)));
	COLOR = vec4(vec3(0.72,0.79,0.69), scan+reflection+edge*0.025);
}
