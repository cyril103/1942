shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
void fragment() {
 vec2 p=UV*2.0-1.0;
 float r=length(p);
 float angle=atan(p.y,p.x);
 float core=exp(-r*r*38.0);
 float corona=exp(-pow((r-.34)*13.0,2.0));
 float rays=pow(.5+.5*sin(angle*7.0+TIME*4.0+r*9.0),10.0);
 rays*=exp(-r*r*4.0)*smoothstep(.12,.25,r);
 float halo=exp(-r*r*5.0)*.28;
 ALBEDO=vec3(.75,.93,1.0)*core*1.5+vec3(.24,.29,1.0)*(halo+corona*.5)+vec3(.7,.3,1.0)*rays;
 ALPHA=1.0-smoothstep(.8,1.0,r);
}
