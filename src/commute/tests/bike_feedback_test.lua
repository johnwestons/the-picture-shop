local Bike=require('src.commute.motorcycle')
local Audio=require('src.commute.audio')
local HUD=require('src.commute.cockpit')
local Test={}
function Test.run(check)
    local bike=Bike.new(100,100,0);bike.upgradeLevel=3;bike.gear=4;bike.speed=20
    local part={rider={bike=bike,gear={mounted=true}},presentation={speed=20,grounded=false,throttle=1}}
    local audible=Audio.partBike(part);local instruments=HUD.telemetry(bike,true,part.presentation)
    local expected=Bike.REDLINE*20/(Bike.GEARS[4].speed*22.35/Bike.MAX_SPEED)
    check('commute_upgraded_guest_rpm_matches_authoritative_gear_ratio',math.abs(audible.rpm-expected)<1e-8
        and math.abs(instruments.rpm-expected)<1e-8 and audible.rpm<Bike.REDLINE
        and audible.rpm==Bike.rpmForSpeed(bike))
    check('commute_speedometer_covers_top_upgrade_speed',HUD.MAX_MPH>=26.8*2.236936)
    local audio=Audio.new();local volumes={}
    function audio:loadSources()end
    function audio:loop(name,volume)volumes[name]=volume end
    audio:update(.1,audible,true,{brake=1})
    check('commute_airborne_tires_and_brakes_silent_but_wind_remains',volumes.tires==0 and volumes.brake==0
        and volumes.wind>0 and volumes['engine-5000']>0)
    part.presentation.grounded=true;audio:update(.1,Audio.partBike(part),true,{brake=1})
    check('commute_ground_contact_resumes_rolling_and_brake_audio',volumes.tires>0 and volumes.brake>0)
    bike.reverse=true;part.presentation.speed=1
    check('commute_reverse_and_engine_off_instruments_remain_consistent',Audio.partBike(part).rpm==Bike.IDLE_RPM+500
        and HUD.telemetry(bike,true,part.presentation).rpm==Bike.IDLE_RPM+500
        and HUD.telemetry(bike,false,part.presentation).rpm==0)
    part.presentation.speed=10;part.presentation.brake=0;part.presentation.slip=0;part.presentation.tireSlip=0
    audio:update(.1,Audio.partBike(part),true,{brake=1})
    check('commute_remote_brakes_use_authoritative_input',volumes.brake==0)
    part.presentation.slip=.8
    audio:update(.1,Audio.partBike(part),true,{brake=0})
    check('commute_sliding_tires_are_audible_without_brake_input',volumes.brake>0 and volumes.tires>0)
    part.presentation.grounded=false
    audio:update(.1,Audio.partBike(part),true,{brake=1})
    check('commute_airborne_slip_never_plays_tire_audio',volumes.brake==0 and volumes.tires==0)
end
return Test
