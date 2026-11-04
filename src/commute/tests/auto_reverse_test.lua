local Bike=require('src.commute.motorcycle')
local Rider=require('src.commute.rider')
local Bindings=require('src.commute.bindings')
local Camera=require('src.commute.camera')
local Test={}
local world={height=function()return 0 end,supportHeight=function()return 0 end,
    roads={nearest=function()return 0,{width=8}end,blocked=function()return false end}}
local function new()
    return Rider.new(100,100,0,{version=1,outfit='geared',mounted=true,engine=true,revision=0})
end
local function run(r,axis,seconds,hz)
    hz=hz or 60
    for _=1,math.floor(seconds*hz+.5) do Rider.update(r,{drive=axis,boost=true},1/hz,world) end
end
function Test.run(check)
    local r=new();run(r,1,1)
    check('auto_reverse_back_input_starts_reverse_without_toggle',r.bike.reverse and r.bike.x<99.7
        and r.bike.speed<=Bike.REVERSE_MAX_SPEED and not r.bike.boosting)
    local command=Bike.command;local switches=0;local safe=true
    Bike.command=function(bike,action)
        if action=='reverse' then
            switches=switches+1
            safe=safe and bike.speed==0 and bike.vx==0 and bike.vz==0 and bike.grounded
        end
        return command(bike,action)
    end
    local okay,reason=xpcall(function()
        local before=r.bike.speed
        Rider.update(r,{drive=-1},1/120,world)
        check('auto_reverse_forward_input_brakes_backward_motion_before_changing_direction',r.bike.reverse and r.bike.speed<before)
        run(r,-1,2);local ahead=r.bike.x
        check('auto_reverse_forward_input_returns_to_forward_without_toggle',not r.bike.reverse and r.bike.vx>0)
        run(r,1,3)
        check('auto_reverse_held_brake_stops_then_backs_up',r.bike.reverse and r.bike.x<ahead+3
            and r.bike.vx<0 and switches==2 and safe)
    end,debug.traceback)
    Bike.command=command;assert(okay,reason)
    local reverse=r.bike.reverse;run(r,0,2)
    check('auto_reverse_releasing_input_stops_without_flipping_direction',r.bike.speed==0 and r.bike.reverse==reverse)
    r=new();r.gear.engine=false;run(r,1,1)
    check('auto_reverse_engine_off_stays_parked',r.bike.x==100 and not r.bike.reverse)
    r=new();Bike.resetContact(r.bike,world)
    r.bike.h,r.bike.grounded,r.bike.pitch=20,false,.4
    run(r,1,.1)
    check('auto_reverse_back_in_air_still_brakes_and_levels_without_gear_change',not r.bike.reverse
        and r.bike.brake==1 and r.bike.throttle==0 and r.bike.pitch<.4)
    r=new();run(r,.4,.25)
    check('auto_reverse_preserves_analog_backing_strength',r.bike.reverse and r.bike.throttle==.4)
    local results={}
    for _,hz in ipairs({30,60,120}) do
        local rider=new();run(rider,-1,1,hz);run(rider,1,2,hz);run(rider,-1,1,hz)
        results[#results+1]=rider.bike
    end
    check('auto_reverse_stop_and_direction_changes_match_30_60_120hz',math.abs(results[1].x-results[2].x)<.001
        and math.abs(results[1].x-results[3].x)<.001 and results[1].reverse==results[3].reverse)
    for _,mode in ipairs({'fixed','follow','firstPerson'}) do
        r=new();r.bike.heading=-math.pi/2
        local camera=Camera.new(r.bike,world)
        if mode=='firstPerson' then camera:setFirstPerson(true,r.bike) else camera:setOutsideMode(mode,r.bike) end
        local profile=Bindings.defaults();local touch={x=0,y=1}
        for _=1,60 do
            local steer,drive=Bindings.drive(profile,touch,camera,r.bike)
            Rider.update(r,{steer=steer,drive=drive},1/60,world)
        end
        check('auto_reverse_android_stick_backs_up_stably_in_'..mode,r.bike.reverse and r.bike.z>100.3
            and math.abs(r.bike.heading+math.pi/2)%(math.pi*2)<.001)
    end
end
return Test
