shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

#include "res://shaders/ocean_surface.gdshaderinc"
varying vec2 world_xz;

void vertex() {
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	ALBEDO = ocean_surface(world_xz);
}
