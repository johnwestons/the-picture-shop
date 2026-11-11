attribute float WorldHeight;
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
    if(firstPerson)return riderProjection(transform_projection,world);
    vec2 delta=world.xz-cameraCenter;
    float c=cos(cameraYaw),s=sin(cameraYaw);
    float right=delta.x*c-delta.y*s,depth=delta.x*s+delta.y*c;
    float height=world.y-cameraFocusHeight;
    vec2 screen=cameraScreenCenter+vec2(right*48.0*cameraZoom,(depth*29.0*cameraGroundScale-height*22.0*cameraHeightScale)*cameraZoom);
    vec4 clip=transform_projection*vec4(screen,0.0,1.0);
    clip.z=-(depth*22.0*cameraHeightScale+height*29.0*cameraGroundScale)/groundDepthSpan*clip.w;
    return clip;
}
