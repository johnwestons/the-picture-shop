local Bike=require('src.commute.motorcycle')
local Upgrades=require('src.commute.bike_upgrades')
local Audio=require('src.commute.audio')
local HUD=require('src.commute.cockpit')
local Art=require('src.commute.bike_art')
local Test={}
function Test.run(check)
    check('commute_condition_icon_uses_east_facing_parked_bike',
        Art.directions[HUD.CONDITION_BIKE_FRAME]=='east')
    local iconState,iconFrame
    local iconImage=love.graphics.newCanvas(320,320)
    local iconQuad=love.graphics.newQuad(0,0,320,320,320,320)
    HUD.drawCondition({damage=20},0,0,{resolve=function(_,state,frame)
        iconState,iconFrame=state,frame
        return iconImage,iconQuad
    end})
    check('commute_condition_panel_draws_parked_east_sprite',
        iconState=='parked' and iconFrame==HUD.CONDITION_BIKE_FRAME)
    iconImage:release();iconQuad:release()
    local bike=Bike.new(100,100,0);bike.upgradeLevel=3;bike.gear=4;bike.speed=20
    bike.service.fuel=.51
    local normal=HUD.telemetry(bike,true)
    check('bike_dashboard_uses_current_litres_and_tank_fraction',
        normal.fuel==.51 and normal.fuelFraction==.51/4 and not normal.lowFuel and normal.beam=='off')
    bike.service.fuel=.5;Bike.command(bike,'headlight')
    local reserve=HUD.telemetry(bike,true)
    check('bike_dashboard_reserve_and_low_beam_light_at_threshold',reserve.lowFuel and reserve.beam=='low')
    bike.service.fuel=0;Bike.command(bike,'beam')
    local empty=HUD.telemetry(bike,true)
    check('bike_dashboard_empty_tank_and_high_beam',empty.fuelFraction==0 and empty.lowFuel and empty.beam=='high')
    bike.service.fuel=4;Bike.command(bike,'headlight')
    local filled=HUD.telemetry(bike,true)
    check('bike_dashboard_refill_clears_warning_and_lamp_off_wins_over_beam_setting',
        filled.fuelFraction==1 and not filled.lowFuel and filled.beam=='off')
    local part={rider={bike=bike,gear={mounted=true}},presentation={speed=20,grounded=false,throttle=1}}
    local audible=Audio.partBike(part);local instruments=HUD.telemetry(bike,true,part.presentation)
    local expected=Bike.REDLINE*20/(Bike.GEARS[4].speed*Upgrades.profile(3).maxSpeed/Bike.MAX_SPEED)
    check('commute_upgraded_guest_rpm_matches_authoritative_gear_ratio',math.abs(audible.rpm-expected)<1e-8
        and math.abs(instruments.rpm-expected)<1e-8 and audible.rpm<Bike.REDLINE
        and audible.rpm==Bike.rpmForSpeed(bike))
    check('commute_speedometer_covers_top_upgrade_speed',HUD.MAX_MPH>=75)
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
