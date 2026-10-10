// Shared open sea / coast shading guarantees identical waves at the join.
uniform sampler2D ocean_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform vec3 ocean_tint : source_color = vec3(1.0);
uniform float sea_desaturation = 0.0;
uniform float tile_size = 14.0;
uniform float scroll_a = 0.0;
uniform float scroll_b = 0.0;
uniform float wave_phase = 0.0;

vec3 seamless_water(vec2 uv) {
	vec2 p = fract(uv);
	vec2 q = fract(p + 0.5);
	vec2 blend = smoothstep(vec2(0.30), vec2(0.50), abs(p - 0.5));
	vec3 a = texture(ocean_texture, p).rgb;
	vec3 b = texture(ocean_texture, vec2(q.x, p.y)).rgb;
	vec3 c = texture(ocean_texture, vec2(p.x, q.y)).rgb;
	vec3 d = texture(ocean_texture, q).rgb;
	return mix(mix(a, b, blend.x), mix(c, d, blend.x), blend.y);
}

vec3 ocean_surface(vec2 world_xz) {
	vec2 uv_a = world_xz / tile_size - vec2(0.0, scroll_a);
	vec2 uv_b = world_xz / (tile_size * 1.6) - vec2(0.0, scroll_b) + vec2(0.37, 0.81);
	vec2 ripple = vec2(
		sin(uv_a.y * 18.8495559 + wave_phase),
		cos(uv_a.x * 12.5663706 - wave_phase * 2.0)
	) * 0.008;
	vec3 water_a = seamless_water(uv_a + ripple);
	vec3 water_b = seamless_water(uv_b - ripple * 0.65);
	vec3 water = mix(water_a, water_b, 0.30);
	float glint = sin(uv_a.x * 31.4159265 + uv_a.y * 25.1327412 + wave_phase * 2.0);
	water *= 1.0 + 0.025 * glint;
	vec3 result = mix(vec3(0.003, 0.026, 0.044), water, 0.64);
	result = mix(result,vec3(dot(result,vec3(0.299,0.587,0.114))),sea_desaturation);
	// Crossing swells create small glints; the coast uses this same function.
	float swell_a = sin(world_xz.x*2.1+world_xz.y*1.7-wave_phase*1.6);
	float swell_b = sin(world_xz.x*-3.2+world_xz.y*2.3+wave_phase*1.1);
	float crest = pow(max(0.0,swell_a*.55+swell_b*.45),24.0);
	result += vec3(.13,.28,.32)*crest*.075*(1.0-sea_desaturation*.7);
	return result * ocean_tint;
}
