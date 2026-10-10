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
		vec2 curl=p+vec2(sin(p.y*4.-age*2.1)*.14,0.0);
		float body=(1.-smoothstep(.05,1.,length(curl*vec2(1.,.65))))*n;
		float ember=pow(max(0.,1.-length((p+vec2(0.,.27))*vec2(1.6,2.))),2.);
		float fissures=smoothstep(.4,.72,n)*ember;
		color=mix(vec3(.085,.10,.115),vec3(1.,.31,.045),clamp(ember*1.6+fissures,.0,1.));
		color=mix(color,vec3(1.,.73,.27),fissures*.65);
		alpha=body*.78+ember*.5;
	}else if(kind==2){
		float downstream=UV.y;
		float curl=sin(downstream*14.-age*3.2)*.09*downstream;
		float width=mix(58.,12.,downstream);
		float vapor=exp(-(p.x+curl)*(p.x+curl)*width);
		float filament=exp(-(p.x-curl*.5)*(p.x-curl*.5)*95.);
		alpha=(vapor*.21+filament*.07)*sin(downstream*3.14159)*(1.-downstream*.55);
		color=vec3(.79,.86,.87);
	}
	ALBEDO=color;
	ALPHA=clamp(alpha*strength,0.,.9);
}
