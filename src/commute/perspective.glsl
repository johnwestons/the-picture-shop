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
vec3 riderLight(vec3 surface,vec2 delta,float surfaceHeight) {
    vec2 fromLamp=delta-rideLightOffset;
    float forward=max(0.0,dot(fromLamp,rideForward));
    float side=abs(fromLamp.x*rideForward.y-fromLamp.y*rideForward.x);
    float width=.14+forward*rideBeamSpread;
    float lateral=1.0-smoothstep(width*.60,width,side);
    float range=1.0-smoothstep(rideBeamRange*.72,rideBeamRange,forward);
    float targetHeight=rideLightHeight-surfaceHeight-forward*rideBeamDrop;
    float vertical=1.0-smoothstep(.18+forward*.035,.72+forward*.075,abs(targetHeight));
    float beam=lateral*range*vertical*smoothstep(.15,.9,forward);
    return surface+vec3(.30,.27,.15)*beam;
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
