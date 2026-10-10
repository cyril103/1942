shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
uniform vec4 glass_tint : source_color = vec4(.04,.16,.24,1.0);
void fragment() {
    float edge = pow(1.0-clamp(dot(normalize(NORMAL),normalize(VIEW)),0.0,1.0),3.0);
    // Coated opaque glazing avoids refraction and transparent sorting costs.
    ALBEDO = mix(glass_tint.rgb,vec3(.12,.30,.40),edge*.58);
    METALLIC = .48;
    ROUGHNESS = .12;
    SPECULAR = .88;
    RIM = .22;
    RIM_TINT = .65;
}
