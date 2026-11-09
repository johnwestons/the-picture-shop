// Shared-root triangular tufts and wind, projected into
// the commute's depth buffer and its roll-aware first-person camera.
varying vec2 fromCameraCenter;
varying float grassDistance;
varying float surfaceHeight;
#ifdef VERTEX
attribute float WorldHeight;
attribute float GrassHeight;
attribute float WindPhase;
extern vec2 cameraCenter;
extern vec2 cameraScreenCenter;
extern float cameraFocusHeight;
extern float cameraZoom;
extern float cameraYaw;
extern float cameraGroundScale;
extern float cameraHeightScale;
extern float groundDepthSpan;
extern float grassTime;
extern float windStrength;
extern vec2 windDirection;
vec4 position(mat4 transform_projection,vec4 vertex_position) {
    vec2 world=vertex_position.xy;
    float height=max(GrassHeight,0.0);
    float phase=grassTime*1.25+WindPhase+world.x*.47+world.y*.31;
    float wave=sin(phase)*.68+sin(grassTime*.78+WindPhase*.73-world.x*.19+world.y*.53)*.32;
    world+=windDirection*(windStrength*wave*.20*height*height);
    fromCameraCenter=world-cameraCenter;grassDistance=length(fromCameraCenter);
    surfaceHeight=WorldHeight;
    if(firstPerson) return riderProjection(transform_projection,vec3(world.x,WorldHeight,world.y));
    float c=cos(cameraYaw),s=sin(cameraYaw);
    float right=fromCameraCenter.x*c-fromCameraCenter.y*s;
    float depth=fromCameraCenter.x*s+fromCameraCenter.y*c;
    vec2 screen=cameraScreenCenter+vec2(right*48.0*cameraZoom,
        (depth*29.0*cameraGroundScale-(WorldHeight-cameraFocusHeight)*22.0*cameraHeightScale)*cameraZoom);
    vec4 clip=transform_projection*vec4(screen,vertex_position.z,vertex_position.w);
    float order=depth*22.0*cameraHeightScale+(WorldHeight-cameraFocusHeight)*29.0*cameraGroundScale;
    clip.z=-order/groundDepthSpan*clip.w;
    return clip;
}
#endif
#ifdef PIXEL
extern vec3 seasonTint;
extern float grassRadius;
vec4 effect(vec4 color,Image image,vec2 uv,vec2 pixel) {
    float fade=1.0-smoothstep(grassRadius*.72,grassRadius,grassDistance);
    if(fade<.015) discard;
    // LÖVE already includes VertexColor in effect's color argument.
    vec3 surface=seasonTint*color.rgb;
    if(firstPerson && rideHeadlight) surface=riderLight(surface,fromCameraCenter,surfaceHeight);
    return vec4(surface,color.a*fade);
}
#endif
