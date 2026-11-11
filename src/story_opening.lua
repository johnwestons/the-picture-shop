-- Illustrated Millhaven departure followed by a scripted ride on generated
-- roads and a walk to Grandpa. Only the presentation clock is transient;
-- an interrupted opening safely replays from its first beat.
local Opening={DURATION=19.2}
local Condition=require('src.warehouse_condition')
local Lettering=require('src.story_lettering')
local Arrival=require('src.story_arrival')
local packingPath='assets/generated/story-intro/packing-poses-v1.png'
local bikePath='assets/commute/bike/mounted.png'
local parkedPath='assets/commute/bike/parked.png'
local apartmentPath='assets/generated/story-intro/millhaven-apartment-v1.png'
local streetPath='assets/generated/story-intro/millhaven-street-v1.png'
local bridgePath='assets/generated/story-intro/millhaven-bridge-v1.png'
local farmRoadPath='assets/generated/story-intro/miller-farm-road-v1.png'
local art
local musicSource
local W,H=960,678
local function clamp(x,a,b) return math.max(a,math.min(b,x)) end
local function ease(x) x=clamp(x,0,1);return x*x*(3-2*x) end
local function color(r,g,b,a) love.graphics.setColor(r,g,b,a or 1) end
local function rect(x,y,w,h,radius)
    love.graphics.rectangle('fill',x,y,w,h,radius or 0)
end
local function loadArt()
    if art then return art end
    local packing=love.graphics.newImage(packingPath)
    local bike=love.graphics.newImage(bikePath)
    local parked=love.graphics.newImage(parkedPath)
    local apartment=love.graphics.newImage(apartmentPath)
    local street=love.graphics.newImage(streetPath)
    local bridge=love.graphics.newImage(bridgePath)
    local farmRoad=love.graphics.newImage(farmRoadPath)
    for _,image in ipairs({packing,bike,parked,apartment,street,bridge,farmRoad}) do image:setFilter('linear','linear') end
    art={packing=packing,bike=bike,parked=parked,apartment=apartment,street=street,
        bridge=bridge,farmRoad=farmRoad,poses={},bikeQuad=love.graphics.newQuad(640,0,320,320,1280,640)}
    for i=0,2 do art.poses[i+1]=love.graphics.newQuad(i*443,0,443,443,1329,443) end
    return art
end
local function drawPose(index,x,y,scale,alpha)
    local a=loadArt()
    color(1,1,1,alpha or 1)
    love.graphics.draw(a.packing,a.poses[index],x,y,0,scale,scale)
end
local function drawBike(image,x,y,scale,alpha)
    local a=loadArt()
    color(1,1,1,alpha or 1)
    love.graphics.draw(image,a.bikeQuad,x,y,0,scale,scale)
end
local function drawPlate(image,pan,alpha)
    local g=love.graphics
    local scale=math.max(W/image:getWidth(),H/image:getHeight())
    color(1,1,1,alpha or 1)
    g.draw(image,(W-image:getWidth()*scale)*.5+(pan or 0),0,0,scale,scale)
end
local function location(title,subtitle)
    Lettering.draw(title,27,14,650,.38,'left')
    Lettering.draw(subtitle,27,42,650,.31,'left')
end
local function caption(text)
    Lettering.draw(text,36,549,888,.49,'center')
end
local function stopMusic()
    local source=musicSource
    musicSource=nil
    if not source then return end
    pcall(source.stop,source)
    if source.release then pcall(source.release,source) end
end
local function startMusic(R)
    stopMusic()
    if not love or not love.audio or type(love.audio.newSource)~='function' then return false end
    local path=require('src.soundscape').path('music-pixel_memory',
        'assets/audio/music/vibes/pixel_memory.wav')
    local okay,source=pcall(love.audio.newSource,path,'stream')
    if not okay or not source then return false end
    local sound=R.App and R.App.sound
    local volume=.24*(sound and sound.masterVolume or 1)
        *require('src.soundscape').gain('music-pixel_memory','music')
    if sound and sound.muted then volume=0 end
    local started=pcall(function()
        source:setLooping(false)
        source:setVolume(volume)
        source:play()
        if sound and sound.paused then source:pause() end
    end)
    if not started then
        pcall(source.stop,source)
        if source.release then pcall(source.release,source) end
        return false
    end
    musicSource=source
    return true
end
local function interior(t)
    local g=love.graphics
    drawPlate(art.apartment,14-ease(t/8)*28)
    color(.12,.10,.08,.40);g.ellipse('fill',477,538,219,20)
    local pose=t<3.0 and 1 or t<5.4 and 2 or 3
    local x=320+ease((t-5.8)/2.1)*120
    local bob=pose==3 and math.sin(t*8)*2 or math.sin(t*3)*1.5
    local boundary=pose==1 and 3.0 or pose==2 and 5.4 or nil
    if boundary and boundary-t<.26 and boundary-t>0 then
        local blend=ease(1-(boundary-t)/.26)
        drawPose(pose,x,225+bob,.72,1-blend)
        drawPose(pose+1,x,225+bob,.72,blend)
    else drawPose(pose,x,225+bob,.72) end
    location('MILLHAVEN CITY','The morning before the return')
    caption(t<3 and 'Packing up for a new adventure.' or t<5.4 and 'Ten years since the Picture Shop closed.'
        or 'Grandpa is waiting in the town where it all began.')
end
local function street(t)
    drawPlate(art.street,17-(t-8)*13)
    local walk=ease((t-8)/1.35)
    local mounted=ease((t-9.45)/.42)
    drawBike(art.parked,562,287,.72,1-mounted)
    drawPose(3,110+walk*323,257,.53,1-mounted)
    drawBike(art.bike,562,287+math.sin(t*12)*1.5,.72,mounted)
    location('MILLHAVEN CITY','Leaving the apartment behind')
    caption('Packed and ready for the road to Grandpa\'s farm.')
end
local function road(t)
    local p=clamp((t-10.7)/7.5,0,1)
    local country=ease((p-.46)/.31)
    drawPlate(art.bridge,23-p*44)
    if country>.001 then drawPlate(art.farmRoad,22-p*42,country) end
    local bob=math.sin(t*25)*2.5
    drawBike(art.bike,361+math.sin(t*.9)*7,264+bob,.82)
    location(p<.28 and 'LEAVING MILLHAVEN' or p<.62 and 'RIVER BRIDGE' or 'THE ROAD TO MILLER FARM',
        p<.28 and 'City streets give way to the highway' or p<.62 and 'Across the river toward home'
        or 'The town and Grandpa are just ahead')
    caption(p<.62 and 'It\'s a long yet familiar journey back towards Grandpa\'s.'
        or 'Finally made it. Adventure awaits.')
end
function Opening.active(R) return R._storyOpening~=nil end
function Opening.begin(R)
    local c=Condition.of(R.state)
    R._storyOpening=nil
    if c and c.mode=='story' and c.openingSeen==false and not c.grandpaMet
        and R.World.player.sceneId=='commute' then
        R._storyOpening={time=0}
        startMusic(R)
        return true
    end
    return false
end
function Opening.finish(R,skip)
    if not Opening.active(R) then return false end
    local opening=R._storyOpening
    stopMusic()
    if skip then require('src.story_intro').parkAtFarm(R) end
    R._storyOpening=nil
    local camera=R._commute and R._commute.camera
    if camera then
        local Commute=require('src.commute.runtime')
        local part=Commute.localPart(R)
        camera.lastActor=require('src.commute.rider').actor(part.rider)
        Commute.applyCameraPreference(R,camera,part.rider)
        camera:recenter()
    end
    if skip and opening.arrival then require('src.commute.runtime').releaseView(R) end
    local c=Condition.of(R.state)
    if c and c.mode=='story' then
        c.openingSeen=true
        if skip then c.grandpaMet=true end
        R.state.message=skip and 'You have the shop keys. The town is yours to explore.'
            or 'You have arrived at Miller Farm. Walk to Grandpa on the house porch.'
        if R.multiplayer:isHost() then R.multiplayer:markShopDirty(true) end
        if not R.multiplayer:isClient() then
            local saved=R.saveCurrent(true)
            if not saved then R.state.message='The opening finished, but the game could not save. Try again from the menu.' end
        end
        if not skip and opening.arrival then
            require('src.story_intro').open(R)
        end
    end
    return true
end
function Opening.focus(R,focused)
    if not Opening.active(R) or not musicSource then return false end
    if not focused then
        pcall(musicSource.pause,musicSource)
        return true
    end
    local okay,position=pcall(musicSource.tell,musicSource)
    local durationOk,duration=pcall(musicSource.getDuration,musicSource)
    if okay and durationOk and type(position)=='number' and type(duration)=='number'
        and position>=duration then return true end
    pcall(musicSource.play,musicSource)
    return true
end
function Opening.update(R,dt)
    local state=R._storyOpening
    if not state then return false end
    dt=math.max(0,math.min(tonumber(dt) or 0,.5))
    if state.arrival then
        local done,reason=Arrival.update(R,state,dt)
        if done==nil then
            require('src.story_intro').parkAtFarm(R)
            require('src.commute.runtime').releaseView(R)
            state.arrival=nil
            Opening.finish(R,false)
            R.state.message='The road arrival was interrupted: '..tostring(reason)..' Walk to Grandpa at the farmhouse.'
        elseif done then Opening.finish(R,false) end
    else
        state.time=math.min(Opening.DURATION,state.time+dt)
        if state.time>=Opening.DURATION then
            local okay,reason=Arrival.begin(R,state)
            if not okay then
                Opening.finish(R,false)
                R.state.message='The road arrival could not start: '..tostring(reason)..' Walk to Grandpa at the farmhouse.'
            end
        end
    end
    return true
end
function Opening.keypressed(R,key)
    if not Opening.active(R) then return false end
    if key=='escape' or key=='back' or key=='space' or key=='return' or key=='s' then
        Opening.finish(R,true)
    end
    return true
end
function Opening.pointer(R,x,y)
    if not Opening.active(R) then return false end
    if x>=745 and x<=940 and y>=12 and y<=78 then Opening.finish(R,true) end
    return true
end
function Opening.draw(R)
    local state=R._storyOpening
    if not state then return false end
    loadArt()
    local g=love.graphics
    g.push('all');g.setShader()
    local t=state.time
    if state.arrival and R._commute and R._commute.renderer and not R._commute.loading then
        require('src.commute.runtime').draw(R,true)
    else
        if t<8 then interior(t)
        elseif t<10.7 then street(t)
        else road(t) end
        local cut=math.max(0,1-math.abs(t-8)/.17,1-math.abs(t-10.7)/.17)
        if cut>0 then color(.015,.023,.025,cut*.86);rect(-220,0,1400,H) end
        local fade=1-ease(t/.65)+(not state.arrival and ease((t-(Opening.DURATION-.9))/.9) or 0)
        if fade>0 then color(.015,.023,.025,clamp(fade,0,1));rect(-220,0,1400,H) end
    end
    Lettering.draw('SKIP INTRO',752,13,179,.34,'center')
    color(.72,.75,.67,.7);rect(44,658,872,4,2)
    local progress=state.arrival and .35+.65*Arrival.progress(state)
        or .35*clamp(t/Opening.DURATION,0,1)
    color(.90,.75,.46);rect(44,658,872*progress,4,2)
    g.pop()
    return true
end
return Opening
