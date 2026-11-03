local Bike = require('src.commute.motorcycle')
local Obstacles = require('src.commute.obstacles')
local Test = {}
local dt = 1/120

local function world(height)
    return {
        supportHeight=function(_,x,z) return height(x,z) end,
        roads={
            nearest=function() return 0,{width=6} end,
            blocked=function() return false end
        }
    }
end

local function crest(x)
    if x<20 then return x*.25 end
    if x<26 then return 5-(x-20)*.25 end
    return 3.5
end

local function jump(airInput)
    local w = world(crest)
    local bike = Bike.new(0,0,0)
    bike.speed, bike.gear = 12, 4
    local flight = {}
    for frame=1,600 do
        Bike.update(bike, flight.launch and airInput or {throttle=1}, dt, w)
        if not bike.grounded and not flight.launch then
            flight.launch, flight.launchPitch, flight.launchVy = frame, bike.pitch, bike.vy
        end
        if flight.launch and frame==flight.launch+40 then
            flight.midPitch,flight.midVy,flight.midX,flight.midH=bike.pitch,bike.vy,bike.x,bike.h
        end
        if flight.launch and bike.grounded and not flight.land then
            flight.land, flight.landPitch = frame, bike.pitch
            flight.rearFirst = bike.rearGrounded and not bike.frontGrounded
        end
        if flight.land and bike.frontGrounded and bike.rearGrounded and not flight.both then
            flight.both=frame
        end
    end
    flight.bike=bike
    return flight
end

function Test.run(check)
    local hillside = world(function(x,z) return 2+.22*x-.18*z end)
    local grades = true
    for _,heading in ipairs({0,math.pi/2,math.pi,math.pi*1.25}) do
        local bike = Bike.new(8,5,heading)
        bike.reverse=true
        Bike.update(bike,{},0,hillside)
        local expected=.22*math.cos(heading)-.18*math.sin(heading)
        grades=grades and math.abs(bike.pitch-math.atan(expected))<1e-8
            and math.abs(bike.h-hillside:supportHeight(bike.x,bike.z))<1e-8
            and bike.frontGrounded and bike.rearGrounded
    end
    check('bike_pitch_follows_both_wheel_supports_in_facing_direction_including_reverse',grades)
    local hump = world(function(x) return math.max(0,1-4*x*x) end)
    local bike = Bike.new(0,0,0)
    Bike.resetContact(bike,hump)
    check('bike_straddles_a_narrow_bump_between_its_wheels',bike.h==0 and bike.pitch==0)

    local coast, throttle, brake = jump({}),jump({throttle=1}),jump({brake=1})
    check('bike_keeps_ramp_attitude_during_ballistic_descent',
        coast.launch and coast.launchVy>1 and coast.launchPitch>.1 and coast.midVy<0 and coast.midPitch>.06)
    check('bike_air_throttle_lifts_the_nose_and_brake_levels_it_without_changing_flight',
        throttle.midPitch>coast.midPitch+.035 and brake.midPitch<coast.midPitch-.015
        and math.abs(brake.landPitch)<coast.landPitch and math.abs(throttle.midX-brake.midX)<1e-7
        and math.abs(throttle.midH-brake.midH)<1e-7)
    check('bike_rear_wheel_lands_first_and_front_wheel_settles_without_crash',
        coast.rearFirst and coast.both>coast.land+1 and coast.bike.frontGrounded and coast.bike.rearGrounded
        and math.abs(coast.bike.pitch)<.001 and coast.bike.damage==0 and not coast.bike.crashPending)

    local flat = world(function() return 0 end)
    local undamaged = true
    for _,height in ipairs({2,25,150}) do
        bike = Bike.new(0,0,0)
        bike.h,bike.pitch,bike.grounded,bike.damage=height,.28,false,37
        local landing=false
        for _=1,1200 do
            Bike.update(bike,{},dt,flat)
            landing=landing or bike.landingPulse>0
        end
        undamaged=undamaged and landing and bike.damage==37 and not bike.crashPending
            and bike.impactPulse==0 and bike.frontGrounded and bike.rearGrounded and math.abs(bike.pitch)<.001
    end
    check('bike_hard_landings_from_any_tested_height_only_load_the_suspension',undamaged)

    local trunk = {x=2,z=0,h=0,collisionRadius=.30,collisionHeight=4}
    function flat:sweepObstacles(x,z,nx,nz,radius,bottom,top)
        local hit,cx,cz=Obstacles.sweep(x,z,nx,nz,radius,trunk,bottom,top)
        return hit,cx,cz,'tree','standing-trunk'
    end
    local airborne = Bike.new(0,0,0)
    airborne.h,airborne.pitch,airborne.speed,airborne.grounded=3,.18,18,false
    airborne.gear,airborne.upgradeLevel=4,3
    for _=1,20 do Bike.update(airborne,{},dt,flat) end
    check('bike_airborne_solid_trunk_collision_can_still_damage_and_eject',airborne.damage>0
        and airborne.crashPending and airborne.collisionKind=='tree' and not airborne.grounded)

    local Town = require('src.commute.town')
    local town = Town.world(assert(Town.generate(712345,{generatorVersion=3})))
    local function hitsTravelLimit(x,z)
        local riderBike = Bike.new(x,z,0)
        riderBike.h,riderBike.grounded,riderBike.speed=town:supportHeight(x,z)+20,false,20
        riderBike.gear,riderBike.upgradeLevel,riderBike.damage=4,3,9
        for _=1,60 do
            Bike.update(riderBike,{},dt,town)
            if riderBike.collisionKind then break end
        end
        return riderBike.collisionKind=='travelLimit' and riderBike.damage==9 and riderBike.impactPulse==0
            and not riderBike.crashPending and not town.roads:blocked(town,riderBike.x,riderBike.z)
    end
    -- This saved v3 terrain has a dry east edge and a shoreline at (164,68).
    check('bike_map_edge_and_shoreline_block_travel_without_impact_damage',
        hitsTravelLimit(town.roads.bounds.x1-1.5,66) and hitsTravelLimit(161,68))
end

return Test
