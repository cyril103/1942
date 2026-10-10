shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform sampler2D atlas : source_color, filter_linear_mipmap_anisotropic;
uniform vec2 cell = vec2(0.0);
uniform float tiling = 0.4;
uniform float metalness = 0.3;
uniform float surface_roughness = 0.82;
uniform float relief = .014;
varying vec3 local_position;
varying vec3 local_normal;
void vertex() { local_position=VERTEX; local_normal=NORMAL; }
vec3 sample_tile(vec2 p) {
    vec2 uv=fract(p*tiling)*0.97+vec2(0.015);
    return texture(atlas,(uv+cell)*0.5).rgb;
}
void fragment() {
    vec3 blend=pow(abs(local_normal),vec3(5.0));
    blend/=max(dot(blend,vec3(1.0)),0.001);
    vec3 paint=sample_tile(local_position.zy)*blend.x+sample_tile(local_position.xz)*blend.y+sample_tile(local_position.xy)*blend.z;
    float grain=dot(paint,vec3(0.2126,0.7152,0.0722));
    ALBEDO=mix(paint,vec3(grain),0.08)*0.96;
    METALLIC=metalness;
    ROUGHNESS=clamp(surface_roughness+(0.28-grain)*.18,.27,.86);
    SPECULAR=.58;
    vec3 dx=dFdx(VERTEX);
    vec3 dy=dFdy(VERTEX);
    vec3 r1=cross(dy,NORMAL);
    vec3 r2=cross(NORMAL,dx);
    float determinant=dot(dx,r1);
    vec3 gradient=sign(determinant)*(dFdx(grain)*r1+dFdy(grain)*r2);
    NORMAL=normalize(max(abs(determinant),.0000001)*NORMAL-relief*gradient);
}
