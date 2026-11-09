local Truck=require('src.commute.delivery_truck')
local Service=require('src.commute.truck_service')
local Test={}
function Test.world(surface)
    return {roads={sample=function()return 0,{width=40} end,blocked=function()return false end},
        supportHeight=function()return 0,surface or 'road' end}
end

function Test.stop(model,options,controller)
    options=options or {};controller=controller or Truck
    local truck=controller.new(256,256,0,'plain',model)
    truck.speed=options.speed or 40/3.6
    truck.reverse=options.reverse==true
    truck.slipAngle=options.slip or 0
    truck.service=options.service
    truck.engine=options.engine~=false
    local world=Test.world(options.surface)
    local input=options.input or {brake=1}
    local dt=options.dt or 1/120
    local distance,elapsed=0,0
    for _=1,math.ceil(20/dt) do
        distance=distance+controller.update(truck,input,dt,world)
        elapsed=elapsed+dt
        if truck.speed==0 then break end
    end
    return {distance=distance,time=elapsed,drift=math.abs(truck.z-256),truck=truck}
end

function Test.run(check)
    local stops={}
    for _,model in ipairs({'box','kei'}) do
        local full=Test.stop(model);stops[model]=full
        check(model..'_firm_road_stop_from_40_kmh',full.truck.speed==0
            and full.distance<(model=='kei' and 7.5 or 10),
            ('distance=%.2fm time=%.2fs'):format(full.distance,full.time))
        local partial=Test.stop(model,{input={brake=.5}})
        check(model..'_brake_pedal_remains_progressive',partial.distance>full.distance*1.85
            and partial.distance<full.distance*2.15)
        local dirt=Test.stop(model,{surface='trail'})
        check(model..'_loose_surface_still_needs_more_stopping_room',dirt.distance>full.distance*1.35)
        local engineOff=Test.stop(model,{engine=false})
        check(model..'_brakes_work_without_engine',math.abs(engineOff.distance-full.distance)<.001)
        local reverse=Test.stop(model,{speed=3.2,reverse=true})
        check(model..'_brakes_stop_reverse_without_changing_gear',reverse.truck.speed==0
            and reverse.truck.reverse and reverse.truck.x<256 and reverse.distance<1)
        local opposite=Test.stop(model,{input={drive=1}})
        check(model..'_opposite_direction_input_uses_firmer_brakes',
            math.abs(opposite.distance-full.distance)<.001 and opposite.truck.reverse)
        local slipping=Test.stop(model,{slip=.2})
        check(model..'_road_brakes_settle_sideways_slip',slipping.drift<(model=='kei' and .13 or .17)
            and slipping.truck.slipAngle==0,('lateral drift=%.3fm'):format(slipping.drift))
        local tired=Service.new()
        tired.brakeMiles=Service.maintenance('brakes').interval
        tired.tireMiles=Service.maintenance('tires').interval
        local worn=Test.stop(model,{service=tired})
        check(model..'_brake_wear_still_matters',worn.distance>full.distance*1.4)
        local slowFrames=Test.stop(model,{dt=1/30})
        check(model..'_stopping_distance_consistent_at_30_and_120_fps',
            math.abs(slowFrames.distance-full.distance)/full.distance<.04)
        local turning=Truck.new(256,256,0,'plain',model)
        turning.speed=10;turning.steering=.6;turning.slipAngle=.15
        for _=1,60 do Truck.update(turning,{brake=1,steer=.6},1/120,Test.world()) end
        check(model..'_braking_keeps_steering_and_road_traction',turning.heading>0
            and math.abs(turning.speed*math.sin(turning.slipAngle))<.2,
            ('sideways speed=%.3fm/s'):format(math.abs(turning.speed*math.sin(turning.slipAngle))))
        local grounded=Truck.new(256,256,0,'plain',model)
        local airborne=Truck.new(256,256,0,'plain',model)
        grounded.speed,airborne.speed=10,10
        grounded.slipAngle,airborne.slipAngle=.2,.2;airborne.grounded=false
        for _=1,24 do
            Truck.update(grounded,{brake=1},1/120,Test.world())
            Truck.update(airborne,{brake=1},1/120,Test.world())
        end
        check(model..'_brake_traction_requires_ground_contact',
            math.abs(grounded.slipAngle)<math.abs(airborne.slipAngle)*.5)
    end
    check('kei_stops_more_aggressively_than_box',stops.kei.distance<stops.box.distance*.8)
end
return Test
