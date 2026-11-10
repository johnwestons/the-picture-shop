local Bays=require('src.room_loading_bays')
local Dock=require('src.dock_renderer')
local Renderer={}
function Renderer.clear()Dock.clear()end
function Renderer.truckTransform(truck)
    local progress=truck:visualTravelProgress()
    return {x=726+(1-progress)*120,y=332-(1-progress)*95,scale=.76,progress=progress}
end
function Renderer.draw(world,assets,state,scene,characters,players,context)
    if not Bays.owns(state,scene)then return end
    local door=world.doorForScene(scene);local a=Bays.aperture
    local g=love.graphics;g.push('all')
    -- The decorative end bay has no stock slots. Its registered aperture
    -- shares the physical loading apron used by the warehouse's truck queue.
    g.setColor(.23,.22,.19);g.polygon('fill',769,91,936,117,936,290,769,264)
    local function truckView()
        local truck=world.truck
        if truck.sceneId~=scene or not truck:isVisible()then return end
        local outline={};for _,p in ipairs(a)do outline[#outline+1]=p.x;outline[#outline+1]=p.y end
        g.stencil(function()g.polygon('fill',unpack(outline))end,'replace',1);g.setStencilTest('greater',0)
        local image=assets.get('deliveryTruck');local cargo=assets.get('truckCargoDoor')
        local sprite=assets.getQuad('truckCargoDoor'..truck:cargoFrame())
        local transform=Renderer.truckTransform(truck)
        g.setColor(1,1,1,1)
        if image then g.draw(image,transform.x,transform.y,0,transform.scale,transform.scale,256,430)end
        if cargo and sprite then g.draw(cargo,sprite.quad,transform.x,transform.y,0,transform.scale,transform.scale,256,430)end
        g.setStencilTest()
    end
    Dock.draw(world,assets,characters,state,players,context,scene,a,truckView)
    g.setColor(.80,.68,.22);g.setLineWidth(3)
    g.line(778,238,778,265);g.line(927,261,927,287)
    g.setColor(.07,.10,.11);g.rectangle('fill',753,208,14,25,2)
    g.setColor(door.state=='closed' and .88 or .30,door.state=='closed' and .33 or .91,.25)
    g.circle('fill',760,218,3)
    g.setColor(.05,.08,.09,.95);g.rectangle('fill',767,78,174,22,3)
    g.setColor(.95,.86,.58)
    g.printf(world.truck.sceneId==scene and world.truck.jobId or 'TRUCK LOADING',772,83,164,'center')
    g.pop()
end
return Renderer
