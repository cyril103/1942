shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
float ellipse(vec2 p, vec2 radius) {
    return 1.0-smoothstep(.75,1.12,length(p/radius));
}
void fragment() {
    vec2 p=UV-.5;
    float body=ellipse(p,vec2(.073,.43));
    float wings=ellipse(p+vec2(0,.065),vec2(.47,.105));
    float tail=ellipse(p-vec2(0,.29),vec2(.21,.065));
    float shape=max(body,max(wings,tail));
    ALBEDO=vec3(.006,.018,.026);
    ALPHA=shape*.24*COLOR.a;
}
