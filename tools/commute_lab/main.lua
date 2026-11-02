if os.getenv('PICTURE_SHOP_BIKE_REVIEW') == 'actions' then
    require('tools.commute_lab.bike_action_review').install()
    return
end
if os.getenv('PICTURE_SHOP_BIKE_REVIEW') == '1' then
    require('tools.commute_lab.bike_review').install()
    return
end
if os.getenv('PICTURE_SHOP_GEAR_ACTION_REVIEW') == '1' then
    require('tools.commute_lab.gear_action_review').install()
    return
end

if os.getenv('PICTURE_SHOP_COMMUTE_AUDIO_TEST')=='1' then
    require('tools.commute_lab.audio_review').install()
    return
end

if os.getenv('PICTURE_SHOP_COMMUTE_BINDINGS_TEST')=='1' then
    require('tools.commute_lab.bindings_review').install();return
end
if os.getenv('PICTURE_SHOP_COMMUTE_CAMERA_TEST')=='1' then
    function love.load()
        local count=0
        local function check(name,okay) assert(okay,name);count=count+1;print('PASS '..name) end
        for _,name in ipairs({'camera_controls','camera','first_person'}) do require('src.commute.tests.'..name..'_test').run(check) end
        print('COMMUTE_CAMERA_OK '..count..' checks; no saves accessed');love.event.quit(0)
    end
    return
end
local CameraControls=require('src.commute.camera_controls')
local Bindings=require('src.commute.bindings')
local Settings=require('src.settings')
local Touch=require('src.commute.touch_controls')
local controlsSettings={motorcycleControls=Bindings.defaults()}
local controlsPanel,touchControls=nil,Touch.new()
local padEdges={}
local function profile() return controlsSettings.motorcycleControls end
local function panelPoint(x,y)
    local w,h=love.graphics.getDimensions();local s=math.min(w/960,h/678)
    return (x-(w-960*s)*.5)/s,(y-(h-678*s)*.5)/s
end
local cameraDrag={}
local Terrain=require('src.commute.terrain')
local Roads=require('src.commute.roads')
local Bike=require('src.commute.motorcycle')
local Rider=require('src.commute.rider')
local Camera=require('src.commute.camera')
local Renderer=require('src.commute.renderer')
local Routes=require('src.commute.routes')
local world,roads,actor,camera,renderer,cockpit
local rider,controlMessage,pointerBoost
local rideAudio,audioMuted,audioVolume=nil,false,.8
local routes,route
local playablePreview=os.getenv('PICTURE_SHOP_RIDE_PREVIEW')=='1'
local previewCheck=playablePreview and os.getenv('PICTURE_SHOP_RIDE_PREVIEW_CHECK')=='1'
local firstPersonCheck=playablePreview and os.getenv('PICTURE_SHOP_FIRST_PERSON_CHECK')=='1'
local apartmentIds={'garden','brick-walkup','courtyard','corner'}
local apartmentIndex=playablePreview and 2 or 1
local elapsed,frames,showMap=0,0,playablePreview
local captureDir=os.getenv('PICTURE_SHOP_COMMUTE_CAPTURE')
local warehouseReview=os.getenv('PICTURE_SHOP_WAREHOUSE_REVIEW')=='1'
local bridgeReview=os.getenv('PICTURE_SHOP_BRIDGE_REVIEW')=='1'
local cases={{name='warehouse',x=110,z=372,yaw=20},{name='river-bridge',x=331,z=270,yaw=335},{name='ridge',x=140,z=160,yaw=28},
    {name='warehouse-autumn',x=110,z=372,yaw=20,month=11},{name='warehouse-winter',x=110,z=372,yaw=20,month=1}}
local caseIndex=1;local waiting=false
if firstPersonCheck then
    cases={
        {name='first-person-shop',x=100,z=380,heading=-.59,firstPerson=true},
        {name='first-person-valley',x=165,z=327,heading=-.59,firstPerson=true},
        {name='first-person-bridge-east',x=308,z=270,heading=0,firstPerson=true},
        {name='first-person-bridge-west',x=352,z=270,heading=math.pi,firstPerson=true},
        {name='first-person-look-right',x=308,z=270,heading=0,firstPerson=true,lookYaw=30,lookPitch=5},
        {name='first-person-look-left',x=308,z=270,heading=0,firstPerson=true,lookYaw=-30,lookPitch=-5},
        {name='first-person-bike-down',x=308,z=270,heading=0,firstPerson=true,lookYaw=0,lookPitch=-55},
        {name='first-person-bike-underfoot',x=308,z=270,heading=0,firstPerson=true,lookYaw=0,lookPitch=-90},
        {name='first-person-bike-rear',x=308,z=270,heading=0,firstPerson=true,lookYaw=180,lookPitch=-65},
        {name='first-person-look-back',x=308,z=270,heading=0,firstPerson=true,lookYaw=180,lookPitch=0},
        {name='first-person-lean',x=175,z=320,heading=-.59,lean=-.28,steering=.8,firstPerson=true},
        {name='first-person-hill',x=140,z=160,heading=2.1,firstPerson=true},
        {name='outside-view-restored',x=100,z=380,heading=-.59},
    }
end
if previewCheck then cases={{name='motorcycle-preview',x=100,z=380,yaw=20},
    {name='motorcycle-on-foot',x=100,z=380,yaw=20,onFoot=true}} end
if warehouseReview then
    cases={};for yaw=0,315,45 do cases[#cases+1]={name='warehouse-orbit-'..yaw,x=100,z=380,yaw=yaw} end
end
if bridgeReview then
    cases={
        {name='bridge-side-yaw-000',x=331,z=270,yaw=0,tilt=55,zoom=.8},
        {name='bridge-end-yaw-090',x=331,z=270,yaw=90,tilt=55,zoom=.8},
        {name='bridge-opposite-yaw-180',x=331,z=270,yaw=180,tilt=55,zoom=.8},
        {name='bridge-end-yaw-270',x=331,z=270,yaw=270,tilt=55,zoom=.8},
        {name='bridge-diagonal-yaw-335',x=331,z=270,yaw=335,tilt=55,zoom=.8},
        {name='bridge-low-tilt-035',x=331,z=270,yaw=0,tilt=35,zoom=.8},
        {name='bridge-high-tilt-075',x=331,z=270,yaw=0,tilt=75,zoom=.8},
          {name='bridge-entry-west-yaw-270',x=307,z=270,yaw=270,tilt=55,zoom=.8},
          {name='bridge-entry-east-yaw-090',x=355,z=270,yaw=90,tilt=55,zoom=.8},
    }
end
local function place(x,z,yaw,tilt,zoom)
    CameraControls.cancel(cameraDrag)
    rider=Rider.new(x,z,-.7,{version=1,outfit='geared',mounted=true,engine=true,revision=0})
    actor=rider.bike;Rider.update(rider,{},0,world);controlMessage=nil;pointerBoost=false
    camera=Camera.new(actor,world);camera.zoom=zoom or .8;camera.targetZoom=zoom or .8
    camera.yaw=yaw or 0;camera.tilt=tilt or Camera.TILT_DEFAULT
    if warehouseReview then
        local site=require('src.commute.sites').warehouse;local a=math.rad(camera.yaw)
        local dx,dz=site.x-actor.x,site.z-actor.z
        camera.offsetX=(dx*math.cos(a)-dz*math.sin(a))*48
        camera.offsetY=(dx*math.sin(a)+dz*math.cos(a))*29
        camera.zoom=.7;camera.targetZoom=.7
    end
    frames=0
end
local function check(name,okay,reason)
    print((okay and 'PASS ' or 'FAIL ')..name..(reason and ' '..tostring(reason) or ''))
    if not okay then error(name..': '..tostring(reason)) end
end
local function reviewCase(p)
    place(p.x,p.z,p.yaw or 20,p.tilt,p.zoom)
    if firstPersonCheck then
        actor.heading=p.heading;actor.lean=p.lean or 0;actor.steering=p.steering or 0
        camera:setFirstPerson(p.firstPerson,actor);showMap=false
        if p.lookYaw then camera:orbit(p.lookYaw,p.lookPitch or 0) end
    end
end
function love.load()
    love.window.setMode(1280,880,{resizable=true,vsync=1})
    love.window.setTitle(playablePreview and 'The Picture Shop — Motorcycle ride home preview'
        or 'The Picture Shop — Scenic commute development ride')
    if os.getenv('PICTURE_SHOP_COMMUTE_SESSION_TEST')=='1' then
        require('src.commute.tests.session_test').run({State=require('src.state')},check)
        print('COMMUTE SESSION TESTS PASSED');love.event.quit(0);return
    end
    if os.getenv('PICTURE_SHOP_COMMUTE_TEST')=='1' then
        for _,name in ipairs({'terrain','camera','first_person','roads','motorcycle','controls','vegetation','flora','routes','bridge_art','gear','rider','gear_home','trip','bike_art','normal_art','sites'}) do require('src.commute.tests.'..name..'_test').run(check) end
        -- These existing domain regressions exercise the apartment handoff and
        -- actual save schema. Their disposable slot lives only in the lab.
        assert(love.filesystem.getIdentity()=='the-picture-shop-commute-lab')
        local save=require('src.save');save.delete(3)
        require('src.tests.home_residents_test').run({save=save},check)
        require('src.tests.weekend_flow_test').run({},check)
        print('COMMUTE TESTS PASSED')
        if not captureDir then love.event.quit(0);return end
    end
    roads=Roads.new();world=roads:attach(Terrain.new());renderer=Renderer.new(world)
    if bridgeReview then
        for _,pier in ipairs(renderer.bridgeArt.piers) do
            print(('BRIDGE SUPPORT x=%.2f z=%.2f terrain=%.2f deck=%.2f'):format(
                pier.x,pier.z,pier.baseHeight,pier.deckHeight))
        end
    end
    cockpit=require('src.commute.cockpit').new()
    controlsSettings.motorcycleControls=(previewCheck or firstPersonCheck) and Bindings.defaults() or Settings.sharedMotorcycle()
    touchControls.visible=love.system.getOS()=='Android' or os.getenv('PICTURE_SHOP_MOBILE')=='1'
    rideAudio=require('src.commute.audio').new()
    rideAudio:setLevels(audioVolume,.85,.42)
    routes=Routes.new(roads);route=assert(routes:find('warehouse',apartmentIds[apartmentIndex]))
    if bridgeReview then place(331,270,0,55,.8)
    else place(100,380,warehouseReview and 0 or 20) end
    if previewCheck then
        assert(love.filesystem.getIdentity()=='the-picture-shop-motorcycle-preview')
        assert(route.from=='warehouse' and route.to=='brick-walkup' and showMap)
        for _=1,60 do Bike.update(actor,{throttle=1,steer=0,brake=0,boost=true},1/60,world) end
        assert(actor.distance>0 and actor.boosting,'Preview motorcycle must be drivable')
        love.keypressed('tab');local selected=apartmentIds[apartmentIndex]
        assert(route.to==selected and selected~='brick-walkup')
        local destination=roads.destinations[selected];actor.x,actor.z,actor.speed=destination.x,destination.z,0
        love.keypressed('return');assert(route.from==selected and route.to=='warehouse')
        love.keypressed('backspace');assert(route.from=='warehouse' and route.to==selected and actor.speed==0 and actor.x==100 and actor.z==380)
        apartmentIndex=2;love.keypressed('backspace')
        love.keypressed('b');assert(rider.bike.reverse)
        love.keypressed('b');assert(not rider.bike.reverse)
        love.keypressed('i');assert(not rider.gear.engine)
        love.keypressed('e')
        for _=1,80 do Rider.update(rider,{},1/60,world) end
        assert(not rider.gear.mounted)
        local parkedX,parkedZ=rider.bike.x,rider.bike.z
        for _=1,30 do Rider.update(rider,{walkX=1},1/60,world) end
        assert(rider.bike.x==parkedX and rider.bike.z==parkedZ and rider.ped.distance>0)
        for _=1,30 do Rider.update(rider,{},1/60,world) end
        love.keypressed('e')
        for _=1,110 do Rider.update(rider,{},1/60,world) end
        assert(rider.gear.mounted and rider.gear.engine)
        actor=Rider.actor(rider)
        local ox,oy,s=require('src.commute.cockpit').layout(1280,880)
        love.mousepressed(ox+425*s,oy+200*s,1);assert(rider.bike.headlight)
        love.mousepressed(ox+200*s,oy+200*s,1);assert(not rider.gear.engine)
        love.mousepressed(ox+200*s,oy+200*s,1);assert(rider.gear.engine)
        print('MOTORCYCLE_PREVIEW_OK: isolated identity, riding, boost, destination selection, arrival, return and restart')
        print('MOTORCYCLE_CONTROLS_PREVIEW_OK: reverse, ignition, dismount, walk, remount and clickable HUD')
        love.keypressed('f10');assert(controlsPanel)
        controlsPanel.save=function()return true end -- Never write preferences during automated checks.
        controlsPanel.capture='ignition';love.keypressed('j','j')
        assert(profile().keyboard.ignition=='j')
        love.keypressed('escape');assert(not controlsPanel)
        love.keypressed('i','i');assert(rider.gear.engine)
        love.keypressed('j','j');assert(not rider.gear.engine)
        love.mousepressed(ox+200*s,oy+200*s,1);assert(rider.gear.engine)
        controlsSettings.motorcycleControls=Bindings.defaults()
        print('MOTORCYCLE_MAPPING_PREVIEW_OK: F10 panel, native key callback, rebind, old-key removal, HUD independence')
    end
    if firstPersonCheck then
        require('src.commute.tests.first_person_test').run(check)
        love.keypressed('p');assert(camera.firstPerson)
        local ox,oy,s=require('src.commute.cockpit').layout(1280,880)
        love.mousepressed(ox+625*s,oy+278*s,1);assert(not camera.firstPerson)
        love.keypressed('p');camera:orbit(35,10)
        for _=1,30 do camera:updateRide(rider,1/60) end
        love.mousepressed(ox+650*s,oy+224*s,1)
        assert(camera.lookYaw==0 and camera.headYaw==0 and camera.viewHeading==actor.heading)
        print('FIRST_PERSON_PREVIEW_CONTROLS_OK: view toggle and fixed center button')
        reviewCase(cases[1])
    end
end
function love.update(dt)
    if not renderer then return end
    if controlsPanel then return end
    dt=math.min(dt,.1);elapsed=elapsed+dt;frames=frames+1
    local k=love.keyboard.isDown
    local ix=(k('d','right') and 1 or 0)-(k('a','left') and 1 or 0)
    local iy=(k('s','down') and 1 or 0)-(k('w','up') and 1 or 0)
    local mappedBoost
    if rider.gear.mounted then ix,iy,mappedBoost=Bindings.drive(profile(),touchControls)
    elseif math.abs(touchControls.x)+math.abs(touchControls.y)>0 then ix,iy=touchControls.x,touchControls.y end
    local wx,wz=camera:screenVectorToWorld(ix,iy)
    local finished=Rider.update(rider,{throttle=math.max(0,-iy),brake=k('space') and 1 or math.max(0,iy),
        steer=ix,boost=mappedBoost or pointerBoost,walkX=wx,walkZ=wz},dt,world)
    if finished or ix~=0 or iy~=0 then controlMessage=nil end
    actor=Rider.actor(rider)
    if firstPersonCheck then
        local p=cases[caseIndex];actor.lean=p.lean or 0;actor.steering=p.steering or 0
    end
    camera:updateRide(rider,dt);renderer:prepare(camera,dt)
    Bindings.camera(profile(),camera,dt,touchControls)
    rideAudio:update(dt,rider.bike,rider.gear.engine)
    if captureDir and frames>100 and renderer.pending==0
        and renderer.plantSprites:readyFor(renderer.visibleProps,renderer.calendar,renderer.clock) and not waiting then waiting=true end
end
local function map()
    local g=love.graphics;local ox,oy,s=835,165,.78
    g.setColor(.06,.1,.09,.94);g.rectangle('fill',ox-15,oy-30,425,425,8)
    g.setColor(.55,.76,.76);local pts={}
    for z=40,472,5 do pts[#pts+1]=ox+(world:riverCenterX(z)-40)*s;pts[#pts+1]=oy+(z-40)*s end
    g.setLineWidth(7);g.line(pts)
    g.setLineWidth(2);g.setColor(.77,.75,.61)
    for _,path in ipairs(roads.paths) do local p={};for _,v in ipairs(path.points) do p[#p+1]=ox+(v.x-40)*s;p[#p+1]=oy+(v.z-40)*s end;g.line(p) end
    g.setColor(.95,.64,.24);g.setLineWidth(3)
    local line={};for _,v in ipairs(route.points) do line[#line+1]=ox+(v.x-40)*s;line[#line+1]=oy+(v.z-40)*s end
    g.line(line);g.setLineWidth(1);g.setColor(.77,.75,.61)
    for _,p in pairs(roads.destinations) do local x,y=ox+(p.x-40)*s,oy+(p.z-40)*s;g.circle('fill',x,y,4);g.print(p.label,x+6,y-14) end
    g.setColor(1,.66,.24);g.circle('fill',ox+(actor.x-40)*s,oy+(actor.z-40)*s,6)
    g.setColor(1,1,1);g.print('SCENIC COMMUTE / fixed town',ox,oy-23);g.setLineWidth(1)
end
function love.draw()
    if controlsPanel then
        local w,h=love.graphics.getDimensions();local s=math.min(w/960,h/678)
        love.graphics.push();love.graphics.translate((w-960*s)*.5,(h-678*s)*.5);love.graphics.scale(s)
        controlsPanel:draw();love.graphics.pop();return
    end
    if not renderer then return end
    local g=love.graphics;local sw,sh=g.getDimensions();local scale=math.min(sw/1280,sh/880)
    g.push();g.translate((sw-1280*scale)*.5,(sh-880*scale)*.5);g.scale(scale)
    local actors={{actor=rider.bike,bikeOnly=not rider.gear.mounted}}
    if not rider.gear.mounted then actors[#actors+1]={actor=rider.ped,gear=rider.gear} end
    renderer:draw(camera,actor,actors)
    if not warehouseReview and not bridgeReview then
    if camera.firstPerson then
        local destination=roads.destinations[route.to]
        local distance=math.sqrt((actor.x-destination.x)^2+(actor.z-destination.z)^2)
        g.setColor(.035,.06,.05,.88);g.rectangle('fill',18,18,790,76,8)
        g.setColor(.94,.91,.78)
        g.print(('RIDER VIEW  /  %s  ·  %.0f m to destination'):format(destination.label,distance),34,29)
        g.setColor(.80,.85,.79)
        g.print(Bindings.hint(profile(),'accelerate')..': accelerate · '..Bindings.hint(profile(),'brake')..': brake · '..Bindings.hint(profile(),'view')..': view · F10: controls',34,51)
        g.print(controlMessage or (distance<5 and actor.speed<.1 and 'Arrived · Enter: practice the return ride'
            or 'Middle-drag: look · Wheel: field of view · C: center · Tab: destination · Esc: close'),34,73)
    else
    g.setColor(.035,.06,.05,.88);g.rectangle('fill',18,18,790,96,8)
    g.setColor(.94,.91,.78);g.print(playablePreview and 'THE WAY HOME  /  Playable motorcycle preview' or 'THE WAY HOME  /  Scenic terrain development ride',34,29)
    g.setColor(.80,.85,.79);g.print(Bindings.label(profile().mouse.orbit)..': rotate/tilt · '..Bindings.label(profile().mouse.pan)..': pan · '..Bindings.hint(profile(),'recenter')..': center · F10: controls',34,53)
    g.print(controlMessage or (rider.gear.mounted and (Bindings.hint(profile(),'ignition')..': engine · '..Bindings.hint(profile(),'reverse')..': reverse · '..Bindings.hint(profile(),'headlight')..': light · '..Bindings.hint(profile(),'interact')..': dismount')
        or ('WASD: walk · '..Bindings.hint(profile(),'interact')..': remount beside bike · F10: controls · Esc: close')),34,78)
    local destination=roads.destinations[route.to]
    local distance=math.sqrt((actor.x-destination.x)^2+(actor.z-destination.z)^2)
    g.setColor(.035,.06,.05,.88);g.rectangle('fill',18,120,790,55,8)
    g.setColor(.94,.91,.78)
    g.print(('Ride to %s · road route %.0f m · %.0f m direct to destination'):format(destination.label,route.length,distance),34,130)
    g.setColor(.80,.85,.79)
    g.print(distance<5 and actor.speed<.1 and 'Arrived · Enter: practice the return ride'
        or 'Tab: choose apartment · M: route map · Stop within the destination ring to turn back',34,150)
    if playablePreview then
        g.setColor(.035,.06,.05,.88);g.rectangle('fill',18,181,790,49,8)
        g.setColor(.94,.91,.78);g.print('Backspace: restart · '..Bindings.hint(profile(),'boost')..': boost · '..Bindings.hint(profile(),'transmission')..': gearbox · F10: controls',34,190)
        g.setColor(.80,.85,.79);g.print(('F9: sound %s · [ / ]: volume %d%% · Ride-only sandbox'):format(audioMuted and 'off' or 'on',math.floor(audioVolume*100+.5)),34,209)
    end
    end
    if showMap then map() end
    if rider.gear.mounted then cockpit:draw(rider.bike,rider.gear.engine,1280,880,nil,camera,profile()) end
    touchControls:draw(1280,880,profile())
    g.setColor(.08,.13,.10,.95);g.rectangle('fill',1120,18,142,42,5)
    g.setColor(.94,.92,.76);g.printf('F10  CONTROLS',1124,32,134,'center')
    if renderer.pending>0 then g.setColor(1,1,1);g.print('Preparing nearby scenery… '..renderer.pending,24,838) end
    elseif warehouseReview then
        local site=require('src.commute.sites').warehouse
        local x,y=camera:screen(site.door.x,site.door.z,site.h)
        g.setColor(1,.8,.3);g.circle('line',x,y,12);g.print('Door approach',x+16,y)
        g.setColor(1,1,1);g.print('Warehouse sprite / camera yaw '..camera.yaw,18,18)
    else
        g.setColor(1,1,1);g.print(('Concrete bridge / yaw %03d / tilt %02d'):format(camera.yaw,camera.tilt),18,18)
    end
    g.pop()
    if waiting then
        waiting=false
        local name=cases[caseIndex].name
        g.captureScreenshot(function(data)
            local bytes=data:encode('png');local file=assert(io.open(captureDir..'/'..name..'.png','wb'));file:write(bytes:getString());file:close()
            print('CAPTURE '..name..' chunks='..#renderer.visible..' buildMs='..renderer.buildMs)
            caseIndex=caseIndex+1
            if caseIndex>#cases then love.event.quit(0)
            else
                local p=cases[caseIndex];renderer.calendar={month=p.month or 5,totalDays=0};reviewCase(p)
                if p.onFoot then
                    rider.bike.headlight=true;assert(Rider.command(rider,'dismount',world))
                    for _=1,80 do Rider.update(rider,{},1/60,world) end
                    for _=1,60 do Rider.update(rider,{walkX=1},1/60,world) end
                    for _=1,30 do Rider.update(rider,{},1/60,world) end
                    actor=Rider.actor(rider)
                end
            end
        end)
    end
end
local function openControls()
    CameraControls.cancel(cameraDrag);touchControls:cancel();pointerBoost=false
    if rideAudio then rideAudio:setPaused(true) end
    controlsPanel=require('src.commute.controls_screen').new(controlsSettings,
        function() return Settings.sharedMotorcycle(profile()) end,
        function() controlsPanel=nil;if rideAudio then rideAudio:setPaused(false) end end)
end
local function perform(id)
    local a=Bindings.byId[id]
    if a and a.preview and a.preview~='' then love.keypressed(a.preview,true) end
end
function love.keypressed(key,semantic)
    semantic=semantic==true
    if controlsPanel then return controlsPanel:keypressed(key) end
    if not camera then return end
    if not semantic then
        if key=='f10' then openControls();return end
        local id=Bindings.action(profile(),'keyboard',key)
        if id then
            if Bindings.byId[id].held or Bindings.byId[id].modifier then return end
            key=Bindings.byId[id].preview;if not key or key=='' then return end
        elseif ({p=true,q=true,t=true,e=true,i=true,h=true,b=true,r=true,f=true,c=true,v=true,z=true,x=true,g=true,['=']=true,['-']=true})[key] then return end
    end
    if key=='escape' then love.event.quit()
    elseif key=='p' then
        if camera:toggleView(rider) then
            if camera.firstPerson then showMap=false end
            controlMessage=camera.firstPerson and 'First-person view · Middle-drag: look around · C: center · P: outside view' or 'Outside view'
        end
    elseif key=='q' then camera:orbit(-15,0)
    elseif key=='t' then camera:orbit(15,0)
    elseif key=='e' then
        local _,message=Rider.command(rider,rider.gear.mounted and 'dismount' or 'mount',world)
        controlMessage=message or (rider.gear.mounted and 'Getting off the motorcycle…' or 'Mounting and starting the motorcycle…')
    elseif key=='g' then
        local _,message=Rider.command(rider,rider.gear.outfit=='normal' and 'equip' or 'remove',world);controlMessage=message
    elseif key=='i' or key=='h' or key=='b' then
        local _,message=Rider.command(rider,({i='ignition',h='headlight',b='reverse'})[key],world);controlMessage=message
    elseif key=='r' then camera:orbit(0,5)
    elseif key=='f' then camera:orbit(0,-5)
    elseif key=='c' then camera:recenter()
    elseif key=='m' then showMap=not showMap
    elseif key=='v' then local _,message=Rider.command(rider,rider.bike.transmission=='manual' and 'automatic' or 'manual',world);controlMessage=message
    elseif key=='z' then local _,message=Rider.command(rider,'shiftdown',world);controlMessage=message
    elseif key=='x' then local _,message=Rider.command(rider,'shiftup',world);controlMessage=message
    elseif key=='tab' then
        apartmentIndex=apartmentIndex%#apartmentIds+1
        route=assert(routes:find('warehouse',apartmentIds[apartmentIndex]))
    elseif key=='backspace' then
        route=assert(routes:find('warehouse',apartmentIds[apartmentIndex]))
        place(100,380,20)
    elseif key=='return' then
        local p=roads.destinations[route.to]
        if (actor.x-p.x)^2+(actor.z-p.z)^2<25 and actor.speed<.1 then
            route=assert(routes:find(route.to,route.from))
        end
    elseif key=='f9' then audioMuted=not audioMuted;rideAudio:setMuted(audioMuted)
    elseif key=='[' or key==']' then
        audioVolume=math.max(0,math.min(1,audioVolume+(key==']' and .1 or -.1)))
        rideAudio:setLevels(audioVolume,.85,.42)
    elseif key=='f8' then renderer.radius=renderer.radius==48 and 64 or renderer.radius==64 and 80 or 48
    elseif key=='f7' then
        local months={[5]=8,[8]=11,[11]=1,[1]=5}
        renderer.calendar={month=months[renderer.calendar.month] or 5,totalDays=0}
    elseif key=='1' then place(100,380,20)
    elseif key=='2' then place(331,270,335)
    elseif key=='3' then place(140,160,28)
    elseif key=='=' then camera:zoomBy(1)
    elseif key=='-' then camera:zoomBy(-1) end
end
function love.wheelmoved(x,y)
    if controlsPanel then return controlsPanel:wheelmoved(x,y) end
    local id=Bindings.action(profile(),'mouse',y>0 and 'wheelup' or 'wheeldown')
    if y~=0 then perform(id) end
end
function love.mousepressed(x,y,button,isTouch)
    if isTouch then return end
    if controlsPanel then local px,py=panelPoint(x,y);return controlsPanel:mousepressed(px,py,button) end
    local sw0,sh0=love.graphics.getDimensions();local sc0=math.min(sw0/1280,sh0/880)
    local ux,uy=(x-(sw0-1280*sc0)*.5)/sc0,(y-(sh0-880*sc0)*.5)/sc0
    if button==1 and ux>=1120 and ux<=1262 and uy>=18 and uy<=60 then openControls();return end
    if button==1 and profile().showTouch and touchControls:press('mouse',ux,uy,1280,880,profile(),perform) then return end
    local modifier=profile().keyboard.panModifier
    if camera and CameraControls.press(cameraDrag,button,modifier~='' and love.keyboard.isDown(modifier),profile()) then return end
    if button~=1 then perform(Bindings.action(profile(),'mouse','mouse'..button));return end
    if button~=1 or not cockpit or not rider.gear.mounted then return end
    local sw,sh=love.graphics.getDimensions();local scale=math.min(sw/1280,sh/880)
    local key=require('src.commute.cockpit').keyAt((x-(sw-1280*scale)*.5)/scale,
        (y-(sh-880*scale)*.5)/scale,1280,880,rider.bike,nil,camera)
    if key=='boost' then pointerBoost=true
    elseif key then love.keypressed(key,true) end
end
function love.mousereleased(x,y,button,isTouch)
    if isTouch then return end
    if controlsPanel then local px,py=panelPoint(x,y);return controlsPanel:mousereleased(px,py,button) end
    CameraControls.release(cameraDrag,button)
    touchControls:release('mouse')
    if button==1 then pointerBoost=false end
end
function love.mousemoved(x,y,dx,dy,isTouch)
    if isTouch then return end
    if controlsPanel then local px,py=panelPoint(x,y);return controlsPanel:mousemoved(px,py) end
    if not camera then return end
    local sw,sh=love.graphics.getDimensions()
    local sc=math.min(sw/1280,sh/880)
    touchControls:move('mouse',(x-(sw-1280*sc)*.5)/sc,(y-(sh-880*sc)*.5)/sc,1280,880,profile())
    CameraControls.move(cameraDrag,camera,dx,dy,math.min(sw/1280,sh/880))
end
function love.focus(focused)
    if not focused then pointerBoost=false;CameraControls.cancel(cameraDrag);touchControls:cancel() end
    if rideAudio then rideAudio:setPaused(not focused) end
end
function love.gamepadpressed(joy,button)
    if controlsPanel then return controlsPanel:gamepadpressed(joy,button) end
    if button=='start' then openControls();return end
    local id=Bindings.action(profile(),'controller',button);if id and not Bindings.byId[id].held then perform(id) end
end
function love.gamepadaxis(joy,axis,value)
    if controlsPanel then return controlsPanel:gamepadaxis(joy,axis,value) end
    local edge=tostring(joy)..':'..axis;local sign=math.abs(value)>.65 and (value<0 and '-' or '+') or nil
    if sign and padEdges[edge]~=sign then
        local id=Bindings.action(profile(),'controller','axis:'..axis..sign)
        if id and not Bindings.byId[id].held then perform(id) end
    end
    if math.abs(value)<.3 or sign then padEdges[edge]=sign end
end
local function ridePoint(x,y)
    local w,h=love.graphics.getDimensions();local s=math.min(w/1280,h/880)
    return (x-(w-1280*s)*.5)/s,(y-(h-880*s)*.5)/s
end
function love.touchpressed(id,x,y)
    if controlsPanel then local px,py=panelPoint(x,y);return controlsPanel:mousepressed(px,py,1) end
    local px,py=ridePoint(x,y)
    if px>=1120 and py<70 then openControls();return end
    if touchControls:press(id,px,py,1280,880,profile(),perform) then return end
    if rider.gear.mounted then
        local key=require('src.commute.cockpit').keyAt(px,py,1280,880,rider.bike,nil,camera)
        if key=='boost' then touchControls.contacts[id]={action='boost'};touchControls.held.boost=true
        elseif key then love.keypressed(key,true) end
    end
end
function love.touchmoved(id,x,y)
    if controlsPanel then local px,py=panelPoint(x,y);return controlsPanel:mousemoved(px,py) end
    local px,py=ridePoint(x,y);return touchControls:move(id,px,py,1280,880,profile())
end
function love.touchreleased(id,x,y)
    if controlsPanel then return controlsPanel:mousereleased() end
    touchControls:release(id)
end
function love.quit() if rideAudio then rideAudio:release() end;if renderer then renderer:release() end;if cockpit then cockpit:release() end end
