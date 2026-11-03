local Trip=require('src.commute.trip')
local Rider=require('src.commute.rider')
local Gear=require('src.commute.gear')
local Town=require('src.commute.town')
local Upgrades=require('src.commute.bike_upgrades')
local Paint=require('src.commute.bike_paint')
local Repairs=require('src.commute.bike_repairs')
local Residents=require('src.home_residents')
local M=require('src.commute.vendor.mathx')
local CameraControls=require('src.commute.camera_controls')
local Bindings=require('src.commute.bindings')
local Touch=require('src.commute.touch_controls')
local Cockpit=require('src.commute.cockpit')
local Icons=require('src.commute.ui_icons')
local C={}
function C.enabled() return os.getenv('PICTURE_SHOP_COMMUTE')~='0' end
function C.bindings(R)
    R.App=R.App or {};R.App.settings=R.App.settings or {}
    if not R.App.settings.motorcycleControls then R.App.settings.motorcycleControls=Bindings.defaults() end
    return R.App.settings.motorcycleControls
end
function C.applyCameraPreference(R,camera,rider)
    local mode=C.bindings(R).outsideCamera=='follow' and 'follow' or 'fixed'
    if camera and camera.outsideMode~=mode then
        camera:setOutsideMode(mode,Rider.actor(rider),rider.gear.mounted and not rider.gear.transition)
    end
end
function C.toggleOutsideCamera(R)
    local part=C.localPart(R);if not part then return false end
    local profile=C.bindings(R)
    profile.outsideCamera=profile.outsideCamera=='follow' and 'fixed' or 'follow'
    C.cancelCameraDrag(R)
    C.applyCameraPreference(R,R._commute and R._commute.camera,part.rider)
    local saved=require('src.settings').save(R.App.settings)
    local label=profile.outsideCamera=='follow' and 'Follow rider' or 'Fixed angle'
    R.state.message=label..' outside camera.'..(saved and '' or ' Active this session; preferences could not be saved.')
    return true
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
    local town=R.state.home and R.state.home.town
    local id=town and town.id or 'original-valley-v3'
    if R._commute.world and R._commute.world.townId~=id then C.release(R);R._commute={} end
    if not R._commute.world then R._commute.world=Town.world(town) end
    R._commute.world.calendar=R.state.calendar
    return R._commute.world
end
function C.localPart(R)
    local t=R.state.home and R.state.home.commute
    return t and t.participants[Residents.key(R.World.player)]
end
function C.mapRect(R)
    return {x=24,y=132,width=R.Config.baseWidth-48,height=R.Config.baseHeight-156}
end
function C.mapButton(R)
    local view=R._commute
    if not C.localPart(R) or not view or not view.renderer or view.loading or view.mechanicOffer then return nil end
    local _,bounds
    if R.optionsAccessLayout then _,bounds=R.optionsAccessLayout() end
    local right=bounds and bounds.right or R.Config.baseWidth
    return {x=right-140,y=58,width=122,height=32}
end
function C.mobileInputEnabled(R)
    return R.mobileControls and R.mobileControls.isEnabled and R.mobileControls:isEnabled() or false
end
function C.controlContext(R,part)
    part=part or C.localPart(R)
    local rider=part and part.rider
    local gear=rider and rider.gear or {}
    local bike=rider and rider.bike or {}
    local view=R._commute or {}
    return {
        mounted=gear.mounted==true,engine=gear.engine==true,gearOutfit=gear.outfit,
        gearTransition=gear.transition~=nil,arrived=part and part.arrived==true,
        transmission=bike.transmission,reverse=bike.reverse==true,
        headlight=bike.headlight==true,outsideMode=view.camera and view.camera.outsideMode
            or C.bindings(R).outsideCamera or 'fixed',
    }
end
function C.cameraButton(R)
    local map=C.mapButton(R);if not map then return nil end
    return {x=map.x-94,y=map.y,width=88,height=map.height}
end
function C.toggleMap(R)
    if not C.mapButton(R) then return false end
    C.cancelCameraDrag(R)
    local view=R._commute
    view.mapOpen=not view.mapOpen
    if view.mapOpen and not view.routeMap then view.routeMap=require('src.commute.route_map').new(C.world(R)) end
    return true
end
function C.mapPointer(R,x,y)
    local button=C.mapButton(R)
    if not button then return false end
    if x>=button.x and x<=button.x+button.width and y>=button.y and y<=button.y+button.height then
        return C.toggleMap(R)
    end
    -- A tap on the map must never activate the covered bike controls.
    return R._commute.mapOpen==true
end
function C.drawMap(R,part)
    local button=C.mapButton(R)
    if not button then return end
    local g=love.graphics;g.push('all')
    local view=R._commute
    if view.mapOpen then
        if not view.routeMap then view.routeMap=require('src.commute.route_map').new(C.world(R)) end
        local trip=R.state.home.commute
        view.routeMap:draw(C.mapRect(R),Rider.actor(C.visualRider(part,R.World.player)),{
            origin=trip.origin,destination=trip.destination,home=R.state.home.apartmentId,
            bike=not part.rider.gear.mounted and part.rider.bike or nil,
            closeHint=Bindings.hint(C.bindings(R),'map')..' / Esc: close map'})
    end
    require('src.screens.ui').panel(button,{.10,.15,.15,1},{.43,.53,.51,1},6,1)
    g.setColor(.94,.95,.89)
    Icons.draw('map',button.x+15,button.y+button.height*.5,20)
    local label=view.mapOpen and 'CLOSE' or 'MAP'
    if not C.mobileInputEnabled(R) then label=label..'  ['..Bindings.hint(C.bindings(R),'map')..']' end
    g.printf(label,
        button.x+28,button.y+(button.height-g.getFont():getHeight())/2,button.width-30,'center')
    g.pop()
end
function C.drawCameraButton(R)
    local button=C.cameraButton(R);if not button then return false end
    local view=R._commute;local g=love.graphics
    g.push('all')
    require('src.screens.ui').panel(button,{.10,.15,.15,1},{.43,.53,.51,1},6,1)
    g.setColor(.94,.95,.89)
    Icons.draw('camera',button.x+13,button.y+button.height*.5,18)
    local label=view.camera and view.camera.firstPerson and 'OUTSIDE' or 'CAM'
    if not C.mobileInputEnabled(R) then label=label..'  ['..Bindings.hint(C.bindings(R),'view')..']' end
    g.printf(label,
        button.x+25,button.y+(button.height-g.getFont():getHeight())/2,button.width-27,'center')
    g.pop()
    return true
end
function C.cameraPointer(R,x,y)
    local button=C.cameraButton(R)
    if not button or x<button.x or x>button.x+button.width
        or y<button.y or y>button.y+button.height then return false end
    C.keypressed(R,'p',true)
    return true
end
function C.syncPlayer(player,part)
    local actor=Rider.actor(part.rider)
    player.sceneId='commute';player.x,player.y=actor.x,actor.z
    player.moving=(part.presentation and part.presentation.speed or actor.speed or 0)>.01
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
        if name=='bike' and part.presentation then
            for _,key in ipairs({'h','vy','grounded','suspension','landingPulse','pitch'}) do
                if part.presentation[key]~=nil then positioned[key]=part.presentation[key] end
            end
        end
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
    if type(command)~='string' or #command>80 then return nil end
    local repairToken,repairRevision,damage=command:match('^bikerepair:(%d+):(%d+):(%d+)$')
    if repairToken then
        repairToken,repairRevision,damage=tonumber(repairToken),tonumber(repairRevision),tonumber(damage)
        if repairToken>=1 and repairToken<=1e12 and Repairs.validRevision(repairRevision) and Repairs.validQuotedDamage(damage) then
            return 'bikerepair',repairToken,{token=repairToken,expectedRepairRevision=repairRevision,expectedDamage=damage}
        end
        return nil
    end
    local paintToken,paintRevision,paintId=command:match('^bikepaint:(%d+):(%d+):([a-z]+)$')
    if paintToken then
        paintToken,paintRevision=tonumber(paintToken),tonumber(paintRevision)
        if paintToken>=1 and paintToken<=1e12 and Paint.validRevision(paintRevision) and Paint.valid(paintId) then
            return 'bikepaint',paintToken,{token=paintToken,paintId=paintId,expectedPaintRevision=paintRevision}
        end
        return nil
    end
    local token,expected,level=command:match('^bikeupgrade:(%d+):([012]):([123])$')
    if token then
        token,expected,level=tonumber(token),tonumber(expected),tonumber(level)
        if token>=1 and token<=1e12 and level==expected+1 then
            return 'bikeupgrade',token,{token=token,expectedLevel=expected,level=level}
        end
        return nil
    end
    local revision;token,revision,level=command:match('^upgrade:(%d+):(%d+):([123])$')
    if token then
        token,revision,level=tonumber(token),tonumber(revision),tonumber(level)
        if token>=1 and token<=1e12 and revision>=0 and revision<=1e12 then
            return 'upgrade',token,{token=token,expectedRevision=revision,level=level}
        end
        return nil
    end
    if command=='remove' then return 'remove',0 end
    local action;action,token=command:match('^(%a+):(%d+)$');token=tonumber(token)
    if not actions[action] or not token or token<1 or token>1e12 then return nil end
    return action,token
end
function C.command(R,player,command)
    local action,token,intent=C.decode(command)
    if not action then return false,'invalid_action','Choose an available riding action.','commute' end
    local okay,message,event
    if action=='bikerepair' then
        okay,message=Repairs.purchase(R.state,player,R.state.home.commute,C.world(R),intent)
    elseif action=='bikepaint' then
        okay,message=Paint.purchase(R.state,player,R.state.home.commute,C.world(R),intent)
    elseif action=='upgrade' or action=='bikeupgrade' then
        okay,message=Upgrades.purchase(R.state,player,R.state.home.commute,C.world(R),intent)
        if action=='upgrade' and R._commute and R._commute.mechanicOffer then require('src.commute.mechanic_shop').close(R) end
    elseif token==0 then
        local resident=Residents.get(R.state,player);local gear=resident and resident.ridingGear
        if C.active(R) or not gear then return false,'wrong_scene','Use the motorcycle controls outside.','commute' end
        okay,message=Gear.begin(gear,'remove',{moving=player.moving==true})
        if okay then resident.revision=resident.revision+1;R.state.home.revision=R.state.home.revision+1 end
    elseif action=='finish' or action=='force' or action=='cancel' then
        if action=='cancel' then okay,event=Trip.cancel(R.state,player,token,C.world(R))
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
    if R._commute and (R._commute.mechanicOffer or R._commute.loading) then return 0,0,false end
    if not part or part.arrived or part.rider.gear.transition or part.presentation and part.presentation.pose~='normal_idle'
        and part.presentation.pose~='geared_idle' and part.presentation.pose~='riding' and part.presentation.pose~='seated' then return 0,0 end
    local touch=C.touch(R);local keyboardBoost
    if part.rider.gear.mounted then
        local view=R._commute
        x,y,keyboardBoost=Bindings.drive(C.bindings(R),touch,view and view.camera,part.rider.bike)
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
    if R._commute and R._commute.mechanicOffer then require('src.commute.mechanic_shop').update(R,dt) end
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
        C.applyCameraPreference(R,view.camera,rider)
        if not rider.gear.mounted or not M.finite(actor.h) then actor.h=world:supportHeight(actor.x,actor.z) end
        view.camera:updateRide(rider,dt,part.presentation)
        if R.state.screen=='world' and not view.mechanicOffer and not view.loading and not view.mapOpen then Bindings.camera(C.bindings(R),view.camera,dt,view.touchControls) end
        if view.mechanicOffer then return dirty end
        if not view.renderer then
            -- Present a loading frame before decoding/uploading shared ride art.
            if not view.loading then view.loading=true;return dirty end
            view.renderer=require('src.commute.renderer').new(world)
            view.renderer:prewarmViews()
            view.cockpit=require('src.commute.cockpit').new()
            view.cockpit:prewarmFirstPerson()
            Icons.prewarm()
        end
        view.renderer.characterAssets=R.CharacterAssets
        view.renderer.calendar=R.state.calendar
        view.renderer:prepare(view.camera,dt)
        if view.loading and view.renderer:terrainReady()
            and view.renderer.vegetation:stats().pending==0
            and view.renderer.plantSprites:readyFor(view.renderer.visibleProps,view.renderer.calendar,view.renderer.clock) then
            view.loading=nil
        end
    end
    return dirty
end
function C.draw(R)
    local part=C.localPart(R);local view=R._commute
    if not part or not view then return end
    if view.mechanicOffer and C.drawMechanic(R) then return end
    if not view.renderer or view.loading then
        local g=love.graphics
        g.clear(.025,.04,.035,1);g.setColor(.95,.89,.70)
        g.printf('Preparing your ride…',20,R.Config.baseHeight*.46,R.Config.baseWidth-40,'center')
        g.setColor(.75,.82,.76)
        local message='Loading your saved town and motorcycle.'
        if view.renderer then
            local stats=view.renderer:terrainStats()
            message=stats.ready and 'Preparing roadside scenery.'
                or ('Preparing the complete terrain: %d%%'):format(math.floor(100*stats.completed/math.max(1,stats.total)))
        end
        g.printf(message,20,R.Config.baseHeight*.46+30,R.Config.baseWidth-40,'center')
        g.setColor(1,1,1);return
    end
    local bindings=C.bindings(R)
    local g=love.graphics;local scale=math.min(R.Config.baseWidth/1280,R.Config.baseHeight/880)
    if view.mapOpen then g.clear(.025,.04,.035,1) else
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
        local p=view.world.sites.byId[id].door;local sx,sy=view.camera:screen(p.x,p.z,p.h+.1)
        g.setColor(.9,.8,.45);g.circle('line',sx,sy,18);g.print('DOOR',sx-18,sy-30)
    end
    g.pop()
    end
    local target=view.world.roads.destinations[R.state.home.commute.destination]
    local hint=Cockpit.riderHint(part.rider,part.presentation)
    local routeLabel=(R.state.home.commute.purpose=='outing' and 'TOWN OUTING' or 'RIDE HOME')
        ..'  ·  '..target.label..Cockpit.conditionLabel(part.rider.bike)
    local routeWidth=math.min(610,g.getFont():getWidth(routeLabel)+20)
    g.setColor(.025,.04,.035,.84);g.rectangle('fill',16,14,routeWidth,34,7)
    g.setColor(.95,.89,.70);g.print(routeLabel,25,23)
    local note=hint or R.state.message
    local mobile=C.mobileInputEnabled(R)
    if not mobile then
        g.setColor(.76,.83,.76)
        g.print(Bindings.hint(bindings,'accelerate')..' GO  ·  '..Bindings.hint(bindings,'brake')
            ..' BRAKE  ·  '..Bindings.hint(bindings,'left')..' / '..Bindings.hint(bindings,'right')
            ..' STEER  ·  drag to look',16,64)
    end
    if note and tostring(note)~='' then
        local noteY=mobile and 53 or 91
        local noteWidth=math.min(630,g.getFont():getWidth(tostring(note))+18)
        g.setColor(.025,.04,.035,.72);g.rectangle('fill',16,noteY,noteWidth,27,6)
        g.setColor(.83,.88,.80);g.printf(tostring(note),24,noteY+7,620,'left')
    end
    if part.rider.gear.mounted and not view.mapOpen then
        if not view.cockpit then view.cockpit=require('src.commute.cockpit').new() end
        view.cockpit:draw(part.rider.bike,part.rider.gear.engine,R.Config.baseWidth,R.Config.baseHeight,part.presentation,view.camera,C.bindings(R))
    end
    if not view.mapOpen then
        C.touch(R):draw(R.Config.baseWidth,R.Config.baseHeight,bindings,C.controlContext(R,part),
            {mobile=mobile,showActions=true})
    end
    C.drawCameraButton(R)
    C.drawMap(R,part)
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
    if R._commute and R._commute.loading and key~='escape' and key~='back' and key~='f10' then return true end
    if R._commute and R._commute.mechanicOffer then
        if key==(semantic and 'e' or C.bindings(R).keyboard.interact) then key='e' end
        return require('src.commute.mechanic_shop').keypressed(R,key)
    end
    if R._commute and R._commute.mapOpen and (key=='escape' or key=='back') then
        return C.toggleMap(R)
    end
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
    if key=='m' then C.toggleMap(R)
    elseif key=='p' and camera then
        if camera:toggleView(r) then
            R.state.message=camera.firstPerson and ('First-person view. '..Bindings.hint(C.bindings(R),'recenter')..' centers your view.')
                or (camera.outsideMode=='follow' and 'Follow rider camera.' or 'Fixed-angle camera.')
        end
    elseif key=='o' then C.toggleOutsideCamera(R)
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
            local sites=C.world(R).sites.byId
            local function near(p)return p and M.length(r.ped.x-p.door.x,r.ped.z-p.door.z)<=1.8 end
            if near(sites.mechanic) then C.openMechanic(R)
            else C.request(R,(near(sites[t.destination]) and 'arrive:' or near(sites[t.origin]) and 'cancel:' or 'mount:')..t.token) end
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
    if R._commute and R._commute.mechanicOffer and device=='controller' then
        local key=({b='escape',x='tab',leftshoulder='tab',rightshoulder='tab',back='escape',a='return',dpup='up',dpdown='down',dpleft='left',dpright='right'})[token]
        if key then require('src.commute.mechanic_shop').keypressed(R,key) end
        return true
    end
    local id=Bindings.action(C.bindings(R),device,token)
    if R._commute and R._commute.mapOpen and device=='mouse' and id~='map' then return true end
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
function C.gearTouchButton(R)
    if R.state.screen~='world' or R.World.player.sceneId~='commute' then return nil end
    local part=C.localPart(R)
    if not part or part.arrived or part.rider.gear.mounted or R._commute and R._commute.loading then return nil end
    local gear=part.rider.gear
    local width,height=R.Config.baseWidth,R.Config.baseHeight
    for _,button in ipairs(Touch.actionButtons(width,height,C.bindings(R),C.controlContext(R,part),{mobile=true})) do
        if button.action=='gear' then
            local diameter=button.hitRadius*2
            return {x=button.x-button.hitRadius,y=button.y-button.hitRadius,width=diameter,height=diameter,
                enabled=gear.transition==nil,
        label=gear.transition and 'CHANGING GEAR...' or gear.outfit=='normal' and 'PUT ON GEAR' or 'REMOVE GEAR'}
        end
    end
end
function C.drawGearTouch(R)
    local button=C.gearTouchButton(R)
    if not button or not (C.touch(R).visible or C.bindings(R).showTouch) then return false end
    local g=love.graphics;g.push('all')
    g.setColor(.025,.055,.045,.94);g.rectangle('fill',button.x,button.y,button.width,button.height,7)
    if button.enabled then g.setColor(.95,.87,.52,1) else g.setColor(.42,.48,.43,.85) end
    g.rectangle('line',button.x,button.y,button.width,button.height,7)
    g.printf(button.label,button.x+8,button.y+16,button.width-16,'center')
    g.pop();return true
end
function C.touchPressed(R,id,x,y)
    if R.state.screen~='world' or R.World.player.sceneId~='commute' or not C.localPart(R) then return false end
    local view=R._commute
    if not view or not view.renderer or view.loading then return true end
    if R._commute and R._commute.mechanicOffer then C.pointer(R,x,y,id);return true end
    if C.mapPointer(R,x,y) then return true end
    if C.cameraPointer(R,x,y) then return true end
    local touch=C.touch(R)
    local part=C.localPart(R)
    if touch:press(id,x,y,R.Config.baseWidth,R.Config.baseHeight,C.bindings(R),
        function(action) C.perform(R,action) end,C.controlContext(R,part),{mobile=true}) then return true end
    return C.cameraTouchPressed(R,id,x,y)
end
function C.touchMoved(R,id,x,y)
    local view=R._commute
    if view and view.touchControls and view.touchControls:move(id,x,y,R.Config.baseWidth,R.Config.baseHeight,C.bindings(R)) then return true end
    return C.cameraTouchMoved(R,id,x,y)
end
function C.touchReleased(R,id)
    local view=R._commute
    if view and view.touchControls and view.touchControls:release(id) then return true end
    return C.cameraTouchReleased(R,id)
end
function C.pointer(R,x,y,source)
    if R.state.screen~='world' then return false end
    local offer=R._commute and R._commute.mechanicOffer
    if offer then return require('src.commute.mechanic_shop').pointer(R,x,y) end
    if R.World.player.sceneId=='commute' and C.localPart(R)
        and (not R._commute or not R._commute.renderer or R._commute.loading) then return true end
    if C.mapPointer(R,x,y) then return true end
    if C.cameraPointer(R,x,y) then return true end
    local part=C.localPart(R)
    if not part then return false end
    local mobile=C.mobileInputEnabled(R)
    local action=Touch.actionAt(x,y,R.Config.baseWidth,R.Config.baseHeight,C.bindings(R),
        C.controlContext(R,part),{mobile=mobile})
    if action then
        if not action.enabled then return true end
        local spec=Bindings.byId[action.action]
        if spec and spec.held then
            R._commute=R._commute or {}
            local touch=C.touch(R);touch.held[action.action]=true
            R._commute.pointerAction=action.action;R._commute.pointerActionSource=source or 'pointer'
            return true
        end
        return C.perform(R,action.action) or true
    end
    if not part.rider.gear.mounted then return false end
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
    if view and view.pointerAction and (source==nil or source==view.pointerActionSource) then
        local action=view.pointerAction;local touch=view.touchControls
        if touch then
            touch.held[action]=nil
            for _,contact in pairs(touch.contacts) do if contact.action==action then touch.held[action]=true end end
        end
        view.pointerAction=nil;view.pointerActionSource=nil
        return true
    end
    if not view or not view.touchBoost or source~=nil and view.touchBoostSource~=source then return false end
    view.touchBoost=false;view.touchBoostSource=nil
    return true
end
function C.cameraPointerPressed(R,button,leftAlt)
    local view=R._commute
    if R.state.screen~='world' or not C.active(R) or not view or not view.camera or not view.renderer or view.loading or view.mechanicOffer or view.mapOpen then return false end
    view.cameraDrag=view.cameraDrag or {}
    local profile=C.bindings(R)
    if leftAlt==nil then local key=profile.keyboard.panModifier;leftAlt=key~='' and love.keyboard.isDown(key) end
    return CameraControls.press(view.cameraDrag,button,leftAlt,profile)
end
function C.cancelCameraDrag(R)
    local view=R._commute
    if view and view.cameraDrag then CameraControls.cancel(view.cameraDrag) end
    if view and view.touchControls then view.touchControls:cancel() end
    if view then view.cameraTouches=nil;view.cameraPinch=nil end
    if view then
        view.touchBoost=false;view.pointerAction=nil;view.pointerActionSource=nil
    end
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
function C.cameraTouchPressed(R,id,x,y)
    local view=R._commute
    if R.state.screen~='world' or not C.active(R) or not view or not view.camera or not view.renderer
        or view.loading or view.mechanicOffer or view.mapOpen then return false end
    view.cameraTouches=view.cameraTouches or {}
    view.cameraTouches[id]={x=x,y=y}
    local firstId,first
    for otherId,touch in pairs(view.cameraTouches) do
        if otherId~=id then firstId,first=otherId,touch;break end
    end
    if first then
        C.cameraPointerReleased(R,3)
        local dx,dy=x-first.x,y-first.y
        view.cameraPinch={firstId,id,distance=math.max(1,math.sqrt(dx*dx+dy*dy))}
    else
        view.cameraDrag=view.cameraDrag or {}
        CameraControls.press(view.cameraDrag,3,false)
    end
    return true
end
function C.cameraTouchMoved(R,id,x,y)
    local view=R._commute;local touch=view and view.cameraTouches and view.cameraTouches[id]
    if not touch then return false end
    local dx,dy=x-touch.x,y-touch.y
    touch.x,touch.y=x,y
    local pinch=view.cameraPinch
    if pinch then
        local first,second=view.cameraTouches[pinch[1]],view.cameraTouches[pinch[2]]
        if first and second then
            local sx,sy=second.x-first.x,second.y-first.y
            local distance=math.max(1,math.sqrt(sx*sx+sy*sy))
            if pinch.distance>0 then view.camera:zoomBy(math.log(distance/pinch.distance)/.12) end
            pinch.distance=distance
            return true
        end
    end
    return C.cameraPointerMoved(R,dx,dy)
end
function C.cameraTouchReleased(R,id)
    local view=R._commute
    if not view or not view.cameraTouches or not view.cameraTouches[id] then return false end
    view.cameraTouches[id]=nil
    local pinch=view.cameraPinch
    if pinch then
        view.cameraPinch=nil
        local remainingId=pinch[1]==id and pinch[2] or pinch[1]
        if view.cameraTouches[remainingId] then CameraControls.press(view.cameraDrag or {},3,false)
        else C.cameraPointerReleased(R,3) end
    else C.cameraPointerReleased(R,3) end
    return true
end
function C.release(R)
    if R._commute and R._commute.mechanicOffer then require('src.commute.mechanic_shop').close(R) end
    if R._commute and R._commute.renderer then R._commute.renderer:release() end
    if R._commute and R._commute.cockpit then R._commute.cockpit:release() end
    if R._commute and R._commute.routeMap then R._commute.routeMap:release() end
    Icons.release()
    R._commute=nil
end
function C.openMechanic(R)
    C.cancelCameraDrag(R)
    if R._commute then R._commute.mapOpen=false end
    return require('src.commute.mechanic_shop').open(R)
end
function C.buyUpgrade(R) return require('src.commute.mechanic_shop').confirm(R) end
function C.drawMechanic(R) return require('src.commute.mechanic_shop').draw(R) end
return C
