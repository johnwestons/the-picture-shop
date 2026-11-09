-- One packet of interpolation for guest technicians. Drawing never advances
-- simulation; the App update supplies real dt even while a guest opens a GUI.
local Pose=require("src.technician_pose")
local Replica={DURATION=1/12}
local entries=setmetatable({},{__mode="k"})
local function copy(value)
    local out={};for k,v in pairs(value) do out[k]=v end;return out
end
function Replica.accept(state,target)
    if target==false then state._technicianPose=false;entries[state]=nil;return end
    local current=state._technicianPose
    if not current or current.species~=target.species or current.status~=target.status
        or (current.x-target.x)^2+(current.y-target.y)^2>96^2 then
        state._technicianPose=copy(target);entries[state]=nil;return
    end
    local distance=current.animationDistance
    local advance=(target.animationDistance-distance%Pose.CYCLE_DISTANCE)%Pose.CYCLE_DISTANCE
    if advance>Pose.CYCLE_DISTANCE-.02 then advance=0 end -- subpixel rounding at the loop seam
    local actor=copy(target)
    actor.x,actor.y,actor.animationDistance=current.x,current.y,distance
    -- Finish the last achieved displacement before entering the stopped pose.
    actor.inMotion=target.inMotion or advance>.001
    state._technicianPose=actor
    entries[state]={fromX=current.x,fromY=current.y,fromDistance=distance,
        target=copy(target),distance=distance+advance,age=0}
end
function Replica.update(state,dt)
    local actor=state._technicianPose
    if not actor then entries[state]=nil;return end
    dt=math.max(0,tonumber(dt) or 0)
    local entry=entries[state]
    if entry then
        entry.age=math.min(Replica.DURATION,entry.age+dt)
        local t=entry.age/Replica.DURATION
        actor.x=entry.fromX+(entry.target.x-entry.fromX)*t
        actor.y=entry.fromY+(entry.target.y-entry.fromY)*t
        actor.animationDistance=entry.fromDistance+(entry.distance-entry.fromDistance)*t
        if t>=1 then actor.inMotion=entry.target.inMotion;entries[state]=nil end
    end
    if actor.status=="servicing" then actor.animationClock=actor.animationClock+dt end
    if not actor.inMotion then actor.idleClock=actor.idleClock+dt end
end
return Replica
