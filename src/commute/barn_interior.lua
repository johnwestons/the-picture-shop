-- Miller Farm barn. The room and pose are saved with the independent town trip.
local Animation=require('src.character_animation')
local Config=require('src.config')
local WalkMotion=require('src.player_walk_motion')
local Bubble=require('src.speech_bubble')
local DisplayFonts=require('src.screens.reference_display_fonts')
local Barn={}
local background,grandpa,font
local BACKGROUND='assets/generated/story-barn-v1/barn-interior-v1.png'
local GRANDPA='assets/generated/story-intro/grandpa-seated-v1.png'
local GRANDPA_X,GRANDPA_Y=635,381
local GRANDPA_DRAW_HEIGHT=106
local BARN_PLAYER_SCALE=1.10

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
    if view then view.barnTarget=nil end
    return x,y
end
function Barn.mobileAction(R,part)
    if require('src.story_intro').dialogueOpen(R) then return 'e','NEXT' end
    local pose=part and part.interiorPose
    if Barn.nearExit(pose) then return 'e','EXIT' end
    if Barn.nearGrandpa(pose) and require('src.story_intro').grandpaPresent(R) then
        return 'e','TALK'
    end
    return 'e',''
end
function Barn.interact(R,part)
    local Intro=require('src.story_intro')
    local pose=part and part.interiorPose
    if Barn.nearGrandpa(pose) then return Intro.open(R) end
    if Barn.nearExit(pose) then return Intro.exitBarn(R) end
    return false
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
    local scale=Config.player.drawScale*BARN_PLAYER_SCALE*assets.getNormalization(character,action)
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
    local footprints=require('src.player_footprints')
    local remotePlayers=R.multiplayer and R.multiplayer.remotePlayers and R.multiplayer:remotePlayers() or {}
    if part.interiorPose then
        footprints.update(R.state,{x=part.interiorPose.x,y=part.interiorPose.y,
            moving=part.interiorPose.moving,sceneId='barn'},remotePlayers,love.timer.getTime())
    end
    g.push('all');g.setShader();g.scale(R.Config.baseWidth/960,R.Config.baseHeight/678)
    g.setColor(1,1,1)
    g.draw(background,0,0,0,960/background:getWidth(),678/background:getHeight())
    local daylight=require('src.commute.day_night').sample(R.state.calendar).daylight
    if daylight<1 then
        g.setColor(.025,.045,.085,.48*(1-daylight));g.rectangle('fill',0,48,960,630)
    end
    footprints.draw('barn')
    local Intro=require('src.story_intro')
    if Intro.grandpaPresent(R) then
        local portraitHeight=GRANDPA_DRAW_HEIGHT
        local portraitWidth=portraitHeight*grandpa:getWidth()/grandpa:getHeight()
        g.setColor(1,1,1)
        g.draw(grandpa,GRANDPA_X-portraitWidth/2,GRANDPA_Y-portraitHeight,0,
            portraitWidth/grandpa:getWidth(),portraitHeight/grandpa:getHeight())
        if not Intro.dialogueOpen(R) then
            local labelY=GRANDPA_Y-portraitHeight-26
            g.setFont(font);g.setColor(.04,.07,.06,.88);g.rectangle('fill',GRANDPA_X-55,labelY,110,23,5)
            g.setColor(.97,.87,.60);g.printf('GRANDPA',GRANDPA_X-55,labelY+4,110,'center')
        end
    end
    drawPlayer(R,part.interiorPose)
    if Intro.dialogueOpen(R) then
        local visible,full=Intro.currentLine(R)
        if visible then Bubble.draw(visible,font,GRANDPA_X,
            GRANDPA_Y-GRANDPA_DRAW_HEIGHT-8,960,full) end
    end
    local mobile=R.mobileControls and R.mobileControls:isEnabled()
    g.setColor(.02,.04,.035,.92);g.rectangle('fill',0,0,960,mobile and 68 or 48)
    g.setColor(.96,.85,.59);DisplayFonts.draw('groovySlab','MILLER FARM',22,7,31,'left',270)
    g.setColor(.96,.85,.59);g.printf('/  BARN',245,15,180,'left')
    local pose=part.interiorPose
    local hint=Barn.nearExit(pose) and 'LEAVE BARN  ·  E'
        or not Intro.grandpaPresent(R) and 'GRANDPA IS IN THE FARMHOUSE FOR THE NIGHT'
        or Barn.nearGrandpa(pose) and 'TALK TO GRANDPA  ·  E'
        or 'WALK TO GRANDPA  ·  WASD TO MOVE'
    if mobile and not Intro.dialogueOpen(R) then
        hint=Barn.nearExit(pose) and 'MOVE WITH THUMBSTICK  ·  PRESS EXIT'
            or not Intro.grandpaPresent(R) and 'MOVE WITH THUMBSTICK  ·  GRANDPA IS IN THE FARMHOUSE'
            or Barn.nearGrandpa(pose) and 'MOVE WITH THUMBSTICK  ·  PRESS TALK'
            or 'MOVE WITH THUMBSTICK  ·  WALK TO GRANDPA'
        g.setColor(.80,.87,.81);g.printf(hint,18,39,924,'left')
    end
    if not Intro.dialogueOpen(R) then
        if not mobile then
            g.setColor(.02,.04,.035,.9);g.rectangle('fill',175,615,610,45,7)
            g.setColor(.75,.67,.41,.95);g.rectangle('line',175,615,610,45,7)
            g.setColor(.97,.9,.68);g.printf(hint,185,629,590,'center')
        end
    end
    g.pop()
    Intro.drawHud(R)
    return true
end
function Barn.pointer(R,part,x,y)
    -- World taps do not move the character or activate Grandpa; use the
    -- directional controls and contextual action button instead.
    return true
end
return Barn
