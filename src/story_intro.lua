-- The first playable story beat. Grandpa stays at the farm after the handoff,
-- while completion lives in the warehouse condition so it survives saves/LAN.
local Intro={}
local Condition=require('src.warehouse_condition')
local Residents=require('src.home_residents')
local Rider=require('src.commute.rider')
local Sites=require('src.commute.sites')
local function condition(R)
    local c=Condition.of(R.state)
    return c and c.mode=='story' and c or nil
end
function Intro.grandpaPresent(R)
    -- He leaves the barn for the farmhouse when the town's actual daylight ends.
    return require('src.commute.day_night').sample(R.state.calendar).daylight>=.15
        or Intro.dialogueOpen(R)==true
end
local function anchor(R)
    local world=R._commute and R._commute.world
    local farm=world and world.sites and world.sites.byId.farm
    if not farm then return nil end
    local door=Sites.farmStory.barnDoor
    local x,z,h=farm:toWorld(door.x,door.z,0)
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
    R.state.message='You have arrived at Miller Farm. Walk to the barn and meet Grandpa inside.'
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
    local trip=R.state.home and R.state.home.commute
    if c and c.openingSeen==false or not trip or not trip.independent
        or not part or part.interior then return false end
    local rider=part.rider
    if not rider or rider.gear.mounted or rider.gear.transition or rider.vehicle=='truck' then return false end
    local x,z=anchor(R)
    return x and (rider.ped.x-x)^2+(rider.ped.z-z)^2<=3.6^2 or false
end
local function lines(R)
    local c=condition(R)
    if not c or c.grandpaMet then
        return {'Good to see you, kid. I spend the daylight hours out here in the barn.',
            'Take care on the road. You can always stop by for a chat.'}
    end
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
function Intro.currentLine(R)
    local view=R._commute
    local page=view and view.introDialogue
    local text=page and lines(R)[page]
    if not text then return nil end
    local c=condition(R)
    local emotions=c and not c.grandpaMet and {'greeting','sad','worried','agreement','happy'}
        or {'greeting','happy'}
    return require('src.dialogue_presentation').present(view,'grandpa',text,
        emotions[page] or 'neutral')
end
function Intro.open(R)
    local Commute=require('src.commute.runtime')
    local part=Commute.localPart(R)
    if not part then return false end
    if part.interior=='barn' then
        if not require('src.commute.barn_interior').nearGrandpa(part.interiorPose) then
            return false
        end
        if not Intro.grandpaPresent(R) then
            R.state.message='Grandpa has gone into the farmhouse for the night. Come back during the day.'
            return true
        end
        R._commute.introDialogue=1
        R._commute.barnTarget=nil
        return true
    end
    if not Intro.near(R,part) then return false end
    part.interior='barn'
    local player=R.World.player
    part.interiorPose={character=player.character,x=480,y=570,intentX=0,intentY=-1,
        animationDistance=0,idleClock=0,moving=false,velocityX=0,velocityY=0,
        furColorway=player.furColorway,overallsColorway=player.overallsColorway}
    R._commute.mapOpen=false;R._commute.barnTarget=nil
    Commute.syncPlayer(player,part)
    R.state.message=Intro.grandpaPresent(R) and 'Grandpa is waiting inside the barn.'
        or 'The barn is empty. Grandpa has gone into the farmhouse for the night.'
    if not R.multiplayer:isClient() then R.saveCurrent(true) end
    return true
end
function Intro.exitBarn(R)
    local Commute=require('src.commute.runtime')
    local part=Commute.localPart(R)
    if not part or part.interior~='barn' or Intro.dialogueOpen(R) then return false end
    if not require('src.commute.barn_interior').nearExit(part.interiorPose) then return false end
    part.interior=nil;part.interiorPose=nil
    R._commute.barnTarget=nil
    Commute.syncPlayer(R.World.player,part)
    R.state.message='You step out of the barn at Miller Farm.'
    if not R.multiplayer:isClient() then R.saveCurrent(true) end
    return true
end
function Intro.advance(R)
    local view=R._commute
    if not view or not view.introDialogue then return false end
    local nextPage=view.introDialogue+1
    if nextPage>#lines(R) then
        view.introDialogue=nil
        local part=require('src.commute.runtime').localPart(R)
        if part then part.presentation=nil end
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
    -- Grandpa is rendered by the barn scene, not on the farmhouse porch.
end
function Intro.advanceButton(R)
    local width=math.min(238,math.max(0,R.Config.baseWidth-32))
    local height=48
    return {x=(R.Config.baseWidth-width)*.5,
        y=R.Config.baseHeight-height-14,width=width,height=height}
end
function Intro.drawHud(R)
    local c=condition(R)
    if not c and not Intro.dialogueOpen(R) then return end
    local g=love.graphics
    local view=R._commute
    local page=view and view.introDialogue
    if not page then
        local part=require('src.commute.runtime').localPart(R)
        local hint=Intro.near(R,part) and 'ENTER BARN  ·  ACTION / E'
            or c and not c.grandpaMet and part and part.interior~='barn' and 'VISIT GRANDPA IN THE BARN'
            or nil
        if hint then
            local width=math.min(560,R.Config.baseWidth-32)
            local x=(R.Config.baseWidth-width)*.5
            local y=R.Config.baseHeight-56
            g.push('all');g.setColor(.02,.04,.04,.9);g.rectangle('fill',x,y,width,42,7)
            g.setColor(.95,.88,.65);g.printf(hint,x+10,y+12,width-20,'center');g.pop()
        end
        return
    end
    local last=page==#lines(R)
    local button=Intro.advanceButton(R)
    g.push('all')
    g.setShader();g.setColor(.02,.045,.04,.94)
    g.rectangle('fill',button.x,button.y,button.width,button.height,8)
    g.setColor(.58,.78,.63,1)
    g.rectangle('line',button.x,button.y,button.width,button.height,8)
    g.setColor(.97,.98,.9,1)
    g.printf(last and 'TAKE THE KEYS  ·  TAP / ENTER' or 'NEXT  ·  TAP / ENTER',
        button.x+8,button.y+16,button.width-16,'center')
    g.pop()
end
function Intro.pointer(R,x,y)
    if not Intro.dialogueOpen(R) then return false end
    -- With dialogue open, movement controls are paused. Let any pointer/touch
    -- advance so the conversation remains usable even when a device has a
    -- different safe-area inset or the button is obscured by system chrome.
    Intro.advance(R)
    return true
end
return Intro
