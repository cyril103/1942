shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

#include "res://shaders/ocean_surface.gdshaderinc"
uniform sampler2D island_atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D relief_atlas : filter_linear_mipmap, repeat_disable;
uniform float relief_height = 0.0;
uniform vec2 island_size = vec2(14.0);
uniform vec2 atlas_cell = vec2(0.0);
uniform vec3 land_tint : source_color = vec3(1.0);
uniform vec3 detail_tint : source_color = vec3(1.0);
uniform float phase_offset = 0.0;
uniform float coast_blend_lod : hint_range(4.0, 7.0) = 6.0;
uniform float shallows_strength : hint_range(0.0, 1.0) = 0.72;
varying vec2 world_xz;
varying vec3 terrain_normal;
varying float terrain_height;

void vertex() {
	vec2 atlas_uv = (atlas_cell + clamp(UV,vec2(.003),vec2(.997))) * .5;
	float height = textureLod(relief_atlas,atlas_uv,0.0).r;
	float step_uv = 1.0 / 256.0;
	float left = textureLod(relief_atlas,atlas_uv-vec2(step_uv,0.0),0.0).r;
	float right = textureLod(relief_atlas,atlas_uv+vec2(step_uv,0.0),0.0).r;
	float top = textureLod(relief_atlas,atlas_uv-vec2(0.0,step_uv),0.0).r;
	float bottom = textureLod(relief_atlas,atlas_uv+vec2(0.0,step_uv),0.0).r;
	vec3 slope = normalize(vec3((left-right)*relief_height*64.0/island_size.x,1.0,(top-bottom)*relief_height*64.0/island_size.y));
	terrain_normal = normalize(mat3(MODEL_MATRIX)*slope);
	terrain_height = height * step(.001,relief_height);
	VERTEX.y += height * relief_height;
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	// Every island uses its own quadrant. Inset sampling and the cell mask
	// prevent neighboring sprites and stray alpha pixels leaking into view.
	vec2 local_uv = clamp(UV, vec2(0.003), vec2(0.997));
	vec2 atlas_uv = (atlas_cell + local_uv) * 0.5;
	vec4 texel = texture(island_atlas, atlas_uv);
	vec4 relief = textureLod(relief_atlas,atlas_uv,0.0);
	float has_relief = step(.001,relief_height);
	// Height-field alpha stores a signed, smoothed distance to real land,
	// not to the outside alpha silhouette of the painted lagoon.
	float shore_distance = (relief.a-.5)*48.0*(island_size.x+island_size.y)/256.0;
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
	float shimmer = sin(UV.x * 48.0 + wave_phase * 2.0 + phase_offset)
		* sin(UV.y * 38.0 - wave_phase);
	// Sea-glass lagoons retain their reefs but sit in the same exposure as the
	// open water. The bright turquoise from the painted atlas is deliberately restrained.
	vec3 shallows = (texel.rgb * .36 + vec3(.008,.052,.047)) * ocean_tint * (.96+.016*shimmer);
	vec3 coastal_water = mix(sea, shallows, shallow_blend * shallows_strength);
	vec2 surf = shoreline_surf((UV-.5)*island_size,shore_distance,phase_offset)*has_relief;
	coastal_water *= 1.0-surf.y*.10;
	// The same height field displaces geometry and lights its slopes. Cool
	// shadowed ravines and warm high ridges make the relief readable from above.
	vec3 normal = normalize(terrain_normal);
	float daylight = max(0.0,dot(normal,normalize(vec3(-.52,.82,-.35))));
	float relief_light = .63 + .46 * daylight;
	vec3 land = texel.rgb * land_tint * detail_tint;
	land = mix(vec3(dot(land,vec3(.299,.587,.114))),land,.82);
	land *= mix(vec3(.67,.78,.76),vec3(.94,.95,.82),daylight) * relief_light;
	land += vec3(.018,.018,.01) * terrain_height;
	// A slight lee shadow joins raised rock to the lagoon without real-time
	// shadow maps or modifying the gameplay navigation footprint.
	float lee_height = textureLod(relief_atlas,atlas_uv-vec2(.009,.014),1.0).r * step(.001,relief_height);
	coastal_water *= 1.0 - smoothstep(.015,.2,lee_height)*.19;
	float surface_water = max(water_mask,1.0-texel.a);
	vec3 surface = mix(land,coastal_water,surface_water);
	vec3 foam_color = vec3(.57,.74,.70)*mix(vec3(1.0),ocean_tint,.18);
	ALBEDO = mix(surface,foam_color,surf.x);
	// Let breakers continue into transparent atlas water. The underlying colour
	// there is the exact shared ocean, so the shore has no rectangular blend seam.
	float surf_coverage = (1.0-smoothstep(.95,1.20,shore_distance))*has_relief;
	ALPHA = max(texel.a,surf_coverage)*cell_mask;
}
