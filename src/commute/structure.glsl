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
extern vec3 sunDirection;
extern vec3 sunColor;
extern vec3 fogColor;
extern float sunlight;
extern float ambientLight;
extern bool useStructureTexture;
vec4 effect(vec4 color,Image image,vec2 uv,vec2 pixel) {
    vec3 normal=normalize(structureNormal);
    float sun=max(dot(normal,normalize(sunDirection)),0.0);
    float sky=.5+.5*normal.y;
    vec4 albedo=useStructureTexture ? Texel(image,uv)*color : color;
    vec3 surface=albedo.rgb*(vec3(ambientLight*(.7+.3*sky))+sunColor*(sunlight*sun));
    surface=localLighting(surface,structureDelta,structureHeight);
    surface=riderLight(surface,structureDelta,structureHeight);
    // Reserved vertex alpha .99 marks opaque lamp glass (byte-quantized).
    if(!useStructureTexture && albedo.a>.985 && albedo.a<.995) {
        surface=mix(surface,vec3(1.0,.87,.52),localNight);albedo.a=1.0;
    }
    surface=mix(surface,fogColor,smoothstep(structureRadius*.78,structureRadius,structureDistance));
    return vec4(surface,albedo.a);
}
#endif
