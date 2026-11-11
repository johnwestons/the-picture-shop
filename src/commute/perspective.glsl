// Shared homogeneous projection: the GPU clips triangles crossing the eye
// plane and interpolates texture coordinates in perspective.
extern bool firstPerson;
#ifdef PIXEL
extern bool rideHeadlight;
extern vec2 rideForward;
extern vec2 rideLightOffset;
extern float rideLightHeight;
extern float rideBeamRange;
extern float rideBeamSpread;
extern float rideBeamDrop;
extern float rideLightSeparation;
extern int localLightCount;
extern float localNight;
extern vec4 localLightPosition[4];
extern vec3 localLightDirection[4];
extern int localBlockerCount;
extern vec4 localBlockerBase[4];
extern vec4 localBlockerSize[4];
bool bodyPart(vec3 a,vec3 v,vec3 center,vec3 radius) {
    vec3 o=(a-center)/radius,d=v/radius;
    float q=dot(d,d),b=dot(o,d),disc=b*b-q*(dot(o,o)-1.0);
    if(disc<0.0 || q<.00001) return false;
    float t=(-b-sqrt(disc))/q;
    return t>.015 && t<.98;
}
bool characterShape(vec3 a,vec3 v) {
    return bodyPart(a,v,vec3(0,1.40,0),vec3(.24,.25,.25))
        || bodyPart(a,v,vec3(0,1.66,-.17),vec3(.10,.17,.09))
        || bodyPart(a,v,vec3(0,1.66,.17),vec3(.10,.17,.09))
        || bodyPart(a,v,vec3(0,.94,0),vec3(.22,.34,.27))
        || bodyPart(a,v,vec3(0,.88,-.34),vec3(.12,.31,.11))
        || bodyPart(a,v,vec3(0,.88,.34),vec3(.12,.31,.11))
        || bodyPart(a,v,vec3(0,.32,-.15),vec3(.13,.32,.12))
        || bodyPart(a,v,vec3(0,.32,.15),vec3(.13,.32,.12));
}
float localVisibility(vec3 source,vec3 target) {
    for(int j=0;j<4;j++) {
        if(j>=localBlockerCount) break;
        vec4 b=localBlockerBase[j];vec3 sz=localBlockerSize[j].xyz;
        float c=cos(b.w),s=sin(b.w);
        vec3 a=source-b.xyz,v=target-source;
        a=vec3(a.x*c+a.z*s,a.y,-a.x*s+a.z*c);
        v=vec3(v.x*c+v.z*s,v.y,-v.x*s+v.z*c);
        vec3 safe=vec3(v.x>=0.0?1.0:-1.0,v.y>=0.0?1.0:-1.0,v.z>=0.0?1.0:-1.0)*max(abs(v),vec3(.0001));
        vec3 t0=(vec3(-sz.x,.08,-sz.y)-a)/safe;
        vec3 t1=(vec3(sz.x,sz.z,sz.y)-a)/safe;
        vec3 lo=min(t0,t1),hi=max(t0,t1);
        float enter=max(max(lo.x,lo.y),lo.z),leave=min(min(hi.x,hi.y),hi.z);
        if(enter<leave && enter<.98 && leave>.015) {
            float kind=localBlockerSize[j].w;
            if(kind<.5) { if(enter>.015) return .12; }
            else if((kind<2.5 && characterShape(a,v)) || (kind>1.5 && bodyPart(a,v,vec3(0,.43,0),vec3(.85,.35,.23)))) return .12;
        }
    }
    return 1.0;
}
vec3 localLighting(vec3 surface,vec2 delta,float height) {
    if(localNight<=.001) return surface;
    vec3 target=vec3(delta.x,height+.025,delta.y);
    for(int i=0;i<4;i++) {
        if(i>=localLightCount) break;
        vec4 lamp=localLightPosition[i];vec3 v=target-lamp.xyz;
        float attenuation=1.0-smoothstep(0.0,lamp.w,length(v));
        float front=smoothstep(-.3,.25,dot(v.xz,localLightDirection[i].xy)+.3);
        surface+=vec3(.85,.61,.30)*attenuation*attenuation*front*localNight*localLightDirection[i].z*localVisibility(lamp.xyz,target);
    }
    return surface;
}
vec3 riderLight(vec3 surface,vec2 delta,float surfaceHeight) {
    if(!rideHeadlight) return surface;
    vec3 target=vec3(delta.x,surfaceHeight+.025,delta.y);
    for(int lamp=0;lamp<2;lamp++) {
    if(lamp==1 && rideLightSeparation==0.0) break;
    vec2 origin=rideLightOffset+vec2(-rideForward.y,rideForward.x)*rideLightSeparation*(lamp==0?-1.0:1.0);
    vec2 fromLamp=delta-origin;
    float forward=max(0.0,dot(fromLamp,rideForward));
    float side=abs(fromLamp.x*rideForward.y-fromLamp.y*rideForward.x);
    float width=.14+forward*rideBeamSpread;
    float lateral=1.0-smoothstep(width*.60,width,side);
    float range=1.0-smoothstep(rideBeamRange*.72,rideBeamRange,forward);
    float targetHeight=rideLightHeight-surfaceHeight-forward*rideBeamDrop;
    float vertical=1.0-smoothstep(.18+forward*.035,.72+forward*.075,abs(targetHeight));
    float beam=lateral*range*vertical*smoothstep(.15,.9,forward);
    surface+=vec3(.34,.31,.21)*beam*mix(.30,1.0,smoothstep(0.0,4.0,forward))*localVisibility(vec3(origin.x,rideLightHeight,origin.y),target);
    }
    return surface;
}
#endif
#ifdef VERTEX
extern vec3 eyePosition;
extern vec3 eyeAngles;
extern vec3 eyeLens;
extern vec2 viewCenter;
vec4 riderProjection(mat4 transform_projection, vec3 world)
{
    vec3 delta=world-eyePosition;
    float c=cos(eyeAngles.x),s=sin(eyeAngles.x);
    float right=-delta.x*s+delta.z*c;
    float forward=delta.x*c+delta.z*s;
    float cp=cos(eyeAngles.y),sp=sin(eyeAngles.y);
    float depth=forward*cp+delta.y*sp;
    float up=delta.y*cp-forward*sp;
    float cr=cos(eyeAngles.z),sr=sin(eyeAngles.z);
    vec2 rotated=vec2(right*cr+up*sr,up*cr-right*sr);
    vec4 clip=transform_projection*vec4(viewCenter.x*depth+rotated.x*eyeLens.x,
        viewCenter.y*depth-rotated.y*eyeLens.x,0.0,depth);
    float n=eyeLens.y,f=eyeLens.z;
    clip.z=(f+n)/(f-n)*depth-2.0*f*n/(f-n);
    return clip;
}
#endif
