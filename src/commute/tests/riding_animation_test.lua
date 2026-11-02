local A=require('src.commute.riding_animation')
local Bike=require('src.commute.motorcycle')
local Art=require('src.commute.bike_art')
local Rider=require('src.commute.rider')
local Test={}
local world={supportHeight=function() return 0 end,
    roads={nearest=function() return 0,{width=6} end,blocked=function() return false end}}
function Test.run(check)
    local bike=Bike.new(100,100,0);bike.transmission='manual'
    Bike.update(bike,{throttle=1,boost=true},.1,world)
    local before=bike.ridingAnimation.remaining
    assert(Bike.shift(bike,1))
    local action,weight=Art.action(bike)
    check('riding_shift_physics_does_not_override_active_boost_pose',bike.gear==2
        and bike.shiftTime==Bike.SHIFT_TIME and action=='boost' and weight>0
        and bike.ridingAnimation.remaining==before and bike.ridingAnimation.queue[1]=='shift')
    A.request(bike,'shift');A.request(bike,'boost')
    check('riding_repeated_requests_do_not_restart_or_build_backlog',#bike.ridingAnimation.queue==1
        and bike.ridingAnimation.remaining==before)
    A.update(bike,before)
    local kind,left=A.sample(bike);action,weight=Art.action(bike)
    check('riding_boost_finishes_at_neutral_before_queued_shift',kind=='shift'
        and math.abs(left-.32)<1e-8 and weight<1e-8 and action=='shift')
    A.update(bike,.16)
    check('riding_shift_visual_has_separate_slower_duration',select(2,Art.action(bike))>.99)
    A.request(bike,'boost');A.update(bike,.16)
    action,weight=Art.action(bike)
    check('riding_boost_waits_for_shift_to_return_to_neutral',action=='boost' and weight<1e-8)
    A.update(bike,.78)
    check('riding_sequence_returns_to_idle_without_replaying_events',A.sample(bike)=='idle'
        and #bike.ridingAnimation.queue==0)
    bike.lean=.25;A.request(bike,'shift');A.update(bike,.1)
    check('riding_shift_gesture_waits_for_hard_turn',A.sample(bike)=='idle' and #bike.ridingAnimation.queue==1)
    bike.lean=0;A.update(bike,0);A.update(bike,.16)
    check('riding_new_hard_turn_smoothly_suppresses_shift_overlay',select(2,Art.action(bike,nil,1))==0
        and select(2,Art.action(bike,nil,.5))>.49)
    bike.impactPulse=.4;A.request(bike,'boost');A.update(bike,.01)
    check('riding_collision_discards_boost_but_defers_one_shift',A.sample(bike)=='idle'
        and #bike.ridingAnimation.queue==1 and bike.ridingAnimation.queue[1]=='shift' and Art.action(bike)=='impact')
    bike.impactPulse=0;A.update(bike,0)
    check('riding_collision_recovery_plays_shift_from_neutral',A.sample(bike)=='shift'
        and select(2,Art.action(bike))<1e-8)
    A.update(bike,.32)
    check('riding_collision_recovery_does_not_replay_old_boost',A.sample(bike)=='idle')
    local hit=Bike.new(100,100,0);hit.impactPulse=.4
    assert(Bike.shift(hit,1));A.update(hit,.1)
    check('riding_shift_accepted_while_bracing_waits_until_brace_ends',hit.gear==2
        and A.sample(hit)=='idle' and hit.ridingAnimation.queue[1]=='shift')
    local visual={ridingAction='boost',ridingActionTime=.39,shiftTime=.1}
    check('riding_remote_authoritative_pose_ignores_physical_shift_priority',Art.action(bike,visual)=='boost')
    check('riding_old_snapshot_also_protects_boost_response',Art.action(bike,{boostPulse=.39,shiftTime=.1})=='boost')
    check('riding_animation_snapshot_validation_is_bounded',A.valid(nil,nil) and A.valid('idle',0)
        and A.valid('shift',.32) and not A.valid('shift',.78) and not A.valid('unknown',0)
        and not A.valid('boost',0/0) and not A.valid(nil,.1))
    local r=Rider.new(100,100,0)
    A.request(r.bike,'boost');A.update(r.bike,.1);A.request(r.bike,'shift')
    local restored=assert(Rider.restore(Rider.snapshot(r),world,{x=100,z=100}))
    check('riding_save_load_starts_neutral_without_stale_queue',A.sample(restored.bike)=='idle'
        and #restored.bike.ridingAnimation.queue==0)
    local automatic=Bike.new(100,100,0);automatic.speed=3.7
    Bike.update(automatic,{throttle=1,boost=true},.05,world)
    check('riding_automatic_shift_queues_behind_new_boost_once',automatic.gear==2
        and A.sample(automatic)=='boost' and #automatic.ridingAnimation.queue==1)
    local held=Bike.new(100,100,0);held.transmission='manual'
    for _=1,100 do Bike.update(held,{throttle=1,boost=true},.01,world) end
    check('riding_held_boost_does_not_repeat_visual_response',A.sample(held)=='idle'
        and #held.ridingAnimation.queue==0)
end
return Test
