shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
#include "res://shaders/ocean_surface.gdshaderinc"

// Opaque coastal geometry writes depth and receives ordinary light/shadows.
// Local coordinates keep all paint and road markings attached to the land.
uniform vec2 field_size = vec2(48.0, 120.0);
uniform float seed_phase = 0.0;
uniform vec3 grass_color : source_color = vec3(0.18, 0.29, 0.105);
uniform vec3 meadow_color : source_color = vec3(0.38, 0.38, 0.17);
uniform vec3 sand_color : source_color = vec3(0.73, 0.67, 0.46);
uniform vec3 rock_color : source_color = vec3(0.35, 0.37, 0.30);
uniform float snow_cover : hint_range(0.0, 1.0) = 0.0;
uniform sampler2D ground_detail : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D landscape_texture : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform bool use_ground_detail = false;
uniform float pigment_exponent = 1.0;
uniform float landscape_gain = 0.38;
// Only the active non-tropical material is loaded by terrain.
// 0=tropical original, 1=basalt, 2=arctic; no jungle recolouring in 1/2.
uniform int biome_material = 0;
uniform sampler2D biome_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float biome_tile_metres = 4.0;
uniform float biome_secondary_strength : hint_range(0.0, 0.3) = 0.2;
uniform bool use_shared_layout = false;
// The same opaque shader shades the optional authored road/strip meshes.
// Their UV2 carries local metre coordinates and float CUSTOM0.xy extents.
uniform int infrastructure_layer = 0;
varying vec2 infrastructure_uv;
varying vec2 infrastructure_extent;
varying vec3 local_position;
varying float coast_depth;
varying vec2 world_xz;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0)), f.x), f.y);
}

float rectangle(vec2 p, vec2 half_extent, float softness) {
	vec2 edge = abs(p) - half_extent;
	return 1.0 - smoothstep(-softness, softness, max(edge.x, edge.y));
}

void vertex() {
	local_position = VERTEX;
	coast_depth = COLOR.r;
	world_xz = (MODEL_MATRIX * vec4(VERTEX,1.0)).xz;
	infrastructure_uv = UV2;
	infrastructure_extent = CUSTOM0.xy;
}

void fragment() {
	vec2 p = local_position.xz;
	float broad = noise(p * 0.105 + vec2(seed_phase));
	float patches = noise(p * 0.56 + broad * 2.8);
	float grain = noise(p * 5.5);
	float meadow = smoothstep(0.18, 0.90, broad * 0.72 + patches * 0.28);
	// The authored aerial map carries real composition, vegetation and tracks.
	// Fine material modulation adds detail under the lowered camera without
	// replacing that landscape with an enlarged, repeating camouflage pattern.
	vec3 soil;
	if (biome_material == 0) {
		// Preserve the original tropical macro, pigments and grass microdetail.
		vec2 macro_uv = UV;
		if (infrastructure_layer > 0 || (use_shared_layout && coast_depth >= 0.76)) {
			// Ground and opaque road shoulders must evaluate the SAME inverse
			// projection per pixel. Mixing the ground's interpolated UV with an
			// analytic road UV exposes junction silhouettes on a detailed macro.
			// The narrow coastline retains its original mapping and ocean blend.
			float half_length = field_size.y * .5 - 1.0 - sin(p.x * .20 + seed_phase) * .65 - sin(p.x * .41) * .35;
			float v = p.y / (2.0 * half_length) + .5;
			float nominal_z = (v - .5) * field_size.y;
			float half_width = field_size.x * .5 - 1.05 - sin(nominal_z * .083 + seed_phase) * .68 - sin(nominal_z * .21 - seed_phase) * .32;
			macro_uv = vec2(p.x / (2.0 * half_width) + .5, v);
		}
		vec3 landscape = texture(landscape_texture, macro_uv).rgb;
		soil = landscape;
		vec3 biome_tint = normalize(grass_color + meadow_color) / normalize(vec3(.60,.86,.34));
		soil *= mix(vec3(1.0), biome_tint, 0.13);
		soil *= 0.97 + grain * 0.06;
		if (use_ground_detail) {
			vec3 detail_a = texture(ground_detail, p * 0.10).rgb;
			vec3 detail_b = texture(ground_detail, p.yx * 0.167 + vec2(0.37, 0.61)).rgb;
			vec3 detail = mix(detail_a, detail_b, 0.35);
			float detail_luma = dot(detail, vec3(0.299, 0.587, 0.114));
			soil *= 1.0 + (detail_luma - 0.38) * 0.32;
		}
		float outer = smoothstep(field_size.x * 0.33, field_size.x * 0.43, abs(p.x));
		float exposed_rock = outer * smoothstep(0.72, 0.90, patches) * 0.45;
		soil = mix(soil, rock_color * (0.87 + grain * 0.18), exposed_rock);
	} else {
		// Native albedos represent the actual surface material. The tropical
		// aerial map is not sampled, desaturated or substituted for rock/snow.
		vec2 material_uv = p / max(biome_tile_metres, 0.25);
		vec3 material_a = texture(biome_albedo, material_uv).rgb;
		vec3 material_b = texture(biome_albedo, material_uv * 0.63 + vec2(0.37, 0.61)).rgb;
		soil = mix(material_a, material_b, biome_secondary_strength);
		float macro_variation = noise(p * 0.035 + vec2(seed_phase));
		soil *= 0.94 + macro_variation * 0.12;
		// Flat base colour only: real mesh/light creates relief. No parallax,
		// raymarching, generated normal map or full-ground transparency.
	}
	// Curving supply road and a short secondary airstrip. Dusty shoulders,
	// longitudinal wear, repair patches and sparse markings avoid flat decals.
	if (!use_shared_layout && infrastructure_layer == 0) {
		float road_x = sin(p.y * 0.037 + seed_phase) * field_size.x * 0.12;
		float road_distance = abs(p.x - road_x);
		float road_shoulder = 1.0 - smoothstep(1.03, 1.52 + patches * 0.28, road_distance);
		float road = 1.0 - smoothstep(0.72, 1.02, road_distance);
		float ruts = (1.0 - smoothstep(0.06, 0.16, abs(road_distance - 0.43))) * road;
		// Narrow logistics trail connects the installations; the wider irregular
		// tracks and clearings already belong to the painted macro landscape.
		soil = mix(soil, sand_color * (0.60 + grain * 0.12), road_shoulder * 0.18);
		soil = mix(soil, sand_color * (0.54 + patches * 0.14), road * 0.35);
		soil *= 1.0 - ruts * 0.09;
		vec2 runway_p = p - vec2(field_size.x * 0.18, 0.0);
		float runway_length = min(30.0, field_size.y * 0.22);
		float shoulder = rectangle(runway_p, vec2(2.08, runway_length + 0.65), 0.22);
		float runway = rectangle(runway_p, vec2(1.70, runway_length), 0.055);
		soil = mix(soil, sand_color * (0.64 + patches * 0.07), shoulder * 0.77);
		vec3 tarmac = mix(vec3(0.125, 0.14, 0.13), vec3(0.40, 0.43, 0.43), snow_cover);
		float repairs = smoothstep(0.5, 0.56, noise(p * vec2(1.1, 0.22)));
		tarmac *= 0.78 + grain * 0.15 + repairs * 0.11;
		float slab_joints = 1.0-smoothstep(.017,.037,min(abs(fract(p.x*1.2)-.5),abs(fract(p.y*.7)-.5)));
		tarmac *= 1.0-slab_joints*.23;
		float skid = (1.0-smoothstep(.025,.070,abs(abs(runway_p.x)-.57))) * smoothstep(4.0,runway_length,abs(runway_p.y));
		tarmac *= 1.0-skid*.24;
		soil = mix(soil, tarmac, runway);
		float dash = step(0.47, fract((runway_p.y + 0.5) / 3.5));
		float center_line = (1.0 - smoothstep(0.055, 0.085, abs(runway_p.x))) * dash;
		float side_lines = 1.0 - smoothstep(0.035, 0.075, abs(abs(runway_p.x) - 1.46));
		float thresholds = (1.0 - smoothstep(0.7, 1.4, abs(abs(runway_p.y) - (runway_length - 2.0)))) * step(0.40, fract(runway_p.x * 2.9));
		float paint = max(center_line, max(side_lines * 0.65, thresholds));
		soil = mix(soil, vec3(0.72, 0.72, 0.60), paint * runway * (0.70 + grain * 0.14));
	}
	// Authored geometry has no per-fragment loop over the route catalogue.
	// Its road/strip extents use the same local coordinates as real targets.
	if (infrastructure_layer == 1) {
		float half_width = max(infrastructure_extent.x, 0.1);
		bool cap = infrastructure_extent.y > 0.5;
		float distance_to_axis = cap ? length(infrastructure_uv) : abs(infrastructure_uv.x);
		float worn_edge = (noise(p * 1.8) - 0.5) * 0.10;
		float shoulder = 1.0 - smoothstep(half_width - 0.03, half_width + 0.34, distance_to_axis + worn_edge);
		float road = 1.0 - smoothstep(half_width - 0.10, half_width + 0.05, distance_to_axis + worn_edge);
		float aggregate = noise(p * 11.0);
		float packed = noise(p * vec2(1.4, 0.58) + vec2(seed_phase));
		float weathered = smoothstep(0.38, 0.79, noise(p * 0.63));
		vec3 road_colour = sand_color * (0.50 + grain * 0.12 + aggregate * 0.08);
		road_colour = mix(road_colour, rock_color * (0.72 + aggregate * 0.14), weathered * 0.25);
		if (biome_material == 1) {
			road_colour = mix(soil, vec3(0.22, 0.205, 0.18), 0.36);
		} else if (biome_material == 2) {
			road_colour = mix(soil, vec3(0.34, 0.38, 0.38), 0.48);
		}
		soil = mix(soil, road_colour, shoulder * 0.22);
		soil = mix(soil, road_colour * (0.84 + packed * 0.22), road * (0.53 + packed * 0.12));
		float ruts = 1.0 - smoothstep(0.018, 0.065, abs(abs(infrastructure_uv.x) - half_width * 0.58));
		soil *= 1.0 - ruts * road * (cap ? 0.0 : 0.09);
	} else if (infrastructure_layer == 2) {
		vec2 rp = infrastructure_uv;
		vec2 extent = infrastructure_extent;
		float shoulder = rectangle(rp, extent + vec2(0.34, 0.65), 0.18);
		float runway = rectangle(rp, extent, 0.045);
		soil = mix(soil, sand_color * (0.62 + patches * 0.08), shoulder * 0.65);
		vec3 tarmac = biome_material == 2 ? vec3(0.25, 0.29, 0.30) : vec3(0.125, 0.14, 0.13);
		float repairs = smoothstep(0.5, 0.56, noise(p * vec2(1.1, 0.22)));
		tarmac *= 0.78 + grain * 0.15 + repairs * 0.11;
		float joints = 1.0 - smoothstep(.017, .037, min(abs(fract(rp.x * 1.2) - .5), abs(fract(rp.y * .7) - .5)));
		tarmac *= 1.0 - joints * .23;
		float skid = 1.0 - smoothstep(.025, .070, abs(abs(rp.x) - min(.57, extent.x * .45)));
		tarmac *= 1.0 - skid * smoothstep(2.0, max(extent.y, 2.1), abs(rp.y)) * .24;
		soil = mix(soil, tarmac, runway);
		float dash = step(0.47, fract((rp.y + 0.5) / 3.5));
		float centre = (1.0 - smoothstep(0.045, 0.080, abs(rp.x))) * dash;
		float sidelines = 1.0 - smoothstep(0.025, 0.065, abs(abs(rp.x) - (extent.x - .16)));
		float threshold = (1.0 - smoothstep(.45, 1.1, abs(abs(rp.y) - (extent.y - 1.1)))) * step(.40, fract(rp.x * 2.9));
		float paint = max(centre, max(sidelines * .65, threshold));
		soil = mix(soil, vec3(.72, .72, .60), paint * runway * (.70 + grain * .14));
	}
	// The narrow littoral uses three real material bands. The exposed coral
	// sand must not inherit the previous dark olive underwater pigment.
	float shoreline_depth = coast_depth + (patches - 0.5) * 0.035;
	float beach = 1.0 - smoothstep(0.54, 0.87, shoreline_depth);
	float wet = 1.0 - smoothstep(0.24, 0.49, shoreline_depth);
	vec3 coral_sand = sand_color * vec3(1.05, 1.11, 1.24);
	coral_sand = mix(coral_sand, vec3(0.77, 0.82, 0.83), snow_cover);
	vec3 beach_color = coral_sand * (0.975 + grain * 0.05) * (1.0 - wet * 0.19);
	soil = mix(soil, beach_color, beach);
	// Keep the atlas' natural saturation and microcontrast under direct light.
	// The opaque battlefield receives the real installations' cast shadows.
	vec3 pigment = pow(max(soil, vec3(0.0)), vec3(pigment_exponent));
	ALBEDO = pigment * landscape_gain;
	EMISSION = vec3(0.0);
	SPECULAR = 0.0;
	// Water is already lit in the shared ocean texture. Compose its shallows,
	// swash and wet sand before lighting, instead of adding a shadowed brown
	// slope on top of it. This avoids the old black/gray seam at the waterline.
	// Fully inland, only the ordinary lit material remains and receives shadows.
	if (coast_depth < 0.76) {
		vec3 water = ocean_surface(world_xz);
		vec3 turquoise = mix(vec3(0.03,0.31,0.30),vec3(0.10,0.28,0.34),snow_cover);
		turquoise *= ocean_tint;
		turquoise = mix(turquoise,vec3(dot(turquoise,vec3(.299,.587,.114))),sea_desaturation);
		float shallows = smoothstep(0.16,0.30,shoreline_depth);
		float water_detail = dot(water,vec3(.299,.587,.114));
		vec3 lagoon = mix(water,turquoise*(0.78+water_detail*2.4),shallows * (0.71 + patches * 0.08));
		float caustic = pow(max(0.0,sin(p.x*7.3+p.y*5.8+wave_phase*.7)),12.0);
		lagoon += turquoise * caustic * 0.055 * shallows;
		float dry_land = smoothstep(0.32,0.47,shoreline_depth);
		vec3 coast_color = mix(lagoon,beach_color,dry_land);
		float swash_center = 0.32 + sin(wave_phase*.85+p.x*.95+p.y*.72)*0.022 + noise(p*2.5)*.014;
		float swash = exp(-pow((shoreline_depth-swash_center)/0.014,2.0));
		swash *= smoothstep(0.18,0.66,noise(p*5.7+wave_phase*.08));
		coast_color = mix(coast_color,vec3(.80,.90,.84),swash*.48);
		float lit_land = smoothstep(0.51,0.76,coast_depth);
		ALBEDO *= lit_land;
		EMISSION = coast_color * (1.0-lit_land);
	}
	ROUGHNESS = mix(0.95, 0.79, wet * beach);
	METALLIC = 0.0;
	// COAST_ALPHA_HOOK
}
