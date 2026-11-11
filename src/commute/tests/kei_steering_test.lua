local Truck=require('src.commute.delivery_truck')
local Art=require('src.commute.truck_art')
local Test={}

local road={sample=function()return 0,{width=20} end,blocked=function()return false end}
local world={roads=road,supportHeight=function()return 0,'road' end}

local function drive(model,steer,seconds,speed)
    local truck=Truck.new(256,256,0,'plain',model)
    truck.speed=speed
    for _=1,math.floor(seconds/.05+.5) do
        Truck.update(truck,{drive=-1,steer=steer},.05,world)
    end
    return truck
end

function Test.run(check)
    local camera={firstPerson=true,viewHeading=0,shoulderPerspective=true}
    for _,model in ipairs({'box','kei'}) do
        local fine=Truck.new(256,256,0,'plain',model)
        fine.speed=6
        local firstFrame=Art.frame(camera,fine.heading,model,'chase')
        Truck.update(fine,{drive=-1,steer=.2},.05,world)
        local correctedHeading=fine.heading
        check(model..'_steers_between_sprite_angles',correctedHeading>0
            and Art.frame(camera,correctedHeading,model,'chase')==firstFrame)
        for _=1,40 do Truck.update(fine,{drive=-1,steer=0},.05,world) end
        local settledHeading=fine.heading
        for _=1,20 do Truck.update(fine,{drive=-1,steer=0},.05,world) end
        check(model..'_holds_a_fine_road_heading_after_steering_centers',
            settledHeading>correctedHeading and math.abs(fine.heading-settledHeading)<.0001)
    end
    local quiet=drive('kei',.03,1,6)
    check('kei_small_steering_noise_keeps_a_straight_course',
        math.abs(quiet.heading)<1e-8 and math.abs(quiet.z-256)<1e-8)

    local kei=drive('kei',.2,.6,6)
    local box=drive('box',.2,.6,6)
    check('kei_small_corrections_turn_at_a_box_truck_like_rate',
        kei.heading>box.heading*.6 and kei.heading<box.heading*1.2,
        ('kei=%.3f box=%.3f'):format(kei.heading,box.heading))

    local keiTurn=drive('kei',1,1,2)
    local boxTurn=drive('box',1,1,2)
    check('kei_can_still_turn_tighter_than_the_box_truck',
        keiTurn.heading>boxTurn.heading*1.1 and keiTurn.heading<boxTurn.heading*1.6,
        ('kei=%.3f box=%.3f'):format(keiTurn.heading,boxTurn.heading))

    local keiRelease=Truck.new(256,256,0,'plain','kei')
    local boxRelease=Truck.new(256,256,0,'plain','box')
    keiRelease.speed,boxRelease.speed=6,6
    keiRelease.steering,boxRelease.steering=.4,.4
    for _=1,8 do
        Truck.update(keiRelease,{drive=-1,steer=0},.05,world)
        Truck.update(boxRelease,{drive=-1,steer=0},.05,world)
    end
    check('kei_steering_recenters_after_releasing_the_controls',
        keiRelease.steering<boxRelease.steering*.5
            and keiRelease.heading<boxRelease.heading*1.1)
    check('box_truck_keeps_its_existing_steering_response',
        math.abs(box.steering-.2*(1-math.exp(-4.5*.6)))<1e-6)
end

return Test
