local PixelCanvas=require('src.tests.support.pixel_canvas')
local Network=require('src.commute.delivery_traffic')
local Town=require('src.commute.town')
local Routes=require('src.commute.routes')
local DrivingPath=require('src.commute.driving_path')
local TruckArt=require('src.commute.truck_art')
local Camera=require('src.commute.camera')
local StopControl=require('src.commute.tests.stop_control_test')
local Test={}

local function byCompany(actors)
    local result={}
    for _,entry in ipairs(actors) do
        if entry.actor and entry.actor.company then result[entry.actor.company]=entry end
    end
    return result
end

function Test.run(check)
    require('src.commute.tests.npc_driving_test').run(check)
    local actor={x=0,z=0,h=0}
    check('truck_free_camera_keeps_isometric_art_at_every_tilt',
        TruckArt.viewKind({tilt=30},actor,0)=='isometric'
            and TruckArt.viewKind({tilt=Camera.TILT_MIN},actor,0)=='isometric')
    check('truck_free_camera_keeps_isometric_art_near_a_parked_truck',
        TruckArt.viewKind({tilt=55,centerX=0,centerZ=0,lastActor={x=0,z=0}},
            {x=3,z=0,h=0},0)=='isometric')
    check('truck_first_person_and_shoulder_keep_chase_art',
        TruckArt.viewKind({firstPerson=true},actor,0)=='chase'
            and TruckArt.viewKind({projectionCamera={includeLocalRider=true,shoulderPerspective=true}},actor,0)=='chase')
    check('truck_follow_camera_ignores_legacy_chase_hint_and_low_elevation',
        TruckArt.viewKind({outsideMode='follow',tilt=Camera.TILT_MIN,localTruckChase=true},actor,0)=='isometric'
            and TruckArt.viewKind({firstPerson=true,projectionCamera={includeLocalRider=true,
                outsideMode='follow',centerX=0,centerZ=3,eyeHeight=2}},actor,0)=='isometric')
    local aligned=true
    local outside={firstPerson=false,yaw=0}
    local firstPerson={firstPerson=true,viewHeading=.73}
    for index=0,63 do
        local step=index*math.pi*2/64
        aligned=aligned and TruckArt.frame(outside,-math.pi/2+step,'box')==index+1
            and TruckArt.frame(firstPerson,.73+step,'box')==index+1
    end
    check('box_truck_retains_uniform_64_view_calibration',aligned)
    for _,kind in ipairs({'isometric','chase'}) do
        local expected=kind=='isometric' and {1,14,33,43} or {1,15,33,43}
        for index=0,3 do
            local angle=index*math.pi/2
            check('kei_'..kind..'_cardinal_'..index,
                TruckArt.frame(outside,angle-math.pi/2,'kei',kind)==expected[index+1]
                and TruckArt.frame(firstPerson,.73+angle,'kei',kind)==expected[index+1])
        end
        check('kei_'..kind..'_rear_diagonal_uses_diagonal_not_repeated_rear',
            TruckArt.frame(outside,math.rad(315)-math.pi/2,'kei',kind)==53)
        local pages=require('src.commute.kei_turntable_pages')
        local wrapped=true
        for degrees=-720,720 do
            local angle=math.rad(degrees)
            wrapped=wrapped and pages.frame(angle,kind)==pages.frame(angle+math.pi*2,kind)
        end
        check('kei_'..kind..'_heading_wraps_without_changing_sprite',wrapped)
    end

    local town=assert(Town.generate(712345))
    local world=Town.world(town)
    require('src.commute.tests.scheduled_driving_test').run(check,town,world)
    local planner=Routes.new(world.roads,{includeTruckOnly=world.truckDestinations~=nil,
        pavedOnly=true,destinations=world.truckDestinations})
    local liveRoute=planner:findFromPoint(world.mainlandExit.x,world.mainlandExit.z,
        world.truckDestinations and 'warehouse_truck_dock' or 'warehouse')
    local speedLimits=liveRoute and DrivingPath.speedLimits(liveRoute.points) or {}
    local validSpeedProfile=#speedLimits>0
    for _,marker in ipairs(speedLimits) do
        validSpeedProfile=validSpeedProfile and marker.speed>=2.7 and marker.speed<=8.6
    end
    check('delivery_traffic_live_routes_derive_turn_speed_limits',validSpeedProfile,
        ('markers=%d'):format(#speedLimits))
    local state={calendar={secondsPerDay=300},inventory={stock={}},procurement={
        orders={{id='PO-TRAFFIC-1',shipmentId='SHIP-TRAFFIC-1',category='paper',
            company='CritterNet Paper Depot',pallets={{id='PO-TRAFFIC-1-PALLET',location='awaiting_delivery'}}}},
        shipments={{id='SHIP-TRAFFIC-1',status='awaiting_delivery',orderIds={'PO-TRAFFIC-1'},delivery={
            status='awaiting_schedule',expectedAtHours=105}}},
    },jobs={active={{id='JOB-TRAFFIC-1',company='Blue Ridge Packaging',delivery={
        status='pending_arrival',readyAtHours=105},pallets={{id='JOB-TRAFFIC-1-P1',location='awaiting_delivery'}}}},completed={}}}
    local epoch=1700000000
    local routesChanged=Network.update(state,town,105,epoch)
    local supplierRoute=state.procurement.shipments[1].delivery.route
    local jobRoute=state.jobs.active[1].delivery.route
    check('delivery_traffic_routes_supplier_and_client_shipments',
        routesChanged and supplierRoute and jobRoute
        and supplierRoute.transportId==state.jobs.active[1].id
        and supplierRoute.originCompany=='CritterNet Paper Depot'
        and jobRoute.originCompany=='Millhaven Freight',
        string.format("changed=%s supplierTransport=%s supplierCompany=%s jobCompany=%s",
            tostring(routesChanged),tostring(supplierRoute and supplierRoute.transportId),
            tostring(supplierRoute and supplierRoute.originCompany),tostring(jobRoute and jobRoute.originCompany)))

    local shipment=state.procurement.shipments[1]
    local job=state.jobs.active[1]
    local duration=shipment.delivery.route.arrivedAtEpoch-epoch
    local midEpoch=epoch+duration*.5
    local midway=byCompany(Network.actors(state,town,105,midEpoch))
    check('delivery_traffic_merges_manifests_into_one_shared_freight_truck',
        midway['Millhaven Freight'] and #Network.actors(state,town,105,midEpoch)==1
        and midway['Millhaven Freight'].phase=='approaching'
        and midway['Millhaven Freight'].actor.livery=='plain')
    local sharedTruck={phase='approaching'}
    job.delivery.route.vehicle=sharedTruck
    shipment.delivery.route.vehicle=sharedTruck
    local earlyArrival=Network.arrived(job,midEpoch)
    sharedTruck.phase='at_bay'
    local arrivalEpoch=job.delivery.route.arrivedAtEpoch
    local finalArrival=Network.arrived(job,arrivalEpoch)
    check('delivery_traffic_gates_warehouse_dropoff_until_arrival',
        not earlyArrival and finalArrival,
        string.format("duration=%.3f shipArrival=%s jobArrival=%s early=%s final=%s vehicle=%s phase=%s",
            duration,tostring(shipment.delivery.route.arrivedAtEpoch),tostring(arrivalEpoch),
            tostring(earlyArrival),tostring(finalArrival),tostring(job.delivery.route.vehicle),
            tostring(job.delivery.route.vehicle and job.delivery.route.vehicle.phase)))

    job.delivery.status='received'
    job.delivery.receivedAtHours=105.5
    shipment.delivery.status='received'
    shipment.delivery.receivedAtHours=105.5
    local returnEpoch=job.delivery.route.arrivedAtEpoch+1
    local returnChanged=Network.update(state,town,106,returnEpoch)
    local returning=byCompany(Network.actors(state,town,106,returnEpoch+1))
    check('delivery_traffic_preserves_client_brand_on_return_route',
        returnChanged
        and job.delivery.returnRoute.originCompany=='Blue Ridge Packaging'
        and returning['Blue Ridge Packaging']~=nil,
        string.format("changed=%s returnCompany=%s actorCount=%d shipmentStatus=%s jobStatus=%s",
            tostring(returnChanged),tostring(job.delivery.returnRoute and job.delivery.returnRoute.originCompany),
            #Network.actors(state,town,106,returnEpoch+1),tostring(shipment.delivery.status),tostring(job.delivery.status)))

    local art=TruckArt.new()
    local g=love.graphics
    local decal=assert(art.decals:companyImage('Blue Ridge Packaging'))
    local width,height=decal:getDimensions()
    local decalData=decal:newImageData()
    local visible=0
    for y=0,height-1,4 do
        for x=0,width-1,4 do
            local _,_,_,alpha=decalData:getPixel(x,y)
            if alpha>.5 then visible=visible+1 end
        end
    end
    decalData:release()
    check('delivery_company_decal_is_a_separate_high_resolution_overlay',
        width==512 and height==200 and visible>100)

    local preview=PixelCanvas(640,448,{format='rgba8'})
    local camera={zoom=1,yaw=0,tilt=55,screen=function() return 320,320 end}
    local actor={x=0,z=0,h=0,heading=0,livery='plain',company='Blue Ridge Packaging'}
    g.push('all');g.setCanvas(preview);g.origin();g.clear(0,0,0,0)
    art:draw(actor,camera,{supportHeight=function() return 0 end})
    g.pop()
    local previewData=preview:newImageData()
    local rendered=0
    for y=0,447,8 do
        for x=0,639,8 do
            local _,_,_,alpha=previewData:getPixel(x,y)
            if alpha>.5 then rendered=rendered+1 end
        end
    end
    previewData:release();preview:release();art:release()
    check('delivery_company_decal_draws_over_the_existing_64_angle_truck',rendered>100)
    StopControl.run(check,town)
    require('src.commute.tests.pickup_and_deadlock_test').run(check,town)
end

return Test
