-- Transient full-body pose sequencing, independent of transmission physics.
local A={durations={boost=.78,shift=.32}}
function A.reset(bike)
    bike.ridingAnimation={kind='idle',remaining=0,queue={}}
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
