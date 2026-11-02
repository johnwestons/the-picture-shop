local Trip=require('src.commute.trip')
local Rider=require('src.commute.rider')
local Gear=require('src.commute.gear')
local Roads=require('src.commute.roads')
local Residents=require('src.home_residents')
local M=require('src.commute.vendor.mathx')
local CameraControls=require('src.commute.camera_controls')
local Bindings=require('src.commute.bindings')
local Touch=require('src.commute.touch_controls')
local C={}
function C.enabled() return os.getenv('PICTURE_SHOP_COMMUTE')=='1' end
function C.bindings(R)
    R.App=R.App or {};R.App.settings=R.App.settings or {}
    if not R.App.settings.motorcycleControls then R.App.settings.motorcycleControls=Bindings.defaults() end
    return R.App.settings.motorcycleControls
end
function C.touch(R)
    R._commute=R._commute or {}
    if not R._commute.touchControls then
        R._commute.touchControls=Touch.new()
        if R.mobileControls then R._commute.touchControls.visible=R.mobileControls.enabled==true;R.mobileControls:cancelAll() end
    end
    return R._commute.touchControls
end
function C.active(R) return R.state.home and R.state.home.commute~=nil end
function C.world(R)
    R._commute=R._commute or {}
    if not R._commute.world then R._commute.world=Roads.new():attach(require('src.commute.terrain').new()) end
    return R._commute.world
end
function C.localPart(R)
    local t=R.state.home and R.state.home.commute
    return t and t.participants[Residents.key(R.World.player)]
end
function C.syncPlayer(player,part)
    local actor=Rider.actor(part.rider)
    player.sceneId='commute';player.x,player.y=actor.x,actor.z
    player.moving=(actor.speed or part.presentation and part.presentation.speed or 0)>.01
    player.animationDistance=(actor.distance or 0)*48;player.resting=false
end
function C.visualRider(part,player)
    local source=part and part.rider
    if not source then return nil end
    if type(player)~='table' or player.sceneId~='commute'
        or not M.finite(player.x) or not M.finite(player.y) then return source end
    local visual={}
    for key,value in pairs(source) do visual[key]=value end
    local name=source.gear and source.gear.mounted and 'bike' or 'ped'
    local actor=source[name]
    if actor then
        local positioned={}
        for key,value in pairs(actor) do positioned[key]=value end
        positioned.x,positioned.z=player.x,player.y
        visual[name]=positioned
    end
    return visual
end
function C.restore(R)
    if not C.active(R) then return end
    R.state.home.commute=assert(Trip.restore(R.state.home.commute,C.world(R)))
    local part=C.localPart(R);if part then C.syncPlayer(R.World.player,part) end
end
function C.bind(R,player,connected)
    if not C.active(R) then return true end
    local okay,part=Trip.rebind(R.state,player,connected,C.world(R))
    if okay then C.syncPlayer(player,part) end
    return okay,part
end
local actions={equip=true,remove=true,mount=true,dismount=true,arrive=true,finish=true,force=true,cancel=true,
    automatic=true,manual=true,shiftup=true,shiftdown=true,ignition=true,headlight=true,reverse=true}
function C.decode(command)
    if type(command)~='string' or #command>40 then return nil end
    if command=='remove' then return 'remove',0 end
    local action,token=command:match('^(%a+):(%d+)$');token=tonumber(token)
    if not actions[action] or not token or token<1 or token>1e12 then return nil end
    return action,token
end
function C.command(R,player,command)
    local action,token=C.decode(command)
    if not action then return false,'invalid_action','Choose an available riding action.','commute' end
    local okay,message,event
    if token==0 then
        local resident=Residents.get(R.state,player);local gear=resident and resident.ridingGear
        if C.active(R) or not gear then return false,'wrong_scene','Use the motorcycle controls outside.','commute' end
        okay,message=Gear.begin(gear,'remove',{moving=player.moving==true})
        if okay then resident.revision=resident.revision+1;R.state.home.revision=R.state.home.revision+1 end
    elseif action=='finish' or action=='force' or action=='cancel' then
        if action=='cancel' then okay,event=Trip.cancel(R.state,player,token)
        else okay,event=Trip.finish(R.state,player,token,action=='force') end
        if okay then
            local players=require('src.weekend_runtime').players(R)
            require('src.home_residents').recover(R.state)
            require('src.home_travel').placeArrival(R.state,players,event.destination~='warehouse',{
                resolveShopSpawn=function(x,y,id,party)return R.World.resolveNetworkSpawn(x,y,id,R.Assets,R.state,party) end})
            message=event.message;R.state.screen='world';R.World.selectedInteraction=nil
        else message=event end
    else
        okay,message=Trip.command(R.state,player,token,action,C.world(R))
        if okay and action=='arrive' and (player.id or 1)==1 then
            local ready=true
            for _,part in pairs(R.state.home.commute.participants) do ready=ready and part.arrived end
            if ready then return C.command(R,player,'finish:'..token) end
            message='Waiting at the door for the other riders. F brings everyone inside.'
        end
    end
    message=message or (okay and 'Riding action started.' or 'That riding action is unavailable.')
    if okay then R.state.message=message;R.saveCurrent();if R.multiplayer:isHost() then R.multiplayer:markShopDirty() end end
    return okay,okay and 'accepted' or 'not_allowed',message,'commute'
end
function C.request(R,command)
    local okay,code,message
    if R.multiplayer:isClient() then okay,message=R.multiplayer:requestInteraction('commute',command)
    else okay,code,message=C.command(R,R.World.player,command) end
    if message then R.state.message=message end
    return okay
end
function C.localInput(R)
    local x,y=R.Input.movement();local part=C.localPart(R)
    if not part or part.arrived or part.rider.gear.transition or part.presentation and part.presentation.pose~='normal_idle'
        and part.presentation.pose~='geared_idle' and part.presentation.pose~='riding' and part.presentation.pose~='seated' then return 0,0 end
    local touch=C.touch(R);local keyboardBoost
    if part.rider.gear.mounted then x,y,keyboardBoost=Bindings.drive(C.bindings(R),touch)
    else
        if math.abs(touch.x)+math.abs(touch.y)>0 then x,y=touch.x,touch.y end
        local camera=R._commute and R._commute.camera
        if camera then x,y=camera:screenVectorToWorld(x,y) end
    end
    local view=R._commute
    return x,y,part.rider.gear.mounted and (keyboardBoost or view and view.touchBoost==true) or false
end
local function input(rider,x,y,boost)
    local magnitude=M.length(x,y)
    local steer=magnitude>1 and x/magnitude or x
    return rider.gear.mounted and {steer=steer,throttle=math.max(0,-y),brake=math.max(0,y),boost=boost==true}
        or {walkX=x,walkZ=y}
end
function C.update(R,dt,x,y,boost)
    local dirty=false
    if not R.multiplayer:isClient() then
        local players=require('src.weekend_runtime').players(R)
        if C.active(R) then
            local world=C.world(R)
            for _,player in ipairs(players) do
                local part=R.state.home.commute.participants[Residents.key(player)]
                if part then
                    local ix,iy,boostInput=0,0,false
                    if player==R.World.player then ix,iy,boostInput=x or 0,y or 0,boost==true
                    elseif R.multiplayer.clock()-(player.lastInputAt or 0)<=.35 then
                        ix,iy,boostInput=player.inputX or 0,player.inputY or 0,player.inputBoost==true
                    end
                    dirty=Trip.update(R.state,player,input(part.rider,ix,iy,boostInput),dt,world) or dirty
                    C.syncPlayer(player,part)
                end
            end
            R._commute.networkClock=(R._commute.networkClock or 0)+dt
            if R._commute.networkClock>=.1 then
                R._commute.networkClock=0
                if R.multiplayer:isHost() then R.multiplayer:markShopDirty() end
            end
            R._commute.saveClock=(R._commute.saveClock or 0)+dt
            if R._commute.saveClock>=5 then R._commute.saveClock=0;dirty=true end
        else
            for _,player in ipairs(players) do
                local resident=Residents.get(R.state,player);local gear=resident and resident.ridingGear
                if gear and Gear.update(gear,dt) then resident.revision=resident.revision+1;R.state.home.revision=R.state.home.revision+1;dirty=true end
            end
        end
        if dirty and R.multiplayer:isHost() then R.multiplayer:markShopDirty() end
    end
    local part=C.localPart(R)
    if part then
        local world=C.world(R);local rider=C.visualRider(part,R.World.player)
        local actor=Rider.actor(rider);local view=R._commute
        if not view.camera then view.camera=require('src.commute.camera').new(actor,world);view.camera.zoom=1;view.camera.targetZoom=1 end
        actor.h=world:supportHeight(actor.x,actor.z)
        view.camera:updateRide(rider,dt,part.presentation)
        if R.state.screen=='world' then Bindings.camera(C.bindings(R),view.camera,dt,view.touchControls) end
        if not view.renderer then view.renderer=require('src.commute.renderer').new(world) end
        view.renderer.characterAssets=R.CharacterAssets
        view.renderer.calendar=R.state.calendar
        view.renderer:prepare(view.camera,dt)
    end
    return dirty
end
function C.draw(R)
    local part=C.localPart(R);local view=R._commute
    if not part or not view or not view.renderer then return end
    local bindings=C.bindings(R)
    local g=love.graphics;local scale=math.min(R.Config.baseWidth/1280,R.Config.baseHeight/880)
    g.push();g.translate((R.Config.baseWidth-1280*scale)*.5,(R.Config.baseHeight-880*scale)*.5);g.scale(scale)
    local localId=R.multiplayer.localId or 1;local playersById={}
    for _,player in ipairs(R.multiplayer:remotePlayers()) do playersById[player.id]=player end
    local actors={}
    for id,p in pairs(R.state.home.commute.participants) do
        local player=p.slot==localId and R.World.player or playersById[p.slot]
        local r=C.visualRider(p,player)
        actors[#actors+1]={actor=r.bike,bikeOnly=not r.gear.mounted,presentation=p.presentation}
        if not r.gear.mounted then actors[#actors+1]={actor=r.ped,gear=r.gear,presentation=p.presentation,appearance=p.appearance} end
    end
    view.renderer:draw(view.camera,Rider.actor(C.visualRider(part,R.World.player)),actors)
    for _,id in ipairs({R.state.home.commute.origin,R.state.home.commute.destination}) do
        local p=Roads.destinations[id];local sx,sy=view.camera:screen(p.x,p.z-3,p.h+.1)
        g.setColor(.9,.8,.45);g.circle('line',sx,sy,18);g.print('DOOR',sx-18,sy-30)
    end
    g.pop()
    g.setColor(.025,.04,.035,.92);g.rectangle('fill',12,12,R.Config.baseWidth-24,view.camera.firstPerson and 80 or 109,7)
    g.setColor(.95,.89,.70)
    local target=Roads.destinations[R.state.home.commute.destination]
    g.print((view.camera.firstPerson and 'RIDER VIEW — ' or 'THE WAY HOME — ')..target.label,25,22)
    g.setColor(.8,.87,.81)
    if view.camera.firstPerson then
        g.print(Bindings.hint(bindings,'accelerate')..': accelerate  '..Bindings.hint(bindings,'brake')..': brake  '..Bindings.hint(bindings,'view')..': view  F10: controls/options',25,44)
        g.print(tostring(R.state.message or 'I: ignition    B: reverse    H: headlight    E: dismount when stopped'),25,63)
    else
        g.print(Bindings.hint(bindings,'interact')..': mount / door  '..Bindings.hint(bindings,'gear')..': riding gear  '..Bindings.hint(bindings,'boost')..': boost  F10: controls/options',25,44)
        g.print(Bindings.label(bindings.mouse.orbit)..': rotate / tilt  '..Bindings.label(bindings.mouse.pan)..': pan  '..Bindings.hint(bindings,'panModifier')..': pan modifier',25,63)
    end
    local pose=part.presentation and part.presentation.pose or Gear.pose(part.rider.gear)
    if not view.camera.firstPerson then g.print('Development artwork · '..pose..' · '..tostring(R.state.message or ''),25,84) end
    if part.rider.gear.mounted then
        if not view.cockpit then view.cockpit=require('src.commute.cockpit').new() end
        view.cockpit:draw(part.rider.bike,part.rider.gear.engine,R.Config.baseWidth,R.Config.baseHeight,part.presentation,view.camera,C.bindings(R))
    end
    C.touch(R):draw(R.Config.baseWidth,R.Config.baseHeight,C.bindings(R))
    g.setColor(1,1,1)
end
function C.keypressed(R,key,semantic)
    if R.state.screen~='world' then return false end
    if not C.active(R) then
        if semantic and key=='g' or not semantic and key==C.bindings(R).keyboard.gear then
            local gear=require('src.commute.outfit').get(R.state,R.World.player)
            if gear and gear.outfit=='geared' then C.request(R,'remove');return true end
        end
        local gear=require('src.commute.outfit').get(R.state,R.World.player)
        if gear and (gear.outfit=='geared' or gear.transition) then
            local target=R.World.getInteraction and R.World.getInteraction()
            if key=='escape' or key=='back' or key=='e' and target and target.kind=='homeTravel' then return false end
            R.state.message='Take off your riding gear with '..Bindings.hint(C.bindings(R),'gear')..' before using other activities.'
            return true
        end
        return false
    end
    local part=C.localPart(R);if not part then return false end
    if not semantic then
        if key=='escape' or key=='back' then C.cancelCameraDrag(R);return false end
        if key=='f10' then
            C.cancelCameraDrag(R)
            if R.openOptions then R.openOptions() end
            if R.OptionsScreen and R.OptionsScreen.openMotorcycleControls then R.OptionsScreen.openMotorcycleControls() end
            return true
        end
        local id=Bindings.action(C.bindings(R),'keyboard',key)
        if not id or Bindings.byId[id].held then return true end
        key=Bindings.byId[id].main
        if not key or key=='' then return true end
    end
    local t=R.state.home.commute;local r=part.rider;local camera=R._commute and R._commute.camera
    if key=='p' and camera then
        if camera:toggleView(r) then R.state.message=camera.firstPerson and 'First-person view. C centers your view.' or 'Outside view.' end
    elseif key=='g' then C.request(R,(r.gear.outfit=='normal' and 'equip:' or 'remove:')..t.token)
    elseif key=='i' then C.request(R,'ignition:'..t.token)
    elseif key=='h' then C.request(R,'headlight:'..t.token)
    elseif key=='b' then C.request(R,'reverse:'..t.token)
    elseif key=='v' then C.request(R,(r.bike.transmission=='manual' and 'automatic:' or 'manual:')..t.token)
    elseif key=='z' then C.request(R,'shiftdown:'..t.token)
    elseif key=='x' then C.request(R,'shiftup:'..t.token)
    elseif key=='f' then C.request(R,'force:'..t.token)
    elseif key=='e' or key=='return' then
        if part.arrived then C.request(R,'finish:'..t.token)
        elseif r.gear.mounted then C.request(R,'dismount:'..t.token)
        else
            local dest,origin=Roads.destinations[t.destination],Roads.destinations[t.origin]
            local function near(p)return M.length(r.ped.x-p.x,r.ped.z-(p.z-3))<=1.8 end
            C.request(R,(near(dest) and 'arrive:' or near(origin) and 'cancel:' or 'mount:')..t.token)
        end
    elseif key=='q' and camera then camera:orbit(-15,0)
    elseif key=='r' and camera then camera:orbit(15,0)
    elseif key=='t' and camera then camera:orbit(0,5)
    elseif key=='y' and camera then camera:orbit(0,-5)
    elseif key=='c' and camera then camera:recenter()
    elseif key=='=' and camera then camera:zoomBy(1)
    elseif key=='-' and camera then camera:zoomBy(-1)
    elseif key=='escape' or key=='back' then C.cancelCameraDrag(R);return false end
    return true
end
function C.perform(R,id)
    local spec=Bindings.byId[id]
    return spec and spec.main and spec.main~='' and C.keypressed(R,spec.main,true) or false
end
function C.deviceInput(R,device,token)
    if R.state.screen~='world' or not C.active(R) then return false end
    local id=Bindings.action(C.bindings(R),device,token)
    if id then
        if not Bindings.byId[id].held then C.perform(R,id) end
        return true
    end
    return device=='controller' or device=='mouse'
end
function C.gamepadaxis(R,joystick,axis,value)
    if R.state.screen~='world' or not C.active(R) then return false end
    local view=R._commute or {};R._commute=view;view.axisEdges=view.axisEdges or {}
    local edge=tostring(joystick)..':'..axis
    local sign=math.abs(value)>.65 and (value<0 and '-' or '+') or nil
    if sign and view.axisEdges[edge]~=sign then C.deviceInput(R,'controller','axis:'..axis..sign) end
    if math.abs(value)<.3 or sign then view.axisEdges[edge]=sign end
    return true
end
function C.touchPressed(R,id,x,y)
    if R.state.screen~='world' or not C.active(R) then return false end
    local touch=C.touch(R)
    if touch:press(id,x,y,R.Config.baseWidth,R.Config.baseHeight,C.bindings(R),function(action) C.perform(R,action) end) then return true end
    return C.pointer(R,x,y,id)
end
function C.touchMoved(R,id,x,y)
    local view=R._commute
    return view and view.touchControls and view.touchControls:move(id,x,y,R.Config.baseWidth,R.Config.baseHeight,C.bindings(R)) or false
end
function C.touchReleased(R,id)
    local view=R._commute
    if view and view.touchControls then return view.touchControls:release(id) end
    return false
end
function C.pointer(R,x,y,source)
    if R.state.screen~='world' then return false end
    local part=C.localPart(R)
    if not part or not part.rider.gear.mounted then return false end
    local key=require('src.commute.cockpit').keyAt(x,y,R.Config.baseWidth,R.Config.baseHeight,part.rider.bike,part.presentation,R._commute and R._commute.camera)
    if key=='boost' then
        R._commute=R._commute or {}
        R._commute.touchBoost=true;R._commute.touchBoostSource=source or 'pointer'
        return true
    end
    return key and C.keypressed(R,key,true) or false
end
function C.pointerReleased(R,source)
    local view=R._commute
    if not view or not view.touchBoost or source~=nil and view.touchBoostSource~=source then return false end
    view.touchBoost=false;view.touchBoostSource=nil
    return true
end
function C.cameraPointerPressed(R,button,leftAlt)
    local view=R._commute
    if R.state.screen~='world' or not C.active(R) or not view or not view.camera then return false end
    view.cameraDrag=view.cameraDrag or {}
    local profile=C.bindings(R)
    if leftAlt==nil then local key=profile.keyboard.panModifier;leftAlt=key~='' and love.keyboard.isDown(key) end
    return CameraControls.press(view.cameraDrag,button,leftAlt,profile)
end
function C.cancelCameraDrag(R)
    local view=R._commute
    if view and view.cameraDrag then CameraControls.cancel(view.cameraDrag) end
    if view and view.touchControls then view.touchControls:cancel() end
    if view then view.touchBoost=false end
end
function C.cameraPointerReleased(R,button)
    local view=R._commute
    return view and view.cameraDrag and CameraControls.release(view.cameraDrag,button) or false
end
function C.cameraPointerMoved(R,dx,dy)
    local view=R._commute
    if R.state.screen~='world' or not C.active(R) then C.cancelCameraDrag(R);return false end
    if not view or not view.cameraDrag then return false end
    local scale=math.min(R.Config.baseWidth/1280,R.Config.baseHeight/880)
    return CameraControls.move(view.cameraDrag,view.camera,dx,dy,scale)
end
function C.release(R)
    if R._commute and R._commute.renderer then R._commute.renderer:release() end
    if R._commute and R._commute.cockpit then R._commute.cockpit:release() end
    R._commute=nil
end
return C
