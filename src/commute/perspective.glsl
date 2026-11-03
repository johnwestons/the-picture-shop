// Shared homogeneous projection: the GPU clips triangles crossing the eye
// plane and interpolates texture coordinates in perspective.
extern bool firstPerson;
#ifdef PIXEL
extern bool rideHeadlight;
extern vec2 rideForward;
vec3 riderLight(vec3 surface,vec2 delta) {
    float forward=dot(delta,rideForward);
    float side=abs(delta.x*rideForward.y-delta.y*rideForward.x);
    float beam=(1.0-smoothstep(.3+forward*.12,.6+forward*.22,side))
        *smoothstep(.3,1.0,forward)*(1.0-smoothstep(4.0,11.0,forward));
    return surface+vec3(.18,.16,.09)*beam;
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
