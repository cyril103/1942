shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never;

float wake_noise(vec2 p) {
    vec2 cell = floor(p);
    vec2 f = fract(p);
    f = f*f*(3.0-2.0*f);
    vec4 corners = vec4(dot(cell,vec2(127.1,311.7)),dot(cell+vec2(1,0),vec2(127.1,311.7)),dot(cell+vec2(0,1),vec2(127.1,311.7)),dot(cell+vec2(1,1),vec2(127.1,311.7)));
    corners = fract(sin(corners)*43758.5453);
    return mix(mix(corners.x,corners.y,f.x),mix(corners.z,corners.w,f.x),f.y);
}

void fragment() {
    vec2 p = UV*2.0-1.0;
    float travel = UV.y;
    float turbulence = wake_noise(vec2(p.x*14.0,p.y*11.0-TIME*.85));
    float fine = wake_noise(vec2(p.x*32.0,p.y*27.0-TIME*1.7));
    float spread = travel*.62+.045+sin(p.y*8.0-TIME*.9)*.018;
    float width = .065+travel*.10;
    float shoulders = exp(-pow((abs(p.x)-spread+(turbulence-.5)*.07)/width,2.0));
    float churn = exp(-pow(p.x/(.09+travel*.15),2.0))*.48;
    float foam = smoothstep(.23,.77,turbulence)*(.40+.60*fine);
    float taper = smoothstep(.06,.27,travel)*(1.0-smoothstep(.38,.97,travel));
    ALBEDO = mix(vec3(.24,.48,.49),vec3(.62,.79,.76),fine);
    ALPHA = (shoulders+churn)*foam*taper*.30;
}
