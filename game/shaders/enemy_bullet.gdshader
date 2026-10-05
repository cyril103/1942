shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never;
void fragment() {
 float r=length(UV*2.0-1.0);
 float body=1.0-smoothstep(.43,.52,r);
 float core=1.0-smoothstep(.12,.29,r);
 float ring=smoothstep(.30,.35,r)*(1.0-smoothstep(.43,.49,r));
 // Opaque dark keyline preserves contrast over bright sand and foam.
 vec3 ink=vec3(.19,.012,.055);
 vec3 shell=mix(ink,vec3(1.0,.12,.26),body);
 shell=mix(shell,vec3(1.0,.63,.20),ring);
 ALBEDO=mix(shell,vec3(1.0,.98,.83),core);
 ALPHA=clamp((1.0-smoothstep(.55,.65,r))+exp(-r*r*5.0)*.24*(1.0-smoothstep(.7,1.0,r)),0.0,1.0);
}
