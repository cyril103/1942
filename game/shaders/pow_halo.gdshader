shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform float strength = 1.0;
uniform float burst = 0.0;
void fragment() {
    vec2 p = UV*2.0-1.0;
    float r = length(p);
    float a = atan(p.y,p.x);
    float ring = exp(-pow((r-0.67)/0.024,2.0));
    float aura = exp(-r*r*4.5)*0.38;
    float ticks = pow(max(0.0,cos(a*12.0+TIME*2.0)),16.0)*exp(-pow((r-0.78)/0.045,2.0));
    ALBEDO = mix(vec3(1.0,0.40,0.035),vec3(1.0,0.94,0.55),ring);
    ALPHA = (ring+ticks*0.7+aura*(1.0-burst))*strength;
}
