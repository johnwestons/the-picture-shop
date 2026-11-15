local Town=require('src.commute.town')
local Truck=require('src.commute.delivery_truck')
local Trip=require('src.commute.trip')
local Motion=require('src.commute.company_truck_motion')
local Network=require('src.commute.delivery_traffic')
local Footprint=require('src.commute.truck_footprint')
local Codec=require('src.net.codec')
local Test={}
local function roundTrip(value)
    local limits={maxBytes=65536,maxEntries=2048}
    return assert(Codec.decode(assert(Codec.encode(value,limits)),limits))
end
local function copy(value)
    if type(value)~='table' then return value end
    local result={};for k,v in pairs(value) do result[k]=copy(v) end;return result
end
local function fixture(seed,model,dock)
    local town=assert(Town.generate(seed));local world=Town.world(town)
    local box=assert(Trip.truckParking(world,{fuelLiters=60},'box'))
    local kei=assert(Trip.truckParking(world,{fuelLiters=60},'kei',box))
    local source=model=='box' and box or kei
    if dock then
        local site=world.sites.byId.warehouse
        source.x,source.z,source.heading=site.truckParking.x,site.truckParking.z,site.yaw
    end
    source.engine=false
    local motion=Motion.start(source,world)
    local state={home={town=town,commute={participants={},truck=box,keiTruck=kei}},
        employment={companyTruck={deliveryRun={},vehicleModel=model,exterior=motion}}}
    return state,world,motion
end
local function run(state,world,motion,seconds,wanted)
    local hit,invalid,jumped=false,false,false
    for _=1,seconds*10 do
        Network.installVehicleObstacles(state,world)
        local x,z,phase=motion.vehicle.x,motion.vehicle.z,motion.phase
        Motion.update(motion,world,.1,state)
        hit=hit or motion.vehicle.collisionContact
        invalid=invalid or not Motion.valid(motion)
        jumped=jumped or phase~='waiting_return' and
            (motion.vehicle.x-x)^2+(motion.vehicle.z-z)^2>1
        if wanted and motion.phase==wanted then break end
    end
    local v=motion.vehicle;local x,z=world.sites.byId.warehouse:toLocal(v.x,v.z)
    return (not wanted or motion.phase==wanted) and not hit and not invalid and not jumped,
        ('%s %.2f,%.2f h%.2f v%.2f i%d blocked=%s hit=%s invalid=%s jump=%s'):
        format(motion.phase,x,z,v.heading,v.speed,motion.index,tostring(motion.blocked),
            tostring(hit),tostring(invalid),tostring(jumped))
end
local function clean(world)
    world.vehicleObstacles=nil;world.sweepTrafficObstacles=nil
end
local function playerAhead(state,motion,kind,gap)
    local v=motion.vehicle;local reverse=motion.phase=='reverse_out'
    local sign=reverse and -1 or 1
    local distance=Footprint.dimensions(v).halfLength+(kind=='bike' and .62 or .55)+(gap or .8)
    local actor={x=v.x+math.cos(v.heading)*distance*sign,
        z=v.z+math.sin(v.heading)*distance*sign,h=v.h,heading=v.heading,speed=0}
    state.home.commute.participants.blocker={slot=1,rider=kind=='bike'
        and {gear={mounted=true},bike=actor} or {gear={mounted=false},ped=actor}}
end
local function clearPlayer(state)state.home.commute.participants.blocker=nil end
function Test.run(_,check)
    for _,seed in ipairs({712345,712346,43127}) do
        for _,model in ipairs({'box','kei'}) do
            local state,world,motion=fixture(seed,model)
            local okay,detail=run(state,world,motion,180,'away')
            check('company_physical_departure_'..model..'_'..seed,okay,detail)
            motion.phase='waiting_return'
            okay,detail=run(state,world,motion,180,'return_walk')
            local home=world.sites.byId.warehouse.truckHomeParking[model]
            check('company_physical_return_'..model..'_'..seed,okay
                and motion.vehicle.x==home.x and motion.vehicle.z==home.z
                and not motion.vehicle.engine,detail)
            clean(world)
        end
    end
    for _,model in ipairs({'box','kei'}) do
        local state,world,motion=fixture(712345,model)
        playerAhead(state,motion,'pedestrian')
        local x,z=motion.vehicle.x,motion.vehicle.z
        local okay,detail=run(state,world,motion,2)
        check('company_reverse_stops_for_player_'..model,okay and motion.phase=='reverse_out'
            and motion.vehicle.speed<.025 and (motion.vehicle.x-x)^2+(motion.vehicle.z-z)^2<1,detail)
        motion=roundTrip(motion)
        state.employment.companyTruck.exterior=motion
        x,z=motion.vehicle.x,motion.vehicle.z
        okay,detail=run(state,world,motion,2)
        check('company_saved_blocked_reverse_stays_stopped_'..model,okay
            and motion.vehicle.x==x and motion.vehicle.z==z,detail)
        clearPlayer(state)
        okay,detail=run(state,world,motion,90,'departing')
        check('company_reverse_resumes_after_player_moves_'..model,okay,detail)
        run(state,world,motion,2)
        playerAhead(state,motion,'bike',1.8)
        x,z=motion.vehicle.x,motion.vehicle.z
        okay,detail=run(state,world,motion,2)
        check('company_forward_stops_for_motorcycle_'..model,okay and motion.phase=='departing'
            and motion.vehicle.speed<.025 and (motion.vehicle.x-x)^2+(motion.vehicle.z-z)^2<9,detail)
        clearPlayer(state)
        okay,detail=run(state,world,motion,120,'away')
        check('company_departure_resumes_after_motorcycle_moves_'..model,okay,detail)
        motion.phase='waiting_return'
        local other=model=='box' and state.home.commute.keiTruck or state.home.commute.truck
        local saved=copy(other);local gate=world.truckAccess.entryGate
        other.x,other.z=gate.x,gate.z
        okay,detail=run(state,world,motion,30)
        check('company_return_waits_for_occupied_entry_'..model,okay
            and motion.phase=='waiting_return' and not Motion.visible(motion),detail)
        for k,v in pairs(saved)do other[k]=v end
        local home=world.sites.byId.warehouse.truckHomeParking[model]
        state.home.commute.participants.blocker={slot=1,rider={ped={x=home.x,z=home.z},gear={mounted=false}}}
        okay,detail=run(state,world,motion,120)
        check('company_return_waits_for_occupied_stall_'..model,okay
            and motion.phase=='returning' and motion.vehicle.speed<.025,detail)
        motion=roundTrip(motion)
        state.employment.companyTruck.exterior=motion
        x,z=motion.vehicle.x,motion.vehicle.z
        okay,detail=run(state,world,motion,30)
        check('company_saved_blocked_return_stays_stopped_'..model,okay
            and motion.vehicle.x==x and motion.vehicle.z==z,detail)
        clearPlayer(state)
        okay,detail=run(state,world,motion,120,'return_walk')
        check('company_return_resumes_and_parks_after_stall_clears_'..model,okay,detail)
        clean(world)
        state,world,motion=fixture(712345,model,true)
        okay,detail=run(state,world,motion,180,'away')
        check('company_can_depart_from_loading_dock_'..model,okay,detail)
        clean(world)
    end
    local state,world,motion=fixture(712345,'box')
    playerAhead(state,motion,'pedestrian')
    run(state,world,motion,2)
    local distance,fuel=motion.vehicle.distance,motion.vehicle.fuel
    check('company_yard_watchdog_exposes_manual_recovery',Network.debugUnstickAvailable(state,'company-yard:box'))
    local moved,message=Network.debugUnstick(state,'company-yard:box')
    check('company_yard_manual_recovery_uses_clear_checkpoint',moved
        and motion.vehicle.distance==distance and motion.vehicle.fuel==fuel,tostring(message))
    local okay,detail=run(state,world,motion,5,'departing')
    check('company_yard_resumes_protocol_after_manual_recovery',okay,detail)
    clean(world)
end
return Test
