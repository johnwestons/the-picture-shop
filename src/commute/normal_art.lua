-- Reuse the selected worker's actual sprites before dressing and after removal.
local Config=require('src.config')
local Colorways=require('src.rabbit_colorways')
local Animation=require('src.character_animation')
local Rider=require('src.commute.rider')
local Art={}
function Art.appearance(player)
    player=player or {}
    local fur,overalls=Colorways.normalize(player.furColorway,player.overallsColorway)
    return {character=Config.characters[player.character] and player.character or Config.player.character,
        furColorway=fur,overallsColorway=overalls}
end
function Art.valid(a)
    if a==nil then return true end
    if type(a)~='table' or not Config.characters[a.character] then return false end
    local fur,overalls=Colorways.normalize(a.furColorway,a.overallsColorway)
    return a.furColorway==fur and a.overallsColorway==overalls
end
function Art.selection(actor,camera,visual)
    local direction=camera:headingDirection(actor.heading)
    local mirror=({west='east',northwest='northeast',southwest='southeast'})[direction]
    local speed=visual and visual.speed or actor.speed or 0
    local action=speed>.01 and 'walk' or 'idle'
    local authored=mirror or direction
    if authored~='east' then action=action..'_'..authored end
    return action,mirror and -1 or 1,visual and visual.distance or actor.distance or 0
end
function Art.draw(assets,actor,camera,world,appearance,visual,clock,opacity)
    local a=Art.appearance(appearance)
    local action,mirror,distance=Art.selection(actor,camera,visual)
    if not assets.hasAction(a.character,action) then action='idle' end
    if assets.resolveAction then action=assets.resolveAction(a.character,action) end
    local _,_,count=assets.get(a.character,action,1)
    local frame=Animation.frameForPlayerAction(action,count or 1,distance/Rider.FRAME_DISTANCE,
        clock or 0,1,Config.player.idleAnimationRate)
    local image,quad=assets.get(a.character,action,frame)
    if not image or not quad then return false end
    local ax,ay=assets.getAnchor(a.character,action,frame)
    local x,y=camera:screen(actor.x,actor.z,actor.h or world:supportHeight(actor.x,actor.z))
    local scale=Config.player.drawScale*.7*camera.zoom*assets.getNormalization(a.character,action)
    love.graphics.setColor(1,1,1,opacity or 1)
    if a.character=='rabbit-worker' then
        Colorways.draw(image,quad,x,y,0,scale*mirror,scale,ax,ay,0,0,a.furColorway,a.overallsColorway,opacity)
    else love.graphics.draw(image,quad,x,y,0,scale*mirror,scale,ax,ay) end
    return true
end
return Art
