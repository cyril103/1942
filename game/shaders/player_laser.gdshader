shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform float beam_length = 18.0;
float hash(float n) { return fract(sin(n)*43758.5453); }
float noise(float x) {
 float i=floor(x); float f=fract(x);
 return mix(hash(i),hash(i+1.0),f*f*(3.0-2.0*f));
}
void fragment() {
 float x=(UV.x-.5)*2.1;
 float z=UV.y*beam_length;
 float flow=z*2.3+TIME*15.0;
 float turbulence=noise(flow)*.6+noise(flow*2.1)*.3;
 float width=.24+turbulence*.045;
 float core=1.0-smoothstep(width*.25,width,abs(x));
 float sheath=exp(-x*x*13.0);
 float halo=exp(-x*x*3.8)*.28;
 float filament=0.0;
 for(int i=0; i<3; i++) {
  float phase=float(i)*2.094;
  float ribbon=sin(z*3.7+TIME*12.0+phase)*.32;
  ribbon+=(noise(flow+float(i)*19.0)-.5)*.09;
  filament+=exp(-pow((x-ribbon)*42.0,2.0))*.65;
 }
 float packets=pow(.5+.5*sin(z*5.0+TIME*24.0),8.0)*sheath*.25;
 float ends=smoothstep(0.0,.16,z)*smoothstep(0.0,.12,beam_length-z);
 vec3 energy=vec3(.19,.26,1.0)*(sheath+halo);
 energy+=vec3(.73,.27,1.0)*filament;
 energy+=vec3(.72,.94,1.0)*core*1.4+vec3(.25,.6,1.0)*packets;
 ALBEDO=energy;
 ALPHA=ends*(1.0-smoothstep(.82,1.05,abs(x)));
}
