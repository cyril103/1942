shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

#include "res://shaders/ocean_surface.gdshaderinc"
uniform sampler2D island_atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform vec2 atlas_cell = vec2(0.0);
uniform vec3 land_tint : source_color = vec3(1.0);
uniform float phase_offset = 0.0;
uniform float coast_blend_lod : hint_range(4.0, 7.0) = 6.0;
uniform float shallows_strength : hint_range(0.0, 1.0) = 0.72;
varying vec2 world_xz;

void vertex() {
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	// Every island uses its own quadrant. Inset sampling and the cell mask
	// prevent neighboring sprites and stray alpha pixels leaking into view.
	vec2 local_uv = clamp(UV, vec2(0.003), vec2(0.997));
	vec2 atlas_uv = (atlas_cell + local_uv) * 0.5;
	vec4 texel = texture(island_atlas, atlas_uv);
	vec2 edge_distance = min(UV, vec2(1.0) - UV);
	float cell_mask = smoothstep(0.015, 0.065, min(edge_distance.x, edge_distance.y));
	float water_mask = smoothstep(0.02, 0.16, texel.g - texel.r)
		* smoothstep(0.015, 0.09, texel.b - texel.r);
	// Fade the water COLOR to the exact ocean before the image alpha ends.
	// Broad footprints soften the edge without blurring beaches or foliage.
	float broad_alpha = textureLod(island_atlas, atlas_uv, coast_blend_lod).a;
	float fine_alpha = textureLod(island_atlas, atlas_uv, coast_blend_lod - 1.0).a;
	float irregularity = sin(UV.x * 81.0 + sin(UV.y * 43.0) * 2.0)
		* sin(UV.y * 67.0 + sin(UV.x * 37.0)) * 0.035;
	float depth = min(broad_alpha, fine_alpha) + irregularity;
	float shallow_blend = pow(smoothstep(0.54, 0.99, depth), 1.4);
	vec3 sea = ocean_surface(world_xz);
	float shimmer = sin(UV.x * 90.0 + wave_phase * 2.0 + phase_offset)
		* sin(UV.y * 74.0 - wave_phase);
	vec3 shallows = texel.rgb * ocean_tint * (0.91 + 0.018 * shimmer);
	vec3 coastal_water = mix(sea, shallows, shallow_blend * shallows_strength);
	ALBEDO = mix(texel.rgb * land_tint * 0.96, coastal_water, water_mask);
	ALPHA = texel.a * cell_mask;
}
