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
float bikePaintRect(vec2 p,vec4 r) {
    return step(r.x,p.x)*step(r.y,p.y)*step(p.x,r.z)*step(p.y,r.w);
}
vec4 bikePaintSurface(vec4 source,vec2 uv) {
    if(!bikePaintEnabled || source.a<0.01) return source;
    vec2 p=uv*bikePaintTextureSize-bikePaintFrame.xy;
    float region;
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
    return vec4(mix(c,finish,region*material),source.a);
}
#endif
