shader_type canvas_item;
uniform int weather_kind = 0;
uniform float strength = 0.5;
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise(vec2 p) {
    vec2 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);
    return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);
}
void fragment() {
    vec2 p=UV;
    float cloud=noise(p*4.0+vec2(TIME*0.015,-TIME*0.024));
    cloud+=noise(p*9.0+vec2(0.0,-TIME*0.04))*0.4;
    float alpha=smoothstep(0.7,1.3,cloud)*0.09;
    vec3 color=vec3(0.72,0.81,0.85);
    if(weather_kind==1) {
        vec2 q=vec2(p.x*85.0+p.y*7.0,p.y*24.0+TIME*15.0);
        vec2 cell=floor(q); vec2 f=fract(q);
        float drop=smoothstep(0.97,1.0,1.0-abs(f.x-0.5))*pow(1.0-f.y,3.0)*step(0.55,hash(cell));
        alpha+=drop*0.22;
    } else if(weather_kind==2 || weather_kind==3) {
        vec2 q=p*vec2(36.0,45.0)+vec2(TIME*0.28,TIME*0.65);
        vec2 cell=floor(q), f=fract(q)-vec2(hash(floor(q)),hash(floor(q)+3.1));
        float flake=(1.0-smoothstep(0.025,0.06,length(f)))*step(0.6,hash(cell));
        alpha+=flake*0.34;
        if(weather_kind==3) color=vec3(0.61,0.42,0.25);
    }
    COLOR=vec4(color,alpha*strength);
}
