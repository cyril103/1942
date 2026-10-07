shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never;
void fragment() {
 float r=length(UV*2.0-1.0);
 float rim=1.0-smoothstep(.53,.60,r);
 float shell=1.0-smoothstep(.39,.46,r);
 float core=1.0-smoothstep(.19,.28,r);
 // Broad opaque keyline stays legible over sand, vegetation and white foam.
 // Warm hostile rounds remain distinct from the player's cyan tracers.
 vec3 color=mix(vec3(.025,.012,.028),vec3(1.0,.075,.08),rim);
 color=mix(color,vec3(1.0,.57,.04),shell);
 ALBEDO=mix(color,vec3(1.0,1.0,.91),core);
 float body=1.0-smoothstep(.66,.75,r);
 float halo=exp(-r*r*3.4)*.30*(1.0-smoothstep(.78,1.0,r));
 ALPHA=clamp(body+halo,0.0,1.0);
}
