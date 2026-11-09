-- Transient full-body pose sequencing, independent of transmission physics.
local M=require('src.commute.vendor.mathx')
local A={durations={boost=.78,shift=.32}}
function A.reset(bike)
    bike.ridingAnimation={kind='idle',remaining=0,queue={},accelerationWeight=0,brakingWeight=0}
end
function A.request(bike,kind)
    assert(A.durations[kind],'Unknown riding animation')
    if not bike.ridingAnimation then A.reset(bike) end
    local state=bike.ridingAnimation
    -- Holding/repeatedly tapping a control must not restart its current pose.
    if state.kind==kind then return end
    for _,queued in ipairs(state.queue) do if queued==kind then return end end
    state.queue[#state.queue+1]=kind
end
local function feedback(state,bike,dt)
    local grounded=bike.grounded~=false
    local acceleration=grounded and not bike.reverse
        and M.smooth(((bike.acceleration or 0)-.6)/2.4)*M.smooth(((bike.throttle or 0)-.2)/.6) or 0
    local braking=grounded and M.smooth(((bike.brake or 0)-.35)/.5)*M.smooth(((bike.speed or 0)-.7)/2.5) or 0
    local function ease(current,target,rise,fall)
        current=current or 0
        return M.lerp(current,target,1-math.exp(-math.max(0,dt)/(target>current and rise or fall)))
    end
    state.accelerationWeight=ease(state.accelerationWeight,acceleration,.07,.10)
    state.brakingWeight=ease(state.brakingWeight,braking,.05,.09)
    if not grounded or bike.reverse and (bike.brake or 0)==0 then
        state.accelerationWeight,state.brakingWeight=0,0
    end
end
function A.update(bike,dt)
    if not bike.ridingAnimation then A.reset(bike) end
    -- Drop stale acceleration reactions after a collision, but retain one gear
    -- gesture, including a shift accepted while the rider is still bracing.
    if (bike.impactPulse or 0)>0 then
        local shift=bike.ridingAnimation.kind=='shift'
        for _,kind in ipairs(bike.ridingAnimation.queue) do shift=shift or kind=='shift' end
        A.reset(bike)
        if shift then A.request(bike,'shift') end
        return
    end
    local state=bike.ridingAnimation
    feedback(state,bike,dt)
    local left=math.max(0,dt)
    if state.kind~='idle' then
        local used=math.min(left,state.remaining)
        state.remaining=math.max(0,state.remaining-used);left=left-used
        if state.remaining>1e-8 then return end
        state.kind='idle';state.remaining=0
    end
    local hardTurn=math.abs(bike.lean or 0)>.15
    for index,kind in ipairs(state.queue) do
        if kind~='shift' or not hardTurn then
            table.remove(state.queue,index)
            state.kind=kind;state.remaining=math.max(0,A.durations[kind]-left)
            return
        end
    end
end
function A.sample(bike)
    local state=bike.ridingAnimation
    return state and state.kind or 'idle',state and state.remaining or 0
end
function A.valid(kind,remaining)
    if kind==nil then return remaining==nil end -- older snapshots
    local duration=kind=='idle' and 0 or A.durations[kind]
    return duration~=nil and type(remaining)=='number' and remaining==remaining
        and remaining>=0 and remaining<=duration
end
return A
