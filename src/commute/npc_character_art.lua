-- Renders commuter pedestrians from their existing authored character art.
local NormalArt=require('src.commute.normal_art')
local Art={}

function Art.draw(characterAssets,actor,character,camera,world,clock)
    if character=='mechanic-raccoon' then
        local x,y=camera:screen(actor.x,actor.z,actor.h or world:supportHeight(actor.x,actor.z))
        local heading=actor.heading or 0
        local sourceActor={x=x,y=y,intentX=math.cos(heading),intentY=math.sin(heading),
            moving=(actor.speed or 0)>.01,animationDistance=(actor.distance or 0)*96,
            idleClock=clock or 0}
        return require('src.warehouse_renderer').drawDeliveryDriver(sourceActor,camera.zoom)
    end
    return NormalArt.draw(characterAssets,actor,camera,world,{character=character},nil,clock)
end

return Art
