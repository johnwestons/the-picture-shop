-- Miller Farm barn. The room and pose are saved with the independent town trip.
local Animation=require('src.character_animation')
local Config=require('src.config')
local WalkMotion=require('src.player_walk_motion')
local Bubble=require('src.speech_bubble')
local Barn={}
local background,grandpa,font
local BACKGROUND='assets/generated/story-barn-v1/barn-interior-v1.png'
local GRANDPA='assets/generated/story-intro/grandpa-seated-v1.png'
local GRANDPA_X,GRANDPA_Y=635,381

function Barn.walkable(x,y)
    return x>=82 and x<=878 and y>=165 and y<=604
        and (x-GRANDPA_X)^2+(y-GRANDPA_Y)^2>=37^2
end
function Barn.nearGrandpa(pose)
    return pose and (pose.x-GRANDPA_X)^2+(pose.y-GRANDPA_Y)^2<=146^2
end
function Barn.nearExit(pose)
    return pose and (pose.x-480)^2+(pose.y-570)^2<=75^2
end
function Barn.movePose(pose,x,y,dt,state)
    return WalkMotion.update(pose,x,y,dt,Barn.walkable,state)
end
function Barn.input(R,pose,x,y)
    local view=R._commute
    local target=view and view.barnTarget
    if math.abs(x)+math.abs(y)>.05 then
        if view then view.barnTarget=nil end
        return x,y
    end
    if target then
        local dx,dy=target.x-pose.x,target.y-pose.y
        local distance=math.sqrt(dx*dx+dy*dy)
        if distance<13 then view.barnTarget=nil;return 0,0 end
        return dx/distance,dy/distance
    end
    return 0,0
end
local function drawPlayer(R,pose)
    local assets=R.CharacterAssets
    if not assets then return end
    local character=pose.character or Config.player.character
    local action,mirror
    if pose.moving then action,mirror=Animation.actorWalkAction(pose)
    else action,mirror=Animation.directionalIdleAction(pose.intentX,pose.intentY) end
    if not assets.hasAction(character,action) then action=pose.moving and 'walk' or 'idle' end
    if assets.resolveAction then action=assets.resolveAction(character,action) end
    local _,_,count=assets.get(character,action,1)
    local frame=Animation.frameForPlayerAction(action,count or 1,pose.animationDistance,pose.idleClock,
        Config.player.walkPixelsPerFrame,Config.player.idleAnimationRate)
    local image,quad=assets.get(character,action,frame)
    if not image or not quad then return end
    local ax,ay=assets.getAnchor(character,action,frame)
    local scale=Config.player.drawScale*assets.getNormalization(character,action)
    love.graphics.setColor(1,1,1)
    if character=='rabbit-worker' then
        require('src.rabbit_colorways').draw(image,quad,pose.x,pose.y,0,scale*(mirror or 1),scale,
            ax,ay,0,0,pose.furColorway,pose.overallsColorway)
    else love.graphics.draw(image,quad,pose.x,pose.y,0,scale*(mirror or 1),scale,ax,ay) end
end
function Barn.draw(R,part)
    local g=love.graphics
    if not background then background=g.newImage(BACKGROUND);background:setFilter('linear','linear') end
    if not grandpa then grandpa=g.newImage(GRANDPA);grandpa:setFilter('linear','linear') end
    font=font or g.newFont(12)
    g.push('all');g.setShader();g.scale(R.Config.baseWidth/960,R.Config.baseHeight/678)
    g.setColor(1,1,1)
    g.draw(background,0,0,0,960/background:getWidth(),678/background:getHeight())
    local daylight=require('src.commute.day_night').sample(R.state.calendar).daylight
    if daylight<1 then
        g.setColor(.025,.045,.085,.48*(1-daylight));g.rectangle('fill',0,48,960,630)
    end
    local Intro=require('src.story_intro')
    if Intro.grandpaPresent(R) then
        local portraitHeight=148
        local portraitWidth=portraitHeight*grandpa:getWidth()/grandpa:getHeight()
        g.setColor(1,1,1)
        g.draw(grandpa,GRANDPA_X-portraitWidth/2,GRANDPA_Y-portraitHeight,0,
            portraitWidth/grandpa:getWidth(),portraitHeight/grandpa:getHeight())
        g.setFont(font);g.setColor(.04,.07,.06,.88);g.rectangle('fill',GRANDPA_X-55,GRANDPA_Y-160,110,23,5)
        g.setColor(.97,.87,.60);g.printf('GRANDPA',GRANDPA_X-55,GRANDPA_Y-156,110,'center')
    end
    drawPlayer(R,part.interiorPose)
    if Intro.dialogueOpen(R) then
        local visible,full=Intro.currentLine(R)
        if visible then Bubble.draw(visible,font,GRANDPA_X,GRANDPA_Y-170,960,full) end
    end
    g.setColor(.02,.04,.035,.89);g.rectangle('fill',0,0,960,48)
    g.setColor(.96,.85,.59);g.printf('MILLER FARM  /  BARN',18,14,450,'left')
    if not Intro.dialogueOpen(R) then
        local pose=part.interiorPose
        local hint=Barn.nearExit(pose) and 'LEAVE BARN  ·  E / TAP'
            or not Intro.grandpaPresent(R) and 'GRANDPA IS IN THE FARMHOUSE FOR THE NIGHT'
            or Barn.nearGrandpa(pose) and 'TALK TO GRANDPA  ·  E / TAP'
            or 'WALK TO GRANDPA  ·  WASD / TAP THE FLOOR'
        g.setColor(.02,.04,.035,.9);g.rectangle('fill',175,615,610,45,7)
        g.setColor(.75,.67,.41,.95);g.rectangle('line',175,615,610,45,7)
        g.setColor(.97,.9,.68);g.printf(hint,185,629,590,'center')
    end
    g.pop()
    Intro.drawHud(R)
    return true
end
function Barn.pointer(R,part,x,y)
    x=x*960/R.Config.baseWidth;y=y*678/R.Config.baseHeight
    if y>610 and Barn.nearGrandpa(part.interiorPose) then return require('src.story_intro').open(R) end
    if y>610 and Barn.nearExit(part.interiorPose) then return require('src.story_intro').exitBarn(R) end
    if (x-GRANDPA_X)^2+(y-GRANDPA_Y)^2<95^2 then
        if Barn.nearGrandpa(part.interiorPose) then return require('src.story_intro').open(R) end
        R._commute.barnTarget={x=570,y=455};return true
    end
    if y>590 and math.abs(x-480)<100 then
        if Barn.nearExit(part.interiorPose) then return require('src.story_intro').exitBarn(R) end
        R._commute.barnTarget={x=480,y=570};return true
    end
    if Barn.walkable(x,y) then R._commute.barnTarget={x=x,y=y};return true end
    return true
end
return Barn
