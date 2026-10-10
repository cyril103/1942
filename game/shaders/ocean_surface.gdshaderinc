// Shared open sea / coast shading guarantees identical waves at the join.
uniform sampler2D ocean_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform vec3 ocean_tint : source_color = vec3(1.0);
uniform float sea_desaturation = 0.0;
uniform float tile_size = 14.0;
uniform float scroll_a = 0.0;
uniform float scroll_b = 0.0;
uniform float wave_phase = 0.0;
uniform vec3 reflection_tint : source_color = vec3(0.48, 0.67, 0.72);

float coast_hash(vec2 p) {
	p = fract(p * vec2(123.34,456.21));
	p += dot(p,p+45.32);
	return fract(p.x*p.y);
}

float coast_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f*f*(3.0-2.0*f);
	return mix(mix(coast_hash(i),coast_hash(i+vec2(1.0,0.0)),f.x),mix(coast_hash(i+vec2(0.0,1.0)),coast_hash(i+vec2(1.0)),f.x),f.y);
}

// Shared island/raid surf. Signed distance is in metres: positive on water,
// zero at the shoreline, negative on land. X is foam opacity, Y is undertow.
// Three fronts travel toward shore per wrapped cycle, leaving broken foam
// behind them. Circular drift makes every noise sample continuous at TAU.
vec2 shoreline_surf(vec2 local_metres, float signed_distance_metres, float phase_seed) {
	vec2 p = local_metres + vec2(phase_seed*2.7,phase_seed*.8);
	// Rotate the noise grids away from one another. Their lattice must not
	// produce square holes aligned with the signed-distance atlas texels.
	vec2 q = vec2(p.x*.8-p.y*.6,p.x*.6+p.y*.8);
	vec2 r = vec2(p.x*.38+p.y*.925,-p.x*.925+p.y*.38);
	vec2 drift = vec2(sin(wave_phase),cos(wave_phase))*.19;
	float coast_breaks = coast_noise(q*1.15);
	float lace = coast_noise(r*12.0+drift);
	float weather = coast_noise(p*3.7+vec2(coast_breaks*.3)-drift*.7);
	float shore = signed_distance_metres + (coast_breaks-.5)*.09;
	float reach = smoothstep(.015,.14,shore)*(1.0-smoothstep(.52,.95,shore));
	float travel = shore*8.4 + wave_phase*3.0 + phase_seed + coast_breaks*1.15;
	float front = pow(max(0.0,sin(travel)),mix(2.3,4.2,weather));
	float residue = pow(max(0.0,sin(travel-.72)),2.0);
	// Fine bubbles soften each patch; complete gaps belong to the larger masks
	// below, so small details never punch coarse, black squares into the wash.
	float porous = mix(.18,1.0,smoothstep(.18,.83,lace));
	// Both masks really reach zero. This removes entire stretches of crest,
	// rather than leaving a dim but continuous cartographic/selection outline.
	float broken = smoothstep(.36,.67,coast_breaks)*smoothstep(.22,.58,weather);
	float foam = (front*.87+residue*.20)*broken*porous*reach;
	// A thin, intermittent wash makes contact with beaches without drawing a
	// permanent white contour around every island.
	float contact = (1.0-smoothstep(.025,.16,abs(shore)))*porous*broken;
	foam += contact*.24*smoothstep(-.2,.9,sin(wave_phase*3.0+phase_seed+coast_breaks*2.0));
	float undertow = pow(max(0.0,sin(travel+.65)),4.0)*reach;
	return vec2(clamp(foam,0.0,.85),undertow);
}

vec3 seamless_water(vec2 uv) {
	vec2 p = fract(uv);
	vec2 q = fract(p + 0.5);
	vec2 blend = smoothstep(vec2(0.30), vec2(0.50), abs(p - 0.5));
	// The original photograph supplies restrained microdetail instead of
	// hundreds of equally bright crests competing with hostile projectiles.
	vec3 a = textureLod(ocean_texture, p, 2.0).rgb;
	vec3 b = textureLod(ocean_texture, vec2(q.x, p.y), 2.0).rgb;
	vec3 c = textureLod(ocean_texture, vec2(p.x, q.y), 2.0).rgb;
	vec3 d = textureLod(ocean_texture, q, 2.0).rgb;
	return mix(mix(a, b, blend.x), mix(c, d, blend.x), blend.y);
}

vec3 ocean_surface(vec2 world_xz) {
	vec2 uv_a = world_xz / tile_size - vec2(0.0, scroll_a);
	vec2 uv_b = world_xz / (tile_size * 1.6) - vec2(0.0, scroll_b) + vec2(0.37, 0.81);
	// All phase multipliers are integral, so bounded scrolling phases can wrap
	// after hours of play without a jump in the water or its coastal continuation.
	float a = (uv_a.x * 1.1 + uv_a.y * 2.0) * 6.2831853 - wave_phase;
	float b = (-uv_b.x * 2.15 + uv_b.y) * 6.2831853 + wave_phase * 2.0;
	float c = (uv_a.x * 4.0 + uv_a.y * 3.0) * 6.2831853 + wave_phase;
	float cross_ripple = (uv_b.x*3.0+uv_b.y*5.0)*6.2831853-wave_phase*2.0;
	// Cross swells bend the broad ribbons instead of forming a regular grid.
	a += sin(b)*.21;
	b += sin(c)*.13;
	vec2 drift = vec2(sin(a), cos(b)) * .012;
	vec3 texture_detail = seamless_water(uv_a + drift);
	float swell = sin(a) * .57 + sin(b) * .28 + sin(c) * .15;
	vec3 depth = mix(vec3(.005, .030, .049), vec3(.013, .063, .079), swell * .5 + .5);
	vec3 water = depth + texture_detail * .15;
	// Broad anisotropic ribbons suggest a sunlit surface; no high-frequency
	// white sparkles, screen-space reflections, depth reads or extra render pass.
	vec3 normal = normalize(vec3(-cos(a)*.16+cos(b)*.07+cos(cross_ripple)*.017,1.0,-cos(a)*.11-cos(b)*.12-cos(c)*.035));
	vec3 half_light = normalize(vec3(-.13,1.0,-.095));
	float reflection = pow(max(dot(normal,half_light),0.0),100.0);
	reflection *= .3 + .7 * smoothstep(-.35,.8,sin(a));
	water += reflection_tint * reflection * .045;
	float fine_reflection = pow(max(dot(normal,half_light),0.0),190.0)*smoothstep(.3,.94,sin(c));
	water += reflection_tint*fine_reflection*.009;
	water = mix(water,vec3(dot(water,vec3(.299,.587,.114))),sea_desaturation*.7);
	return water * ocean_tint * 1.35;
}
