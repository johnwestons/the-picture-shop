local Pose=require('src.commute.bike_action_pose')
local Bike=require('src.commute.motorcycle')
local Test={}
function Test.run(check)
    local bike=Bike.new(0,0,0);bike.grounded=true;bike.speed=8
    local function selected(values)
        local state,action=Pose.select(bike,values);return state,action
    end
    check('bike_action_pose_rest_uses_approved_upright',selected({speed=0,lean=0,ridingAction='idle'})=='upright')
    check('bike_action_pose_real_acceleration_reaches_matched_midpoint_and_full',
        selected({speed=3,throttle=1,acceleration=1.8,ridingAction='idle'})=='boostMid'
        and selected({speed=6,throttle=1,acceleration=3.4,ridingAction='idle'})=='boost')
    check('bike_action_pose_cruising_or_coasting_does_not_fake_acceleration',
        selected({speed=8,throttle=1,acceleration=0,ridingAction='idle'})=='upright'
        and selected({speed=8,throttle=0,acceleration=3.4,ridingAction='idle'})=='upright')
    check('bike_action_pose_hard_braking_uses_midpoint_then_full',
        selected({speed=8,brake=.6,ridingAction='idle'})=='brakeMid'
        and selected({speed=8,brake=1,ridingAction='idle'})=='brake')
    check('bike_action_pose_hard_braking_overrides_stale_boost_sequence',
        selected({speed=8,brake=1,ridingAction='boost',ridingActionTime=.39})=='brake')
    check('bike_action_pose_visible_smoothed_braking_keeps_midpoint_and_full_priority',
        selected({speed=8,brakingPose=.25,ridingAction='boost',ridingActionTime=.39})=='brakeMid'
        and selected({speed=8,brakingPose=.75,ridingAction='shift',ridingActionTime=.16})=='brake')
    check('bike_action_pose_stopping_and_airborne_back_input_release_bracing',
        selected({speed=0,brake=1,ridingAction='idle'})=='upright'
        and selected({speed=8,brake=1,grounded=false,ridingAction='idle'})=='upright')
    check('bike_action_pose_signed_lean_selects_independent_left_and_right_art',
        selected({lean=.225,ridingAction='idle'})=='turnLeftMid'
        and selected({lean=.3,ridingAction='idle'})=='turnLeft'
        and selected({lean=-.225,ridingAction='idle'})=='turnRightMid'
        and selected({lean=-.3,ridingAction='idle'})=='turnRight')
    check('bike_action_pose_speed_selects_new_tuck_without_direction_fallback',
        selected({speed=(Bike.TUCK_START_SPEED+Bike.BOOST_MAX_SPEED)/2,ridingAction='idle'})=='aeroMid'
        and selected({speed=Bike.BOOST_MAX_SPEED,ridingAction='idle'})=='aero')
    check('bike_action_pose_collision_precedes_braking_and_acceleration',
        selected({speed=8,impactPulse=Bike.IMPACT_DURATION/2,impactStrength=1,brake=1,
            ridingAction='boost',ridingActionTime=.39})=='impact')
    bike.reverse=true
    check('bike_action_pose_automatic_reverse_does_not_show_forward_acceleration',
        selected({speed=1,throttle=1,acceleration=4,ridingAction='idle'})=='upright')
    bike.reverse=false
    local actorState=selected({speed=8,brake=1,ridingAction='idle'})
    local remote={speed=8,brake=1,grounded=true,ridingAction='idle',ridingActionTime=0}
    check('bike_action_pose_remote_feedback_selects_same_braking_pose',selected(remote)==actorState)
    local Sequence=require('src.commute.riding_animation')
    local smoothAcceleration,smoothBraking,release=true,true,true
    local resumedShift,resumedBoost,resumedAcceleration=true,true,true
    for _,rate in ipairs({30,60,120}) do
        local actor=Bike.new(0,0,0);actor.grounded=true;actor.speed=8
        actor.throttle=1;actor.acceleration=3.4;Sequence.reset(actor)
        local mid,full=false,false
        for _=1,rate/5 do
            Sequence.update(actor,1/rate)
            local state=Pose.select(actor);mid=mid or state=='boostMid';full=full or state=='boost'
        end
        smoothAcceleration=smoothAcceleration and mid and full
        actor.brake=1;actor.throttle=0;actor.acceleration=-9;mid,full=false,false
        for _=1,rate/5 do
            Sequence.update(actor,1/rate)
            local state=Pose.select(actor);mid=mid or state=='brakeMid';full=full or state=='brake'
        end
        smoothBraking=smoothBraking and mid and full
        actor.brake=0;actor.acceleration=0
        for _=1,rate/2 do Sequence.update(actor,1/rate) end
        release=release and Pose.select(actor)=='upright'
        -- Keep the actual residual weight: resetting the sequence here would
        -- hide the bug where an invisible brake pose blocked every later event.
        Sequence.request(actor,'shift');Sequence.update(actor,Sequence.durations.shift/2)
        resumedShift=resumedShift and actor.ridingAnimation.brakingWeight>0 and Pose.select(actor)=='shift'
        Sequence.update(actor,Sequence.durations.shift)
        Sequence.request(actor,'boost');Sequence.update(actor,Sequence.durations.boost/2)
        resumedBoost=resumedBoost and actor.ridingAnimation.brakingWeight>0 and Pose.select(actor)=='boost'
        Sequence.update(actor,Sequence.durations.boost)
        actor.throttle=1;actor.acceleration=3.4
        for _=1,rate/5 do Sequence.update(actor,1/rate) end
        resumedAcceleration=resumedAcceleration and actor.ridingAnimation.brakingWeight>0 and Pose.select(actor)=='boost'
        actor.grounded=false;actor.brake=1;actor.throttle=1;actor.acceleration=4
        Sequence.update(actor,1/rate)
        release=release and actor.ridingAnimation.brakingWeight==0 and actor.ridingAnimation.accelerationWeight==0
    end
    check('bike_action_pose_digital_acceleration_visits_midpoint_before_full_at_30_60_120_fps',smoothAcceleration)
    check('bike_action_pose_digital_braking_visits_midpoint_before_full_at_30_60_120_fps',smoothBraking)
    check('bike_action_pose_feedback_settles_and_airborne_inputs_clear_ground_reactions',release)
    check('bike_action_pose_brake_release_allows_later_shift_at_30_60_120_fps',resumedShift)
    check('bike_action_pose_brake_release_allows_later_boost_at_30_60_120_fps',resumedBoost)
    check('bike_action_pose_brake_release_allows_later_acceleration_at_30_60_120_fps',resumedAcceleration)
end
return Test
