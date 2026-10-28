-- Transient work poses follow authoritative task state; no fields enter saves.
local Timing=require("src.employee_work_animation")
local Art=require("src.worker_work_art")
local Presentation={}
local records=setmetatable({},{__mode="k"})
local actions={"work_cutter","work_press","work_wrapping"}

function Presentation.encode(action,frame)
    for i,name in ipairs(actions) do
        if action==name and type(frame)=="number" and frame==math.floor(frame) and frame>=1 and frame<=8 then
            return (i-1)*8+frame
        end
    end
    return 0
end
function Presentation.decode(value)
    if type(value)~="number" or value~=math.floor(value) or value<1 or value>24 then return nil end
    return actions[math.floor((value-1)/8)+1],(value-1)%8+1
end
function Presentation.pose(actor)
    if type(actor.workPose)=="number" then return Presentation.decode(actor.workPose) end
    local record=records[actor]
    if record and record.action then return Timing.sample(record,record.clip.frameCount) end
end
function Presentation.capture(actor)
    return Presentation.encode(Presentation.pose(actor))
end
function Presentation.reset(actor)
    records[actor]=nil
end
function Presentation.clip(character,action,contactFrame)
    local expanded=Art.paths[character] and Art.paths[character][action]
    if not expanded then return {action=action,frameCount=4,secondsPerFrame=.12} end
    local wrapping=action=="work_wrapping"
    return {action=action,frameCount=8,readyFrame=1,secondsPerFrame=.12,
        approachFrames=wrapping and {2,3} or {2,3,4},
        contactFrame=contactFrame or (wrapping and 3 or 4),operationFrame=wrapping and 5 or 6,
        operationEntryFrame=wrapping and 4 or nil,operationEntryDuration=.10,
        recoveryFrames=wrapping and {6,7,8} or {7,8}}
end
function Presentation.update(state,worker,dt)
    if not worker.visible or worker.moving or (worker.phase~="working" and worker.phase~="idle") then
        Presentation.reset(worker)
        return
    end
    local input=require("src.employee_work").presentation(state,worker)
    local record=records[worker]
    if not input then
        if not record then return end
        input={mode="release",safeToRecover=require("src.employee_work").safe(worker,state)}
    end
    record=record or Timing.newRecord()
    local action=input.action
    local clip=action and Presentation.clip(worker.character or "cat-worker",action,input.contactFrame)
    records[worker]=Timing.update(record,input,dt,clip)
end
return Presentation
