-- Directional sink-action presentation. Gameplay rewards stay in home_residents
-- and home_chores; this module only draws the existing shared activity.
local R=require("src.home_washing_registration")
local Colorways=require("src.rabbit_colorways")
local Art={}
local root="assets/generated/home-washing-v2/"
local bodies,props={},{}
local bodyShader,propShader
local stanceShifts={{0,0},{-3,0},{3,0},{0,-3},{0,3},{-6,0},{6,0},{0,-6},{0,6},
    {-9,0},{9,0},{0,-9},{0,9},{-12,0},{12,0},{0,-12},{0,12},{-15,0},{15,0},{0,-15},{0,15}}

local function loadBody(file)
    if bodies[file] then return bodies[file] end
    local image=love.graphics.newImage(root..file);image:setFilter("linear","linear")
    local width,height=image:getDimensions()
    assert(width==1536 and height==1024,"Unregistered sink-action source dimensions: "..file)
    local asset={image=image,quads={},handMeshes={}}
    for index,direction in ipairs(R.order) do
        local view=R.views[direction]
        asset.quads[index]=love.graphics.newQuad(view.sourceX,view.sourceY,R.cellWidth,R.cellHeight,width,height)
    end
    bodies[file]=asset
    return asset
end

local function loadProp(kind)
    if props[kind] then return props[kind] end
    local file=kind=="plate" and "plate-eight-directions.png" or "mug-eight-directions.png"
    local image=love.graphics.newImage(root..file);image:setFilter("linear","linear")
    local width,height=image:getDimensions()
    assert(width==1536 and height==1024,"Unregistered sink-action prop dimensions: "..file)
    local asset={image=image,quads={}}
    for index,direction in ipairs(R.order) do
        local view=R.views[direction]
        asset.quads[index]=love.graphics.newQuad(view.sourceX,view.sourceY,R.cellWidth,R.cellHeight,width,height)
    end
    props[kind]=asset
    return asset
end

local function bodyFile(kind,phase)
    local files=assert(R.bodyFiles[kind],"Unknown sink action: "..tostring(kind))
    return files[math.min(phase,#files)]
end

local function handMesh(asset,kind,direction)
    local key=kind..":"..direction
    if asset.handMeshes[key] then return asset.handMeshes[key] end
    local view=R.views[direction];local centres=view.hands[kind];local vertices={}
    local function vertex(x,y)
        return {x,y,(view.sourceX+x)/1536,(view.sourceY+y)/1024,1,1,1,1}
    end
    for _,centre in ipairs(centres) do
        for n=0,15 do
            local a,b=n*math.pi/8,(n+1)*math.pi/8
            vertices[#vertices+1]=vertex(centre[1],centre[2])
            vertices[#vertices+1]=vertex(centre[1]+math.cos(a)*19,centre[2]+math.sin(a)*16)
            vertices[#vertices+1]=vertex(centre[1]+math.cos(b)*19,centre[2]+math.sin(b)*16)
        end
    end
    local mesh=love.graphics.newMesh(vertices,"triangles","static");mesh:setTexture(asset.image)
    asset.handMeshes[key]=mesh
    return mesh
end

function Art.frame(kind,seconds)
    local files=R.bodyFiles[kind]
    if not files or #files<2 then return 1 end
    return math.floor(math.max(0,seconds or 0)*(R.fps[kind] or 4))%2+1
end

local function inside(polygon,x,y)
    local hit=false;local j=#polygon-1
    for i=1,#polygon,2 do
        local ax,ay,bx,by=polygon[i],polygon[i+1],polygon[j],polygon[j+1]
        if (ay>y)~=(by>y) and x<(bx-ax)*(y-ay)/(by-ay)+ax then hit=not hit end
        j=i
    end
    return hit
end

function Art.standingPose(state,fixtureName,kind)
    kind=kind or "wash"
    local Layout=require("src.home_layouts");local entry=Layout.get(state)
    local fixture=entry.fixtures[fixtureName]
    if not fixture then return nil end
    local x,y=Layout.toWorld(unpack(fixture.approach))
    local direction=require("src.character_animation").authoredDirection(
        fixture.x-fixture.approach[1],(fixture.y-fixture.approach[2])*2)
    local assets={getData=function()return Layout.mask(state.home.apartmentId) end}
    local Navigation=require("src.navigation");local obstacles=require("src.home_furniture").obstacles(state)
    local fallbackX,fallbackY
    for _,shift in ipairs(stanceShifts) do
        local px,py=x+shift[1],y+shift[2]
        if Navigation.isWalkable(assets,px,py,obstacles) then
            fallbackX,fallbackY=fallbackX or px,fallbackY or py
            local view=R.views[direction]
            local hands=view.hands[kind]
            local hx=(hands[1][1]+hands[2][1])/2
            local hy=(hands[1][2]+hands[2][2])/2
            local sourceX,sourceY=Layout.toSource(px+(hx-view.foot[1])*R.bodyScale,
                py+(hy-view.foot[2])*R.bodyScale)
            if inside(fixture.outline,sourceX,sourceY) then return px,py,direction end
        end
    end
    if fallbackX then return fallbackX,fallbackY,direction end
end

local function worldHands(x,y,direction,kind)
    local view=R.views[direction];local hands=view.hands[kind]
    local first,second=hands[1],hands[2]
    return x+(first[1]-view.foot[1])*R.bodyScale,
        y+(first[2]-view.foot[2])*R.bodyScale,
        x+(second[1]-view.foot[1])*R.bodyScale,
        y+(second[2]-view.foot[2])*R.bodyScale
end

local function drawWater(kind,x,y,seconds)
    love.graphics.setShader();love.graphics.setColor(.52,.82,.95,.88)
    for i=1,3 do
        local phase=(math.max(0,seconds or 0)*5+i*3)%10
        local px=x+(i-2)*2.4
        if kind=="cupfill" then
            love.graphics.line(px,y-16,px,y-5+phase*.25)
            love.graphics.circle("fill",px,y-5+phase*.25,1.1)
        else
            love.graphics.circle("fill",px,y-3-phase*.35,1.2-(phase*.025))
        end
    end
end

function Art.draw(kind,direction,phase,x,y,player,seconds)
    local view=assert(R.views[direction]);phase=phase or 1
    local body=loadBody(bodyFile(kind,phase))
    local hx1,hy1,hx2,hy2=worldHands(x,y,direction,kind)
    local propKind=(kind=="dishes" and "plate") or (kind=="cupwash" or kind=="cupfill") and "mug"
    local prop=propKind and loadProp(propKind)
    -- Prop centers sit just below the registered hands so fingers remain visible.
    local px,py=(hx1+hx2)/2,(hy1+hy2)/2+(propKind=="plate" and 3 or 0)
    bodyShader=bodyShader or love.graphics.newShader(Colorways.blendShaderSource()..[[
        vec4 effect(vec4 c,Image t,vec2 uv,vec2 s){vec4 p=Texel(t,uv);if(p.a<.18)discard;return applyRabbitColorways(p)*c;}
    ]])
    propShader=propShader or love.graphics.newShader([[vec4 effect(vec4 c,Image t,vec2 uv,vec2 s){vec4 p=Texel(t,uv);if(p.a<.18)discard;return p*c;} ]])
    love.graphics.push("all");love.graphics.setColor(1,1,1,1)
    local function drawBody()
        love.graphics.setShader(bodyShader)
        Colorways.configureShader(bodyShader,player and player.furColorway,player and player.overallsColorway)
        love.graphics.draw(body.image,body.quads[view.index],x,y,0,R.bodyScale,R.bodyScale,view.foot[1],view.foot[2])
    end
    local function drawProp()
        if not prop then return end
        love.graphics.setShader(propShader)
        local scale=R.propScale[propKind]
        love.graphics.draw(prop.image,prop.quads[view.index],px,py,0,scale,scale,192,256)
    end
    if view.rear then drawProp();drawBody()
    else
        drawBody();drawProp()
        if prop then
            love.graphics.setShader(bodyShader)
            Colorways.configureShader(bodyShader,player and player.furColorway,player and player.overallsColorway)
            love.graphics.draw(handMesh(body,kind,direction),x,y,0,R.bodyScale,R.bodyScale,view.foot[1],view.foot[2])
        end
    end
    local hx,hy=(hx1+hx2)/2,(hy1+hy2)/2
    drawWater(kind,hx,hy,seconds)
    love.graphics.pop()
end

function Art.release()
    for _,asset in pairs(bodies) do
        asset.image:release()
        for _,quad in ipairs(asset.quads) do quad:release() end
        for _,mesh in pairs(asset.handMeshes) do mesh:release() end
    end
    for _,asset in pairs(props) do
        asset.image:release();for _,quad in ipairs(asset.quads) do quad:release() end
    end
    if bodyShader then bodyShader:release() end
    if propShader then propShader:release() end
    bodies,props,bodyShader,propShader={},{},nil,nil
end

return Art
