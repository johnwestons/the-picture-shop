#ifdef GL_ES
precision highp float;
#define EFFECT_IO_PRECISION mediump
#else
#define EFFECT_IO_PRECISION
#endif

extern vec2 cleanedPuddles;
extern float conditionSeed;
extern vec4 puddle1;
extern vec4 puddle2;
extern Image eraseMask;
extern vec2 canvasSize;

float grainNoise(vec2 p) {
    vec2 cell=floor(p),f=fract(p);
    f=f*f*(3.0-2.0*f);
    float a=fract(sin(dot(cell,vec2(127.1,311.7))+conditionSeed)*43758.5453);
    float b=fract(sin(dot(cell+vec2(1.0,0.0),vec2(127.1,311.7))+conditionSeed)*43758.5453);
    float c=fract(sin(dot(cell+vec2(0.0,1.0),vec2(127.1,311.7))+conditionSeed)*43758.5453);
    float d=fract(sin(dot(cell+vec2(1.0,1.0),vec2(127.1,311.7))+conditionSeed)*43758.5453);
    return mix(mix(a,b,f.x),mix(c,d,f.x),f.y);
}
float blob(vec2 p,vec2 center,vec2 radius,float seed) {
    vec2 q=(p-center)/radius;
    float warp=(grainNoise(p*.049+seed)-.5)*.28
        +(grainNoise(p*.12+seed*2.0)-.5)*.12;
    return smoothstep(-.09,.16,1.0-dot(q,q)+warp);
}
float spill(vec2 p,vec4 bounds,float seed) {
    vec2 c=bounds.xy,r=bounds.zw;
    float body=blob(p,c,r*vec2(.77,.75),seed);
    body=max(body,blob(p,c+r*vec2(-.49,.13),r*vec2(.38,.53),seed+3.0));
    body=max(body,blob(p,c+r*vec2(.38,-.27),r*vec2(.43,.55),seed+7.0));
    body=max(body,blob(p,c+r*vec2(.11,.46),r*vec2(.32,.38),seed+11.0));
    return body;
}
vec4 effect(EFFECT_IO_PRECISION vec4 color,Image texture,
            EFFECT_IO_PRECISION vec2 uv,EFFECT_IO_PRECISION vec2 pixel) {
    vec2 p=pixel;
    float left=spill(p,puddle1,37.0)*(1.0-cleanedPuddles.x);
    float right=spill(p,puddle2,71.0)*(1.0-cleanedPuddles.y);
    float water=max(left,right);
    float grain=grainNoise(p*.11+83.0)*.65+grainNoise(p*.31+101.0)*.35;
    float gleam=smoothstep(.72,.94,grainNoise(p*.19+47.0))*.24;
    float ripple=max(0.0,sin(p.x*.11+sin(p.y*.16)*1.7))*.04;
    vec3 tint=mix(vec3(.025,.11,.16),vec3(.075,.29,.33),grain)
        +vec3(gleam*.22,gleam*.34,gleam*.38)+ripple*vec3(.03,.06,.06);
    float erased=Texel(eraseMask,p/canvasSize).a;
    float alpha=water*(.60+.14*grain)*(1.0-erased);
    return vec4(tint,alpha)*color;
}
