-- Compile programs during the existing startup load, never on a first door
-- opening. Closed docks allocate no exterior canvases or geometry.
local Programs={}
local pool
local boundsPixel=[[
#ifdef PIXEL
extern vec2 dockOriginDelta;
extern vec2 dockForward;
extern vec2 dockExtent;
void clipDock(vec2 position) {
    vec2 delta=position-dockOriginDelta;
    float forward=dot(delta,dockForward);
    float side=dot(delta,vec2(-dockForward.y,dockForward.x));
    if(forward<0.0 || forward>dockExtent.x || abs(side)>dockExtent.y)discard;
}
#endif
]]
local spriteVertex=[[
#ifdef VERTEX
extern float spriteDepth;
vec4 position(mat4 projection,vec4 vertex) {
    vec4 clip=projection*vertex;clip.z=spriteDepth*clip.w;return clip;
}
#endif
]]
local spritePixel=[[
#ifdef PIXEL
extern vec3 exteriorTint;
extern float exteriorOpacity;
vec4 effect(vec4 color,Image image,vec2 uv,vec2 pixel) {
    vec4 surface=Texel(image,uv)*color;
    surface.a*=exteriorOpacity;
    if(surface.a<.04)discard;
    surface=applyRabbitColorways(surface);
    return vec4(surface.rgb*exteriorTint,surface.a);
}
#endif
]]
function Programs.prepare()
    if pool then return pool end
    local prefix=love.filesystem.read('src/commute/perspective.glsl')..'\n'
    local ground=love.filesystem.read('src/commute/vendor/ground.glsl')
    -- The apron uses the outdoor renderer's asphalt color. Give its otherwise
    -- flat hardscape a restrained aggregate grain in this close doorway view;
    -- paint and the atlas-based grass/dirt materials retain their own finish.
    ground=ground:gsub('vec3 surface=color%.rgb;',function()return [[
    clipDock(worldPosition);
    vec3 surface=color.rgb;
    if(materialWeights.w<.001 && max(color.r,max(color.g,color.b))<.7) {
        vec2 p=worldPosition;
        float grain=sin(p.x*63.0+sin(p.y*47.0))*sin(p.y*59.0+cos(p.x*41.0));
        float wear=sin(p.x*1.7+p.y*.6)*sin(p.y*2.1-p.x*.4);
        surface*=1.0+grain*.075+wear*.025;
    }
    ]]end)
    local structure=love.filesystem.read('src/commute/structure.glsl'):gsub('vec3 normal=normalize%(structureNormal%);',
        'clipDock(structureDelta); vec3 normal=normalize(structureNormal);')
    pool={ground=love.graphics.newShader(prefix..boundsPixel..ground),
        structure=love.graphics.newShader(prefix..boundsPixel..structure),
        sprite=love.graphics.newShader(spriteVertex..require('src.rabbit_colorways').blendShaderSource()..spritePixel)}
    return pool
end
return Programs
