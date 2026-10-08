shader_type spatial;
// PHASE 5 CANDIDATE. Same pool, quad, body/core radii and one rendering pass.
// Premultiplied output mixes the opaque keyline/body and adds the outer halo.
// No depth write, texture lookup, noise, time modulation or second pass.
render_mode unshaded, blend_premul_alpha, cull_disabled, depth_draw_never;
void fragment() {
	float r = length(UV * 2.0 - 1.0);
	float rim = 1.0 - smoothstep(.58, .64, r);
	float shell = 1.0 - smoothstep(.39, .46, r);
	float core = 1.0 - smoothstep(.19, .28, r);
	vec3 color = mix(vec3(.025, .012, .028), vec3(1.0, .075, .08), rim);
	color = mix(color, vec3(1.0, .57, .04), shell);
	color = mix(color, vec3(1.0, 1.0, .91), core);
	float body = 1.0 - smoothstep(.66, .75, r);
	float halo = exp(-r * r * 3.4) * .30 * (1.0 - smoothstep(.78, 1.0, r));
	// The halo adds light without darkening the background outside the body.
	// Core remains opaque, with a narrow dark keyline over snow/foam/explosions.
	ALBEDO = color * body + vec3(1.0, .24, .04) * halo * (1.0 - shell);
	ALPHA = body;
}
