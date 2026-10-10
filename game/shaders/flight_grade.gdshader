shader_type canvas_item;
render_mode unshaded;
// A single pass on the flight viewport. HUD is rendered afterwards and remains
// untouched; no blur, chromatic aberration, grain or temporal ghosting of bullets.
uniform vec3 shadow_tint = vec3(0.965,1.0,1.025);
uniform vec3 light_tint = vec3(1.03,1.01,0.97);
uniform float contrast = 1.035;
uniform float saturation = 0.97;
uniform float vignette = 0.105;

void fragment() {
	vec4 source = texture(TEXTURE,UV);
	float luma = dot(source.rgb,vec3(.2126,.7152,.0722));
	vec3 color = mix(vec3(luma),source.rgb,saturation);
	color *= mix(shadow_tint,light_tint,smoothstep(.10,.88,luma));
	color = (color-.35)*contrast+.35;
	vec2 p = (UV-.5)*2.0;
	float edge = smoothstep(.32,1.5,dot(p,p));
	color *= 1.0-vignette*edge;
	// Very bright player fire and hostile cores retain their original intensity.
	color = mix(color,source.rgb,smoothstep(.70,.96,max(source.r,max(source.g,source.b)))*.65);
	COLOR = vec4(clamp(color,vec3(0.0),vec3(1.0)),source.a);
}
