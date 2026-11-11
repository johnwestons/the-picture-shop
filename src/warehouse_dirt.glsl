extern vec3 cleanRegions;
extern float conditionSeed;

float grainNoise(vec2 p) {
    vec2 cell=floor(p),f=fract(p);
    f=f*f*(3.0-2.0*f);
    float a=fract(sin(dot(cell,vec2(127.1,311.7))+conditionSeed)*43758.5453);
    float b=fract(sin(dot(cell+vec2(1.0,0.0),vec2(127.1,311.7))+conditionSeed)*43758.5453);
    float c=fract(sin(dot(cell+vec2(0.0,1.0),vec2(127.1,311.7))+conditionSeed)*43758.5453);
    float d=fract(sin(dot(cell+vec2(1.0,1.0),vec2(127.1,311.7))+conditionSeed)*43758.5453);
    return mix(mix(a,b,f.x),mix(c,d,f.x),f.y);
}
float stain(vec2 p,vec2 center,vec2 radius,float offset) {
    vec2 q=(p-center)/radius;
    float shape=1.0-dot(q,q);
    float rough=grainNoise(p*.055+offset)*.35+grainNoise(p*.14+offset*2.0)*.12;
    return smoothstep(-.12,.34,shape+rough-.23);
}
vec4 effect(vec4 color,Image texture,vec2 uv,vec2 pixel) {
    vec2 p=pixel;
    float west=max(stain(p,vec2(150.0,383.0),vec2(90.0,25.0),3.0),
                   stain(p,vec2(217.0,497.0),vec2(61.0,18.0),7.0));
    float center=max(stain(p,vec2(433.0,426.0),vec2(80.0,25.0),11.0),
                     stain(p,vec2(605.0,260.0),vec2(49.0,14.0),17.0));
    float east=max(stain(p,vec2(770.0,497.0),vec2(85.0,25.0),23.0),
                   stain(p,vec2(846.0,363.0),vec2(54.0,15.0),29.0));
    float mask=max(max(west*cleanRegions.x,center*cleanRegions.y),east*cleanRegions.z);
    float grain=grainNoise(p*.23+31.0)*.60+grainNoise(p*.075+71.0)*.40;
    float dirtAlpha=mask*(.045+.085*grain);
    float water=max(stain(p,vec2(758.0,493.0),vec2(85.0,23.0),37.0),
                    stain(p,vec2(813.0,505.0),vec2(43.0,15.0),41.0))*cleanRegions.z;
    float oil=grainNoise(p*.10+83.0)*.65+grainNoise(p*.31+101.0)*.35;
    float gleam=smoothstep(.74,.94,grainNoise(p*.19+47.0))*.48;
    float rim=smoothstep(.05,.36,water)-smoothstep(.54,.86,water);
    float ripple=max(0.0,sin(p.x*.10+sin(p.y*.18)*1.7))*.06;
    vec3 waterColor=mix(vec3(.045,.19,.25),vec3(.10,.34,.40),oil)
        +vec3(gleam*.10,gleam*.14,gleam*.15)
        +rim*vec3(.06,.12,.14)+water*ripple*vec3(.04,.08,.10);
    float waterAlpha=water*(.43+.10*oil);
    float alpha=max(dirtAlpha,waterAlpha);
    vec3 tint=mix(vec3(.24,.20,.14),waterColor,waterAlpha/(waterAlpha+dirtAlpha+.0001));
    return vec4(tint,alpha);
}
