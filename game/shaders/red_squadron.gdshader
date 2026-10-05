shader_type spatial;
render_mode blend_mix, depth_draw_never;
uniform sampler2D paint : source_color;
void fragment() {
    vec4 base = texture(paint, UV);
    float luminance = dot(base.rgb, vec3(0.299, 0.587, 0.114));
    // Work in linear light: retain near-black glazing and bright markings.
    float mask = smoothstep(0.012,0.040,luminance);
    mask *= 1.0-smoothstep(0.55,0.80,luminance);
    mask *= 1.0-smoothstep(0.01,0.05,base.b-base.r);
    ALBEDO = vec3(0.42,0.015,0.009)*clamp(0.20+luminance*4.0,0.20,1.10);
    ROUGHNESS = 0.42;
    METALLIC = 0.15;
    ALPHA = mask*0.98;
}
