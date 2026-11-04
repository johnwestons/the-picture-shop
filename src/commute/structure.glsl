// Untextured solid structures share both camera projections with terrain.
varying vec3 structureNormal;
varying vec2 structureDelta;
varying float structureDistance;
varying float structureHeight;
#ifdef VERTEX
attribute float WorldHeight;
attribute vec3 StructureNormal;
extern vec2 cameraCenter;
extern vec2 cameraScreenCenter;
extern float cameraFocusHeight;
extern float cameraZoom;
extern float cameraYaw;
extern float cameraGroundScale;
extern float cameraHeightScale;
extern float groundDepthSpan;
vec4 position(mat4 transform_projection,vec4 vertex_position) {
    vec3 world=vec3(vertex_position.x,WorldHeight,vertex_position.y);
    structureNormal=StructureNormal;
    structureDelta=world.xz-cameraCenter;
    structureHeight=WorldHeight;
    structureDistance=length(structureDelta);
    if(firstPerson) return riderProjection(transform_projection,world);
    float c=cos(cameraYaw),s=sin(cameraYaw);
    float right=structureDelta.x*c-structureDelta.y*s;
    float depth=structureDelta.x*s+structureDelta.y*c;
    float height=WorldHeight-cameraFocusHeight;
    vec2 screen=cameraScreenCenter+vec2(right*48.0*cameraZoom,
        (depth*29.0*cameraGroundScale-height*22.0*cameraHeightScale)*cameraZoom);
    vec4 clip=transform_projection*vec4(screen,0.0,1.0);
    // Match terrain depth so the shared scene buffer can occlude structures,
    // roads and billboard scenery consistently.
    clip.z=-(depth*22.0*cameraHeightScale+height*29.0*cameraGroundScale)/groundDepthSpan*clip.w;
    return clip;
}
#endif
#ifdef PIXEL
extern float structureRadius;
vec4 effect(vec4 color,Image image,vec2 uv,vec2 pixel) {
    vec3 normal=normalize(structureNormal);
    float sun=max(dot(normal,normalize(vec3(-.4,.8,-.3))),0.0);
    float sky=.5+.5*normal.y;
    vec3 surface=color.rgb*(vec3(.43+.13*sky)+vec3(1.0,.91,.78)*(.48*sun));
    if(firstPerson && rideHeadlight) surface=riderLight(surface,structureDelta,structureHeight);
    vec3 fog=firstPerson?vec3(.57,.68,.70):vec3(.22,.27,.26);
    surface=mix(surface,fog,smoothstep(structureRadius*.78,structureRadius,structureDistance));
    return vec4(surface,color.a);
}
#endif
