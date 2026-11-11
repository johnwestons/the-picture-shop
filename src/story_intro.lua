-- The first playable story beat. Grandpa stays at the farm after the handoff,
-- while completion lives in the warehouse condition so it survives saves/LAN.
local Intro={}
local Condition=require('src.warehouse_condition')
local Residents=require('src.home_residents')
local Rider=require('src.commute.rider')
local Sites=require('src.commute.sites')
local IMAGE='assets/generated/story-intro/grandpa-seated-v1.png'
local portrait
local function condition(R)
    local c=Condition.of(R.state)
    return c and c.mode=='story' and c or nil
end
local function anchor(R)
    local world=R._commute and R._commute.world
    local farm=world and world.sites and world.sites.byId.farm
    if not farm then return nil end
    local porch=Sites.farmStory.porch
    local x,z,h=farm:toWorld(porch.x,porch.z,0)
    return x,z,world:supportHeight(x,z) or h
end
function Intro.spawn(R)
    if not condition(R) then return true end
    local Commute=require('src.commute.runtime')
    local world=Commute.world(R)
    local farm=world.sites and world.sites.byId.farm
    if not farm then return false,'The farm is missing from this town.' end
    local player=R.World.player
    player.sceneId='warehouse'
    local okay,reason=require('src.commute.free_travel').enter(R.state,player,world,nil,{player})
    if not okay then return false,reason end
    local part=R.state.home.commute.participants[Residents.key(player)]
    if not Intro.parkAtFarm(R,part) then return false,'The farm parking is unavailable.' end
    R.state.message='You have arrived at Miller Farm. Walk to Grandpa on the house porch.'
    return true
end
function Intro.parkAtFarm(R,part)
    local Commute=require('src.commute.runtime')
    local world=Commute.world(R)
    local farm=world.sites.byId.farm
    part=part or Commute.localPart(R)
    if not farm or not part then return false end
    local bikeX,bikeZ=farm:toWorld(0,25,0)
    local pedX,pedZ=farm:toWorld(0,22.7,0)
    local rider=part.rider
    rider.gear.outfit='normal';rider.gear.mounted=false;rider.gear.engine=false
    rider.gear.transition=nil;rider.gear.revision=rider.gear.revision+1
    rider.bike.x,rider.bike.z=bikeX,bikeZ
    rider.bike.safeX,rider.bike.safeZ=bikeX,bikeZ
    rider.bike.speed=0;rider.bike.vx=0;rider.bike.vz=0
    require('src.commute.motorcycle').resetHorizontal(rider.bike)
    rider.ped.x,rider.ped.z=pedX,pedZ
    rider.ped.speed=0;rider.ped.vx=0;rider.ped.vz=0
    rider.ped.heading=math.atan2(-farm.cos,farm.sin)
    rider.bike.heading=rider.ped.heading
    rider.bike.safeHeading=rider.bike.heading
    require('src.commute.motorcycle').resetContact(rider.bike,world)
    Rider.update(rider,{},0,world)
    part.presentation=nil
    Commute.syncPlayer(R.World.player,part)
    return true
end
function Intro.near(R,part)
    local c=condition(R)
    if not c or c.openingSeen==false or c.grandpaMet or not part or part.interior then return false end
    local rider=part.rider
    if not rider or rider.gear.mounted or rider.gear.transition or rider.vehicle=='truck' then return false end
    local x,z=anchor(R)
    return x and (rider.ped.x-x)^2+(rider.ped.z-z)^2<=3.6^2 or false
end
local function lines(R)
    local trip=R.state.home and R.state.home.commute
    local count=0
    for _ in pairs(trip and trip.participants or {}) do count=count+1 end
    local greeting=count>2 and 'You brought the whole family! It is good to see all of you back in town.'
        or count>1 and 'You brought your sibling! It is good to see you both back in town.'
        or 'I am glad you made it back to town. It is good to see you.'
    return {greeting,
        'The Picture Shop has been closed for ten years. My health will not let me run it anymore, but I want you to have it.',
        'The building is sound. The power and water are disconnected, the breaker needs work, and the floors need a good cleaning.',
        'I set aside repair money. The cutter blade is dull and the wrapper needs service; buy kits for both. Then we can hold a grand opening.',
        'Your apartment and the shop are marked on the town map. Your motorcycle is here. I am proud of you, kid.'}
end
function Intro.open(R)
    local part=require('src.commute.runtime').localPart(R)
    if not Intro.near(R,part) then return false end
    R._commute.introDialogue=1
    R._commute.mapOpen=false
    return true
end
function Intro.advance(R)
    local view=R._commute
    if not view or not view.introDialogue then return false end
    local nextPage=view.introDialogue+1
    if nextPage>#lines(R) then
        view.introDialogue=nil
        if R.multiplayer:isClient() then
            R.state.message='Grandpa explained the shop restoration. The host will lead the grand opening.'
            return true
        end
        local c=condition(R)
        if c and not c.grandpaMet then
            c.grandpaMet=true
            R.state.message='Grandpa handed you the Picture Shop keys. Explore town whenever you are ready.'
            if R.multiplayer:isHost() then R.multiplayer:markShopDirty(true) end
            if not R.multiplayer:isClient() then R.saveCurrent(true) end
        end
    else view.introDialogue=nextPage end
    return true
end
function Intro.dialogueOpen(R)
    return R._commute and R._commute.introDialogue~=nil
end
function Intro.drawWorld(R,camera)
    if not condition(R) then return end
    local x,z,h=anchor(R)
    if not x then return end
    local bottomX,bottomY=camera:screen(x,z,h)
    -- Match the established player billboard scale in the outside renderer.
    -- The seated portrait is shorter than the standing rabbit, but should not
    -- shrink to the size of a road prop when the camera is pitched down.
    local _,topY=camera:screen(x,z,h+4.6)
    local height=math.abs(bottomY-topY)
    if height<8 or height>500 or bottomX<-100
        or bottomX>(camera.viewportWidth or 1280)+100 then return end
    if not portrait then portrait=love.graphics.newImage(IMAGE) end
    local width=height*portrait:getWidth()/portrait:getHeight()
    local g=love.graphics
    g.push('all')
    g.setShader();g.setColor(1,1,1,1)
    g.draw(portrait,bottomX-width*.5,bottomY-height,0,width/portrait:getWidth(),height/portrait:getHeight())
    g.setColor(.04,.08,.07,.85)
    g.rectangle('fill',bottomX-42,bottomY-height-26,84,21,5)
    g.setColor(.95,.86,.58);g.printf('GRANDPA',bottomX-42,bottomY-height-24,84,'center')
    g.pop()
end
function Intro.drawHud(R)
    if not condition(R) then return end
    local g=love.graphics
    local view=R._commute
    local page=view and view.introDialogue
    if not page then
        local part=require('src.commute.runtime').localPart(R)
        local hint=Intro.near(R,part) and 'TALK TO GRANDPA  ·  ACTION / E'
            or not condition(R).grandpaMet and 'VISIT GRANDPA AT THE FARM HOUSE'
            or nil
        if hint then
            g.push('all');g.setColor(.02,.04,.04,.9);g.rectangle('fill',360,730,560,48,7)
            g.setColor(.95,.88,.65);g.printf(hint,370,744,540,'center');g.pop()
        end
        return
    end
    local text=lines(R)[page]
    local last=page==#lines(R)
    g.push('all')
    g.setShader();g.setColor(0,0,0,.58);g.rectangle('fill',0,0,R.Config.baseWidth,R.Config.baseHeight)
    g.setColor(.035,.065,.06,.98);g.rectangle('fill',108,570,1064,243,12)
    g.setColor(.62,.78,.65);g.rectangle('line',108,570,1064,243,12)
    g.setColor(.96,.87,.58);g.print('GRANDPA',139,599)
    local visible=require('src.dialogue_presentation').present(view,'grandpa',text,page==1 and 'greeting' or 'neutral')
    g.setColor(.95,.95,.88);g.printf(visible or text,139,641,1002,'left')
    g.setColor(.09,.38,.38);g.rectangle('fill',875,744,255,51,7)
    g.setColor(.95,.98,.89);g.printf(last and 'TAKE THE KEYS' or 'CONTINUE',880,760,245,'center')
    g.pop()
end
function Intro.pointer(R,x,y)
    if not Intro.dialogueOpen(R) then return false end
    if x>=850 and x<=1150 and y>=720 and y<=820 then Intro.advance(R) end
    return true
end
return Intro
