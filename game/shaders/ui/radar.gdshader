shader_type canvas_item;
render_mode unshaded;
uniform float sweep = 0.0;
uniform sampler2D island_atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 island_data[6];
uniform vec2 island_details[6];
uniform vec2 world_size = vec2(18.75,25.0);
uniform vec2 map_margin = vec2(0.05568445,0.07272727);
void fragment() {
	vec2 p = (UV-0.5)*2.0;
	float r = length(p);
	float angle = atan(p.y,p.x);
	float trail = mod(sweep-angle+6.283185, 6.283185);
	float beam = exp(-trail*5.0)*(1.0-smoothstep(0.94,1.0,r));
	vec2 grid = abs(fract(UV*12.0-0.5)-0.5)/fwidth(UV*12.0);
	float line = 1.0-min(min(grid.x,grid.y),1.0);
	float rings = pow(0.5+0.5*cos(r*3.0*6.283185),70.0)*(1.0-smoothstep(0.98,1.0,r));
	float vignette = max(0.25,1.0-r*0.45);
	vec3 base = vec3(0.012,0.032,0.025)*vignette;
	vec2 map_uv = (UV-map_margin)/(vec2(1.0)-map_margin*2.0);
	float land = 0.0;
	for (int i=0;i<6;i++) {
		vec2 local = (map_uv-island_data[i].xy)*world_size;
		float angle = island_details[i].x;
		local = mat2(vec2(cos(angle),sin(angle)),vec2(-sin(angle),cos(angle)))*local;
		local = local/max(island_data[i].zw,vec2(0.001))+0.5;
		if (local.x>0.0 && local.x<1.0 && local.y>0.0 && local.y<1.0) {
			float variant = island_details[i].y;
			vec2 cell = vec2(mod(variant,2.0),floor(variant/2.0));
			vec4 texel = texture(island_atlas,(cell+clamp(local,vec2(0.003),vec2(0.997)))*0.5);
			float water = smoothstep(0.02,0.16,texel.g-texel.r)*smoothstep(0.015,0.09,texel.b-texel.r);
			land = max(land,texel.a*(1.0-water));
		}
	}
	vec3 chart = vec3(0.27,0.31,0.16)*land*0.65;
	COLOR = vec4(base + chart + vec3(0.13,0.23,0.13)*line*0.30 + vec3(0.12,0.23,0.12)*rings*0.25 + vec3(0.09,0.30,0.12)*beam*0.42, 1.0);
}
