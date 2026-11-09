local Style={
    DEFAULT_COLOR="yellow",
    DEFAULT_STYLE="filled",
    COLOR_ORDER={"yellow","red","green","blue"},
    COLORS={
        yellow={.78,.73,.57},
        red={.78,.43,.43},
        green={.43,.66,.46},
        blue={.39,.58,.78},
    },
    LABELS={yellow="YELLOW",red="RED",green="GREEN",blue="BLUE"},
    STYLES={"filled","outline"},
    STYLE_LABELS={filled="FILLED",outline="OUTLINE"},
}
local shaderStates=setmetatable({}, {__mode="k"})

local function validColor(color)
    return type(color)=="string" and Style.COLORS[color]~=nil
end

function Style.normalize(color,mode)
    if not validColor(color) then color=Style.DEFAULT_COLOR end
    if mode~="outline" then mode=Style.DEFAULT_STYLE end
    return color,mode
end

function Style.resolve(settings)
    settings=settings or {}
    local color,mode=Style.normalize(settings.occlusionHighlightColor,
        settings.occlusionHighlightStyle)
    return {colorName=color,color=Style.COLORS[color],style=mode,outlineOnly=mode=="outline"}
end

function Style.send(shader,enabled,settings)
    if not shader then return end
    local resolved=settings and settings.color and settings.outlineOnly~=nil
        and settings or Style.resolve(settings)
    local state=shaderStates[shader]
    if not state then
        state={
            hasMode=shader:hasUniform("silhouetteMode"),
            hasColor=shader:hasUniform("silhouetteColor"),
            hasOutline=shader:hasUniform("silhouetteOutlineOnly"),
        }
        shaderStates[shader]=state
    end
    local mode=enabled==true
    local outline=mode and resolved.outlineOnly or false
    if state.hasMode and state.mode~=mode then
        shader:send("silhouetteMode",mode);state.mode=mode
    end
    if state.hasColor and state.color~=resolved.color then
        shader:send("silhouetteColor",resolved.color);state.color=resolved.color
    end
    if state.hasOutline and state.outline~=outline then
        shader:send("silhouetteOutlineOnly",outline);state.outline=outline
    end
end

Style.shaderFunctions=[[
extern bool silhouetteOutlineOnly;
bool silhouetteOutlinePixel(Image source,vec2 uv) {
    float sourceAlpha=Texel(source,uv).a;
    vec2 dx=dFdx(uv)*1.5;
    vec2 dy=dFdy(uv)*1.5;
    float neighborAlpha=1.0;
    neighborAlpha=min(neighborAlpha,Texel(source,uv+dx).a);
    neighborAlpha=min(neighborAlpha,Texel(source,uv-dx).a);
    neighborAlpha=min(neighborAlpha,Texel(source,uv+dy).a);
    neighborAlpha=min(neighborAlpha,Texel(source,uv-dy).a);
    neighborAlpha=min(neighborAlpha,Texel(source,uv+dx+dy).a);
    neighborAlpha=min(neighborAlpha,Texel(source,uv+dx-dy).a);
    neighborAlpha=min(neighborAlpha,Texel(source,uv-dx+dy).a);
    neighborAlpha=min(neighborAlpha,Texel(source,uv-dx-dy).a);
    // Alpha-matted sprites often have a soft fringe rather than a fully
    // transparent texel immediately beside the solid shape. Keep those edge
    // pixels so outline mode remains visible after the filled pixels discard.
    return sourceAlpha>=0.06 && neighborAlpha<0.55;
}
float silhouetteOutputAlpha(float sourceAlpha) {
    // Preserve antialiasing for filled mode; give outline pixels enough alpha
    // to remain readable even when their source edge pixels are faint.
    return silhouetteOutlineOnly ? .78 : sourceAlpha*.78;
}
]]

return Style
