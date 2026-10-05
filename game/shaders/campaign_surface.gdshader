shader_type spatial;
uniform sampler2D atlas : source_color, filter_linear_mipmap;
uniform vec2 cell = vec2(0.0);
uniform float tiling = 0.4;
uniform float metalness = 0.3;
uniform float surface_roughness = 0.82;
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
    ALBEDO=mix(paint,vec3(dot(paint,vec3(0.2126,0.7152,0.0722))),0.15)*0.55;
    METALLIC=metalness;
    ROUGHNESS=surface_roughness;
}
