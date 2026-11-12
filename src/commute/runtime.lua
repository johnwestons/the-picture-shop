local Trip=require('src.commute.trip')
local Rider=require('src.commute.rider')
local Gear=require('src.commute.gear')
local Town=require('src.commute.town')
local Upgrades=require('src.commute.bike_upgrades')
local Paint=require('src.commute.bike_paint')
local Repairs=require('src.commute.bike_repairs')
local BikeTires=require('src.commute.bike_tires')
local Service=require('src.commute.bike_service')
local TruckService=require('src.commute.truck_service')
local TruckMechanic=require('src.commute.truck_mechanic')
local Station=require('src.commute.gas_station')
local TownStore=require('src.commute.town_store')
local Residents=require('src.home_residents')
local M=require('src.commute.vendor.mathx')
local CameraControls=require('src.commute.camera_controls')
local CameraMenu=require('src.commute.camera_menu')
local Bindings=require('src.commute.bindings')
local Touch=require('src.commute.touch_controls')
local Cockpit=require('src.commute.cockpit')
local Icons=require('src.commute.ui_icons')
local DoorTransition=require('src.commute.door_transition')
local C={}
local DOOR_PROMPT_RADIUS=3.0
local function sceneTransform(R)
    local width,height=R.Config.baseWidth,R.Config.baseHeight
    if R.Viewport and R.Viewport.fullScreenDevice and R.Viewport.fullScreenDevice() then
        local scale=height/880
        return (width-1280*scale)*.5,0,scale,scale
    end
    local scale=math.min(width/1280,height/880)
    return (width-1280*scale)*.5,(height-880*scale)*.5,scale,scale
end
function C.enabled() return os.getenv('PICTURE_SHOP_COMMUTE')~='0' end
function C.bindings(R)
    R.App=R.App or {};R.App.settings=R.App.settings or {}
    if not R.App.settings.motorcycleControls then R.App.settings.motorcycleControls=Bindings.defaults() end
    return R.App.settings.motorcycleControls
end
function C.touchControlView(R,part)
    local offer=R and R._commute and R._commute.mechanicOffer
    if offer then
        if offer.interiorKind=='grocery' then return 'grocery' end
        if offer.interiorKind=='station' then return 'gas_station' end
        return 'mechanic_shop'
    end
    local player=R and R.World and R.World.player
    if not player then return 'overworld' end
    if player.sceneId=='commute' then
        part=part or C.localPart(R)
        local rider=part and part.rider
        if rider and rider.vehicle=='truck' then return 'truck' end
        if rider and rider.gear and rider.gear.mounted then return 'motorcycle' end
        return 'overworld'
    end
    if player.sceneId=='warehouse' then return 'warehouse' end
    if player.sceneId=='home' then return 'home' end
    if player.sceneId=='grocery' then return 'grocery' end
    if player.sceneId=='barn' then return 'walking' end
    if player.sceneId=='station' or player.sceneId=='gas_station' then return 'gas_station' end
    if player.sceneId=='mechanic' or player.sceneId=='mechanic_shop' then return 'mechanic_shop' end
    if player.sceneId=='front_left' or player.sceneId=='front_right' then return 'room' end
    return 'walking'
end
function C.touchProfile(R,part)
    local base=C.bindings(R)
    local view=C.touchControlView(R,part)
    local layout=require('src.settings').controlLayoutFor(R.App.settings,view)
    local profile={}
    for key,value in pairs(base) do profile[key]=value end
    profile.layout={}
    for key,point in pairs(base.layout or {}) do
        profile.layout[key]={x=point.x,y=point.y}
    end
    for key,point in pairs(layout or base.layout or {}) do
        profile.layout[key]={x=point.x,y=point.y}
    end
    return profile
end
function C.applyCameraPreference(R,camera,rider)
    local mode=C.bindings(R).outsideCamera or 'fixed'
    if mode=='shoulder' and not CameraMenu.enabled(mode,rider) then mode='fixed' end
    if camera and camera.outsideMode~=mode then
        camera:setOutsideMode(mode,Rider.actor(rider),(rider.gear.mounted or rider.vehicle=='truck') and not rider.gear.transition)
    end
end
function C.toggleOutsideCamera(R)
    local part=C.localPart(R);if not part then return false end
    local profile=C.bindings(R)
    profile.outsideCamera=profile.outsideCamera=='follow' and 'fixed' or 'follow'
    C.cancelCameraDrag(R)
    C.applyCameraPreference(R,R._commute and R._commute.camera,part.rider)
    local saved=require('src.settings').save(R.App.settings)
    if not saved then R.state.message='Camera preference could not be saved.' end
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
function C.hasWorld(R) return R.state.home and R.state.home.commute~=nil end
function C.active(R) return C.localPart(R)~=nil end
function C.indoorControlsActive(R)
    local offer=R and R._commute and R._commute.mechanicOffer
    return offer and (offer.interiorKind=='grocery' and offer.page=='groceryFloor'
        or offer.interiorKind=='station' and offer.page=='stationFloor') or false
end
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
function C.localTrip(R)
    local t=R.state.home and R.state.home.commute
    local part=C.localPart(R)
    if not t or not t.independent or not part then return t end
    local run=t.deliveryDriver==Residents.key(R.World.player) and t.deliveryRun or false
    return setmetatable({origin=part.origin,destination=part.destination,deliveryRun=run,
        purpose=run and 'delivery' or 'outing'},{__index=t})
end
function C.worldUiBounds(R)
    if not C.mobileInputEnabled(R) or not R.optionsAccessLayout then return nil end
    local _,bounds=R.optionsAccessLayout()
    return bounds
end
function C.cardX(R)
    local bounds=C.worldUiBounds(R)
    return (bounds and bounds.left or 0)+Cockpit.CARD_X
end
local function nearbyTruck(trip,rider)
    if not trip or not rider then return nil end
    if rider.vehicle=='truck' and rider.truck then return rider.truck end
    return require('src.commute.trip').nearestTruck(trip,rider,5.5)
end
function C.mapRect(R)
    return {x=16,y=132,width=R.Config.baseWidth-32,height=R.Config.baseHeight-156}
end
function C.mapButton(R)
    local view=R._commute
    if not C.localPart(R) or not view or not view.renderer or view.loading or view.mechanicOffer then return nil end
    local _,bounds
    if R.optionsAccessLayout then _,bounds=R.optionsAccessLayout() end
    local right=bounds and bounds.right or R.Config.baseWidth
    if view.mapOpen then
        local mobile=C.mobileInputEnabled(R)
        local width=mobile and 148 or 134
        local height=mobile and 48 or 42
        return {x=right-width-16,y=82,width=width,height=height}
    end
    return {x=right-144,y=12,width=80,height=36}
end
function C.miniMapButton(R)
    if R._commute and R._commute.mapOpen then return nil end
    local camera=C.cameraButton(R)
    return camera and {x=camera.x-72,y=camera.y,width=68,height=camera.height} or nil
end
local function miniMapBaseSize(R)
    local narrow=R.Config.baseWidth<760
    local width=narrow and 250 or math.min(370,math.max(300,R.Config.baseWidth*.30))
    local height=narrow and 155 or math.min(260,math.max(110,R.Config.baseHeight*.55-138))
    return width,height
end
local function miniMapScale(R)
    local settings=R.App and R.App.settings or {}
    local scale=tonumber(settings.gpsMiniMapScale) or 1
    if scale~=scale then scale=1 end
    return math.max(.62,math.min(1,scale))
end
function C.miniMapRect(R)
    local width,height=miniMapBaseSize(R)
    local scale=miniMapScale(R)
    width,height=width*scale,height*scale
    local bounds=C.worldUiBounds(R)
    local narrow=R.Config.baseWidth<760
    return {x=(bounds and bounds.right or R.Config.baseWidth)-width-18,
        y=narrow and 70 or 54,width=width,height=height}
end
function C.miniMapResizeHandle(rect)
    local size=28
    return {x=rect.x,y=rect.y+rect.height-size,width=size,height=size}
end
local function miniMapResizeHit(rect,x,y)
    local handle=C.miniMapResizeHandle(rect)
    return x>=handle.x and x<=handle.x+handle.width
        and y>=handle.y and y<=handle.y+handle.height
end
function C.drawMiniMapResizeHandle(rect)
    local handle=C.miniMapResizeHandle(rect)
    local x,y,size=handle.x,handle.y,handle.width
    local g=love.graphics
    g.setColor(.02,.06,.06,.94)
    g.polygon('fill',x,y,x,y+size,x+size,y+size)
    g.setColor(.68,.82,.76,1);g.setLineWidth(1.5)
    g.line(x,y,x,y+size,x+size,y+size)
    g.setColor(.94,.97,.90,1);g.setLineWidth(2)
    g.line(x+7,y+size-5,x+12,y+size-10)
    g.line(x+13,y+size-5,x+19,y+size-11)
end
function C.mobileInputEnabled(R)
    return R.mobileControls and R.mobileControls.isEnabled and R.mobileControls:isEnabled() or false
end
local function horizontalTouchSteering(R,rider)
    local settings=R.App and R.App.settings or {}
    local mode=settings.mobileVehicleSteering
    if mode==nil then mode=settings.mobileBikeSteering=='horizontal' and 'bike-horizontal' or 'radial' end
    return mode=='all-horizontal' or mode=='bike-horizontal' and rider and rider.vehicle~='truck'
end
local function touchStickSensitivity(R,rider)
    local settings=R.App and R.App.settings or {}
    local driving=rider and (rider.vehicle=='truck' or rider.gear and rider.gear.mounted)
    return driving and settings.mobileDriveSensitivity or settings.mobileWalkSensitivity or 100
end
local function toggleMobileSteeringMode(R)
    local part=C.localPart(R)
    local settings=R.App and R.App.settings
    if not part or not settings then return false end
    if horizontalTouchSteering(R,part.rider) then
        settings.mobileVehicleSteering='radial'
    else
        settings.mobileVehicleSteering=part.rider.vehicle=='truck' and 'all-horizontal' or 'bike-horizontal'
    end
    settings.mobileBikeSteering=settings.mobileVehicleSteering=='radial' and 'radial' or 'horizontal'
    if not require('src.settings').save(settings) then
        R.state.message='Steering mode changed for this session, but could not be saved.'
    end
    return true
end
local function rideNotice(R,part)
    if not part then return nil end
    local trip=C.localTrip(R)
    local stationWorld=R._commute and R._commute.world
    local parkedTruck=nearbyTruck(trip,part.rider) or trip and trip.truck
    if part.rider.vehicle=='truck' and Station.truckAtPump(parkedTruck,stationWorld) then
        return 'Park at the marked gas pump · '..Bindings.hint(C.bindings(R),'interact')..' to exit, then '
            ..Bindings.hint(C.bindings(R),'worldAction')..' to refuel'
    elseif part.rider.gear.mounted and Station.bikeAtPump(part.rider,stationWorld) then
        return Bindings.hint(C.bindings(R),'interact')..' to dismount, then '
            ..Bindings.hint(C.bindings(R),'worldAction')..' to refuel'
    elseif Station.pumpMode(part.rider,parkedTruck,stationWorld) then
        return Bindings.hint(C.bindings(R),'worldAction')..' / ACTION: Fuel pump'
    end
    local doorNotice=R._commute and R._commute.closedDoorNotice
    if doorNotice and part.rider.ped then
        local site=stationWorld and stationWorld.sites and stationWorld.sites.byId[doorNotice.buildingId]
        local distance=site and site.door and M.length(part.rider.ped.x-site.door.x,part.rider.ped.z-site.door.z)
        if distance and distance<=5 then return doorNotice.message end
        if not distance or distance>5 then R._commute.closedDoorNotice=nil end
    end
    if trip and trip.deliveryRun then
        local run=trip.deliveryRun;local stop=run.stops[run.stopIndex]
        if run.status=='loading' then
            local loaded,total=require('src.commute.delivery_run').loadingProgress(R.state,run)
            return ('DELIVERY · %d/%d pallets loaded · '):format(loaded or 0,total or run.palletCount)
                ..(part.rider.vehicle=='truck' and 'Back the rear doors against the dock; load from inside the warehouse'
                    or 'Load inside the warehouse or let employees load the truck')
        end
        if run.status=='offmap' then return 'Delivering in Millhaven · returning to the town gate shortly' end
        if run.status=='returning' or not stop then
            return 'Delivery complete · You are free to continue your day'
        end
        local progress=('STOP %d/%d · '):format(run.stopIndex,#run.stops)
        if part.rider.vehicle=='truck' then
            local label=stop.kind=='city' and ('Drive to the Millhaven gate · '..stop.label)
                or ('Drive to '..stop.label)
            return progress..label..' · '..Bindings.hint(C.bindings(R),'interact')..' to get out'
        end
        if stop.kind=='town' then return progress..'Walk to '..stop.label..' and '
            ..Bindings.hint(C.bindings(R),'worldAction')..' to hand off the pallets' end
        return progress..'Drive to the Millhaven gate for the off-map delivery'
    end
    if part.rider.vehicle=='truck' then
        local truck=nearbyTruck(trip,part.rider) or trip and trip.truck
        if truck and (truck.fuel or require('src.commute.delivery_truck').TANK_LITERS)<=0 then
            return 'Delivery truck out of fuel  ·  walk to the gas station and refuel'
        elseif truck and (truck.fuel or require('src.commute.delivery_truck').TANK_LITERS)<=12 then
            return 'Low delivery truck fuel  ·  refill at the gas station soon'
        end
        if truck and truck.service and truck.service.mechanicalFailure then
            local fault=({oil_pressure='oil pressure failure',overheating='cooling system failure',
                ignition_misfire='ignition misfire'})[truck.service.failureType] or 'engine failure'
            return 'Truck '..fault..'  ·  take it to the mechanic'
        end
        return 'Delivery truck  ·  steer, accelerate and brake  ·  '
            ..Bindings.hint(C.bindings(R),'interact')..' to get out'
    end
    local truck=nearbyTruck(trip,part.rider)
    if truck and trip.origin=='warehouse' then
        return (truck.model=='kei' and 'Kei truck nearby' or 'Delivery truck nearby')..'  ·  '
            ..Bindings.hint(C.bindings(R),'interact')..' to get in'
    end
    if Station.atCounter(part.rider,R._commute and R._commute.world) then
        return Bindings.hint(C.bindings(R),'worldAction')..' / ACTION: Gas station service counter'
    end
    if Station.nearCounter(part.rider,R._commute and R._commute.world) then
        return part.rider.gear.mounted and 'Dismount to use the gas station counter'
            or Bindings.hint(C.bindings(R),'worldAction')..' / ACTION: Gas station service counter'
    end
    local storeId=TownStore.nearCounter(part.rider,R._commute and R._commute.world)
    if storeId then
        local label=storeId=='grocery' and 'Town grocery' or storeId=='diner' and 'Diner takeout' or 'General store'
        if part.rider.gear.mounted then return 'Dismount to shop at '..label end
        return Bindings.hint(C.bindings(R),'worldAction')..(storeId=='grocery' and ' / ENTER: ' or ' / SHOP: ')..label
    end
    return Cockpit.riderHint(part.rider,part.presentation) or R.state.message
end
function C.controlContext(R,part,controlsTop)
    part=part or C.localPart(R)
    local rider=part and part.rider
    local gear=rider and rider.gear or {}
    local bike=rider and rider.bike or {}
    local isTruck=rider and rider.vehicle=='truck'
    local view=R._commute or {}
    local trip=C.localTrip(R)
    local truck=trip and (rider and rider.vehicle=='truck' and rider.truck
        or require('src.commute.trip').nearestTruck(trip,rider,5.5))
    local nearTruck=truck and trip.origin=='warehouse' and rider and not gear.mounted and not gear.transition
        and rider.vehicle~='truck' or false
    truck=truck or trip and require('src.commute.trip').truckFor(rider,trip)
    local world=C.world(R)
    local gearNearBike=rider and not gear.mounted and rider.vehicle~='truck'
        and rider.bike and M.length(rider.ped.x-rider.bike.x,rider.ped.z-rider.bike.z)<=3.2 or false
    local nearBike=gearNearBike and not gear.transition
    local atFuelPump=rider and Station.pumpMode(rider,truck,world)~=nil or false
    local worldActionLabel
    local vehicleActionLabel=nearTruck and 'GET IN TRUCK' or nearBike and 'MOUNT' or nil
    if part and part.arrived then
        worldActionLabel='FINISH'
    elseif part and rider and not rider.gear.mounted and rider.vehicle~='truck' and not rider.ped.crash then
        local sites=world.sites.byId
        local function nearDoor(site)
            return site and site.door and M.length(rider.ped.x-site.door.x,rider.ped.z-site.door.z)<=DOOR_PROMPT_RADIUS
        end
        local run=trip and trip.deliveryRun
        local stop=run and run.stops[run.stopIndex]
        local selectedTruck=Trip.truckFor(rider,trip)
        if run and run.status=='driving' and stop and stop.kind=='town' and nearDoor(sites[stop.id]) then worldActionLabel='DELIVER'
        elseif atFuelPump then worldActionLabel='FUEL'
        elseif nearDoor(sites['gas-station']) then worldActionLabel='ENTER'
        elseif nearDoor(sites.mechanic) then worldActionLabel='ENTER'
        else
            local storeId
            for _,id in ipairs({'grocery','general-store','diner'}) do
                if nearDoor(sites[id]) then storeId=id;break end
            end
            if storeId then
                worldActionLabel=storeId=='grocery' and 'ENTER' or 'SHOP'
            elseif trip.independent and (nearDoor(sites.warehouse)
                or nearDoor(sites[R.state.home.apartmentId])) then worldActionLabel='ENTER'
            elseif nearDoor(sites[part.destination or trip.destination]) then worldActionLabel='ENTER'
            elseif nearDoor(sites[part.origin or trip.origin]) then worldActionLabel='ENTER'
            elseif run and run.status=='loading' and nearTruck and Trip.truckAtLoadingBay(world,truck)
                and (not selectedTruck or selectedTruck.model==truck.model) then worldActionLabel='MANIFEST' end
        end
    end
    if require('src.story_intro').near(R,part) then worldActionLabel='ENTER' end
    if not controlsTop then controlsTop=select(3,Cockpit.infoLayout(C.mobileInputEnabled(R),rideNotice(R,part))) end
    return {
        cameraMenu=true,controlsTop=controlsTop,mounted=gear.mounted==true or rider and rider.vehicle=='truck',
        vehicle=rider and rider.vehicle,nearTruck=nearTruck,nearBike=nearBike,gearNearBike=gearNearBike,
        cardX=C.cardX(R),
        vehicleActionLabel=vehicleActionLabel,worldActionLabel=worldActionLabel,atFuelPump=atFuelPump,
        engine=isTruck and truck.engine~=false or not isTruck and gear.engine==true,gearOutfit=gear.outfit,
        gearTransition=gear.transition~=nil,arrived=part and part.arrived==true,
        transmission=bike.transmission,reverse=bike.reverse==true,
        steeringHorizontal=horizontalTouchSteering(R,rider),
        headlight=isTruck and truck.headlight==true or not isTruck and bike.headlight==true,
        headlightHighBeam=isTruck and truck.headlightHighBeam==true or not isTruck and bike.headlightHighBeam==true,
        turnSignal=isTruck and truck.turnSignal or nil,
        horn=Bindings.value(C.bindings(R),'horn',C.touch(R))>0,
        outsideMode=view.camera and view.camera.outsideMode
            or C.bindings(R).outsideCamera or 'fixed',
        pedCrash=rider and rider.ped.crash~=nil or false,
    }
end
local function nearbyDoor(R,part,trip,view)
    local rider=part and part.rider
    local world=view and view.world
    local camera=view and view.camera
    if not rider or not world or not camera or rider.gear.mounted or rider.gear.transition
        or rider.vehicle=='truck' or rider.ped.crash then return nil end
    local selectedTruck=nearbyTruck(trip,rider) or Trip.truckFor(rider,trip)
    if Station.pumpMode(rider,selectedTruck,world) then return nil end
    local sites=world.sites and world.sites.byId or {}
    local candidates,seen={},{}
    local function add(id)
        if id and not seen[id] and sites[id] and sites[id].door then
            seen[id]=true;candidates[#candidates+1]={id=id,label='ENTER',site=sites[id]}
        end
    end
    local run=trip and trip.deliveryRun
    local stop=run and run.stops[run.stopIndex]
    if stop and stop.kind=='town' then add(stop.id) end
    if part.arrived then
        add(part.destination or trip.destination)
    else
        add('gas-station')
        add('mechanic')
        add('grocery')
        add('general-store')
        add('diner')
        if trip.independent then
            add('warehouse');add(R.state.home.apartmentId)
        else
            add(part.destination or trip.destination)
            add(part.origin or trip.origin)
        end
    end
    local best,bestDistance
    for _,candidate in ipairs(candidates) do
        local door=candidate.site.door
        local distance=M.length(rider.ped.x-door.x,rider.ped.z-door.z)
        if distance<=DOOR_PROMPT_RADIUS and (not bestDistance or distance<bestDistance) then
            best,bestDistance=candidate,distance
        end
    end
    if not best then return nil end
    local door=best.site.door
    local height=door.h
    if not M.finite(height) and world.supportHeight then height=world:supportHeight(door.x,door.z) end
    local x,y=camera:screen(door.x,door.z,(height or 0)+.12)
    if x<20 or x>1260 or y<24 or y>856 then return nil end
    return {x=x,y=y,distance=bestDistance,label=best.label}
end
local function drawDoorBeacon(R,part,trip,view)
    local door=nearbyDoor(R,part,trip,view)
    if not door then return false end
    local offsetX,offsetY,scaleX,scaleY=sceneTransform(R)
    local target={x=door.x,y=door.y,beaconRadius=18,interactionRadius=DOOR_PROMPT_RADIUS}
    local selected={target=target,playerDistance=door.distance,releaseRadius=DOOR_PROMPT_RADIUS,available=true}
    local g=love.graphics
    g.push('all')
    g.translate(offsetX,offsetY);g.scale(scaleX,scaleY)
    local beacon=require('src.interaction_beacon')
    local clock=R.World.player.interactionClock
        or love.timer and love.timer.getTime and love.timer.getTime() or 0
    beacon.drawUnderlay(selected,clock)
    beacon.drawOverlay(selected,clock)
    if door.distance<=DOOR_PROMPT_RADIUS then
        local width=g.getFont():getWidth(door.label)+20
        local x,y=target.x-width*.5,target.y-50
        g.setColor(.018,.028,.024,.91);g.rectangle('fill',x,y,width,23,5)
        g.setColor(1,.87,.43,1);g.printf(door.label,x+5,y+5,width-10,'center')
    end
    g.pop()
    return true
end
local function closedBusinessInfo(R,buildingId)
    local businesses={
        grocery={calendarId='grocery',name='Town Grocery'},
        ['gas-station']={calendarId='gas-station',name='Gas Station'},
        mechanic={calendarId='mechanic',name='Majic Blue Mechanic'},
    }
    local business=businesses[buildingId]
    if not business or not R.state or not R.state.home then return nil end
    local Calendar=require('src.business_calendar')
    local Characters=require('src.commute.town_characters')
    local now=Calendar.absoluteHours(R.state)
    if Characters.isOpen(R.state.home,business.calendarId,now) then return nil end
    local schedule=Characters.businessSchedule(business.calendarId)
    local openHour,closeHour=schedule and schedule.openHour or Characters.OPEN_HOUR,
        schedule and schedule.closeHour or Characters.CLOSE_HOUR
    local openText=Calendar.formatTime(openHour,0,true)
    local closeText=Calendar.formatTime(closeHour,0,true)
    local returnWhen=now%24<openHour and 'TODAY' or 'TOMORROW'
    local returnText='OPENS '..returnWhen..' AT '..openText
    local hoursText=openText..' – '..closeText
    return {name=business.name,hoursLine='HOURS '..hoursText,returnLine=returnText,
        message=business.name..' is closed. Hours: '..hoursText..'. '..
            'Opens '..returnWhen:lower()..' at '..openText..'.'}
end
local function beginDoorTransition(R,kind,token,buildingId)
    local view=R._commute
    if not view or view.doorTransition then return false end
    view.closedDoorNotice=nil
    view.doorTransition=DoorTransition.new(kind,token,buildingId,closedBusinessInfo(R,buildingId))
    view.mapOpen=false;view.mainMapDrag=nil
    C.cancelCameraDrag(R)
    return true
end
local function completeDoorTransition(R,transition)
    if transition.closed then
        local message=transition.closedInfo and transition.closedInfo.message or 'This business is closed right now.'
        R.state.message=message
        R._commute.closedDoorNotice={buildingId=transition.buildingId,message=message}
        return
    end
    local token=transition.token
    if transition.action=='station' then require('src.commute.mechanic_shop').openStationInterior(R)
    elseif transition.action=='mechanic' then C.openMechanic(R)
    elseif transition.action=='grocery' then C.openTownStore(R,'grocery')
    elseif transition.action=='general-store' then C.openTownStore(R,'general-store')
    elseif transition.action=='diner' then C.openTownStore(R,'diner')
    else C.request(R,transition.action..':'..token) end
end
function C.cameraButton(R)
    local map=C.mapButton(R);if not map then return nil end
    return {x=map.x-76,y=map.y,width=72,height=map.height}
end
function C.toggleMap(R)
    if not C.mapButton(R) then return false end
    local visibility=require('src.screens.hud_visibility')
    if not visibility.isVisible(R) then visibility.setVisible(R,true) end
    C.cancelCameraDrag(R)
    local view=R._commute
    if view.mapOpen then view.mainMapDrag=nil end
    view.mapOpen=not view.mapOpen
    if view.mapOpen and not view.routeMap then view.routeMap=require('src.commute.route_map').new(C.world(R)) end
    return true
end
function C.toggleMiniMap(R)
    if not C.miniMapButton(R) then return false end
    C.cancelCameraDrag(R)
    local view=R._commute
    view.miniMapVisible=not (view.miniMapVisible~=false)
    return true
end
function C.activeWaypoint(R)
    local view=R._commute or {};local trip=C.localTrip(R)
    if trip and trip.purpose=='delivery' and trip.deliveryRun then
        if trip.deliveryRun.status=='loading' then return 'warehouse' end
        local stop=trip.deliveryRun.stops[trip.deliveryRun.stopIndex]
        local target=stop and stop.kind=='city' and 'mainland_exit' or stop and stop.id or 'warehouse'
        return C.world(R).roads.destinations[target] and target or 'warehouse'
    end
    -- Story travel has no assigned next stop. An explicit GPS choice may be
    -- resumed, but visiting a place clears it again.
    if trip and trip.independent and not view.waypointId then
        local c=require('src.warehouse_condition').of(R.state)
        if c and c.mode=='story' and not c.firstDestination then return nil end
    end
    -- Regular warehouse outings also start without an automatic GPS route.
    if trip and trip.origin=='warehouse' and not view.waypointId then
        local c=require('src.warehouse_condition').of(R.state)
        if not c or c.mode~='story' or not c.grandpaMet or not c.firstDestination then return nil end
    end
    local part=C.localPart(R)
    local target=view.waypointId or part and part.destination or trip and trip.destination
    local destinations=C.world(R).roads.destinations
    return destinations[target] and target or trip and trip.destination
end
function C.refreshNavigation(R,part,dt,force)
    if not part or not R._commute then return end
    local view=R._commute;local target=C.activeWaypoint(R)
    local actor=Rider.actor(part.rider)
    view.navigationClock=(view.navigationClock or 0)+(dt or 0)
    local moved=not view.navigationX or (actor.x-view.navigationX)^2+(actor.z-view.navigationZ)^2>=16
    if force or target~=view.navigationTarget or moved and view.navigationClock>=.35 then
        local Routes=require('src.commute.routes')
        if not view.routePlanner then view.routePlanner=Routes.new(C.world(R).roads) end
        view.navigationRoute=view.routePlanner:findFromPoint(actor.x,actor.z,target)
        view.navigationTarget=target;view.navigationX,view.navigationZ=actor.x,actor.z
        view.navigationClock=0
    end
end
function C.setWaypoint(R,id)
    local trip=C.localTrip(R)
    if not trip or not C.world(R).roads.destinations[id] then return false end
    if trip.purpose=='delivery' then return id==C.activeWaypoint(R) end
    local part=C.localPart(R)
    local condition=require('src.warehouse_condition').of(R.state)
    if trip.independent and part and condition and condition.mode=='story'
        and condition.grandpaMet and not condition.grandOpened
        and (id=='warehouse' or id==R.state.home.apartmentId) then
        local clearing=C.activeWaypoint(R)==id
        local action=clearing and 'routeclear:'
            or (id=='warehouse' and 'routework:' or 'routehome:')
        if not C.request(R,action..trip.token) then return false end
        if clearing then R._commute.waypointId=nil
        else R._commute.waypointId=id end
        C.refreshNavigation(R,C.localPart(R),0,true)
        return true
    end
    if trip.independent and part and (id=='warehouse' or id==R.state.home.apartmentId) then
        if not C.request(R,(id=='warehouse' and 'routework:' or 'routehome:')..trip.token) then return false end
    end
    local view=R._commute
    if trip.origin=='warehouse' then view.waypointId=view.waypointId~=id and id or nil
    else view.waypointId=id~=(part and part.destination or trip.destination) and id or nil end
    C.refreshNavigation(R,C.localPart(R),0,true)
    local destination=C.world(R).roads.destinations[id]
    R.state.message='Navigation set to '..(destination.label or id)..'.'
    return true
end
function C.miniMapResizeMoved(R,x,y,source)
    local view=R._commute;local drag=view and view.miniMapResize
    if not drag or drag.source~=source then return false end
    local settings=R.App and R.App.settings
    if not settings then R.App=R.App or {};R.App.settings={};settings=R.App.settings end
    local scale=drag.startScale+((drag.startX-x)/drag.baseWidth+(y-drag.startY)/drag.baseHeight)*.5
    settings.gpsMiniMapScale=math.max(.62,math.min(1,scale))
    return true
end
function C.finishMiniMapResize(R,source)
    local view=R._commute;local drag=view and view.miniMapResize
    if not drag or drag.source~=source then return false end
    view.miniMapResize=nil
    if not require('src.settings').save(R.App and R.App.settings or {}) then
        R.state.message='GPS map size could not be saved.'
    end
    return true
end
function C.mapPointer(R,x,y,source)
    if not require('src.screens.hud_visibility').isVisible(R) then return false end
    local button=C.mapButton(R)
    if not button then return false end
    local view=R._commute
    if view.miniMapResize then return true end
    local navButton=C.miniMapButton(R)
    if navButton and x>=navButton.x and x<=navButton.x+navButton.width
        and y>=navButton.y and y<=navButton.y+navButton.height then
        return C.toggleMiniMap(R)
    end
    if x>=button.x and x<=button.x+button.width and y>=button.y and y<=button.y+button.height then
        return C.toggleMap(R)
    end
    local part=C.localPart(R)
    if view.mapOpen then
        if part and view.routeMap then
            local mobile=C.mobileInputEnabled(R)
            local mapRect=C.mapRect(R)
            local actor=Rider.actor(C.visualRider(part,R.World.player,R.state.home.commute.token))
            if view.routeMap:pressControl(mapRect,x,y,mobile,button.x-8,actor) then return true end
            local mapOptions=view.routeMap:uiOptions(mobile,button.x-8)
            mapOptions.destination=C.activeWaypoint(R);mapOptions.home=R.state.home.apartmentId
            local id=view.routeMap:hit(mapRect,x,y,actor,mapOptions)
            if id then C.setWaypoint(R,id) end
            if not id and view.routeMap.mainZoom>1 then
                local layout=require('src.commute.route_map').layout(mapRect,#view.routeMap.entries,mapOptions)
                local area=layout.map
                if x>=area.x and x<=area.x+area.width and y>=area.y and y<=area.y+area.height then
                    view.mainMapDrag={source=source or 'pointer',x=x,y=y,area=area}
                end
            end
        end
        -- The open town map covers the ride controls; consume taps on its background too.
        return true
    end
    if view.miniMapVisible~=false and part then
        local rect=C.miniMapRect(R)
        if miniMapResizeHit(rect,x,y) and not view.miniMapResize then
            local baseWidth,baseHeight=miniMapBaseSize(R)
            view.miniMapResize={source=source or 'pointer',startX=x,startY=y,
                startScale=miniMapScale(R),baseWidth=baseWidth,baseHeight=baseHeight}
            return true
        end
        if x>=rect.x and x<=rect.x+rect.width and y>=rect.y and y<=rect.y+rect.height then
            if not view.routeMap then view.routeMap=require('src.commute.route_map').new(C.world(R)) end
            local actor=Rider.actor(C.visualRider(part,R.World.player,R.state.home.commute.token))
            if view.routeMap:pressMiniFollow(rect,x,y,actor) then return true end
            if view.routeMap:pressMiniZoom(rect,x,y) then return true end
            local id=view.routeMap:hitMini(rect,x,y,actor,{destination=C.activeWaypoint(R),
                home=R.state.home.apartmentId})
            if id then C.setWaypoint(R,id) end
            -- Marker taps choose a route in place. The separate MAP button
            -- remains the deliberate way to open the full town map.
            return true
        end
    end
    return false
end
function C.mapPointerMoved(R,x,y,source)
    local view=R._commute;local drag=view and view.mainMapDrag
    if not drag or source~=drag.source or not view.routeMap then return false end
    view.routeMap:panMain(x-drag.x,y-drag.y,drag.area)
    drag.x,drag.y=x,y
    return true
end
function C.finishMainMapPan(R,source)
    local view=R._commute;local drag=view and view.mainMapDrag
    if not drag or source~=nil and source~=drag.source then return false end
    view.mainMapDrag=nil
    return true
end
function C.mapWheel(R,x,y,amount)
    local view=R._commute
    if not view or amount==0 or not require('src.screens.hud_visibility').isVisible(R) then return false end
    if view.mapOpen then
        local part=C.localPart(R)
        if part then
            if not view.routeMap then view.routeMap=require('src.commute.route_map').new(C.world(R)) end
            local button=C.mapButton(R);local mobile=C.mobileInputEnabled(R)
            local mapRect=C.mapRect(R)
            local options=view.routeMap:uiOptions(mobile,button and button.x-8)
            local area=require('src.commute.route_map').layout(mapRect,#view.routeMap.entries,options).map
            if x>=area.x and x<=area.x+area.width and y>=area.y and y<=area.y+area.height then
                local actor=Rider.actor(C.visualRider(part,R.World.player,R.state.home.commute.token))
                view.routeMap:zoomMain(amount>0 and 1 or -1,actor)
            end
        end
        return true
    end
    if view.miniMapVisible==false then return false end
    local rect=C.miniMapRect(R)
    if x<rect.x or y<rect.y or x>rect.x+rect.width or y>rect.y+rect.height then return false end
    if not view.routeMap then view.routeMap=require('src.commute.route_map').new(C.world(R)) end
    view.routeMap:zoomMini(amount>0 and 1 or -1)
    return true
end
function C.drawMap(R,part)
    local button=C.mapButton(R)
    if not button then return end
    local g=love.graphics;g.push('all')
    local view=R._commute
    local mapTraffic=view.mapOpen and require('src.commute.delivery_traffic').actors(R.state,R.state.home.town,
        require('src.business_calendar').absoluteHours(R.state),os.time(),view.world,
        {customer=R.World.customer,vendor=R.World.vendor}) or view.mapTraffic
    C.refreshNavigation(R,part,0,false)
    if view.mapOpen then
        if not view.routeMap then view.routeMap=require('src.commute.route_map').new(C.world(R)) end
        local trip=C.localTrip(R)
        local mobile=C.mobileInputEnabled(R)
        local mapOptions=view.routeMap:uiOptions(mobile,button.x-8)
        mapOptions.origin=trip.origin;mapOptions.destination=C.activeWaypoint(R);mapOptions.home=R.state.home.apartmentId
        mapOptions.bike=not part.rider.gear.mounted and part.rider.bike or nil
        mapOptions.route=view.navigationRoute
        mapOptions.traffic=mapTraffic
        mapOptions.closeHint=mobile and 'Tap a marker or place to set a route'
            or 'Tap a marker or place to set a route · Esc closes'
        view.routeMap:draw(C.mapRect(R),Rider.actor(C.visualRider(part,R.World.player,R.state.home.commute.token)),mapOptions)
    elseif view.miniMapVisible~=false then
        if not view.routeMap then view.routeMap=require('src.commute.route_map').new(C.world(R)) end
        local otherPlayers={}
        for _,player in ipairs(R.multiplayer:remotePlayers()) do
            if player.sceneId=='commute' and M.finite(player.x) and M.finite(player.y) then
                otherPlayers[#otherPlayers+1]={id=player.id,name=player.name,x=player.x,z=player.y}
            end
        end
        local miniRect=C.miniMapRect(R)
        view.routeMap:drawMini(miniRect,Rider.actor(C.visualRider(part,R.World.player,R.state.home.commute.token)),{
            destination=C.activeWaypoint(R),home=R.state.home.apartmentId,route=view.navigationRoute,
            players=otherPlayers,traffic=mapTraffic,resizeHandle=true})
        C.drawMiniMapResizeHandle(miniRect)
    end
    require('src.screens.ui').panel(button,{.10,.15,.15,1},{.43,.53,.51,1},6,1)
    g.setColor(.94,.95,.89)
    local label=view.mapOpen and 'CLOSE' or 'MAP'
    if not view.mapOpen then
        Icons.draw('map',button.x+15,button.y+button.height*.5,20)
        if not C.mobileInputEnabled(R) and button.width>=105 then
            label=label..'  ['..Bindings.hint(C.bindings(R),'map')..']'
        end
        g.printf(label,button.x+28,button.y+(button.height-g.getFont():getHeight())/2,button.width-30,'center')
    else
        g.setFont(view.routeMap:font(C.mobileInputEnabled(R) and 17 or 16))
        g.printf('CLOSE MAP',button.x+6,button.y+(button.height-g.getFont():getHeight())/2,button.width-12,'center')
    end
    local nav=C.miniMapButton(R)
    if nav then
        local visible=view.miniMapVisible~=false
        require('src.screens.ui').panel(nav,{.10,.15,.15,1},visible and {.64,.79,.57,1} or {.43,.53,.51,1},6,1)
        g.setColor(.94,.95,.89)
        local navLabel=visible and 'HIDE' or 'NAV'
        if not C.mobileInputEnabled(R) then navLabel=navLabel..' TAB' end
        g.printf(navLabel,nav.x+4,nav.y+(nav.height-g.getFont():getHeight())/2,nav.width-8,'center')
    end
    g.pop()
end
function C.drawCameraButton(R)
    if R._commute and R._commute.mapOpen then return false end
    local button=C.cameraButton(R);if not button then return false end
    local view=R._commute;local g=love.graphics
    g.push('all')
    require('src.screens.ui').panel(button,{.10,.15,.15,1},{.43,.53,.51,1},6,1)
    g.setColor(.94,.95,.89)
    Icons.draw('camera',button.x+13,button.y+button.height*.5,18)
    g.printf('CAM',
        button.x+25,button.y+(button.height-g.getFont():getHeight())/2,button.width-27,'center')
    g.pop()
    if view.cameraMenu then CameraMenu.draw(button,view.camera,C.localPart(R).rider,
        require('src.screens.hud_visibility').cameraLocked(R),C.miniMapRect(R).x) end
    return true
end
function C.adjustTruckCabView(R,direction)
    local view=R._commute;local part=C.localPart(R)
    if not view or not view.camera or not part
        or not CameraMenu.hasTruckSeatPad(view.camera,part.rider) then return false end
    local seat=C.bindings(R).truckCabView
    local step=.04
    if direction=='left' then seat.side=math.max(-.72,seat.side-step)
    elseif direction=='right' then seat.side=math.min(.72,seat.side+step)
    elseif direction=='up' then seat.up=math.min(.45,seat.up+step)
    elseif direction=='down' then seat.up=math.max(-.05,seat.up-step)
    elseif direction=='forward' then seat.forward=math.min(.95,seat.forward+step)
    elseif direction=='back' then seat.forward=math.max(-.55,seat.forward-step)
    else return false end
    view.camera.truckCabSide,view.camera.truckCabUp,view.camera.truckCabForward=seat.side,seat.up,seat.forward
    require('src.settings').save(R.App.settings)
    return true
end
function C.cameraPointer(R,x,y)
    if not require('src.screens.hud_visibility').isVisible(R) then return false end
    local button=C.cameraButton(R)
    if not button then return false end
    local view=R._commute
    local function hit(b) return x>=b.x and x<=b.x+b.width and y>=b.y and y<=b.y+b.height end
    if hit(button) then
        C.cancelCameraLook(R)
        view.cameraMenu=not view.cameraMenu
        return true
    end
    if not view.cameraMenu then return false end
    local rider=C.localPart(R).rider
    local mapLeft=C.miniMapRect(R).x
    local seatDirection=CameraMenu.adjustmentAt(button,x,y,view.camera,rider,mapLeft)
    if seatDirection then C.adjustTruckCabView(R,seatDirection);return true end
    for i,mode in ipairs(CameraMenu.modes) do
        if hit(CameraMenu.row(button,i,mapLeft)) then
            local id=mode[1]
            if not CameraMenu.enabled(id,rider,view.camera) then return true end
            if id=='lock' then require('src.screens.hud_visibility').toggleCameraLock(R)
            elseif id=='center' then view.camera:recenter()
            elseif id=='first' then view.camera:setFirstPerson(true,Rider.actor(rider),
                not rider.gear.mounted and rider.vehicle~='truck')
            else
                if view.camera.firstPerson then view.camera:setFirstPerson(false,Rider.actor(rider)) end
                C.bindings(R).outsideCamera=id
                C.applyCameraPreference(R,view.camera,rider)
                require('src.settings').save(R.App.settings)
            end
            break
        end
    end
    view.cameraMenu=false
    return true
end
function C.syncPlayer(player,part)
    if part.interior then
        local pose=part.interiorPose
        player.sceneId=part.interior;player.x,player.y=pose.x,pose.y
        player.velocityX,player.velocityY=pose.velocityX or 0,pose.velocityY or 0
        player.moving=pose.moving==true;player.intentX,player.intentY=pose.intentX or 0,pose.intentY or 1
        player.animationDistance=pose.animationDistance or 0;player.cartPushing=pose.cartPushing==true;player.resting=false
        return
    end
    player.cartPushing=false
    local actor=Rider.actor(part.rider)
    local transition=part.rider.gear.transition
    if transition and transition.kind=='dismount' then actor=part.rider.ped end
    player.sceneId='commute';player.x,player.y=actor.x,actor.z
    local heading=actor.heading or 0
    local vx,vz=actor.vx,actor.vz
    if part.rider.vehicle=='truck' then
        local direction=actor.reverse and -1 or 1
        vx,vz=math.cos(heading)*(actor.speed or 0)*direction,
            math.sin(heading)*(actor.speed or 0)*direction
    end
    if not M.finite(vx) or not M.finite(vz) then
        local direction=actor.reverse and -1 or 1
        vx,vz=math.cos(heading)*(actor.speed or 0)*direction,
            math.sin(heading)*(actor.speed or 0)*direction
    end
    local speed=M.length(vx,vz)
    player.velocityX,player.velocityY=vx,vz
    if part.rider.vehicle=='truck' then player.intentX,player.intentY=math.cos(heading),math.sin(heading)
    elseif speed>.04 then player.intentX,player.intentY=vx/speed,vz/speed
    else player.intentX,player.intentY=math.cos(heading),math.sin(heading) end
    if math.abs(player.intentX)>.01 then player.facing=player.intentX<0 and -1 or 1 end
    player.moving=speed>.01
    player.animationDistance=(actor.distance or 0)*48;player.resting=false
end
function C.visualRider(part,player,token)
    local source=part and part.rider
    if not source then return nil end
    if type(player)~='table' or player.sceneId~='commute'
        or not M.finite(player.x) or not M.finite(player.y) then return source end
    local visual={}
    for key,value in pairs(source) do visual[key]=value end
    local name=source.vehicle=='truck' and 'truck' or source.gear and source.gear.mounted and 'bike' or 'ped'
    local actor=source[name]
    if actor then
        local positioned={}
        for key,value in pairs(actor) do positioned[key]=value end
        local dismounting=source.gear and source.gear.transition
            and source.gear.transition.kind=='dismount'
        -- During dismount syncPlayer follows the rider as they step away.
        -- That pedestrian position must not drag the parked motorcycle along.
        if not (name=='bike' and dismounting) then positioned.x,positioned.z=player.x,player.y end
        if name=='bike' and not dismounting and player._rideMotion and player._rideMotion.token==token then
            visual.motion=player._rideMotion
            positioned.speed,positioned.heading=visual.motion.speed,visual.motion.heading
        end
        if name=='truck' and not require('src.commute.truck_motion').apply(positioned,player,token) then
            local vx,vy=player._visualVelocityX or player.velocityX or 0,
                player._visualVelocityY or player.velocityY or 0
            local speed=M.length(vx,vy)
            local ix,iy=player._visualIntentX or player.intentX or 0,
                player._visualIntentY or player.intentY or 0
            if ix*ix+iy*iy>.25 then positioned.heading=math.atan2(iy,ix) end
            positioned.speed=speed
            if speed>.05 then
                positioned.reverse=vx*math.cos(positioned.heading)+vy*math.sin(positioned.heading)<0
            end
        elseif name=='ped' then
            positioned.vx,positioned.vz=player._visualVelocityX or player.velocityX or 0,
                player._visualVelocityY or player.velocityY or 0
            positioned.speed=M.length(positioned.vx,positioned.vz)
            positioned.distance=player._visualWalkDistance or (player.animationDistance or 0)/48
            local ix,iy=player._visualIntentX or player.intentX or 0,
                player._visualIntentY or player.intentY or 0
            if ix*ix+iy*iy>.25 then positioned.heading=math.atan2(iy,ix) end
        end
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
    if not C.hasWorld(R) then return end
    R.state.home.commute=assert(Trip.restore(R.state.home.commute,C.world(R),
        require('src.company_delivery_driver').ensure(R.state),R.state.home.truckFleet,R.state.warehouse))
    local part=C.localPart(R);if part then C.syncPlayer(R.World.player,part) end
end
function C.bind(R,player,connected)
    if not C.hasWorld(R) then return true end
    local okay,part=Trip.rebind(R.state,player,connected,C.world(R))
    if okay and part then C.syncPlayer(player,part)
    elseif okay then
        local resident=Residents.get(R.state,player)
        require('src.home_travel').placeArrival(R.state,{player},resident and resident.sceneId=='home',{
            resolveShopSpawn=function(x,y,id,party)return R.World.resolveNetworkSpawn(x,y,id,R.Assets,R.state,party) end})
    end
    return okay,part
end
local actions={grocery=true,exitgrocery=true,equip=true,remove=true,mount=true,dismount=true,arrive=true,load_delivery=true,deliver_stop=true,finish=true,force=true,cancel=true,
    enterhome=true,enterwork=true,
    routehome=true,routework=true,routeclear=true,
    automatic=true,manual=true,shiftup=true,shiftdown=true,ignition=true,headlight=true,beam=true,reverse=true,rescue=true,truck=true,
    signalLeft=true,signalRight=true,radioPrevious=true,radioPlay=true,radioNext=true,radioMute=true}
function C.decode(command)
    if type(command)~='string' or #command>80 then return nil end
    local stationToken,revision,item,amount=command:match('^station:(%d+):(%d+):([a-z]+):(%d+)$')
    if stationToken then
        local token,rev=tonumber(stationToken),tonumber(revision)
        amount=tonumber(amount)
        local maximum=item=='truckfuel' and 60000 or 4000
        if token>=1 and token<=1e12 and rev<=1e12 and (item=='fuel' or item=='truckfuel')
            and amount>=1 and amount<=maximum then
            return 'station',token,{item=item,revision=rev,amountMl=amount}
        end
        return nil
    end
    stationToken,revision,item=command:match('^station:(%d+):(%d+):([a-z]+)$')
    if stationToken then
        local token,rev=tonumber(stationToken),tonumber(revision)
        if token>=1 and token<=1e12 and rev<=1e12 and item=='oil' then
            return 'station',token,{item=item,revision=rev}
        end
        return nil
    end
    local tireToken,tireRevision,tireId=command:match('^biketire:(%d+):(%d+):([a-z]+)$')
    if tireToken then
        tireToken,tireRevision=tonumber(tireToken),tonumber(tireRevision)
        if tireToken>=1 and tireToken<=1e12 and BikeTires.validRevision(tireRevision) and BikeTires.valid(tireId) then
            return 'biketire',tireToken,{token=tireToken,tireId=tireId,expectedServiceRevision=tireRevision}
        end
        return nil
    end
    local storeToken,storeRevision,storeId,productId,quantity=command:match('^storebuy:(%d+):(%d+):([a-z%-]+):([a-z_]+):(%d+)$')
    if storeToken then
        storeToken,storeRevision,quantity=tonumber(storeToken),tonumber(storeRevision),tonumber(quantity)
        if storeToken>=1 and storeToken<=1e12 and storeRevision>=0 and storeRevision<=1e12
            and quantity>=1 and quantity<=10
            and TownStore.quote(storeId,productId,quantity) then
            return 'storebuy',storeToken,{storeId=storeId,productId=productId,quantity=quantity,expectedRevision=storeRevision}
        end
        return nil
    end
    local cartToken,cartRevision,cartPayload=command:match('^storecart:(%d+):(%d+):([a-z0-9]+)$')
    if cartToken then
        cartToken,cartRevision=tonumber(cartToken),tonumber(cartRevision)
        local cart=TownStore.decodeCart(cartPayload)
        if cartToken>=1 and cartToken<=1e12 and cartRevision>=0 and cartRevision<=1e12 and cart then
            return 'storecart',cartToken,{storeId='grocery',cart=cart,expectedRevision=cartRevision}
        end
        return nil
    end
    local pushToken,pushValue=command:match('^cartpush:(%d+):([01])$')
    if pushToken then
        pushToken=tonumber(pushToken)
        if pushToken>=1 and pushToken<=1e12 then
            return 'cartpush',pushToken,{pushed=pushValue=='1'}
        end
        return nil
    end
    local repairToken,repairRevision,damage=command:match('^bikerepair:(%d+):(%d+):(%d+)$')
    if repairToken then
        repairToken,repairRevision,damage=tonumber(repairToken),tonumber(repairRevision),tonumber(damage)
        if repairToken>=1 and repairToken<=1e12 and Repairs.validRevision(repairRevision) and Repairs.validQuotedDamage(damage) then
            return 'bikerepair',repairToken,{token=repairToken,expectedRepairRevision=repairRevision,expectedDamage=damage}
        end
        return nil
    end
    local truckToken,truckModel,truckRevision,truckDamage,truckFailed=
        command:match('^truckrepair:(%d+):([a-z]+):(%d+):(%d+):([01])$')
    if truckToken then
        truckToken,truckRevision,truckDamage=tonumber(truckToken),tonumber(truckRevision),tonumber(truckDamage)
        if truckToken>=1 and truckToken<=1e12 and (truckModel=='box' or truckModel=='kei')
            and truckRevision>=0 and truckRevision<=TruckService.MAX_REVISION and truckDamage<=100 then
            return 'truckrepair',truckToken,{token=truckToken,model=truckModel,expectedRevision=truckRevision,
                expectedDamage=truckDamage,expectedFailure=truckFailed=='1'}
        end
        return nil
    end
    local serviceToken,serviceModel,serviceRevision,serviceId=
        command:match('^truckservice:(%d+):([a-z]+):(%d+):([a-z_]+)$')
    if serviceToken then
        serviceToken,serviceRevision=tonumber(serviceToken),tonumber(serviceRevision)
        if serviceToken>=1 and serviceToken<=1e12 and (serviceModel=='box' or serviceModel=='kei')
            and serviceRevision>=0 and serviceRevision<=TruckService.MAX_REVISION
            and TruckService.maintenance(serviceId) then
            return 'truckservice',serviceToken,{token=serviceToken,model=serviceModel,
                expectedRevision=serviceRevision,item=serviceId}
        end
        return nil
    end
    local upgradeToken,upgradeModel,category,upgradeRevision,oldLevel,newLevel=
        command:match('^truckupgrade:(%d+):([a-z]+):([a-z]+):(%d+):([012]):([123])$')
    if upgradeToken then
        upgradeToken,upgradeRevision,oldLevel,newLevel=tonumber(upgradeToken),tonumber(upgradeRevision),
            tonumber(oldLevel),tonumber(newLevel)
        if upgradeToken>=1 and upgradeToken<=1e12 and (upgradeModel=='box' or upgradeModel=='kei')
            and TruckService.UPGRADES[category] and upgradeRevision>=0 and upgradeRevision<=TruckService.MAX_REVISION
            and newLevel==oldLevel+1 then
            return 'truckupgrade',upgradeToken,{token=upgradeToken,model=upgradeModel,category=category,
                expectedRevision=upgradeRevision,expectedLevel=oldLevel,level=newLevel}
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
    local partToken,category,partExpected,partLevel=command:match('^bikepart:(%d+):([a-z]+):([012]):([123])$')
    if partToken then
        partToken,partExpected,partLevel=tonumber(partToken),tonumber(partExpected),tonumber(partLevel)
        if partToken>=1 and partToken<=1e12 and Upgrades.validCategory(category) and partLevel==partExpected+1 then
            return 'bikepart',partToken,{token=partToken,category=category,expectedCategoryLevel=partExpected,level=partLevel}
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
    local action;action,token=command:match('^([%a_]+):(%d+)$');token=tonumber(token)
    if not actions[action] or not token or token<1 or token>1e12 then return nil end
    return action,token
end
function C.command(R,player,command)
    local action,token,intent=C.decode(command)
    if not action then return false,'invalid_action','Choose an available riding action.','commute' end
    local okay,message,event
    if action=='enterhome' or action=='enterwork' then
        local part,t=Trip.participant(R.state,player,token)
        if not part or not t.independent or part.arrived or part.interior
            or player.sceneId~='commute' or t.deliveryRun then
            okay,message=false,'Walk up to the apartment or Picture Shop entrance.'
        else
            local previous=part.destination
            part.destination=action=='enterwork' and 'warehouse' or R.state.home.apartmentId
            local accepted,code,detail,kind=C.command(R,player,'finish:'..token)
            if not accepted then part.destination=previous end
            return accepted,code,detail,kind
        end
    elseif action=='routeclear' then
        local part,t=Trip.participant(R.state,player,token)
        if not part or not t.independent or part.arrived or part.interior
            or player.sceneId~='commute' or t.deliveryRun then
            okay,message=false,'Clear navigation while traveling freely outdoors.'
        else
            okay=require('src.story_progress').clearRoute(R)
            message=okay and 'Navigation cleared.' or 'There is no selected route to clear.'
        end
    elseif action=='routehome' or action=='routework' then
        local part,t=Trip.participant(R.state,player,token)
        local id=action=='routework' and 'warehouse' or R.state.home.apartmentId
        if not part or not t.independent or part.arrived or part.interior
            or player.sceneId~='commute' or t.deliveryRun
            or not C.world(R).roads.destinations[id] then
            okay,message=false,'Choose a destination while traveling freely outdoors.'
        else
            if part.destination~=id then
                part.destination=id
                R.state.home.revision=R.state.home.revision+1
            end
            require('src.story_progress').choose(R,id)
            okay=true
            message='Navigation set to '..(C.world(R).roads.destinations[id].label or id)..'.'
        end
    elseif action=='grocery' or action=='exitgrocery' then
        local part,t=Trip.participant(R.state,player,token)
        if not part or not t.independent then return false,'wrong_scene','This store visit has ended.','commute' end
        if action=='grocery' then
            if part.interior or not TownStore.counter(part.rider,C.world(R),'grocery') then
                return false,'out_of_range','Dismount and walk to the grocery entrance.','commute'
            end
            part.interior='grocery';part.interiorPose={x=480,y=548,intentX=0,intentY=-1,
                animationDistance=0,moving=false,cartPushing=false}
        else
            if part.interior~='grocery' then return false,'wrong_scene','You are not in the grocery store.','commute' end
            part.interior=nil;part.interiorPose=nil
        end
        player.inputX,player.inputY=0,0;C.syncPlayer(player,part)
        R.state.home.revision=R.state.home.revision+1;okay=true
        message=action=='grocery' and 'Welcome to the grocery store.' or 'Back outside the grocery store.'
    elseif action=='cartpush' then
        local part=Trip.participant(R.state,player,token)
        if not part or part.interior~='grocery' or player.sceneId~='grocery'
            or type(part.interiorPose)~='table' then
            okay,message=false,'Take a shopping cart from the grocery entrance first.'
        elseif intent.pushed and part.interiorPose.cartPushing~=true
            and (part.interiorPose.x-520)^2+(part.interiorPose.y-548)^2>54^2 then
            okay,message=false,'Walk to the shopping cart at the entrance to take it.'
        else
            part.interiorPose.cartPushing=intent.pushed==true
            R.state.home.revision=R.state.home.revision+1
            okay=true
            message=intent.pushed and 'Shopping cart taken.' or 'Shopping cart returned to the entrance rack.'
        end
    elseif action=='station' then
        local part,reason=Trip.participant(R.state,player,token)
        if part and not part.arrived and player.sceneId=='commute' then
            okay,message=Station.buy(part.rider,C.world(R),R.state.home,intent.item,intent.revision,
                require('src.company_delivery_driver').ensure(R.state),
                nearbyTruck(R.state.home.commute,part.rider) or R.state.home.commute.truck,
                R.state,intent.amountMl)
            if okay then
                if intent.item~='truckfuel' then
                    local resident=Residents.get(R.state,player)
                    resident.ridingService=Service.copy(part.rider.bike.service)
                    resident.revision=resident.revision+1
                end
                R.state.home.revision=R.state.home.revision+1
            end
        else okay,message=false,reason or 'This ride is over.' end
    elseif action=='storebuy' or action=='storecart' then
        local part,reason=Trip.participant(R.state,player,token)
        if part and not part.arrived and (player.sceneId=='commute' and action=='storebuy'
            or player.sceneId=='grocery' and action=='storecart' and part.interior=='grocery'
                and intent.storeId=='grocery') then
            if action=='storecart' then
                if player.sceneId~='grocery' or part.interiorPose.cartPushing~=true
                    or not require('src.commute.grocery_interior').atCheckout(part.interiorPose) then
                    okay,message=false,'Push your cart to the staffed checkout register before paying.'
                else
                    okay,message=TownStore.purchaseCart(R.state,player,part.rider,C.world(R),intent)
                end
            else okay,message=TownStore.purchase(R.state,player,part.rider,C.world(R),intent.storeId,intent) end
        else okay,message=false,reason or 'This ride is over.' end
    elseif action=='bikerepair' then
        okay,message=Repairs.purchase(R.state,player,R.state.home.commute,C.world(R),intent)
    elseif action=='truckrepair' or action=='truckservice' or action=='truckupgrade' then
        local kind=action=='truckrepair' and 'repair' or action=='truckservice' and 'maintenance' or 'upgrade'
        okay,message=TruckMechanic.purchase(R.state,player,R.state.home.commute,C.world(R),intent,kind)
    elseif action=='biketire' then
        okay,message=BikeTires.purchase(R.state,player,R.state.home.commute,C.world(R),intent)
    elseif action=='bikepaint' then
        okay,message=Paint.purchase(R.state,player,R.state.home.commute,C.world(R),intent)
    elseif action=='upgrade' or action=='bikeupgrade' or action=='bikepart' then
        okay,message=Upgrades.purchase(R.state,player,R.state.home.commute,C.world(R),intent)
        if action=='upgrade' and R._commute and R._commute.mechanicOffer then require('src.commute.mechanic_shop').close(R) end
    elseif token==0 then
        local resident=Residents.get(R.state,player);local gear=resident and resident.ridingGear
        if R.state.home.commute and R.state.home.commute.participants[Residents.key(player)] or not gear then return false,'wrong_scene','Use the motorcycle controls outside.','commute' end
        okay,message=Gear.begin(gear,'remove',{moving=player.moving==true})
        if okay then resident.revision=resident.revision+1;R.state.home.revision=R.state.home.revision+1 end
    elseif action=='finish' or action=='force' or action=='cancel' then
        local t=R.state.home.commute
        if t and t.independent then
            local part=t.participants[Residents.key(player)]
            if not part then return false,'wrong_scene','You are not outside.','commute' end
            okay,event=require('src.commute.free_travel').leave(R.state,player,token,
                action=='cancel' and part.origin or part.destination,C.world(R))
        elseif action=='cancel' then okay,event=Trip.cancel(R.state,player,token,C.world(R))
        else okay,event=Trip.finish(R.state,player,token,action=='force') end
        if okay then
            local storyVisit=t and t.independent
                and require('src.story_progress').visit(R,event.destination)
            local storyMessage=storyVisit and R.state.message
            local players={}
            for _,p in ipairs(require('src.weekend_runtime').players(R)) do
                if event.participants[Residents.key(p)] then players[#players+1]=p end
            end
            require('src.home_travel').placeArrival(R.state,players,event.destination~='warehouse',{
                resolveShopSpawn=function(x,y,id,party)return R.World.resolveNetworkSpawn(x,y,id,R.Assets,R.state,party) end})
            message=storyMessage or event.message
            if (player.id or 1)==(R.World.player.id or 1) then R.state.screen='world';R.World.selectedInteraction=nil end
        else message=event end
    else
        local t=R.state.home.commute
        if action=='arrive' and t and t.independent then return C.command(R,player,'finish:'..token) end
        okay,message=Trip.command(R.state,player,token,action,C.world(R))
        if okay and action=='arrive' and (player.id or 1)==1 then
            local ready=true
            for _,part in pairs(R.state.home.commute.participants) do ready=ready and part.arrived end
            if ready then return C.command(R,player,'finish:'..token) end
            message='Waiting at the door for the other riders. F brings everyone inside.'
        end
    end
    message=message or (okay and 'Riding action started.' or 'That riding action is unavailable.')
    if okay then
        R.state.message=message;R.saveCurrent(action=='routehome' or action=='routework' or action=='routeclear')
        if R.multiplayer:isHost() then R.multiplayer:markShopDirty() end
        if (action=='finish' or action=='force' or action=='cancel') and not C.active(R) then C.releaseView(R) end
    end
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
    if R._commute and R._commute.doorTransition then return 0,0,false end
    local x,y=R.Input.movement();local part=C.localPart(R)
    if part and part.interior then
        if part.interior=='barn' then
            return require('src.commute.barn_interior').input(R,part.interiorPose,x,y)
        end
        local offer=R._commute and R._commute.mechanicOffer
        local view=offer and offer.page=='groceryFloor' and offer.interior
        return view and view.netInputX or 0,view and view.netInputY or 0,false
    end
    if R._commute and (R._commute.mechanicOffer or R._commute.loading) then return 0,0,false end
    if not part or part.arrived or part.rider.gear.transition or part.presentation and part.presentation.pose~='normal_idle'
        and part.presentation.pose~='geared_idle' and part.presentation.pose~='riding' and part.presentation.pose~='seated' then return 0,0 end
    local touch=C.touch(R);local keyboardBoost
    if part.rider.gear.mounted or part.rider.vehicle=='truck' then
        local view=R._commute
        local vehicle=part.rider.vehicle=='truck' and part.rider.truck or part.rider.bike
        local profile=C.bindings(R)
        local steeringMode=horizontalTouchSteering(R,part.rider) and 'horizontal' or nil
        x,y,keyboardBoost=Bindings.drive(profile,touch,view and view.camera,vehicle,
            C.mobileInputEnabled(R),steeringMode)
    else
        if math.abs(touch.x)+math.abs(touch.y)>0 then x,y=touch.x,touch.y end
        local camera=R._commute and R._commute.camera
        if camera then x,y=camera:screenVectorToWorld(x,y) end
    end
    local view=R._commute
    if view and view.renderer and not view.renderer:terrainReady() then
        if part.rider.gear.mounted or part.rider.vehicle=='truck' then return 0,0,false end
        local starter=view.renderer.starter
        if starter then
            local dx,dz=part.rider.ped.x-starter.x,part.rider.ped.z-starter.z
            if dx*dx+dz*dz>(starter.radius-6)^2 and dx*x+dz*y>0 then return 0,0,false end
        end
    end
    local walkingSprint=not part.rider.gear.mounted and part.rider.vehicle~='truck'
        and Bindings.value(C.bindings(R),'boost',touch)>.1
    return x,y,part.rider.gear.mounted and (keyboardBoost or view and view.touchBoost==true)
        or walkingSprint==true
end
local function input(rider,x,y,boost)
    local magnitude=M.length(x,y)
    local steer
    -- Steering and throttle are separate controls for mounted rides and trucks.
    if rider.vehicle=='truck' or rider.gear.mounted then steer=math.max(-1,math.min(1,x))
    else steer=magnitude>1 and x/magnitude or x end
    -- The held boost bit is also the transient sprint input while walking.
    return (rider.gear.mounted or rider.vehicle=='truck')
        and {steer=steer,drive=y,boost=rider.vehicle~='truck' and boost==true}
        or {walkX=x,walkZ=y,sprint=boost==true}
end
function C.update(R,dt,x,y,boost,cinematic)
    if require('src.story_intro').dialogueOpen(R) then x,y,boost=0,0,false end
    local transitionView=R._commute
    if transitionView and transitionView.doorTransition
        and DoorTransition.update(transitionView.doorTransition,dt) then
        local transition=transitionView.doorTransition
        transitionView.doorTransition=nil
        completeDoorTransition(R,transition)
        return false
    end
    if R._commute and R._commute.renderer and not C.active(R) then C.releaseView(R) end
    local localPart=C.localPart(R)
    if localPart and localPart.interior and R._commute and R._commute.renderer then C.releaseView(R) end
    local offer=R._commute and R._commute.mechanicOffer
    if offer and offer.interiorKind=='grocery' and localPart and not localPart.interior then
        require('src.commute.mechanic_shop').close(R,true)
    end
    if R._commute and R._commute.mechanicOffer then require('src.commute.mechanic_shop').update(R,dt) end
    local dirty=false
    if not cinematic and not R.multiplayer:isClient() then
        local players=require('src.weekend_runtime').players(R)
        R._commute=R._commute or {}
        local traffic= require('src.commute.delivery_traffic')
        local commuteWorld=C.hasWorld(R) and C.world(R) or nil
        R._commute.trafficClock=(R._commute.trafficClock or 0)+dt
        if R._commute.trafficClock>=1 then
            R._commute.trafficClock=R._commute.trafficClock-1
            dirty=traffic.update(R.state,R.state.home and R.state.home.town,
                require('src.business_calendar').absoluteHours(R.state),os.time(),commuteWorld) or dirty
        end
        if commuteWorld then traffic.installVehicleObstacles(R.state,commuteWorld,
            {customer=R.World.customer,vendor=R.World.vendor}) end
        if C.hasWorld(R) then
            local world=commuteWorld
            local motionActive=false
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
                    motionActive=motionActive or player.moving or part.rider.gear.transition~=nil
                        or math.abs(ix)+math.abs(iy)>.001
                end
            end
            world.vehicleObstacles=nil;world.sweepTrafficObstacles=nil
            if R._commute.motionActive and not motionActive then dirty=true end
            R._commute.motionActive=motionActive
            R._commute.networkClock=(R._commute.networkClock or 0)+dt
            if motionActive and R._commute.networkClock>=.25 then
                R._commute.networkClock=0
                if R.multiplayer:isHost() then R.multiplayer:markShopDirty() end
            end
            R._commute.saveClock=(R._commute.saveClock or 0)+dt
            if motionActive and R._commute.saveClock>=5 then R._commute.saveClock=0;dirty=true end
        end
        local trafficChanged,trafficMoving=traffic.simulate(R.state,R.state.home and R.state.home.town,
            dt,os.time(),commuteWorld,{customer=R.World.customer,vendor=R.World.vendor})
        dirty=trafficChanged or dirty
        if trafficMoving then
            R._commute.trafficNetworkClock=(R._commute.trafficNetworkClock or 0)+dt
            R._commute.trafficSaveClock=(R._commute.trafficSaveClock or 0)+dt
            if R._commute.trafficNetworkClock>=.25 then
                R._commute.trafficNetworkClock=0
                if R.multiplayer:isHost() then R.multiplayer:markShopDirty() end
            end
            if R._commute.trafficSaveClock>=5 then
                R._commute.trafficSaveClock=0;dirty=true
            end
        else
            R._commute.trafficNetworkClock=0;R._commute.trafficSaveClock=0
        end
        for _,player in ipairs(players) do
            if not C.hasWorld(R) or not R.state.home.commute.participants[Residents.key(player)] then
                local resident=Residents.get(R.state,player);local gear=resident and resident.ridingGear
                if gear and Gear.update(gear,dt) then resident.revision=resident.revision+1;R.state.home.revision=R.state.home.revision+1;dirty=true end
            end
        end
        if dirty and R.multiplayer:isHost() then R.multiplayer:markShopDirty() end
    end
    local part=C.localPart(R)
    if part then
        if part.interior=='barn' then return dirty end
        if part.interior=='grocery' then
            local view=R._commute or {};R._commute=view
            if not view.mechanicOffer and not view.groceryExiting then
                require('src.commute.mechanic_shop').openTownStore(R,'grocery',true)
            end
            return dirty
        elseif R._commute then R._commute.groceryExiting=nil end
        local world=C.world(R);local rider=C.visualRider(part,R.World.player,R.state.home.commute.token)
        local horn=rider.gear.mounted and Bindings.value(C.bindings(R),'horn',C.touch(R))>0 or false
        rider.bike.horn=horn;part.rider.bike.horn=horn
        local actor=Rider.actor(rider);local view=R._commute
        local visual=part.presentation
        view.controlFeedback=nil
        if R.multiplayer:isClient() and visual and not part.arrived then
            if visual.pose=='riding' and rider.gear.mounted and rider.vehicle~='truck' then
            -- Only the local rider's visible controls lead the network. The
            -- host continues to supply position, speed, impacts and gear.
                local steer=input(rider,x or 0,y or 0,false).steer
                local axis=y or 0
                local speed=rider.motion and rider.motion.speed or visual.speed or 0
                local braking=visual.grounded==false and axis>0 or visual.grounded~=false
                    and speed>0 and ((axis>0)~=(actor.reverse==true))
                local brake=braking and math.abs(axis) or 0
                visual=setmetatable({steer=steer,brake=brake,speed=speed,
                    lean=M.clamp(-steer*speed*.025,-.8,.8),
                    brakingPose=M.smooth((brake-.35)/.5)*M.smooth((speed-.7)/2.5)},
                    {__index=part.presentation})
                view.walkVisualDistance=nil
                view.controlFeedback=visual
            elseif rider.vehicle=='truck' and rider.truck then
                local controls=input(rider,x or 0,y or 0,false)
                local speed=rider.truck.speed or visual.speed or 0
                local axis=controls.drive or 0
                local braking=speed>.025 and axis~=0 and ((axis>0)~=(rider.truck.reverse==true))
                local delta=controls.steer-(rider.truck.steering or visual.steer or 0)
                local heading=rider.truck.heading+delta*math.min(speed*.025,.14)
                    *(rider.truck.reverse and -1 or 1)
                rider.truck.heading=heading
                visual=setmetatable({steer=controls.steer,speed=speed,heading=heading,
                    brake=braking and math.abs(axis) or 0},{__index=part.presentation})
                view.walkVisualDistance=nil
                view.controlFeedback=visual
            elseif not rider.gear.mounted and not rider.vehicle and not rider.gear.transition
                and (visual.pose=='normal_idle' or visual.pose=='geared_idle') then
                local magnitude=M.length(x or 0,y or 0)
                local speed=magnitude>.001 and Rider.WALK_SPEED
                    *math.min(1,magnitude)*(boost and Rider.SPRINT_MULTIPLIER or 1) or 0
                local distance=math.max(view.walkVisualDistance or 0,visual.distance or rider.ped.distance or 0)
                    +speed*math.max(0,dt)
                view.walkVisualDistance=distance
                visual=setmetatable({speed=speed,distance=distance,
                    heading=magnitude>.001 and math.atan2(y or 0,x or 0) or rider.ped.heading},
                    {__index=part.presentation})
                rider.ped.heading=visual.heading
                view.controlFeedback=visual
            else
                view.walkVisualDistance=nil
            end
        else
            view.walkVisualDistance=nil
        end
        if not view.camera then view.camera=require('src.commute.camera').new(actor,world);view.camera.zoom=1;view.camera.targetZoom=1 end
        local cabView=C.bindings(R).truckCabView
        view.camera.truckCabSide,view.camera.truckCabUp,view.camera.truckCabForward=
            cabView.side,cabView.up,cabView.forward
        -- Keep the truck cab and outside view on the same optical center on
        -- phones and desktop so the dashboard stays registered to the windshield.
        view.camera.viewCenterY=nil
        if cinematic then
            if view.camera.firstPerson then view.camera:setFirstPerson(false,actor) end
            view.camera:setOutsideMode('follow',actor,rider.gear.mounted and not rider.gear.transition)
            view.camera.targetZoom=rider.gear.mounted and 1.18 or 1.35
            view.camera.offsetY=rider.gear.mounted and -110 or 0
        else C.applyCameraPreference(R,view.camera,rider) end
        if not rider.gear.mounted or rider.vehicle=='truck' or not M.finite(actor.h) then actor.h=world:supportHeight(actor.x,actor.z) end
        view.camera:updateRide(rider,dt,visual)
        C.refreshNavigation(R,part,dt,false)
        if not cinematic and R.state.screen=='world' and not view.mechanicOffer and not view.loading and not view.mapOpen
            and not require('src.screens.hud_visibility').cameraLocked(R) then
            Bindings.camera(C.bindings(R),view.camera,dt,view.touchControls)
        end
        if view.mechanicOffer then return dirty end
        if not view.renderer then
            -- Present a loading frame before decoding/uploading shared ride art.
            if not view.loading then view.loading=true;return dirty end
            view.renderer=require('src.commute.renderer').new(world,{x=actor.x,z=actor.z},
                cinematic and {priorityPath=R._storyOpening and R._storyOpening.arrival
                    and R._storyOpening.arrival.plan.terrainPath} or nil)
            view.renderer:prewarmViews()
            view.cockpit=require('src.commute.cockpit').new()
            view.cockpit:prewarmFirstPerson()
            Icons.prewarm()
        end
        view.renderer.characterAssets=R.CharacterAssets
        view.renderer.calendar=R.state.calendar
        local renderCamera,cabViewport=require('src.commute.cab_viewport').forRuntime(R,view.camera)
        view.renderer:resizeViewport(cabViewport and cabViewport.width or 1280,
            cabViewport and cabViewport.height or 880)
        view.renderer:prepare(renderCamera,dt)
        local localVehicleKind=rider.vehicle=='truck' and 'truck'
            or rider.gear.mounted and 'bike' or nil
        local localVehicle=rider.vehicle=='truck' and rider.truck
            or rider.gear.mounted and rider.bike or nil
        view.renderer:updateTireTracks('local',localVehicle,world,dt,part.presentation,localVehicleKind)
        local particleRiders={};local playersBySlot={}
        for _,player in ipairs(R.multiplayer:remotePlayers()) do playersBySlot[player.id]=player end
        for id,p in pairs(R.state.home.commute.participants) do
            local player=p==part and R.World.player or playersBySlot[p.slot]
            if player and Residents.key(player)~=id then player=nil end
            local r=p==part and rider or C.visualRider(p,player,R.state.home.commute.token)
            local vehicleKind=r.vehicle=='truck' and 'truck'
                or r.gear.mounted and 'bike' or nil
            particleRiders[#particleRiders+1]={id=id,
                vehicle=vehicleKind=='truck' and r.truck or r.bike,
                vehicleKind=vehicleKind,visual=p.presentation,
                engine=player~=nil and (vehicleKind=='truck' and r.truck.engine~=false
                    or vehicleKind=='bike' and r.gear.engine==true),
                mounted=player~=nil and vehicleKind~=nil}
        end
        view.renderer:updateBikeParticles(particleRiders,dt)
        if view.loading and view.renderer:starterReady() then
            view.loading=nil
        end
    end
    return dirty
end
function C.draw(R,cinematic)
    local part=C.localPart(R);local view=R._commute
    if not part or not view then return end
    local showHud=not cinematic and require('src.screens.hud_visibility').isVisible(R)
    if not showHud then view.mapOpen=false;view.mainMapDrag=nil;view.cameraMenu=false end
    if part.interior=='barn' then return require('src.commute.barn_interior').draw(R,part) end
    if view.mechanicOffer and C.drawMechanic(R) then return end
    if not view.renderer or view.loading then
        local g=love.graphics
        g.clear(.025,.04,.035,1);g.setColor(.95,.89,.70)
        g.printf('Preparing your ride…',20,R.Config.baseHeight*.46,R.Config.baseWidth-40,'center')
        g.setColor(.75,.82,.76)
        local message='Loading your saved town and motorcycle.'
        if view.renderer then
            local stats=view.renderer:terrainStats()
            message=('Preparing nearby ground: %d tiles left'):format(stats.starterRemaining)
        end
        g.printf(message,20,R.Config.baseHeight*.46+30,R.Config.baseWidth-40,'center')
        g.setColor(1,1,1);return
    end
    local activeTrip=C.localTrip(R)
    if activeTrip.deliveryRun and activeTrip.deliveryRun.status=='offmap' then
        require('src.commute.city_delivery_scene').draw(R.Config.baseWidth,R.Config.baseHeight,
            activeTrip.deliveryRun,Trip.truckFor(part.rider,activeTrip),view.renderer.truckArt)
        love.graphics.setColor(1,1,1,1);return
    end
    local bindings=C.bindings(R)
    local g=love.graphics;local offsetX,offsetY,scaleX,scaleY=sceneTransform(R)
    if view.mapOpen then g.clear(.025,.04,.035,1) else
    g.push();g.translate(offsetX,offsetY);g.scale(scaleX,scaleY)
    local localId=R.multiplayer.localId or 1;local playersById={}
    local nameplates={}
    for _,player in ipairs(R.multiplayer:remotePlayers()) do playersById[player.id]=player end
    local actors={}
    for id,p in pairs(R.state.home.commute.participants) do
        local player=p.slot==localId and R.World.player or playersById[p.slot]
        if player and Residents.key(player)~=id then player=nil end
        local r=C.visualRider(p,player,R.state.home.commute.token)
        if player and p~=part and not p.interior then
            nameplates[#nameplates+1]={player=player,actor=Rider.actor(r),height=r.vehicle=='truck' and 3.9 or 2.1}
        end
        if p==part and view.controlFeedback and r.vehicle=='truck' and r.truck~=p.rider.truck then
            local feedback=view.controlFeedback
            local delta=feedback.steer-(r.truck.steering or p.presentation.steer or 0)
            r.truck.heading=r.truck.heading+delta*math.min(feedback.speed*.025,.14)
                *(r.truck.reverse and -1 or 1)
            r.truck.steering=feedback.steer;r.truck.brake=feedback.brake
        elseif p==part and view.controlFeedback and r.bike~=p.rider.bike then
            -- Lead the drawn heading slightly while the host turn catches up.
            local feedback=view.controlFeedback
            local delta=feedback.steer-(r.motion and r.motion.steer or p.presentation.steer or 0)
            r.bike.heading=r.bike.heading+delta*math.min(feedback.speed*.025,.14)
                *(r.bike.reverse and -1 or 1)
        elseif p==part and view.controlFeedback and not r.gear.mounted and r.vehicle~='truck'
            and view.controlFeedback.heading then
            r.ped.heading=view.controlFeedback.heading
        end
        local dismounting=r.gear.transition and r.gear.transition.kind=='dismount'
            or p.presentation and p.presentation.pose=='dismount'
        actors[#actors+1]={actor=r.bike,bike=true,bikeOnly=not player or not r.gear.mounted or dismounting,
            dismounting=dismounting==true,actionActor=dismounting and r.ped or nil,
            gear=dismounting and r.gear or nil,appearance=dismounting and p.appearance or nil,
            presentation=p==part and view.controlFeedback or p.presentation,localPlayer=p==part}
        if r.vehicle=='truck' then actors[#actors+1]={actor=r.truck,truck=true,
            presentation=p==part and view.controlFeedback or p.presentation,localPlayer=p==part}
        elseif player and not p.interior and not r.gear.mounted and not dismounting then
            local footPresentation=p.presentation
            if player.sceneId=='commute' then
                footPresentation=setmetatable({speed=M.length(player._visualVelocityX or player.velocityX or 0,
                    player._visualVelocityY or player.velocityY or 0),
                    distance=player._visualWalkDistance or (player.animationDistance or 0)/48},
                    {__index=p.presentation})
            end
            if p==part and view.controlFeedback then footPresentation=view.controlFeedback end
            actors[#actors+1]={actor=r.ped,gear=r.gear,presentation=footPresentation,
                appearance=p.appearance,localPlayer=p==part}
        end
    end
    local trip=C.localTrip(R)
    local companyTruck=R.state.employment and R.state.employment.companyTruck
    local companyBoxAway=companyTruck and companyTruck.deliveryRun~=nil
        and companyTruck.vehicleModel~='kei'
    local companyKeiAway=companyTruck and companyTruck.deliveryRun~=nil
        and companyTruck.vehicleModel=='kei'
    if trip.truck and not trip.truck.driver
        and not companyBoxAway then
        actors[#actors+1]={actor=trip.truck,truck=true,parkedTruck=true}
    end
    if trip.keiTruck and not trip.keiTruck.driver
        and not companyKeiAway then
        actors[#actors+1]={actor=trip.keiTruck,truck=true,parkedTruck=true}
    end
    local traffic=require('src.commute.delivery_traffic').actors(R.state,R.state.home.town,
        require('src.business_calendar').absoluteHours(R.state),os.time(),view.world,
        {customer=R.World.customer,vendor=R.World.vendor})
    view.mapTraffic=traffic
    if R.multiplayer:isClient() then
        view.trafficPresentation=view.trafficPresentation or {}
        local now=love.timer.getTime();local live={}
        for _,entry in ipairs(traffic) do
            local actor=entry.actor;local cache=view.trafficPresentation[entry.id]
            live[entry.id]=true
            if not cache then
                cache={x=actor.x,z=actor.z,h=actor.h or 0,heading=actor.heading,
                    targetX=actor.x,targetZ=actor.z,targetH=actor.h or 0,targetHeading=actor.heading,startedAt=now}
                view.trafficPresentation[entry.id]=cache
            elseif math.abs(cache.targetX-actor.x)+math.abs(cache.targetZ-actor.z)>.01
                or math.abs(cache.targetH-(actor.h or 0))>.01
                or math.abs(math.atan2(math.sin(cache.targetHeading-actor.heading),math.cos(cache.targetHeading-actor.heading)))>.01 then
                local a=math.min(1,(now-cache.startedAt)/.28)
                cache.x=cache.x+(cache.targetX-cache.x)*a
                cache.z=cache.z+(cache.targetZ-cache.z)*a
                cache.h=cache.h+(cache.targetH-cache.h)*a
                local headingDelta=math.atan2(math.sin(cache.targetHeading-cache.heading),math.cos(cache.targetHeading-cache.heading))
                cache.heading=cache.heading+headingDelta*a
                cache.targetX,cache.targetZ,cache.targetH,cache.targetHeading=actor.x,actor.z,actor.h or 0,actor.heading
                cache.startedAt=now
            end
            local a=math.min(1,(now-cache.startedAt)/.28)
            actor.x=cache.x+(cache.targetX-cache.x)*a
            actor.z=cache.z+(cache.targetZ-cache.z)*a
            actor.h=cache.h+(cache.targetH-cache.h)*a
            local headingDelta=math.atan2(math.sin(cache.targetHeading-cache.heading),math.cos(cache.targetHeading-cache.heading))
            actor.heading=cache.heading+headingDelta*a
        end
        for id in pairs(view.trafficPresentation) do
            if not live[id] then view.trafficPresentation[id]=nil end
        end
    end
    for _,entry in ipairs(traffic) do actors[#actors+1]=entry end
    local actor=Rider.actor(C.visualRider(part,R.World.player,R.state.home.commute.token))
    local renderCamera,cabViewport=require('src.commute.cab_viewport').forRuntime(R,view.camera)
    g.push()
    if cabViewport then g.translate(cabViewport.x,cabViewport.y) end
    view.renderer:draw(renderCamera,actor,actors,R.App.settings)
    require('src.story_intro').drawWorld(R,renderCamera)
    local labelCamera=renderCamera.shoulderView or renderCamera
    for _,entry in ipairs(nameplates) do
        local p=entry.actor
        local distance=(p.x-labelCamera.centerX)^2+(p.z-labelCamera.centerZ)^2
        local sx,sy,depth=labelCamera:screen(p.x,p.z,(p.h or view.world:supportHeight(p.x,p.z))+entry.height)
        if distance<(view.renderer.effectiveRadius or 64)^2
            and (not labelCamera.firstPerson or depth and depth>.15)
            and sx>=0 and sx<=(labelCamera.viewportWidth or 1280) and sy>=0 and sy<=(labelCamera.viewportHeight or 880) then
            require('src.player_profile').drawNameplate(entry.player,sx,sy-20)
        end
    end
    for _,entry in ipairs(traffic) do
        if entry.deliveryEmployee and entry.actor and entry.actor.speechCode then
            local px,py=view.camera:screen(entry.actor.x,entry.actor.z,
                (entry.actor.h or view.world:supportHeight(entry.actor.x,entry.actor.z))+1.65)
            local Speech=require('src.employee_speech')
            local caption=Speech.message(entry.actor.speechCode)
            if caption then
                local visible,fullCaption=require('src.dialogue_presentation').present(
                    'commute-delivery:'..tostring(entry.id),entry.characterId,caption,
                    Speech.emotion(entry.actor.speechCode))
                require('src.speech_bubble').draw(visible or caption,love.graphics.getFont(),
                    px,py,labelCamera.viewportWidth or 1280,fullCaption or caption)
            end
        end
    end
    g.pop()
    if not cinematic and not view.renderer:terrainReady() and not view.mapOpen then
        local stats=view.renderer:terrainStats()
        local message=part.rider.gear.mounted
            and ('Town loading %d%% · riding opens when ready'):format(
                math.floor(100*stats.completed/math.max(1,stats.total)))
            or ('Town loading %d%% · walk and gear up while it finishes'):format(
                math.floor(100*stats.completed/math.max(1,stats.total)))
        g.setColor(.025,.04,.035,.82)
        g.rectangle('fill',18,810,math.min(800,g.getFont():getWidth(message)*1.35+24),42,6)
        g.setColor(.87,.91,.82,.95)
        g.print(message,30,819,0,1.35,1.35)
        g.setColor(1,1,1)
    end
    if part.rider.vehicle=='truck' and view.camera.firstPerson then
        if not view.truckCockpit then view.truckCockpit=require('src.commute.truck_cockpit').new() end
        if view.controlFeedback and actor~=part.rider.truck then
            actor.steering=view.controlFeedback.steer;actor.brake=view.controlFeedback.brake
        end
        view.truckCockpit:draw(actor,1280,880,view.camera)
    end
    if showHud then
        local truck=part.rider.vehicle=='truck' and part.rider.truck
        if (truck and truck.engine~=false or part.rider.gear.mounted and part.rider.gear.engine) and not part.arrived
            and Bindings.freeCameraTouch(C.mobileInputEnabled(R),view.camera)
            and not horizontalTouchSteering(R,part.rider) then
            C.touch(R):drawAim(view.camera,actor,truck)
        end
        local markerIds
        if trip.purpose=='delivery' then
            local waypoint=C.activeWaypoint(R)
            markerIds=waypoint~='mainland_exit' and {waypoint} or {}
        elseif trip.origin=='warehouse' then markerIds=view.waypointId and {view.waypointId} or {}
        else markerIds={trip.origin,trip.destination} end
        for _,id in ipairs(markerIds) do
            local site=view.world.sites.byId[id]
            local p=site and site.door
            if p then
                local sx,sy=view.camera:screen(p.x,p.z,p.h+.1)
                g.setColor(.9,.8,.45);g.circle('line',sx,sy,18);g.print('STOP',sx-18,sy-30)
            end
        end
    end
    g.pop()
    end
    if not cinematic and not view.mapOpen and not view.doorTransition then
        drawDoorBeacon(R,part,activeTrip,view)
    end
    if view.doorTransition then
        DoorTransition.draw(view.doorTransition,R.Config.baseWidth,R.Config.baseHeight)
        g.setColor(1,1,1,1);return
    end
    if not showHud then
        if part.rider.gear.mounted and view.camera.firstPerson then
            if not view.cockpit then view.cockpit=require('src.commute.cockpit').new() end
            view.cockpit:draw(part.rider.bike,part.rider.gear.engine,R.Config.baseWidth,R.Config.baseHeight,view.controlFeedback or part.presentation,view.camera,C.bindings(R))
        end
        g.setColor(1,1,1);return
    end
    local trip=C.localTrip(R)
    local targetId
    if trip.purpose=='delivery' or trip.origin=='warehouse' then
        targetId=C.activeWaypoint(R)
    else targetId=trip.destination end
    local target=targetId and view.world.roads.destinations[targetId]
    local note=rideNotice(R,part)
    local mobile=C.mobileInputEnabled(R)
    local noteY,hintY,controlsTop=Cockpit.infoLayout(mobile,note)
    local actionContext=C.controlContext(R,part,controlsTop)
    local cardX=C.cardX(R)
    local bounds=C.worldUiBounds(R)
    local infoRight=view.miniMapVisible~=false and C.miniMapRect(R).x-12
        or (bounds and bounds.right or R.Config.baseWidth)-16
    if note and tostring(note)~='' then
        local noteWidth=math.min(630,g.getFont():getWidth(tostring(note))+18,infoRight-cardX)
        g.setColor(.025,.04,.035,.72);g.rectangle('fill',cardX,noteY,noteWidth,27,6)
        g.setColor(.83,.88,.80);require('src.screens.player_status').printLine(tostring(note),cardX+8,noteY+7,noteWidth-16)
    end
    if not view.mapOpen and part.rider.vehicle=='truck' then
        Cockpit.drawVehicleFrame(cardX,Cockpit.CARD_Y)
        local truck=part.rider.truck
        local label=truck and truck.model=='kei' and 'KEI DELIVERY TRUCK' or 'DELIVERY TRUCK'
        g.setColor(.84,.88,.77);require('src.screens.player_status').printLine(label,cardX+10,Cockpit.CARD_Y+11,Cockpit.CARD_WIDTH-20)
        local mph=(truck and truck.speed or 0)*2.236936
        g.setColor(.96,.83,.48);require('src.screens.player_status').printLine(('SPEED  %02d MPH'):format(math.floor(mph+.5)),cardX+10,Cockpit.CARD_Y+39,Cockpit.CARD_WIDTH-20)
        local condition=100-(truck and truck.damage or 0)
        local fuel=math.floor((truck and truck.fuel or 0)+.5)
        g.setColor(condition<60 and 1 or .68,condition<60 and .53 or .84,.48)
        require('src.screens.player_status').printLine(('COND %d%%  ·  FUEL %d L'):format(condition,fuel),
            cardX+10,Cockpit.CARD_Y+59,Cockpit.CARD_WIDTH-20)
    elseif not view.mapOpen then
        Cockpit.drawCondition(part.rider.bike,cardX,Cockpit.CARD_Y,view.renderer.bikeArt)
    end
    if part.rider.gear.mounted and part.rider.vehicle~='truck' and not view.mapOpen then
        if not view.cockpit then view.cockpit=require('src.commute.cockpit').new() end
        view.cockpit:draw(part.rider.bike,part.rider.gear.engine,R.Config.baseWidth,R.Config.baseHeight,view.controlFeedback or part.presentation,view.camera,C.bindings(R))
    end
    if not view.mapOpen then
        C.touch(R):draw(R.Config.baseWidth,R.Config.baseHeight,C.touchProfile(R,part),actionContext,
            {mobile=mobile,showActions=true,camera=view.camera,bounds=bounds,
                horizontalSteering=mobile and horizontalTouchSteering(R,part.rider)})
    end
    C.drawMap(R,part)
    C.drawCameraButton(R)
    require('src.story_intro').drawHud(R)
    g.setColor(1,1,1)
    return target and target.label,
        trip.purpose=='delivery' and 'CUSTOMER DELIVERY' or target and 'ROUTE SELECTED' or nil
end
local function performVehicleAction(R)
    local trip=C.localTrip(R);local part=C.localPart(R)
    if not trip or not part then return false end
    if require('src.story_intro').open(R) then return true end
    if trip.deliveryRun and trip.deliveryRun.status=='offmap' then return true end
    local rider=part.rider
    if rider.vehicle=='truck' then return C.request(R,'truck:'..trip.token) end
    if rider.gear.mounted then return C.request(R,'dismount:'..trip.token) end
    local truck=nearbyTruck(trip,rider)
    if truck and trip.origin=='warehouse' then return C.request(R,'truck:'..trip.token) end
    if rider.bike and M.length(rider.ped.x-rider.bike.x,rider.ped.z-rider.bike.z)<=3.2 then
        return C.request(R,'mount:'..trip.token)
    end
    return true
end

local function performWorldAction(R)
    local trip=C.localTrip(R);local part=C.localPart(R)
    if not trip or not part then return false end
    if require('src.story_intro').open(R) then return true end
    if trip.deliveryRun and trip.deliveryRun.status=='offmap' then return true end
    if part.arrived then
        return beginDoorTransition(R,'finish',trip.token,part.destination or trip.destination)
    end
    local rider=part.rider;local world=C.world(R);local sites=world.sites.byId
    if rider.gear.mounted or rider.gear.transition or rider.vehicle=='truck' or rider.ped.crash then return true end
    local function near(site)
        return site and site.door
            and M.length(rider.ped.x-site.door.x,rider.ped.z-site.door.z)<=DOOR_PROMPT_RADIUS
    end
    local function onFootAtDoor(site)
        return not rider.gear.mounted and not rider.gear.transition and rider.vehicle~='truck'
            and not rider.ped.crash and near(site)
    end
    local run=trip.deliveryRun;local stop=run and run.stops[run.stopIndex]
    if run and run.status=='driving' and stop and stop.kind=='town' and near(sites[stop.id]) then
        return beginDoorTransition(R,'deliver_stop',trip.token,stop.id)
    end
    local truck=nearbyTruck(trip,rider) or Trip.truckFor(rider,trip)
    local mode=Station.pumpMode(rider,truck,world)
    if mode then
        C.cancelCameraDrag(R);R._commute.mechanicOffer=Station.open(mode);return true
    end
    if onFootAtDoor(sites['gas-station']) then
        return beginDoorTransition(R,'station',trip.token,'gas-station')
    end
    if near(sites.mechanic) then return beginDoorTransition(R,'mechanic',trip.token,'mechanic') end
    for _,id in ipairs({'grocery','general-store','diner'}) do
        if onFootAtDoor(sites[id]) then
            return beginDoorTransition(R,id,trip.token,id)
        end
    end
    if trip.independent and not trip.deliveryRun and onFootAtDoor(sites.warehouse) then
        return beginDoorTransition(R,'enterwork',trip.token,'warehouse')
    end
    if trip.independent and not trip.deliveryRun and onFootAtDoor(sites[R.state.home.apartmentId]) then
        return beginDoorTransition(R,'enterhome',trip.token,R.state.home.apartmentId)
    end
    if near(sites[part.destination or trip.destination]) then
        return beginDoorTransition(R,'arrive',trip.token,part.destination or trip.destination)
    end
    if near(sites[part.origin or trip.origin]) then
        return beginDoorTransition(R,'cancel',trip.token,part.origin or trip.origin)
    end
    if run and run.status=='loading' and truck and Trip.truckAtLoadingBay(world,truck)
        and M.length(rider.ped.x-truck.x,rider.ped.z-truck.z)<=5.5 then
        local selected=Trip.truckFor(rider,trip)
        if selected and selected.model~=truck.model then return true end
        return C.request(R,'load_delivery:'..trip.token)
    end
    return true
end

function C.keypressed(R,key,semantic)
    if R.state.screen~='world' then return false end
    if require('src.story_intro').dialogueOpen(R) then
        if key=='return' or key=='space' or key=='e' or key=='back' or key=='escape'
            or not semantic and key==C.bindings(R).keyboard.worldAction then
            require('src.story_intro').advance(R)
        end
        return true
    end
    if key=='j' and not semantic then
        local c=require('src.warehouse_condition').of(R.state)
        if c and c.mode=='story' and not c.grandOpened then
            require('src.shop_room_controls').open(R,'utilities')
            return true
        end
    end
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
    if part.interior=='barn' then
        if key=='escape' or key=='back' then
            require('src.story_intro').exitBarn(R);return true
        end
        if key=='return' or key=='space' or key=='e'
            or not semantic and (key==C.bindings(R).keyboard.worldAction
                or key==C.bindings(R).keyboard.interact) then
            if not require('src.story_intro').open(R) then
                require('src.story_intro').exitBarn(R)
            end
        end
        return true
    end
    if R._commute and R._commute.doorTransition then return true end
    if R._commute.cameraMenu and (key=='escape' or key=='back') then R._commute.cameraMenu=false;return true end
    if R._commute and R._commute.loading and not part.interior and key~='escape' and key~='back' and key~='f10' then return true end
    if R._commute and R._commute.mechanicOffer then
        if key==(semantic and 'e' or C.bindings(R).keyboard.interact)
            or not semantic and key==C.bindings(R).keyboard.worldAction then key='e' end
        return require('src.commute.mechanic_shop').keypressed(R,key)
    end
    if R._commute and R._commute.mapOpen and (key=='escape' or key=='back') then
        return C.toggleMap(R)
    end
    if not semantic then
        if key=='tab' then C.toggleMiniMap(R);return true end
        if key=='escape' or key=='back' then C.cancelCameraDrag(R);return false end
        if key=='f10' then
            C.cancelCameraDrag(R)
            if R.openOptions then R.openOptions() end
            if R.OptionsScreen and R.OptionsScreen.openMotorcycleControls then R.OptionsScreen.openMotorcycleControls() end
            return true
        end
        local id=Bindings.action(C.bindings(R),'keyboard',key)
        if not id or Bindings.byId[id].held then return true end
        if id=='interact' or id=='worldAction' then return C.perform(R,id) end
        key=Bindings.byId[id].main
        if not key or key=='' then return true end
    end
    local t=C.localTrip(R);local r=part.rider;local camera=R._commute and R._commute.camera
    if t.deliveryRun and t.deliveryRun.status=='offmap' then return true end
    if require('src.screens.hud_visibility').cameraLocked(R)
        and (key=='q' or key=='r' or key=='t' or key=='y' or key=='c' or key=='=' or key=='-') then return true end
    if key=='m' then C.toggleMap(R)
    elseif key=='p' and camera then
        if camera:toggleView(r) then
            C.cancelCameraDrag(R)
        end
    elseif key=='o' then C.toggleOutsideCamera(R)
    elseif key=='g' then C.request(R,(r.gear.outfit=='normal' and 'equip:' or 'remove:')..t.token)
    elseif key=='i' then C.request(R,'ignition:'..t.token)
    elseif key=='h' then C.request(R,'headlight:'..t.token)
    elseif key=='n' then C.request(R,'beam:'..t.token)
    elseif key==',' then C.request(R,'signalLeft:'..t.token)
    elseif key=='.' then C.request(R,'signalRight:'..t.token)
    elseif key=='b' then C.request(R,'reverse:'..t.token)
    elseif key=='v' then C.request(R,(r.bike.transmission=='manual' and 'automatic:' or 'manual:')..t.token)
    elseif key=='z' then C.request(R,'shiftdown:'..t.token)
    elseif key=='x' then C.request(R,'shiftup:'..t.token)
    elseif key=='u' then C.request(R,'rescue:'..t.token)
    elseif key=='f' then C.request(R,'force:'..t.token)
    elseif key=='e' or key=='return' then return performVehicleAction(R)
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
    if require('src.story_intro').dialogueOpen(R) then
        if id=='interact' or id=='worldAction' then require('src.story_intro').advance(R) end
        return true
    end
    local part=C.localPart(R)
    if part and part.interior=='barn' then
        if id=='interact' or id=='worldAction' then
            return require('src.story_intro').open(R)
                or require('src.story_intro').exitBarn(R) or true
        end
        return true
    end
    if id=='steeringMode' then return toggleMobileSteeringMode(R) end
    if id=='interact' or id=='dismount' then
        if R._commute and R._commute.mechanicOffer then
            return require('src.commute.mechanic_shop').keypressed(R,'e')
        end
        return performVehicleAction(R)
    elseif id=='worldAction' then
        if R._commute and R._commute.mechanicOffer then
            return require('src.commute.mechanic_shop').keypressed(R,'e')
        end
        return performWorldAction(R)
    end
    if id=='mountBike' then
        local trip=C.localTrip(R)
        return trip and C.request(R,'mount:'..trip.token) or false
    end
    if id=='radioPrevious' or id=='radioPlay' or id=='radioNext' or id=='radioMute' then
        local trip=C.localTrip(R)
        return trip and C.request(R,id..':'..trip.token) or false
    end
    local spec=Bindings.byId[id]
    return spec and spec.main and spec.main~='' and C.keypressed(R,spec.main,true) or false
end
function C.deviceInput(R,device,token)
    if R.state.screen~='world' or not C.active(R) then return false end
    if require('src.story_intro').dialogueOpen(R) then
        if token=='a' or token=='b' or token=='return' then require('src.story_intro').advance(R) end
        return true
    end
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
    for _,button in ipairs(Touch.actionButtons(width,height,C.touchProfile(R,part),C.controlContext(R,part),
        {mobile=true,bounds=C.worldUiBounds(R)})) do
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
    if R.state.screen~='world' or not C.localPart(R) then return false end
    if require('src.story_intro').dialogueOpen(R) then return require('src.story_intro').pointer(R,x,y) end
    local part=C.localPart(R)
    if part.interior=='barn' then return require('src.commute.barn_interior').pointer(R,part,x,y) end
    local view=R._commute
    if view and view.doorTransition then return true end
    if R._commute and R._commute.mechanicOffer then
        if C.indoorControlsActive(R) and C.mobileInputEnabled(R) then return false end
        C.pointer(R,x,y,id);return true
    end
    if not view or not view.renderer or view.loading then return true end
    if C.cameraPointer(R,x,y) then return true end
    if C.mapPointer(R,x,y,id) then return true end
    local touch=C.touch(R)
    local part=C.localPart(R)
    local profile=C.touchProfile(R,part)
    if touch:press(id,x,y,R.Config.baseWidth,R.Config.baseHeight,profile,
        function(action) C.perform(R,action) end,C.controlContext(R,part),
        {mobile=true,allowGrip=C.mobileInputEnabled(R),camera=R._commute and R._commute.camera,
            stickSensitivity=touchStickSensitivity(R,part.rider),
            hiddenHud=not require('src.screens.hud_visibility').isVisible(R),bounds=C.worldUiBounds(R)}) then return true end
    return C.cameraTouchPressed(R,id,x,y)
end
function C.touchMoved(R,id,x,y)
    local view=R._commute
    if view and view.doorTransition then return true end
    if C.miniMapResizeMoved(R,x,y,id) then return true end
    if C.mapPointerMoved(R,x,y,id) then return true end
    if C.indoorControlsActive(R) and C.mobileInputEnabled(R) then return false end
    local part=C.localPart(R)
    if view and view.touchControls and view.touchControls:move(id,x,y,R.Config.baseWidth,R.Config.baseHeight,
        C.touchProfile(R,part),touchStickSensitivity(R,part and part.rider),C.worldUiBounds(R)) then return true end
    return C.cameraTouchMoved(R,id,x,y)
end
function C.touchReleased(R,id)
    local view=R._commute
    if view and view.doorTransition then return true end
    if C.finishMiniMapResize(R,id) then return true end
    if C.finishMainMapPan(R,id) then return true end
    if C.indoorControlsActive(R) and C.mobileInputEnabled(R) then return false end
    if view and view.touchControls and view.touchControls:release(id) then return true end
    return C.cameraTouchReleased(R,id)
end
function C.pointer(R,x,y,source)
    if R.state.screen~='world' then return false end
    if require('src.story_intro').dialogueOpen(R) then return require('src.story_intro').pointer(R,x,y) end
    local part=C.localPart(R)
    if part and part.interior=='barn' then
        return require('src.commute.barn_interior').pointer(R,part,x,y)
    end
    if R._commute and R._commute.doorTransition then return true end
    local offer=R._commute and R._commute.mechanicOffer
    if offer then return require('src.commute.mechanic_shop').pointer(R,x,y) end
    if R.World.player.sceneId=='commute' and C.localPart(R)
        and (not R._commute or not R._commute.renderer or R._commute.loading) then return true end
    if C.cameraPointer(R,x,y) then return true end
    if C.mapPointer(R,x,y,source or 'pointer') then return true end
    local part=C.localPart(R)
    if not part then return false end
    local mobile=C.mobileInputEnabled(R)
    local action=Touch.actionAt(x,y,R.Config.baseWidth,R.Config.baseHeight,C.touchProfile(R,part),
        C.controlContext(R,part),{mobile=mobile,camera=R._commute and R._commute.camera,
            bounds=C.worldUiBounds(R),
            hiddenHud=not require('src.screens.hud_visibility').isVisible(R)})
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
    if C.finishMiniMapResize(R,source) then return true end
    if C.finishMainMapPan(R,source) then return true end
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
    if require('src.screens.hud_visibility').cameraLocked(R) then
        local action=Bindings.action(C.bindings(R),'mouse','mouse'..button)
        return action=='orbit' or action=='pan'
    end
    view.cameraDrag=view.cameraDrag or {}
    local profile=C.bindings(R)
    if leftAlt==nil then local key=profile.keyboard.panModifier;leftAlt=key~='' and love.keyboard.isDown(key) end
    return CameraControls.press(view.cameraDrag,button,leftAlt,profile)
end
function C.cancelCameraLook(R)
    local view=R._commute
    if view and view.cameraDrag then CameraControls.cancel(view.cameraDrag) end
    if view then view.cameraTouches=nil;view.cameraPinch=nil end
end
function C.cancelCameraDrag(R)
    C.cancelCameraLook(R)
    local view=R._commute
    if view and view.miniMapResize then C.finishMiniMapResize(R,view.miniMapResize.source) end
    if view and view.touchControls then view.touchControls:cancel() end
    if view then
        view.touchBoost=false;view.pointerAction=nil;view.pointerActionSource=nil
    end
end
function C.cameraPointerReleased(R,button)
    local view=R._commute
    return view and view.cameraDrag and CameraControls.release(view.cameraDrag,button) or false
end
function C.cameraPointerMoved(R,dx,dy)
    if require('src.screens.hud_visibility').cameraLocked(R) then return true end
    local view=R._commute
    if R.state.screen~='world' or not C.active(R) then C.cancelCameraDrag(R);return false end
    if not view or not view.cameraDrag then return false end
    local _,_,scaleX,scaleY=sceneTransform(R)
    return CameraControls.move(view.cameraDrag,view.camera,dx,dy,scaleX,scaleY)
end
function C.cameraTouchPressed(R,id,x,y)
    local view=R._commute
    if R.state.screen~='world' or not C.active(R) or not view or not view.camera or not view.renderer
        or view.loading or view.mechanicOffer or view.mapOpen then return false end
    if require('src.screens.hud_visibility').cameraLocked(R) then return true end
    view.cameraTouches=view.cameraTouches or {}
    if view.cameraPinch or view.cameraTouches[id] then return true end
    local first=next(view.cameraTouches)
    view.cameraTouches[id]={x=x,y=y}
    if first then view.cameraPinch={first,id} end
    return true
end
function C.cameraTouchMoved(R,id,x,y)
    if require('src.screens.hud_visibility').cameraLocked(R) then return true end
    local view=R._commute;local touch=view and view.cameraTouches and view.cameraTouches[id]
    if not touch then return false end
    local pair=view.cameraPinch
    if not pair then touch.x,touch.y=x,y;return true end
    local a,b=view.cameraTouches[pair[1]],view.cameraTouches[pair[2]]
    local oldX,oldY=b.x-a.x,b.y-a.y
    local dx,dy=(x-touch.x)*.5,(y-touch.y)*.5
    touch.x,touch.y=x,y
    local newX,newY=b.x-a.x,b.y-a.y
    local d0,d1=M.length(oldX,oldY),M.length(newX,newY)
    local camera=view.camera
    local twist=0
    if d0>=8 and d1>=8 then
        twist=math.deg(math.atan2(oldX*newY-oldY*newX,oldX*newX+oldY*newY))
        camera:zoomBy(math.log(d1/d0)/.12)
    end
    local _,_,scaleX,scaleY=sceneTransform(R)
    local sign=camera.firstPerson and -1 or 1
    camera:orbit(sign*(twist-dx*.45/scaleX),sign*dy*.25/scaleY)
    return true
end
function C.cameraTouchReleased(R,id)
    if require('src.screens.hud_visibility').cameraLocked(R) then return true end
    local view=R._commute
    if not view or not view.cameraTouches or not view.cameraTouches[id] then return false end
    view.cameraTouches[id]=nil
    view.cameraPinch=nil
    return true
end
function C.release(R)
    require('src.commute.city_delivery_scene').release()
    if R._commute and R._commute.mechanicOffer then require('src.commute.mechanic_shop').close(R,true) end
    if R._commute and R._commute.renderer then R._commute.renderer:release() end
    if R._commute and R._commute.cockpit then R._commute.cockpit:release() end
    if R._commute and R._commute.truckCockpit then R._commute.truckCockpit:release() end
    if R._commute and R._commute.routeMap then R._commute.routeMap:release() end
    Icons.release()
    R._commute=nil
end
function C.releaseView(R)
    -- Keep terrain/collision data for remote riders on an indoor host. GPU
    -- assets, camera, maps and cockpit only belong to the local scene.
    local world=R._commute and R._commute.world
    C.release(R)
    if world and C.hasWorld(R) then R._commute={world=world} end
end
function C.openMechanic(R)
    C.cancelCameraDrag(R)
    if R._commute then R._commute.mapOpen=false;R._commute.mainMapDrag=nil end
    return require('src.commute.mechanic_shop').open(R)
end
function C.openTownStore(R,storeId)
    C.cancelCameraDrag(R)
    if R._commute then R._commute.mapOpen=false;R._commute.mainMapDrag=nil end
    return require('src.commute.mechanic_shop').openTownStore(R,storeId)
end
function C.buyUpgrade(R) return require('src.commute.mechanic_shop').confirm(R) end
function C.drawMechanic(R) return require('src.commute.mechanic_shop').draw(R) end
return C
