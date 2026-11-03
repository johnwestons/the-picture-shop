// GLSL ES 1.00 compatible: one atlas sampler, no extra water render pass.
varying vec4 materialWeights;
varying vec3 materialVariants;
varying vec2 groundTextureUV;
varying vec3 surfaceNormal;
varying float viewDistance;
varying vec2 worldPosition;
varying float waterDepth;
varying float cloudLight;
#ifdef VERTEX
attribute float WaterDepth;
extern vec3 cloudPhase;
extern float cloudStrength;
attribute vec4 GroundWeights;
attribute vec3 GroundVariants;
attribute vec3 GroundNormal;
attribute float WorldHeight;
attribute vec2 GroundTextureCoord;
attribute vec2 GroundTexturePhase;
extern vec2 cameraCenter;
extern vec2 cameraScreenCenter;
extern float cameraFocusHeight;
extern float cameraZoom;
extern float cameraYaw;
extern float cameraGroundScale;
extern float cameraHeightScale;
extern float groundDepthSpan;
vec4 position(mat4 transform_projection, vec4 vertex_position)
{
    materialWeights=GroundWeights;materialVariants=GroundVariants;
    // Keep fragment texture coordinates small on GLES mediump hardware while
    // preserving the same world-anchored 8-unit repeat across chunk edges.
    groundTextureUV=GroundTextureCoord+GroundTexturePhase;
    surfaceNormal=GroundNormal;
    // Camera-relative interpolation protects mediump mobile fragment precision.
    // CPU phase offsets retain world anchoring through camera movement.
    worldPosition=vertex_position.xy-cameraCenter;
    waterDepth=WaterDepth;
    float field=.5+.25*sin(vertex_position.x*.14+vertex_position.y*.06+cloudPhase.x)
        +.16*sin(vertex_position.x*-.075+vertex_position.y*.17+cloudPhase.y)
        +.09*sin(vertex_position.x*.31+vertex_position.y*.23+cloudPhase.z);
    cloudLight=1.0-cloudStrength*smoothstep(.28,.76,field);
    float c=cos(cameraYaw),s=sin(cameraYaw);
    float dx=vertex_position.x-cameraCenter.x;
    float dz=vertex_position.y-cameraCenter.y;
    viewDistance=length(vec2(dx,dz));
    if (firstPerson) return riderProjection(transform_projection,vec3(vertex_position.x,WorldHeight,vertex_position.y));
    float right=dx*c-dz*s;
    float depth=dx*s+dz*c;
    vec2 screen=cameraScreenCenter+vec2(right*48.0*cameraZoom,
        (depth*29.0*cameraGroundScale-(WorldHeight-cameraFocusHeight)*22.0*cameraHeightScale)*cameraZoom);
    vec4 clip=transform_projection*vec4(screen,vertex_position.z,vertex_position.w);
    float order=depth*22.0*cameraHeightScale+(WorldHeight-cameraFocusHeight)*29.0*cameraGroundScale;
    clip.z=-order/groundDepthSpan*clip.w;
    return clip;
}
#endif
#ifdef PIXEL
extern Image materialAtlas;
extern float atlasInset;
extern float atlasInner;
extern float detailStrength;
extern vec3 seasonTint;
extern float litterSeasonShift;
extern float snowCoverage;
extern float viewRadius;
extern vec3 sunDirection;
extern vec3 sunColor;
extern float sunlight;
extern float ambientLight;
extern vec3 moonDirection;
extern vec3 moonColor;
extern float moonlight;
extern float waterDetail;
extern vec3 wavePhase;
extern vec2 ripplePhase;
extern vec3 waterView;
extern float waterRoughness;
vec3 waterSurface(vec3 base)
{
    vec2 p=worldPosition;
    // Broad ripples remain stable at distance; fine glints fade before aliasing.
    float a=dot(p,vec2(2.4,1.1))-wavePhase.x;
    float b=dot(p,vec2(-1.3,3.1))+wavePhase.y;
    float c=dot(p,vec2(.57,.83))-wavePhase.z;
    float fine=1.0-smoothstep(12.0,34.0,viewDistance);
    vec3 normal=normalize(vec3(cos(a)*.065+cos(b)*.035,1.0,cos(b)*.075+cos(c)*.035));
    float deep=1.0-exp(-max(waterDepth,0.0)*1.8);
    vec3 bed=mix(vec3(.24,.37,.32),vec3(.045,.18,.225),deep);
    float fresnel=.04+.34*pow(1.0-max(dot(normal,waterView),0.0),3.0);
    vec3 sky=vec3(.40,.57,.63);
    vec3 water=mix(bed,sky,fresnel);
    water+=vec3(.035,.055,.05)*(sin(a)*sin(b)*.5+.5)*fine;
    float crest=smoothstep(.94,.995,sin(p.y*11.0+p.x*.7+sin(c)*.8-ripplePhase.x))
        *smoothstep(.1,.85,sin(p.x*3.6+p.y*.6+ripplePhase.y));
    water+=vec3(.055,.085,.09)*crest*fine*(.7+waterRoughness*.3);
    float sunSpec=pow(max(dot(normal,normalize(sunDirection+waterView)),0.0),64.0);
    float moonSpec=pow(max(dot(normal,normalize(moonDirection+waterView)),0.0),80.0);
    water*=vec3(ambientLight)+sunColor*sunlight+moonColor*moonlight;
    water+=sunColor*sunSpec*sunlight*(.55-waterRoughness*.25)*fine;
    water+=moonColor*moonSpec*moonlight*.5*fine;
    // A narrow, broken shoreline ripple follows depth, rather than mesh edges.
    float edge=(1.0-smoothstep(.015,.22,waterDepth))*smoothstep(0.0,.035,waterDepth);
    float foam=edge*smoothstep(.32,.85,sin(c+sin(a)*.3))*.16;
    water+=vec3(.6,.72,.66)*foam*(ambientLight+sunlight);
    return mix(base,water,waterDetail*smoothstep(0.0,.045,waterDepth));
}
vec3 tile(float id,vec2 uv)
{
    // Mirrored coordinates are continuous at repeat boundaries, avoiding the
    // derivative jump / blurry mip seams caused by fract-based atlas wrapping.
    vec2 p=vec2(1.0)-abs(mod(uv+vec2(id*.193,id*.371),2.0)-vec2(1.0));
    vec2 origin=vec2(mod(id,4.0),floor(id/4.0))*.25;
    return Texel(materialAtlas,origin+vec2(atlasInset)+p*atlasInner).rgb*2.0;
}
vec3 family(float base,float maximum,float value,vec2 uv)
{
    value=clamp(value,0.0,maximum);float lo=floor(value);float blend=value-lo;
    vec3 a=tile(base+lo,uv);
    if (blend<0.001) return a;
    return mix(a,tile(base+min(lo+1.0,maximum),uv),blend);
}
vec4 effect(vec4 color,Image image,vec2 uv,vec2 screen_coords)
{
    vec3 surface=color.rgb;
    if (materialWeights.w>=0.001) {
        vec3 weights=materialWeights.xyz/max(dot(materialWeights.xyz,vec3(1.0)),.001);
        vec3 detail=vec3(0.0);
        if (weights.x>.001) detail+=family(0.0,3.0,materialVariants.x,groundTextureUV)*weights.x;
        if (weights.y>.001) detail+=family(4.0,5.0,materialVariants.y,groundTextureUV+vec2(.37,.19))*weights.y;
        if (weights.z>.001) {
            float deciduous=clamp(materialVariants.z*.5,0.0,1.0);
            float litter=materialVariants.z+litterSeasonShift*deciduous;
            detail+=family(10.0,5.0,litter,vec2(-groundTextureUV.y,groundTextureUV.x))*weights.z;
        }
        surface*=mix(vec3(1.0),detail,detailStrength*materialWeights.w);
        float land=clamp(materialWeights.w,0.0,1.0);
        surface*=mix(vec3(1.0),seasonTint,land);
        surface=mix(surface,vec3(0.84,0.89,0.90),clamp(snowCoverage*land,0.0,0.78));
    }
    float diffuse=max(dot(normalize(surfaceNormal),normalize(sunDirection)),0.0);
    float moonDiffuse=max(dot(normalize(surfaceNormal),normalize(moonDirection)),0.0);
    surface*=vec3(ambientLight)+sunColor*(sunlight*diffuse)+moonColor*(moonlight*moonDiffuse);
    if (waterDepth>0.0 && waterDetail>0.0) surface=waterSurface(surface);
    surface*=cloudLight;
    if(firstPerson && rideHeadlight) surface=riderLight(surface,worldPosition);
    surface=mix(surface,firstPerson ? vec3(.57,.68,.70) : vec3(0.22,0.27,0.26),smoothstep(viewRadius*.74,viewRadius,viewDistance));
    return vec4(surface,color.a);
}
#endif
