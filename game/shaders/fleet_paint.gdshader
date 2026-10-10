shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
uniform sampler2D paint : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D orm_texture : filter_linear_mipmap_anisotropic;
uniform vec4 tint : source_color = vec4(1.0);
uniform bool has_albedo = false;
uniform bool has_normal = false;
uniform bool has_orm = false;
uniform float metalness = 0.25;
uniform float surface_roughness = 0.42;
uniform float normal_strength = 0.85;
uniform float relief = 0.01;
void fragment() {
    vec3 color = has_albedo ? texture(paint,UV).rgb : vec3(1.0);
    float grain = dot(color,vec3(.2126,.7152,.0722));
    vec3 orm = has_orm ? texture(orm_texture,UV).rgb : vec3(1.0);
    ALBEDO = color*tint.rgb*1.08;
    // Authored panels and rivets break highlights, with no detail texture pass.
    METALLIC = has_orm ? clamp(orm.b,.08,.9) : metalness;
    ROUGHNESS = clamp((has_orm ? orm.g*.78 : surface_roughness)+(0.28-grain)*.10,.25,.76);
    SPECULAR = .6;
    if (has_normal) {
        NORMAL_MAP = texture(normal_texture,UV).rgb;
        NORMAL_MAP_DEPTH = normal_strength;
    } else if (has_albedo) {
        vec3 dx = dFdx(VERTEX);
        vec3 dy = dFdy(VERTEX);
        vec3 r1 = cross(dy,NORMAL);
        vec3 r2 = cross(NORMAL,dx);
        float determinant = dot(dx,r1);
        vec3 gradient = sign(determinant)*(dFdx(grain)*r1+dFdy(grain)*r2);
        NORMAL = normalize(max(abs(determinant),.0000001)*NORMAL-relief*gradient);
    }
    RIM = .12;
    RIM_TINT = .35;
}
