local Network=require('src.commute.delivery_traffic')
local Town=require('src.commute.town')
local TruckArt=require('src.commute.truck_art')
local Test={}

local function byCompany(actors)
    local result={}
    for _,entry in ipairs(actors) do
        if entry.actor and entry.actor.company then result[entry.actor.company]=entry end
    end
    return result
end

function Test.run(check)
    local town=assert(Town.generate(712345))
    local state={calendar={secondsPerDay=300},inventory={stock={}},procurement={
        orders={{id='PO-TRAFFIC-1',shipmentId='SHIP-TRAFFIC-1',category='paper',
            company='CritterNet Paper Depot',pallets={{id='PO-TRAFFIC-1-PALLET',location='awaiting_delivery'}}}},
        shipments={{id='SHIP-TRAFFIC-1',status='awaiting_delivery',orderIds={'PO-TRAFFIC-1'},delivery={
            status='awaiting_schedule',expectedAtHours=100}}},
    },jobs={active={{id='JOB-TRAFFIC-1',company='Blue Ridge Packaging',delivery={
        status='pending_arrival',readyAtHours=100},pallets={{id='JOB-TRAFFIC-1-P1',location='awaiting_delivery'}}}},completed={}}}
    local epoch=1700000000
    local routesChanged=Network.update(state,town,100,epoch)
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
    local midway=byCompany(Network.actors(state,town,100,midEpoch))
    check('delivery_traffic_merges_manifests_into_one_shared_freight_truck',
        midway['Millhaven Freight'] and #Network.actors(state,town,100,midEpoch)==1
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
    job.delivery.receivedAtHours=100.5
    shipment.delivery.status='received'
    shipment.delivery.receivedAtHours=100.5
    local returnEpoch=job.delivery.route.arrivedAtEpoch+1
    local returnChanged=Network.update(state,town,101,returnEpoch)
    local returning=byCompany(Network.actors(state,town,101,returnEpoch+1))
    check('delivery_traffic_preserves_client_brand_on_return_route',
        returnChanged
        and job.delivery.returnRoute.originCompany=='Blue Ridge Packaging'
        and returning['Blue Ridge Packaging']~=nil,
        string.format("changed=%s returnCompany=%s actorCount=%d shipmentStatus=%s jobStatus=%s",
            tostring(returnChanged),tostring(job.delivery.returnRoute and job.delivery.returnRoute.originCompany),
            #Network.actors(state,town,101,returnEpoch+1),tostring(shipment.delivery.status),tostring(job.delivery.status)))

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

    local preview=g.newCanvas(640,448,{format='rgba8'})
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
end

return Test
