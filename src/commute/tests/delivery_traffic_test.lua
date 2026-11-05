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
    local state={calendar={secondsPerDay=300},procurement={
        orders={{id='PO-TRAFFIC-1',category='paper',company='CritterNet Paper Depot'}},
        shipments={{id='SHIP-TRAFFIC-1',orderIds={'PO-TRAFFIC-1'},delivery={
            status='awaiting_schedule',expectedAtHours=100}}},
    },jobs={active={{id='JOB-TRAFFIC-1',company='Blue Ridge Packaging',delivery={
        status='pending_arrival',readyAtHours=100}}},completed={}}}
    local epoch=1700000000
    check('delivery_traffic_routes_supplier_and_client_shipments',
        Network.update(state,town,100,epoch)
        and state.procurement.shipments[1].delivery.route.originCompany=='CritterNet Paper Depot'
        and state.jobs.active[1].delivery.route.originCompany=='Blue Ridge Packaging')

    local shipment=state.procurement.shipments[1]
    local job=state.jobs.active[1]
    local duration=shipment.delivery.route.arrivedAtEpoch-epoch
    local midEpoch=epoch+duration*.5
    local midway=byCompany(Network.actors(state,town,100,midEpoch))
    check('delivery_traffic_renders_named_suppliers_on_the_shared_truck',
        midway['CritterNet Paper Depot'] and midway['Blue Ridge Packaging']
        and midway['CritterNet Paper Depot'].phase=='approaching'
        and midway['Blue Ridge Packaging'].phase=='approaching'
        and midway['Blue Ridge Packaging'].actor.livery=='plain')
    check('delivery_traffic_gates_warehouse_dropoff_until_arrival',
        not Network.arrived(job,midEpoch) and Network.arrived(job,job.delivery.route.arrivedAtEpoch))

    job.delivery.status='received'
    job.delivery.receivedAtHours=100.5
    local returnEpoch=job.delivery.route.arrivedAtEpoch+1
    check('delivery_traffic_preserves_client_brand_on_return_route',
        Network.update(state,town,101,returnEpoch)
        and job.delivery.returnRoute.originCompany=='Blue Ridge Packaging'
        and byCompany(Network.actors(state,town,101,returnEpoch+1))['Blue Ridge Packaging']~=nil)

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
