local Bike=require('src.commute.motorcycle')
local Rider=require('src.commute.rider')
local HUD=require('src.commute.cockpit')
local Test={}
local function world(grade)
    return {supportHeight=function(_,x)return x*(grade or 0) end,
        roads={nearest=function()return 0,{width=6} end,blocked=function()return false end}}
end
local function ride(p,input,seconds,w,hz)
    hz=hz or 60;for _=1,seconds*hz do Bike.update(p,input,1/hz,w or world()) end;return p
end
function Test.run(check)
    require('src.commute.tests.riding_animation_test').run(check)
    local p=Bike.new(100,100,0);local seen={[1]=true}
    for _=1,1200 do Bike.update(p,{throttle=1},1/60,world());seen[p.gear]=true end
    check('commute_automatic_uses_all_four_gears',seen[1] and seen[2] and seen[3] and seen[4] and p.speed>11 and p.speed<=12)
    ride(p,{brake=1},5)
    check('commute_automatic_returns_to_first_when_stopped',p.speed==0 and p.gear==1)
    assert(Bike.command(p,'manual'));assert(Bike.command(p,'shiftup'))
    check('commute_manual_shifts_have_torque_pause_and_no_repeat',p.gear==2 and p.shiftTime>0 and not Bike.command(p,'shiftup'))
    ride(p,{},1);assert(Bike.command(p,'shiftup'));ride(p,{},1)
    ride(p,{throttle=1},10)
    check('commute_manual_does_not_shift_for_player',p.gear==3 and p.transmission=='manual')
    p.speed=9;check('commute_manual_rejects_overrev_downshift',not Bike.command(p,'shiftdown') and p.gear==3)
    local low,tall=Bike.new(100,100,0),Bike.new(100,100,0)
    low.transmission='manual';tall.transmission='manual';tall.gear=4
    ride(low,{throttle=1},2,world(.07));ride(tall,{throttle=1},2,world(.07))
    check('commute_low_gear_pulls_hill_better_than_tall_gear',low.speed>tall.speed+2)
    local up,flat,down=Bike.new(100,100,0),Bike.new(100,100,0),Bike.new(100,100,0)
    for _,b in ipairs({up,flat,down}) do b.gear=3;b.transmission='manual';b.speed=6 end
    ride(up,{},1,world(.07));ride(flat,{},1,world());ride(down,{},1,world(-.07))
    check('commute_gravity_affects_uphill_and_downhill_coasting',up.speed<flat.speed and flat.speed<down.speed)
    local full,partial=Bike.new(100,100,0),Bike.new(100,100,0)
    ride(full,{throttle=1},2);ride(partial,{throttle=.35},2)
    check('commute_analog_throttle_changes_acceleration',full.speed>partial.speed+1)
    local a,b=Bike.new(100,100,0),Bike.new(100,100,0)
    ride(a,{throttle=1},12,world(.04),30);ride(b,{throttle=1},12,world(.04),60)
    check('commute_shift_and_slope_physics_frame_consistent',math.abs(a.x-b.x)<.001 and a.gear==b.gear)
    local r=Rider.new(100,100,0);r.bike.transmission='manual';r.bike.gear=3
    local restored=assert(Rider.restore(Rider.snapshot(r),world(),{x=100,z=100}))
    check('commute_save_retains_manual_mode_and_gear',restored.bike.transmission=='manual' and restored.bike.gear==3 and restored.bike.speed==0)
    local legacy=Rider.snapshot(r);legacy.bike.gear=nil;legacy.bike.transmission=nil
    restored=assert(Rider.restore(legacy,world(),{x=100,z=100}))
    check('commute_legacy_bike_defaults_to_automatic_first',restored.bike.transmission=='automatic' and restored.bike.gear==1)
    legacy.bike.gear=9
    check('commute_rejects_invalid_saved_transmission',not Rider.restore(legacy,world(),{x=100,z=100}))
    check('commute_transmission_requires_started_mounted_bike',not Rider.command(r,'manual',world()))
    local telemetry=HUD.telemetry(p,true,{speed=5,grade=.06,throttle=.7,shiftTime=.1})
    check('commute_cockpit_uses_authoritative_client_telemetry',math.abs(telemetry.mph-11.18468)<.001 and telemetry.grade==6
        and telemetry.shifting and telemetry.gear==3 and telemetry.throttle==.7)
    local hit=true
    for _,size in ipairs({{960,678},{1280,880},{640,480}}) do
        local x,y,s=HUD.layout(size[1],size[2])
        hit=hit and HUD.keyAt(x+250*s,y+280*s,size[1],size[2])=='v'
            and HUD.keyAt(x+380*s,y+280*s,size[1],size[2])=='z'
            and HUD.keyAt(x+480*s,y+280*s,size[1],size[2])=='x'
            and HUD.keyAt(0,0,size[1],size[2])==nil
    end
    check('commute_cockpit_pointer_targets_scale_with_viewport',hit)
end
return Test
