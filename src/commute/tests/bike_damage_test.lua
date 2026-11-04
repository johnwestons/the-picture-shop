local Bike = require('src.commute.motorcycle')
local Damage = require('src.commute.bike_damage')
local Test = {}

local function levelWorld(dirt, grade)
    return {
        supportHeight=function(_,x) return x * (grade or 0) end,
        roads={
            nearest=function() return dirt and 20 or 0, {width=6} end,
            blocked=function() return false end
        }
    }
end

local function approach(speed, heading, barrier, hz, wallAngle)
    local world = levelWorld()
    local axisX, axisZ = math.cos(wallAngle or 0), math.sin(wallAngle or 0)
    if barrier then
        world.roads.blocked = function(_,_,x,z) return x*axisX + z*axisZ >= 0 end
    else
        world.sweepObstacles = function(_,x,z,nx,nz,radius)
            if x <= -radius and nx >= -radius and nx > x then
                return (-radius-x)/(nx-x), -1, 0, 'tree', 'trunk'
            end
        end
    end
    local distance = Bike.RADIUS+.10
    local bike = Bike.new(-axisX*distance, -axisZ*distance, (heading or 0)+(wallAngle or 0))
    bike.speed, bike.gear, bike.upgradeLevel = speed, 4, 3
    for _=1,hz do
        Bike.update(bike, {}, 1/hz, world)
        if bike.collisionKind then return bike, world end
    end
    error('Test motorcycle did not reach the obstacle')
end

local function drive(damage, dirt, grade, level, boost)
    local world = levelWorld(dirt, grade)
    local bike = Bike.new(0, 0, 0)
    bike.damage, bike.upgradeLevel = damage, level
    for _=1,1200 do Bike.update(bike, {throttle=1, boost=boost}, 1/60, world) end
    return bike
end

function Test.run(check)
    local bump = approach(2.5, 0, false, 60)
    local medium, wall = approach(8, 0, false, 60)
    local hard = approach(13, 0, false, 60)
    local maximum = approach(26.8, 0, false, 60)
    check('bike_low_speed_bump_stops_and_braces_without_damage',
        bump.speed==0 and bump.impactPulse>0 and bump.impactStrength>0 and bump.damage==0 and not bump.crashPending)
    check('bike_collision_wear_is_small_for_bumps_and_capped_per_crash',
        medium.damage==2 and not medium.crashPending and hard.damage>medium.damage*2 and maximum.damage==24
        and medium.impactStrength>bump.impactStrength)
    local parked=Bike.new(0,0,0)
    Damage.impact(parked,5,-1,0,5,0,'tree')
    check('bike_parking_speed_contacts_cost_no_condition',parked.damage==0)
    parked.damage=92;Damage.impact(parked,27,-1,0,27,0,'tree')
    check('bike_accumulated_wear_still_caps_at_100',parked.damage==100)
    check('bike_hard_hit_stops_bike_and_reports_safe_ejection_direction', hard.speed==0
        and hard.crashPending and hard.crashPending.dx>.99 and hard.crashPending.nx<-.99 and hard.crashPending.kind=='tree')

    local points = medium.damage
    for _=1,120 do Bike.update(medium, {throttle=1}, 1/60, wall) end
    check('bike_holding_throttle_against_obstacle_does_not_repeat_damage_or_brace',
        medium.damage==points and medium.impactPulse==0)

    local glance = approach(20, math.rad(82), false, 60)
    local buildingGlances = true
    for angle=0,45,5 do
        local building = approach(20, math.rad(82), true, 60, math.rad(angle))
        buildingGlances = buildingGlances and building.damage==0 and not building.crashPending and building.speed>18
    end
    check('bike_fast_glancing_tree_and_wall_contacts_preserve_slide_without_ejecting',
        glance.damage==0 and not glance.crashPending and glance.speed>18 and buildingGlances)
    local at30 = approach(8, 0, false, 30)
    local at120 = approach(8, 0, false, 120)
    check('bike_damage_is_stable_across_frame_rates', at30.damage==points and at120.damage==points)

    local fullyDamaged = drive(100,false,0,0,false)
    local boostedDownhill = drive(100,true,-.16,3,true)
    local uphill = drive(100,true,.18,0,false)
    check('bike_total_damage_can_launch_and_limp_at_five_mph_on_road_and_trail',
        fullyDamaged.x>35 and uphill.x>35 and math.abs(fullyDamaged.speed-Damage.LIMP_SPEED)<.01
        and math.abs(uphill.speed-Damage.LIMP_SPEED)<.01 and math.abs(boostedDownhill.speed-Damage.LIMP_SPEED)<.01)
    local partial = drive(50,false,0,0,false)
    local healthy = drive(0,false,0,0,false)
    check('bike_partial_damage_reduces_top_speed_and_repair_restores_it',
        partial.speed>fullyDamaged.speed and healthy.speed>partial.speed+3 and healthy.speed>11.5)
    check('bike_save_damage_accepts_legacy_values_and_rejects_invalid_wear',
        Bike.valid({}) and Bike.valid({damage=100}) and not Bike.valid({damage=101})
        and not Bike.valid({damage=-1}) and not Bike.valid({damage=.5}) and not Bike.valid({damage='0'}))
end

return Test
