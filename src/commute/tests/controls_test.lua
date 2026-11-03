local Bike=require('src.commute.motorcycle')
local Rider=require('src.commute.rider')
local Bindings=require('src.commute.bindings')
local Touch=require('src.commute.touch_controls')
local Test={}
function Test.run(check)
    local world={supportHeight=function()return 0 end,roads={nearest=function()return 0,{width=8} end,blocked=function()return false end}}
    local function new() return Rider.new(100,100,0,{version=1,outfit='geared',mounted=true,engine=true,revision=0}) end
    local function step(r,input,seconds,hz)
        hz=hz or 60;for _=1,math.floor(seconds*hz) do Rider.update(r,input,1/hz,world) end
    end
    local r=new();assert(Rider.command(r,'reverse',world));step(r,{throttle=1,boost=true},5)
    check('reverse_moves_back_at_walking_speed_without_boost',r.bike.x<99 and r.bike.speed<=Bike.REVERSE_MAX_SPEED and not r.bike.boosting and r.bike.distance>0)
    check('moving_cannot_change_direction',not Rider.command(r,'reverse',world) and r.bike.reverse)
    check('moving_cannot_turn_off_or_dismount',not Rider.command(r,'ignition',world) and not Rider.command(r,'dismount',world))
    check('headlight_keyboard_works_while_riding',Rider.command(r,'headlight',world) and r.bike.headlight)
    step(r,{brake=1},1);check('reverse_brake_stops_completely',r.bike.speed==0)
    assert(Rider.command(r,'ignition',world));local x=r.bike.x;step(r,{throttle=1},1)
    check('engine_off_stays_parked',not r.gear.engine and r.bike.x==x)
    local saved=Rider.snapshot(r);local copy=assert(Rider.restore(saved,world,{x=100,z=100}))
    check('save_preserves_parked_ignition_direction_and_light',copy.gear.mounted and not copy.gear.engine and copy.bike.reverse and copy.bike.headlight)
    saved.bike.headlight='yes';check('invalid_headlight_rejected',not Rider.restore(saved,world,{}))
    saved.bike.headlight=true;saved.bike.reverse=1;check('invalid_reverse_rejected',not Rider.restore(saved,world,{}))
    assert(Rider.command(r,'dismount',world));step(r,{},1.2)
    check('dismount_leaves_parked_bike',not r.gear.mounted and not r.gear.engine and r.bike.x==x)
    local px,pz=r.ped.x,r.ped.z
    step(r,{walkX=1},3);step(r,{},.5)
    check('walking_away_leaves_vehicle_in_place',r.ped.x>px+2 and r.bike.x==x)
    check('remote_remount_is_rejected',not Rider.command(r,'mount',world))
    check('on_foot_cannot_operate_ignition',not Rider.command(r,'ignition',world))
    r.ped.x,r.ped.z,r.ped.speed=px,pz,0
    assert(Rider.command(r,'mount',world));step(r,{},2)
    check('nearby_remount_starts_engine_after_animation',r.gear.mounted and r.gear.engine)
    assert(Rider.command(r,'reverse',world));step(r,{throttle=1},2)
    check('forward_selection_drives_forward_again',r.bike.x>x and not r.bike.reverse)
    local a,b=new(),new();assert(Rider.command(a,'reverse',world));assert(Rider.command(b,'reverse',world))
    step(a,{throttle=1,steer=.5},3,30);step(b,{throttle=1,steer=.5},3,60)
    check('reverse_steering_is_reversed_and_frame_consistent',a.bike.heading>math.pi and math.abs(a.bike.x-b.bike.x)<.001)
    local barrier=new();assert(Rider.command(barrier,'reverse',world))
    local old=world.roads.blocked;world.roads.blocked=function(_,_,bx)return bx<99 end
    step(barrier,{throttle=1},4)
    check('reverse_respects_collision_radius',barrier.bike.x>=99+Bike.RADIUS-.02)
    world.roads.blocked=old
    for _,size in ipairs({{1280,880},{960,678},{640,480}}) do
        local profile=Bindings.defaults();local context={mounted=true,transmission='manual'};local working=true
        for _,action in ipairs({'ignition','reverse','headlight','interact','shiftDown','shiftUp'}) do
            local target
            for _,button in ipairs(Touch.actionButtons(size[1],size[2],profile,context,{mobile=true})) do
                if button.action==action then target=button end
            end
            local pressed=target and Touch.actionAt(target.x,target.y,size[1],size[2],profile,context,{mobile=true})
            working=working and pressed~=nil and pressed.action==action
        end
        check('motorcycle_action_targets_scale_to_viewport_'..size[1],working)
    end
    local runtime=require('src.commute.runtime')
    for _,action in ipairs({'ignition','headlight','reverse','rescue'}) do
        local name,token=runtime.decode(action..':123')
        check('network_command_'..action,name==action and token==123)
    end
    require('src.commute.tests.touch_journey_test').run(check)
end
return Test
