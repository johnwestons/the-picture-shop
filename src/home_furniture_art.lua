local Catalog=require("src.home_furniture_catalog")
local Art={};local cache={};local shader
local function resource(kind)
    if cache[kind] then return cache[kind] end
    local entry=Catalog.ITEMS[kind];if not entry then return nil end
    local image=love.graphics.newImage("assets/generated/home-furniture-v1/"..entry.art)
    image:setFilter("linear","linear");local frames={}
    for i=1,8 do
        local column=(i-1)%4;local x,width=column*384,384;local y,height=math.floor((i-1)/4)*512,512
        if kind=="bed" then x=({0,448,704,1152})[column+1];width=({448,256,448,384})[column+1] end
        if entry.columns then x,width=unpack(entry.columns[column+1]) end
        if entry.rows then y,height=unpack(entry.rows[math.floor((i-1)/4)+1]) end
        frames[i]=love.graphics.newQuad(x,y,width,height,image:getDimensions())
    end
    cache[kind]={image=image,frames=frames};return cache[kind]
end
function Art.draw(item,opacity)
    local entry=Catalog.ITEMS[item.kind];local asset=resource(item.kind);if not asset then return end
    shader=shader or love.graphics.newShader([[vec4 effect(vec4 c,Image t,vec2 uv,vec2 sc){ vec4 p=Texel(t,uv); if(p.a<0.18) discard; return p*c; }]])
    local frame=entry.frames[item.direction];local pivot=entry.pivots[frame]
    love.graphics.push("all");love.graphics.setColor(1,1,1,opacity or 1);love.graphics.setShader(shader)
    love.graphics.draw(asset.image,asset.frames[frame],item.x,item.y,0,entry.scale,entry.scale*(entry.frameScaleY and entry.frameScaleY[frame] or 1),pivot[1],pivot[2])
    love.graphics.setShader()
    if entry.television and item.powered and entry.screen[frame] then
        local points={};for _,point in ipairs(entry.screen[frame]) do
            points[#points+1]=item.x+(point[1]-pivot[1])*entry.scale
            points[#points+1]=item.y+(point[2]-pivot[2])*entry.scale
        end
        love.graphics.setColor(.30,.65,.72,(opacity or 1)*.5);love.graphics.polygon("fill",points)
    end
    if item.kind=="cup" and item.contents and (item.contents.water or 0)>0 then
        love.graphics.setColor(.22,.60,.72,(opacity or 1)*.9)
        love.graphics.ellipse("fill",item.x+(190-pivot[1])*entry.scale,item.y+(176-pivot[2])*entry.scale,95*entry.scale,32*entry.scale)
    elseif entry.light and item.lit then
        -- State overlays stay procedural and separate from the generated atlas.
        local light=entry.light;local point=light.points and light.points[frame]
        local x=item.x+(point and (point[1]-pivot[1])*entry.scale or 0)
        local y=item.y+(point and (point[2]-pivot[2])*entry.scale or -light.height)
        local radius=light.radius
        love.graphics.setBlendMode("add")
        for i=3,1,-1 do
            love.graphics.setColor(.5,.34,.12,(opacity or 1)*.055)
            love.graphics.ellipse("fill",x,y,(17+i*5)*radius,(10+i*4)*radius)
        end
        love.graphics.setBlendMode("alpha");love.graphics.setColor(1,.82,.43,(opacity or 1)*.6)
        love.graphics.ellipse("fill",x,y,9*radius,5*radius)
    end
    love.graphics.pop()
end
function Art.bounds(item)
    local entry=Catalog.ITEMS[item.kind];local frame=entry.frames[item.direction];local pivot=entry.pivots[frame]
    local width=item.kind=="bed" and ({448,256,448,384})[(frame-1)%4+1] or 384
    if entry.columns then width=entry.columns[(frame-1)%4+1][2] end
    local sy=entry.scale*(entry.frameScaleY and entry.frameScaleY[frame] or 1)
    local height=entry.rows and entry.rows[math.floor((frame-1)/4)+1][2] or 512
    return {item.x-pivot[1]*entry.scale,item.y-pivot[2]*sy,item.x+(width-pivot[1])*entry.scale,item.y+(height-pivot[2])*sy}
end
function Art.drawRegion(item,polygons)
    if not polygons then return end
    local entry=Catalog.ITEMS[item.kind];local asset=resource(item.kind);local frame=entry.frames[item.direction]
    asset.regions=asset.regions or {}
    if not asset.regions[frame] then
        local quad=asset.frames[frame];local qx,qy=quad:getViewport();local vertices={}
        for _,polygon in ipairs(polygons) do for _,triangle in ipairs(love.math.triangulate(polygon)) do
            for i=1,6,2 do
                local x,y=triangle[i],triangle[i+1];vertices[#vertices+1]={x,y,(qx+x)/1536,(qy+y)/1024,1,1,1,1}
            end
        end end
        local mesh=love.graphics.newMesh(vertices,"triangles","static");mesh:setTexture(asset.image);asset.regions[frame]=mesh
    end
    local pivot=entry.pivots[frame]
    love.graphics.push("all");love.graphics.setColor(1,1,1,1);love.graphics.setShader(shader)
    love.graphics.draw(asset.regions[frame],item.x,item.y,0,entry.scale,entry.scale*(entry.frameScaleY and entry.frameScaleY[frame] or 1),pivot[1],pivot[2])
    love.graphics.pop()
end
function Art.release()
    for _,asset in pairs(cache) do
        for _,mesh in pairs(asset.regions or {}) do mesh:release() end
        asset.image:release();for _,q in ipairs(asset.frames) do q:release() end
    end
    cache={};if shader then shader:release();shader=nil end
end
function Art.icon(kind,x,y,size)
    local item={kind=kind,x=0,y=0,direction="southeast"};local bounds=Art.bounds(item)
    local scale=size/math.max(bounds[3]-bounds[1],bounds[4]-bounds[2])
    item.x,item.y=-(bounds[1]+bounds[3])/2,-(bounds[2]+bounds[4])/2
    love.graphics.push("all");love.graphics.translate(x,y);love.graphics.scale(scale);Art.draw(item);love.graphics.pop()
end
return Art
