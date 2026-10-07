shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform float age = 0.0;
uniform float strength = 1.0;
uniform int kind = 2; // 1: localized fire, 2: wing trail.
float hash(vec2 p) {return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 p) {
	vec2 i=floor(p),f=fract(p); f=f*f*(3.0-2.0*f);
	return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1)),f.x),f.y);
}
void fragment() {
	vec2 p=UV*2.0-1.0;
	float alpha=0.0;
	vec3 color=vec3(.72,.91,1.0);
	if(kind==1){
		float n=noise(p*4.-vec2(0,age*1.8))*.65+noise(p*9.+age)*.35;
		float body=(1.-smoothstep(.05,1.,length(p*vec2(1.,.65))))*n;
		float ember=pow(max(0.,1.-length(p*vec2(1.4,2.))),2.);
		color=mix(vec3(.035,.045,.055),vec3(1.,.29,.035),ember*1.8);
		alpha=body*.85+ember*.5;
	}else if(kind==2){
		alpha=exp(-p.x*p.x*32.)*sin(UV.y*3.14159)*.28;
	}
	ALBEDO=color;
	ALPHA=clamp(alpha*strength,0.,.9);
}
