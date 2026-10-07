shader_type spatial;
render_mode cull_back;
// Shared UV atlas and vertex finish from Blender; one opaque pass per assembly.
uniform sampler2D field_atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float hit_flash : hint_range(0.0, 1.0) = 0.0;
uniform float damage : hint_range(0.0, 1.0) = 0.0;
varying vec3 object_position;
float grain(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}
void vertex() { object_position = VERTEX; }
void fragment() {
	vec3 surface = texture(field_atlas,UV).rgb;
	float soot = damage * (0.50 + 0.25 * grain(floor(object_position.xz * 5.0)));
	vec3 paint = surface * COLOR.rgb;
	paint = mix(paint, vec3(0.055, 0.047, 0.037), soot);
	// Match the daylight exposure of the terrain in Compatibility's additive
	// light passes. Keep metal reflections while preserving painted atlas detail.
	ALBEDO = mix(paint * mix(0.48,0.68,COLOR.a), vec3(1.0), hit_flash);
	METALLIC = COLOR.a * (1.0-damage);
	ROUGHNESS = mix(clamp(0.86-COLOR.a*0.30+(0.22-surface.g)*0.12,0.49,0.94),0.98,damage);
	SPECULAR = 0.18;
	EMISSION = vec3(0.28) * hit_flash;
}
