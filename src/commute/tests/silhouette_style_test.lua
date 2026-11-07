local Style=require('src.commute.silhouette_style')
local Test={}

function Test.run(check)
    local g=love.graphics
    local sourceData=love.image.newImageData(32,32)
    for y=6,25 do
        for x=6,25 do
            local edge=x==6 or x==25 or y==6 or y==25
            sourceData:setPixel(x,y,1,1,1,edge and .12 or 1)
        end
    end
    local source=g.newImage(sourceData)
    source:setFilter('linear','linear')
    local canvas=g.newCanvas(32,32)
    local shader=g.newShader([[
extern bool silhouetteMode;
extern vec3 silhouetteColor;
]]..Style.shaderFunctions..[[
vec4 effect(vec4 color,Image tex,vec2 uv,vec2 pixel) {
    vec4 surface=Texel(tex,uv)*color;
    if(surface.a<.02) discard;
    if(silhouetteMode) {
        if(silhouetteOutlineOnly && !silhouetteOutlinePixel(tex,uv)) discard;
        return vec4(silhouetteColor,silhouetteOutputAlpha(surface.a));
    }
    return surface;
}
]])

    local function sample(style)
        Style.send(shader,true,{occlusionHighlightColor='yellow',occlusionHighlightStyle=style})
        g.push('all');g.setCanvas(canvas);g.origin();g.setScissor();g.clear(0,0,0,0)
        g.setBlendMode('alpha','alphamultiply');g.setColor(1,1,1,1);g.setShader(shader)
        g.draw(source,0,0);g.pop()
        local pixels=canvas:newImageData()
        local _,_,_,edgeAlpha=pixels:getPixel(7,16)
        local _,_,_,centerAlpha=pixels:getPixel(16,16)
        pixels:release()
        return edgeAlpha,centerAlpha
    end

    local outlineEdge,outlineCenter=sample('outline')
    local filledEdge,filledCenter=sample('filled')
    check('silhouette_outline_keeps_antialiased_edge_visible_without_filling_center',
        outlineEdge>.5 and outlineCenter==0,
        ('outline edge alpha=%.3f center alpha=%.3f'):format(outlineEdge,outlineCenter))
    check('silhouette_filled_mode_still_fills_player',filledCenter>.7 and filledEdge>.5,
        ('filled edge alpha=%.3f center alpha=%.3f'):format(filledEdge,filledCenter))

    shader:release();canvas:release();source:release();sourceData:release()
end

return Test
