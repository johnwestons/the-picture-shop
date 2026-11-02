-- Procedural fallback used while the rider changes gear. Stable suited walking
-- uses the production directional character strips registered in walker_art.
local Gear=require('src.commute.gear')
local P={}
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
local function drawSuitedWalker(characterAssets,player)
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
    love.graphics.setColor(1,1,1,1)
    love.graphics.draw(image,quad,player.x,player.y,0,scale*mirror,scale,anchorX,anchorY)
    return true
end

function P.indoor(player,state,characterAssets)
    local resident=require('src.home_residents').display(state,player)
    local gear=resident and resident.ridingGear
    if not gear or gear.outfit=='normal' and not gear.transition then return false end
    if gear.outfit=='geared' and not gear.transition and not gear.mounted
        and drawSuitedWalker(characterAssets,player) then
        return true
    end
    if gear.outfit=='geared' and gear.mounted and not gear.transition then return false end
    P.foot(player.x,player.y,1,gear,(player.animationDistance or 0)/48,player.moving and 1 or 0)
    return true
end
return P
