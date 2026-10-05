shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back;
uniform float strength = 0.0;
void fragment() {
    if (strength < 0.001) { discard; }
    ALBEDO = vec3(1.0);
    EMISSION = vec3(0.4) * strength;
    ALPHA = strength;
}
