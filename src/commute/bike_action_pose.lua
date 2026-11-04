-- One opaque authored pose, sampled from authoritative riding feedback.
local Bike=require('src.commute.motorcycle')
local Sequence=require('src.commute.riding_animation')
local M=require('src.commute.vendor.mathx')
local Pose={}
local function value(actor,visual,key,fallback)
    local result=visual and visual[key]
    if result==nil then result=actor[key] end
    if result==nil then return fallback end
    return result
end
local function pulse(left,duration)
    if not left or left<=0 then return 0 end
    return math.sin((1-M.clamp(left/duration,0,1))*math.pi)
end
function Pose.transition(base,middle,target,weight)
    if weight<.25 then return base end
    if weight<.75 then return middle end
    return target
end
local function feedback(actor,visual,key,stateKey,raw)
    if visual then
        if visual[key]~=nil then return M.clamp(visual[key],0,1) end
    elseif actor.ridingAnimation and actor.ridingAnimation[stateKey]~=nil then
        return actor.ridingAnimation[stateKey]
    end
    return raw
end
function Pose.action(actor,visual,turnBlend)
    local impact=value(actor,visual,'impactPulse',0)
    if impact>0 then
        return 'impact',pulse(impact,Bike.IMPACT_DURATION)*M.clamp(value(actor,visual,'impactStrength',0),0,1)
    end
    local speed=value(actor,visual,'speed',0)
    if value(actor,visual,'grounded',true) then
        local brake=feedback(actor,visual,'brakingPose','brakingWeight',
            M.smooth((value(actor,visual,'brake',0)-.35)/.5)*M.smooth((speed-.7)/2.5))
        -- A decaying weight never reaches zero mathematically. Only a visible
        -- brake pose should override later shift/boost/acceleration reactions.
        if brake>=.25 then return 'brake',brake end
    end
    local kind,remaining
    if visual and visual.ridingAction~=nil then kind,remaining=visual.ridingAction,visual.ridingActionTime
    elseif not visual and actor.ridingAnimation then kind,remaining=Sequence.sample(actor)
    else
        if value(actor,visual,'boostPulse',0)>0 then return 'boost',pulse(value(actor,visual,'boostPulse',0),Bike.BOOST_PULSE) end
        if value(actor,visual,'shiftTime',0)>0 then
            return 'shift',pulse(value(actor,visual,'shiftTime',0),Bike.SHIFT_TIME)*(1-(turnBlend or 0))
        end
    end
    if kind and kind~='idle' then
        local weight=pulse(remaining,Sequence.durations[kind])
        if kind=='shift' then weight=weight*(1-(turnBlend or 0)) end
        return kind,weight
    end
    if not actor.reverse and value(actor,visual,'grounded',true) then
        local weight=feedback(actor,visual,'accelerationPose','accelerationWeight',
            M.smooth((value(actor,visual,'acceleration',0)-.6)/2.4)
                *M.smooth((value(actor,visual,'throttle',0)-.2)/.6))
        if weight>0 then return 'boost',weight end
    end
    return nil,0
end
function Pose.select(actor,visual)
    local speed=value(actor,visual,'speed',0);local lean=value(actor,visual,'lean',0)
    local turnBlend=M.smooth((math.abs(lean)-.15)/.15)
    local tuck=M.smooth((speed-Bike.TUCK_START_SPEED)/(Bike.BOOST_MAX_SPEED-Bike.TUCK_START_SPEED))
    local state=Pose.transition('upright','aeroMid','aero',tuck)
    local turn=lean>=0 and 'turnLeft' or 'turnRight'
    state=Pose.transition(state,turn..'Mid',turn,turnBlend)
    local action,weight=Pose.action(actor,visual,turnBlend)
    state=Pose.transition(state,action and action..'Mid',action,weight)
    return state,action,turnBlend
end
return Pose
