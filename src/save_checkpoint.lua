-- Coalesce continuous simulation checkpoints in real seconds. Explicit player
-- actions and lifecycle saves still commit immediately through saveCurrent.
local Checkpoint = {}
Checkpoint.__index = Checkpoint

function Checkpoint.new(interval)
    return setmetatable({interval=interval or 5,elapsed=0,pending=false},Checkpoint)
end

function Checkpoint:reset()
    self.elapsed,self.pending=0,false
end

function Checkpoint:update(dt,dirty,save)
    self.elapsed=math.min(self.interval,self.elapsed+math.max(0,dt))
    self.pending=self.pending or dirty == true
    if not self.pending or self.elapsed<self.interval then return false end
    self.elapsed=0
    if save() then self.pending=false;return true end
    -- Keep dirty state, but don't retry a failing disk every frame.
    return false
end

return Checkpoint
