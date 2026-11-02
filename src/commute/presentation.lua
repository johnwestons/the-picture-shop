-- Procedural fallback used while the rider changes gear. Stable suited walking
-- uses the production directional character strips registered in walker_art.
local Gear=require('src.commute.gear')
local P={}
local roadMirrorFor={west='east',northwest='northeast',southwest='southeast'}
function P.foot(x,y,scale,gear,distance,speed,presentation)
    local g=love.graphics;local pose,progress=Gear.pose(gear)
    if presentation then pose,progress=presentation.pose,presentation.progress;distance,speed=presentation.distance,presentation.speed end
    local suited=gear.outfit=='geared' or pose=='zip_up' or pose=='boots_gloves' or pose=='helmet_on'
    local helmet=gear.outfit=='geared' and pose~='unzip' and pose~='suit_off'
    if pose=='helmet_on' then helmet=true end
    if pose=='helmet_off' then helmet=progress<.8 end
    local step=(speed or 0)>.01 and math.sin((distance or 0)/.13*math.pi/4)*4 or 0
    g.push();g.translate(x,y);g.scale(scale)
    g.setColor(.03,.04,.03,.25);g.ellipse('fill',0,-1,14,4)
    g.setColor(suited and .22 or .17,suited and .16 or .32,suited and .10 or .55)
    g.rectangle('fill',-10,-40,20,28,5)
    g.setColor(.16,.11,.07);g.rectangle('fill',-11,-14+step,9,13,3);g.rectangle('fill',2,-14-step,9,13,3)
    g.ellipse('fill',-7,-3+step,8,4);g.ellipse('fill',7,-3-step,8,4)
    g.setColor(.35,.24,.14);g.setLineWidth(6);g.line(-10,-37,-15,-22-step);g.line(10,-37,15,-22+step)
    if suited then
        g.setColor(.72,.62,.40);g.setLineWidth(1.4)
        local closure=pose=='zip_up' and progress or pose=='unzip' and 1-progress or 1
        g.line(0,-16,0,-16-24*closure)
        if pose=='zip_up' or pose=='unzip' then g.setColor(.27,.18,.10);g.circle('fill',0,-16-24*closure,4) end
    end
    local lift=pose=='helmet_on' and (1-progress)*12 or pose=='helmet_off' and progress*12 or 0
    g.setColor(helmet and .41 or .78,helmet and .43 or .38,helmet and .24 or .12)
    if not helmet then
        g.ellipse('fill',-6,-64,4,13);g.ellipse('fill',5,-64,4,13)
    end
    g.circle('fill',0,-50-lift,14)
    if helmet then
        g.setColor(.045,.065,.06);g.rectangle('fill',-11,-55-lift,22,8,3)
        g.setColor(.64,.60,.39);g.setLineWidth(1);g.rectangle('line',-11,-55-lift,22,8,3)
    end
    g.pop();g.setLineWidth(1);g.setColor(1,1,1)
end
local function drawSuitedWalker(characterAssets,player,opacity)
    if not characterAssets then return false end
    local character="suited-rider"
    local animation=require("src.character_animation")
    local Config=require("src.config")
    local action,mirror
    if player.moving then
        action,mirror=animation.actorWalkAction(player)
    else
        action,mirror=animation.directionalIdleAction(player.intentX,player.intentY)
    end
    if not characterAssets.hasAction(character,action) then return false end
    if characterAssets.resolveAction then action=characterAssets.resolveAction(character,action) end
    local _,_,frameCount=characterAssets.get(character,action,1)
    local frame=animation.frameForPlayerAction(action,frameCount or 1,
        player.animationDistance or 0,player.idleClock or 0,
        Config.player.walkPixelsPerFrame,Config.player.idleAnimationRate)
    local image,quad=characterAssets.get(character,action,frame)
    if not image or not quad then return false end
    local anchorX,anchorY=characterAssets.getAnchor(character,action,frame)
    local scale=Config.player.drawScale*characterAssets.getNormalization(character,action)
    love.graphics.push('all');love.graphics.setShader();love.graphics.setColor(1,1,1,opacity or 1)
    love.graphics.draw(image,quad,player.x,player.y,0,scale*mirror,scale,anchorX,anchorY)
    love.graphics.pop()
    return true
end

local function drawNormalWalker(characterAssets,player,opacity)
    if not characterAssets then return false end
    local Animation=require('src.character_animation')
    local Config=require('src.config')
    local Colorways=require('src.rabbit_colorways')
    local character=player.character or Config.player.character
    local action,mirror
    if player.moving then action,mirror=Animation.actorWalkAction(player)
    else action,mirror=Animation.directionalIdleAction(player.intentX,player.intentY) end
    if not characterAssets.hasAction(character,action) then action=player.moving and 'walk' or 'idle' end
    if characterAssets.resolveAction then action=characterAssets.resolveAction(character,action) end
    if not characterAssets.hasAction(character,action) then return false end
    local _,_,count=characterAssets.get(character,action,1)
    local frame=Animation.frameForPlayerAction(action,count or 1,player.animationDistance or 0,
        player.idleClock or 0,Config.player.walkPixelsPerFrame,Config.player.idleAnimationRate)
    local image,quad=characterAssets.get(character,action,frame)
    if not image or not quad then return false end
    local anchorX,anchorY=characterAssets.getAnchor(character,action,frame)
    local scale=Config.player.drawScale*characterAssets.getNormalization(character,action)
    love.graphics.push('all');love.graphics.setShader();love.graphics.setColor(1,1,1,opacity or 1)
    if character=='rabbit-worker' then
        Colorways.draw(image,quad,player.x,player.y,0,scale*mirror,scale,anchorX,anchorY,0,0,
            player.furColorway,player.overallsColorway,opacity)
    else love.graphics.draw(image,quad,player.x,player.y,0,scale*mirror,scale,anchorX,anchorY) end
    love.graphics.pop()
    return true
end

local function smooth(value)
    value=math.max(0,math.min(1,value or 0))
    return value*value*(3-2*value)
end

local function drawSuitedRoadWalker(characterAssets,actor,camera,world,visual,clock,opacity)
    if not characterAssets then return false end
    local direction=camera:headingDirection(actor.heading or 0) or 'east'
    local mirrored=roadMirrorFor[direction]
    local authored=mirrored or direction
    local speed=visual and visual.speed or actor.speed or 0
    local action=(speed>.01 and 'walk' or 'idle')..(authored=='east' and '' or '_'..authored)
    local character='suited-rider'
    if characterAssets.resolveAction then action=characterAssets.resolveAction(character,action) end
    if not characterAssets.hasAction(character,action) then return false end
    local _,_,count=characterAssets.get(character,action,1)
    local distance=visual and visual.distance or actor.distance or 0
    local Rider=require('src.commute.rider')
    local Animation=require('src.character_animation')
    local Config=require('src.config')
    local frame=Animation.frameForPlayerAction(action,count or 1,distance/Rider.FRAME_DISTANCE,
        clock or 0,1,Config.player.idleAnimationRate)
    local image,quad=characterAssets.get(character,action,frame)
    if not image or not quad then return false end
    local anchorX,anchorY=characterAssets.getAnchor(character,action,frame)
    local x,y=camera:screen(actor.x,actor.z,actor.h or world:supportHeight(actor.x,actor.z))
    local scale=Config.player.drawScale*.7*camera.zoom*(characterAssets.getNormalization(character,action) or 1)
    love.graphics.push('all');love.graphics.setShader();love.graphics.setColor(1,1,1,opacity or 1)
    love.graphics.draw(image,quad,x,y,0,scale*(mirrored and -1 or 1),scale,anchorX,anchorY)
    love.graphics.pop()
    return true
end

function P.world(characterAssets,actor,camera,world,gear,appearance,visual,clock)
    if not characterAssets or type(gear)~='table' then return false end
    local Normal=require('src.commute.normal_art')
    local selected=Normal.appearance(appearance)
    -- The production suit art is rabbit-specific. Keep other selected species
    -- intact until matching suit sheets are authored for them.
    if selected.character~='rabbit-worker' then
        return Normal.draw(characterAssets,actor,camera,world,selected,visual,clock,1)
    end
    local suited=gear.outfit=='geared' and 1 or 0
    local transition=gear.transition
    if transition and (transition.kind=='equip' or transition.kind=='remove') then
        local duration=Gear.duration(transition.kind)
        local progress=smooth((transition.elapsed or 0)/math.max(.001,duration))
        suited=transition.kind=='equip' and progress or 1-progress
    end
    local normal=1-suited
    local drew=false
    if normal>.001 then
        drew=Normal.draw(characterAssets,actor,camera,world,selected,visual,clock,normal) or drew
    end
    if suited>.001 then
        drew=drawSuitedRoadWalker(characterAssets,actor,camera,world,visual,clock,suited) or drew
    end
    return drew
end

function P.indoor(player,state,characterAssets)
    local resident=require('src.home_residents').display(state,player)
    local gear=resident and resident.ridingGear
    if not gear or gear.outfit=='normal' and not gear.transition then return false end
    local selected=player.character or require("src.config").player.character
    local transition=gear.transition
    if transition and (transition.kind=='equip' or transition.kind=='remove') then
        if selected~='rabbit-worker' then return false end
        local progress=smooth((transition.elapsed or 0)/math.max(.001,Gear.duration(transition.kind)))
        local suited=transition.kind=='equip' and progress or 1-progress
        local normal=1-suited
        local drew=false
        if normal>.001 then drew=drawNormalWalker(characterAssets,player,normal) or drew end
        if suited>.001 then drew=drawSuitedWalker(characterAssets,player,suited) or drew end
        return drew
    end
    if gear.outfit=='geared' and not gear.transition and not gear.mounted
        and selected=="rabbit-worker"
        and drawSuitedWalker(characterAssets,player) then
        return true
    end
    return false
end
return P
