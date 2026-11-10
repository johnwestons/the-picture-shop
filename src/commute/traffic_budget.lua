-- Host-local admission feedback. Existing road users always keep simulating
-- and rendering; only a new off-map departure can be postponed.
local Budget={PAUSE_MS=8,RESUME_MS=5,MIN_TRUCKS=4}
local samples=setmetatable({}, {__mode='k'})
function Budget.record(state,milliseconds,steps)
    local sample=samples[state] or {count=0,mean=0,paused=false}
    samples[state]=sample;sample.count=sample.count+1
    -- Ignore route/atlas cold starts when learning the steady simulation cost.
    if sample.count<=4 then return end
    local cost=milliseconds/math.max(1,steps or 1)
    sample.mean=sample.count==5 and cost or sample.mean*.8+cost*.2
    if sample.mean>Budget.PAUSE_MS then sample.paused=true
    elseif sample.mean<Budget.RESUME_MS then sample.paused=false end
end
function Budget.allows(state,truckCount)
    local sample=samples[state]
    return truckCount<Budget.MIN_TRUCKS or not sample or not sample.paused
end
return Budget
