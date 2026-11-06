local Test={}
function Test.run(check)
    local touch=require('src.commute.touch_controls')
    local profile=require('src.commute.bindings').defaults()
    profile.layout.touch3={x=.84,y=.72} -- Prior phone layout, retained across upgrades.
    local context={mounted=true}
    for _,size in ipairs({{640,480},{960,678},{1280,880}}) do
        local w,h=unpack(size)
        local controls={}
        for _,b in ipairs(touch.actionButtons(w,h,profile,context,{mobile=true})) do controls[b.action]=b end
        local gas,boost=controls.accelerate,controls.boost
        check('mobile_boost_clear_of_gas_'..w,(gas.x-boost.x)^2+(gas.y-boost.y)^2>(gas.hitRadius+boost.hitRadius)^2
            and touch.actionAt(gas.x,gas.y,w,h,profile,context,{mobile=true}).action=='accelerate'
            and touch.actionAt(boost.x,boost.y,w,h,profile,context,{mobile=true}).action=='boost')
    end
    local truck=require('src.commute.delivery_truck').new(100,100,0)
    local Truck=require('src.commute.delivery_truck')
    local shape=require('src.commute.truck_footprint')
    check('truck_collides_at_bumper_tail_and_box_sides',
        shape.overlaps(0,0,1,0,2.72,1,2.72,1,.04) and shape.overlaps(0,0,1,0,-2.7,-1,-2.7,-1,.04)
        and shape.overlaps(0,0,0,1,1,2.7,1,2.7,.04) and not shape.overlaps(0,0,0,1,1.4,2,1.4,2,.04))
    local barrier={supportHeight=function()return 0,'road' end,roads={blocked=function(_,_,x,z)return x>102.80 or x<97.20 end}}
    for _,reverse in ipairs({false,true}) do
        local driver=Truck.new(100,100,0)
        driver.speed,driver.reverse=4,reverse
        Truck.update(driver,{drive=reverse and 1 or -1,steer=1},.1,barrier)
        check('truck_stops_before_crossing_wall_'..tostring(reverse),driver.speed==0 and math.abs(driver.x-100)<.1)
    end
    local part={slot=1,rider={vehicle='truck',truck=truck,bike={},gear={engine=false}}}
    local trip={token=1,truck=truck,participants={owner=part}}
    local state={screen='world',home={commute=trip,revision=0}}
    truck.driver='owner'
    local world={roads={blocked=function() return false end},supportHeight=function() return 2 end}
    local command=require('src.commute.trip').command
    local ok=command(state,{id=1},1,'rescue',world)
    local x,z=truck.x,truck.z
    check('mobile_truck_rescue_moves_driver',ok and (x-100)^2+(z-100)^2>25 and truck.h==2 and truck.driver=='owner')
    ok=command(state,{id=1},1,'rescue',world)
    check('mobile_truck_repeated_rescue_finds_new_ground',ok and (truck.x-x)^2+(truck.z-z)^2>25
        and (truck.x-100)^2+(truck.z-100)^2>=16)
    local sound=require('src.sound').new({state=state,world={player={id=1}}})
    sound:syncCommuteAudio(.1)
    local audio=sound.commuteAudio
    local source=audio.sources['engine-1400']
    check('mobile_truck_idle_loop_started',audio.engine and source and source:isPlaying() and source:getVolume()>0)
    truck.throttle,truck.speed=1,5
    sound:syncCommuteAudio(.1)
    check('mobile_truck_engine_revs',audio.rpm>1400 and audio.load>0)
    truck.engine=false
    for _=1,25 do sound:syncCommuteAudio(.1) end
    check('mobile_truck_ignition_off_fades_motor',not audio.engine and not source:isPlaying())
    audio:release()
    local cab=require('src.commute.truck_cockpit').new()
    local camera={firstPerson=true,viewHeading=0,bikeHeading=0,focal=640/math.tan(math.rad(41))}
    local g=love.graphics
    local canvas=g.newCanvas(1280,880)
    local function sample(yaw)
        camera.viewHeading=yaw
        g.push('all');g.setCanvas(canvas);g.origin();g.clear(0,0,0,0);cab:draw(truck,1280,880,camera);g.pop()
        local data=canvas:newImageData()
        local w,h=data:getDimensions()
        local _,_,_,a=data:getPixel(math.floor(w*620/1280),math.floor(h*680/880))
        data:release()
        return a,#cab.controls(1280,880,camera,truck)
    end
    local front,frontSwitches=sample(0)
    local back,backSwitches=sample(math.pi)
    check('mobile_cab_interior_stays_on_truck_without_rear_switches',
        front>.5 and frontSwitches==9 and back>.5 and backSwitches==0,
        ('frontAlpha=%.3f frontSwitches=%d backAlpha=%.3f backSwitches=%d')
            :format(front,frontSwitches,back,backSwitches))
    canvas:release();cab:release()
end
return Test
