shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never;
void fragment() {
    vec2 p=UV*2.0-1.0;
    float trail=exp(-pow((abs(p.x)-(p.y+1.0)*0.30)/0.08,2.0));
    float foam=0.55+0.45*sin(p.y*85.0-TIME*4.0+sin(p.x*53.0)*2.0);
    float taper=smoothstep(-1.0,-0.55,p.y)*(1.0-smoothstep(-0.1,1.0,p.y));
    ALBEDO=vec3(0.60,0.82,0.84);
    ALPHA=trail*foam*taper*0.36;
}
