// Shared by ordinary sprites, depth/fog billboards and the first-person mesh.
// Paint is sampled only by the fragment stage. Declaring its uniforms in the
// vertex stage as well gives them conflicting default precision on Android GLES.
#ifdef PIXEL
extern bool bikePaintEnabled;
extern vec3 bikePaintColor;
extern vec2 bikePaintTextureSize;
extern vec4 bikePaintFrame;
extern float bikePaintLower;
extern float bikePaintMode;
extern bool bikeTireEnabled;
extern vec4 bikeTireWheel1;
extern vec4 bikeTireWheel2;
// Distance phase, speed strength, projected forward-side and depth components.
extern vec4 bikeTireMotion;
float bikePaintRect(vec2 p,vec4 r) {
    return step(r.x,p.x)*step(r.y,p.y)*step(p.x,r.z)*step(p.y,r.w);
}
float bikeTireRoll(vec2 p,vec4 wheel) {
    if(wheel.z<1.0 || wheel.w<1.0) return 0.0;
    vec2 q=(p-wheel.xy)/wheel.zw;
    float radius=length(q);
    if(q.y<-.35 || radius<.62 || radius>1.04) return 0.0;
    // Only the lower rubber annulus: hubs, brakes, fenders, boots and chassis
    // keep their authored detail. The source material test below narrows this.
    float ring=smoothstep(.62,.76,radius)*(1.0-smoothstep(.96,1.04,radius));
    ring*=smoothstep(-.35,-.10,q.y);
    float side=bikeTireMotion.z;
    float phase=bikeTireMotion.x*3.0;
    float circumferential=sin(atan(q.y,q.x)*8.0-phase*(side<0.0?-1.0:1.0));
    float endOn=sin(q.y*9.0+phase*bikeTireMotion.w);
    return ring*mix(endOn,circumferential,smoothstep(.18,.55,abs(side)));
}
vec4 bikePaintSurface(vec4 source,vec2 uv) {
    if((!bikePaintEnabled && !bikeTireEnabled) || source.a<0.01) return source;
    vec2 p=uv*bikePaintTextureSize-bikePaintFrame.xy;
    float region=0.0;
    if(bikePaintMode>0.5) {
        // Painted front mudguard, central pressed frame, rear mudguard and plate.
        // Gauge, handlebar metal, mirrors, saddle, exhaust and tires are outside.
        region=max(max(bikePaintRect(p,vec4(451.0,88.0,573.0,169.0)),
            bikePaintRect(p,vec4(466.0,383.0,558.0,748.0))),
            max(bikePaintRect(p,vec4(467.0,1120.0,559.0,1194.0)),
            bikePaintRect(p,vec4(462.0,1289.0,561.0,1366.0))));
    } else {
        region=bikePaintRect(p,vec4(0.0,bikePaintLower,bikePaintFrame.z,bikePaintFrame.w));
    }
    vec3 c=source.rgb;
    float hi=max(c.r,max(c.g,c.b));
    float lo=min(c.r,min(c.g,c.b));
    // The source body's olive enamel is separated from red/brown leather and
    // amber lamps. Low-chroma tire/chrome pixels and hot lamp cores stay intact.
    float saturation=(hi-lo)/max(hi,0.001);
    float olive=(c.g-c.b)/max(c.r-c.b,0.001);
    float material=smoothstep(0.22,0.34,saturation)*smoothstep(0.64,0.76,olive)
        *(1.0-smoothstep(1.04,1.18,c.g/max(c.r,0.001)))
        *(1.0-smoothstep(0.68,0.84,min(c.r,c.g)));
    float luminance=dot(c,vec3(0.2126,0.7152,0.0722));
    vec3 finish=clamp(bikePaintColor*(luminance/0.46),0.0,1.0);
    vec3 result=bikePaintEnabled?mix(c,finish,region*material):c;
    if(bikeTireEnabled) {
        float rubber=(1.0-smoothstep(.32,.48,hi))*(1.0-smoothstep(.24,.42,saturation));
        if(rubber>.001) {
            float roll=bikeTireRoll(p,bikeTireWheel1)+bikeTireRoll(p,bikeTireWheel2);
            result*=1.0+clamp(roll,-1.0,1.0)*rubber*bikeTireMotion.y*.24;
        }
    }
    return vec4(result,source.a);
}
#endif
