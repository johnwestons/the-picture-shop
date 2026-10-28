local Bays=require("src.room_loading_bays")
local Renderer={}
local shutter
function Renderer.clear()
    if shutter then shutter:release();shutter=nil end
end
local function polygon(points)
    local out={};for _,p in ipairs(points) do out[#out+1]=p.x;out[#out+1]=p.y end
    return out
end
function Renderer.truckTransform(truck)
    local progress=truck:visualTravelProgress()
    return {
        x=726+(1-progress)*120,
        y=332-(1-progress)*95,
        scale=.76,
        progress=progress,
    }
end
function Renderer.draw(world,assets,state,scene)
    if not Bays.owns(state,scene) then return end
    local door=world.doorForScene(scene)
    local a=Bays.aperture
    local outline=polygon(a)
    love.graphics.push("all")
    -- The sixth decorative rack bay has no stock slots. Replace that end
    -- section with the loading door; all fifteen registered slots stay put.
    love.graphics.setColor(.23,.22,.19)
    love.graphics.polygon("fill",769,91,936,117,936,290,769,264)
    love.graphics.setColor(.08,.10,.12)
    love.graphics.polygon("fill",unpack(outline))
    love.graphics.stencil(function() love.graphics.polygon("fill",unpack(outline)) end,"replace",1)
    love.graphics.setStencilTest("greater",0)
    love.graphics.setColor(.28,.31,.32)
    love.graphics.rectangle("fill",770,230,170,60)
    love.graphics.setColor(.86,.78,.48)
    love.graphics.setLineWidth(3)
    love.graphics.line(780,255,924,277)
    local truck=world.truck
    if truck.sceneId==scene and truck:isVisible() then
        local image=assets.get("deliveryTruck")
        local cargo=assets.get("truckCargoDoor")
        local sprite=assets.getQuad("truckCargoDoor"..truck:cargoFrame())
        local transform=Renderer.truckTransform(truck)
        love.graphics.setColor(1,1,1)
        if image then love.graphics.draw(image,transform.x,transform.y,0,transform.scale,transform.scale,256,430) end
        if cargo and sprite then love.graphics.draw(cargo,sprite.quad,transform.x,transform.y,0,transform.scale,transform.scale,256,430) end
    end
    local image=assets.get("warehouse")
    if image then
        local source=require("src.config").truck.aperture
        local vertices={}
        for i,p in ipairs(a) do
            local q=source[i]
            vertices[i]={p.x,p.y-(door.progress or 0)*170,q.x/960,q.y/678,1,1,1,1}
        end
        if not shutter then shutter=love.graphics.newMesh(vertices,"fan","dynamic")
        else shutter:setVertices(vertices) end
        shutter:setTexture(image);love.graphics.setColor(1,1,1);love.graphics.draw(shutter)
    end
    love.graphics.setStencilTest()
    love.graphics.setColor(.10,.13,.15);love.graphics.setLineWidth(7)
    love.graphics.polygon("line",unpack(outline))
    love.graphics.setColor(.80,.68,.22);love.graphics.setLineWidth(3)
    love.graphics.line(778,238,778,265);love.graphics.line(927,261,927,287)
    love.graphics.setColor(.07,.10,.11);love.graphics.rectangle("fill",753,208,14,25,2)
    love.graphics.setColor(door.state=="closed" and .88 or .30,door.state=="closed" and .33 or .91,.25)
    love.graphics.circle("fill",760,218,3)
    love.graphics.setColor(.05,.08,.09,.95);love.graphics.rectangle("fill",767,78,174,22,3)
    love.graphics.setColor(.95,.86,.58)
    love.graphics.printf(truck.sceneId==scene and truck.jobId or "TRUCK LOADING",772,83,164,"center")
    love.graphics.pop()
end
return Renderer
