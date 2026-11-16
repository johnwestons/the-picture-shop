local Medical=require('src.player_medical')
local Residents=require('src.home_residents')
local Runtime={}
function Runtime.onFoot(R,player)
    if player.resting then return false end
    local lift=R.state.forklift
    if lift and lift.operating and lift.operatorPlayerId==(player.id or 1) then return false end
    local t=R.state.home.commute;local part=t and t.participants[Residents.key(player)]
    if not part or part.interior then return true end
    local r=part.rider;local transition=r.gear.transition
    return not r.vehicle and not r.gear.mounted and not r.ped.crash
        and not (transition and (transition.kind=='mount' or transition.kind=='dismount'))
end
local function stop(R,player)
    if player._medicalStopped then return end
    player._medicalStopped=true
    player.velocityX,player.velocityY,player.inputX,player.inputY=0,0,0,0
    player.moving=false;player.resting=false
    if R.workshopAuthority then R.workshopAuthority:cleanupPlayer({id=player.id or 1},'medical',{state=R.state}) end
    require('src.forklift').forceRelease(R.state,R.Config.forklift,player.id or 1)
    for _,jack in ipairs(require('src.pallet_jack_fleet').all(R.state)) do
        if jack.operatorPlayerId==(player.id or 1) then
            jack.operating=false;jack.moving=false;jack.operatorPlayerId=nil
        end
    end
    local t=R.state.home.commute;local part=t and t.participants[Residents.key(player)]
    if part then
        local r=part.rider
        if r.vehicle=='truck' then r.truck.speed=0;r.truck.engine=false end
        if r.gear.mounted then
            local x,z=require('src.commute.rider').footing(r,require('src.commute.runtime').world(R))
            if x then r.ped.x,r.ped.z=x,z end
            r.gear.mounted=false;r.gear.engine=false;r.gear.transition=nil
        end
        r.bike.speed=0;require('src.commute.motorcycle').resetHorizontal(r.bike)
        r.ped.vx,r.ped.vz,r.ped.speed=0,0,0
    end
    if player==R.World.player then
        R.state.screen='world';R.World.selectedInteraction=nil;R._medicalClinic=nil
        if R._commute then
            R._commute.mapOpen=false
            require('src.commute.mechanic_shop').close(R,true)
            R._commute.introDialogue=nil;R._commute.doorTransition=nil
        end
        if R.WorkshopRemoteScreen then R.WorkshopRemoteScreen.clear() end
        R.localWorkshopLease=nil;R.state._localWorkshopMachineId=nil
    end
end
local function independent(R)
    local t=R.state.home.commute
    if t and not t.independent then
        local origin,destination=t.origin,t.destination
        for _,part in pairs(t.participants) do part.origin=origin;part.destination=destination end
        t.independent=true;t.purpose='outing';t.origin='warehouse';t.destination=R.state.home.apartmentId
        if t.deliveryRun then t.deliveryDriver=t.deliveryDriver or 'owner' end
        for _,p in ipairs(require('src.weekend_runtime').players(R)) do
            local r=Residents.get(R.state,p)
            if r then r.sceneId=t.participants[Residents.key(p)] and 'commute' or p.sceneId=='home' and 'home' or 'warehouse' end
        end
    end
    return t
end
function Runtime.transport(R,player,kind)
    local C=require('src.commute.runtime');local world=C.world(R)
    local resident=Residents.get(R.state,player);local id=Residents.key(player)
    local t=independent(R);local part=t and t.participants[id]
    if part then
        for _,truck in ipairs(require('src.commute.trip').trucks(t)) do
            if truck.driver==id then truck.driver=nil;truck.speed=0;truck.engine=false end
            if truck.owner==id and not (t.deliveryRun and t.deliveryDriver==id) then truck.owner=nil end
        end
        part.rider.vehicle=nil;part.rider.transport=nil;part.rider.truck=nil
        part.rider.gear=require('src.commute.gear').new()
        part.rider.ped.crash=nil
    end
    resident.ridingGear=require('src.commute.gear').new()
    if kind=='rescue' then
        if not part then
            player.sceneId=player.sceneId=='home' and 'home' or 'warehouse'
            local okay,reason=require('src.commute.free_travel').enter(R.state,player,world,nil,require('src.weekend_runtime').players(R))
            if not okay then return false,reason end
            t=R.state.home.commute;part=t.participants[id]
        end
        local farm=world.sites.byId.farm
        -- An unusually crowded legacy map may have no safe farm frontage.
        -- Still complete the rescue at home rather than trapping the patient.
        if not farm then return Runtime.transport(R,player,'home_rescue') end
        local bx,bz=farm:toWorld(0,25,0)
        local oldBike=part.rider.bike
        part.rider=require('src.commute.rider').new(bx,bz,farm.yaw,require('src.commute.gear').new())
        for _,key in ipairs({'transmission','upgradeLevel','upgradeParts','paintId','service','damage'}) do
            part.rider.bike[key]=require('src.save_schema').copy(oldBike[key])
        end
        part.rider.bike.h=world:supportHeight(bx,bz)
        part.arrived=false;part.interior='barn'
        part.interiorPose={x=575,y=415,intentX=1,intentY=0,animationDistance=0,moving=false,
            character=player.character,furColorway=player.furColorway,overallsColorway=player.overallsColorway}
        resident.sceneId='commute';resident.bikeParkedAtHome=false
        C.syncPlayer(player,part)
    else
        if t then t.participants[id]=nil end
        resident.sceneId='home';resident.bikeParkedAtHome=true
        if not t then R.state.home.visit={kind='outing',scene='home'} end
        local x,y=require('src.home_layouts').spawn(R.state,player.id or 1)
        require('src.player_controller').reset(player,{x=x,y=y},R.Config.player)
        player.sceneId='home'
    end
    if player==R.World.player and R._commute then
        R._commute.introDialogue=nil;R._commute.mapOpen=false;R._commute.doorTransition=nil
    end
    R.state.home.revision=R.state.home.revision+1
    return true
end
function Runtime.update(R,dt,hours)
    local changed=false
    for _,player in ipairs(require('src.weekend_runtime').players(R)) do
        local m,resident=Medical.get(R.state,player)
        if m then
            local started=Medical.advance(resident,hours,Runtime.onFoot(R,player))
            if started then
                player._medicalStopped=nil
                stop(R,player)
                if m.phase=='hospital' then Medical.bill(R.state,resident) end
                changed=true
            end
            player.medicalCollapsed=m.phase~=nil
            if m.phase then
                -- Timers belong to the host and are saved, so reconnecting cannot
                -- dodge a bill or repeat an emergency charge.
                stop(R,player)
                local previousSecond=math.ceil(m.remaining)
                m.remaining=math.max(0,m.remaining-math.min(dt,1))
                changed=changed or previousSecond~=math.ceil(m.remaining)
                if m.remaining==0 then
                    local kind=m.phase
                    local okay=kind=='faint' or Runtime.transport(R,player,kind)
                    if okay then
                        Medical.recover(resident,kind);player.medicalCollapsed=false
                        player._medicalStopped=nil;changed=true
                    end
                end
            else player._medicalStopped=nil end
        end
    end
    return changed
end
return Runtime
