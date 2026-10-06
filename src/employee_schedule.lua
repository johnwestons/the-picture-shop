-- Ordered cutter jobs. Production remains owned by the actual cutter domain.
local Fleet=require("src.machine_fleet")
local Payroll=require("src.payroll")
local Contracts=require("src.employment_contracts")
local Schedule={MAX_JOBS=16,MAX_HISTORY=32}
local kinds={queue_employee_job=true,remove_employee_job=true,move_employee_job=true,set_employee_schedule=true}
local function int(n,lo,hi) return type(n)=="number" and n==math.floor(n) and n>=lo and n<=hi end
local function token(s) return type(s)=="string" and #s>0 and #s<=64 and s:match("^[%w_.%-]+$") end
local function hours(n) return type(n)=="number" and n==n and n>=0 and n<1e12 end
local function array(t,max,check)
    if type(t)~="table" or #t>max then return false end
    local count=0
    for k,v in pairs(t) do if not int(k,1,max) or not check(v) then return false end;count=count+1 end
    return count==#t
end
function Schedule.defaultState() return {version=1,nextId=1,revision=1,enabled=true,items={},history={}} end
function Schedule.valid(q)
    if type(q)~="table" or q.version~=1 or not int(q.nextId,1,1000000)
        or not int(q.revision,1,1000000000) or type(q.enabled)~="boolean" then return false end
    local ids,jobs={},{}
    local function item(r,history)
        if type(r)~="table" or not token(r.id) or ids[r.id] or not token(r.jobId)
            or not token(r.machineId) or not hours(r.addedAtHours) then return false end
        local serial=tonumber(r.id:match("^TASK%-(%d+)$"))
        if not int(serial,1,q.nextId-1) then return false end
        if history then
            if not hours(r.finishedAtHours) or r.finishedAtHours<r.addedAtHours
                or (r.result~="complete" and r.result~="unavailable" and r.result~="removed") then return false end
        elseif jobs[r.jobId] then return false
        else jobs[r.jobId]=true end
        ids[r.id]=true;return true
    end
    return array(q.items,Schedule.MAX_JOBS,function(r) return item(r,false) end)
        and array(q.history,Schedule.MAX_HISTORY,function(r) return item(r,true) end)
end
function Schedule.ensure(w) w.schedule=w.schedule or Schedule.defaultState();return w.schedule end
function Schedule.isIntent(kind) return kinds[kind]==true end
function Schedule.job(state,id)
    for _,job in ipairs(state.jobs.active or {}) do if job.id==id then return job end end
end
function Schedule.progress(job)
    local finished,total,nextPallet=0,0,nil
    for _,p in ipairs(job and job.pallets or {}) do
        if p.status~="spoiled_discarded" then
            total=total+1
            if p.status=="cut" or p.status=="printed" or p.status=="wrapped" then finished=finished+1
            elseif not nextPallet then nextPallet=p end
        end
    end
    return finished,total,nextPallet
end
function Schedule.skillAllows(w,job)
    return not (job.difficulty=="hard" and w.cutterSkill<80 or job.difficulty=="medium" and w.cutterSkill<50)
end
function Schedule.claimed(state,w,jobId)
    for _,other in ipairs(state.employment.staff) do
        if other~=w and other.status=="employed" then
            if other.assignment and other.assignment.jobId==jobId then return true end
            for _,row in ipairs(Schedule.ensure(other).items) do if row.jobId==jobId then return true end end
        end
    end
    return false
end
function Schedule.canQueue(state,w,jobId,machineId)
    if w.status~="employed" or w.terminationRequested then return false,"Choose a current employee." end
    local job=Schedule.job(state,jobId)
    local machine=Fleet.byId(state,machineId)
    if not job then return false,"Choose an accepted job." end
    if not machine or machine.modelId~="polar_115" or machine.status~="installed" then return false,"Choose an installed cutter." end
    if not Schedule.skillAllows(w,job) then return false,"This job needs a more skilled cutter operator." end
    local _,total,p=Schedule.progress(job)
    if total==0 or not p then return false,"This job's cutting work is already complete." end
    if not p.paper then return false,"This job has no cutter work order." end
    if Schedule.claimed(state,w,jobId) then return false,"This job is assigned to another employee." end
    for _,row in ipairs(Schedule.ensure(w).items) do if row.jobId==jobId then return false,"This job is already in the schedule." end end
    if #w.schedule.items>=Schedule.MAX_JOBS then return false,"An employee can queue up to 16 jobs." end
    return true,"Ready to add. Stage each pallet beside the selected cutter."
end
local function finish(q,index,result,now)
    local row=table.remove(q.items,index)
    row.result=result;row.finishedAtHours=math.max(now,row.addedAtHours)
    q.history[#q.history+1]=row
    if #q.history>Schedule.MAX_HISTORY then table.remove(q.history,1) end
    q.revision=q.revision+1
end
function Schedule.isLocked(state,w,row)
    if not row then return false end
    if w.assignment and w.assignment.scheduleItemId==row.id then return true end
    for _,p in ipairs((Schedule.job(state,row.jobId) or {}).pallets or {}) do
        if p.location=="at_cutter" then return true end
    end
    return false
end
function Schedule.command(state,w,intent,now)
    local q=Schedule.ensure(w)
    if intent.kind=="queue_employee_job" then
        for _,row in ipairs(q.items) do
            if row.jobId==intent.jobId and row.machineId==intent.machineId then return true,"This job is already queued; no duplicate was added." end
        end
        local okay,message=Schedule.canQueue(state,w,intent.jobId,intent.machineId)
        if not okay then return false,message end
        if q.nextId>=1000000 then return false,"This employee's schedule is full." end
        q.items[#q.items+1]={id=string.format("TASK-%06d",q.nextId),jobId=intent.jobId,
            machineId=intent.machineId,addedAtHours=now}
        q.nextId=q.nextId+1;q.revision=q.revision+1
        return true,"Job added. The employee works through the schedule in order."
    elseif intent.kind=="set_employee_schedule" then
        if q.enabled==intent.enabled then return true,intent.enabled and "Schedule is already running." or "Schedule is already paused." end
        q.enabled=intent.enabled;q.revision=q.revision+1
        if not intent.enabled and w.assignment then w.stopRequested=true end
        return true,intent.enabled and "Schedule resumed. Work continues during the agreed shift." or "Schedule paused. The current cutter cycle stops safely."
    end
    if intent.expectedRevision~=q.revision then return false,"The schedule changed. Review the current list and try again." end
    local index
    for i,row in ipairs(q.items) do if row.id==intent.itemId then index=i;break end end
    if not index then return false,"That job has already left the schedule." end
    if Schedule.isLocked(state,w,q.items[index]) then return false,"Pause work and finish or unload the current pallet before moving this job." end
    if intent.kind=="remove_employee_job" then
        finish(q,index,"removed",now);return true,"Job removed from this employee's schedule."
    elseif intent.kind=="move_employee_job" then
        local target=index+intent.direction
        if target<1 or target>#q.items then return false,"This job is already at the end of the list." end
        if Schedule.isLocked(state,w,q.items[target]) then return false,"The current job stays first until its cutter work stops safely." end
        q.items[index],q.items[target]=q.items[target],q.items[index];q.revision=q.revision+1
        return true,"Job order updated."
    end
    return false,"Unknown schedule action."
end
function Schedule.advance(state,w,now)
    local q=Schedule.ensure(w)
    if not q.enabled or w.status~="employed" or w.terminationRequested or w.stopRequested or w.assignment
        or not w.visible or not w.clockedIn or not Contracts.onShift(w.contract,now) then return false end
    if Payroll.balance(w,now,false)>0 then w.activity="Waiting for overdue wages";return false end
    local changed=false
    while #q.items>0 do
        local row=q.items[1]
        local job=Schedule.job(state,row.jobId)
        if not job then
            local completed=false
            for _,old in ipairs(state.jobs.completed or {}) do if old.id==row.jobId then completed=true end end
            finish(q,1,completed and "complete" or "unavailable",now);changed=true
        else
            local _,total,p=Schedule.progress(job)
            if total>0 and not p then finish(q,1,"complete",now);changed=true
            else
                local machine=Fleet.byId(state,row.machineId)
                if not machine or machine.status~="installed" or machine.modelId~="polar_115" then
                    w.activity="Scheduled cutter unavailable - edit Schedule";return changed
                end
                if not Schedule.skillAllows(w,job) then w.activity="Scheduled job requires higher cutter skill";return changed end
                if not p or not p.paper or (p.remainingSheets or 0)<=0 and p.location~="at_cutter" then
                    w.activity="Waiting for job / replacement stock";return changed
                end
                for _,other in ipairs(state.employment.staff) do
                    if other~=w and other.status=="employed" and other.assignment
                        and (other.assignment.machineId==row.machineId or other.assignment.palletId==p.id) then
                        w.activity="Waiting for another employee to release the cutter";return changed
                    end
                end
                w.assignment={jobId=job.id,palletId=p.id,machineId=row.machineId,scheduleItemId=row.id}
                w.activity="Scheduled job - waiting for staged stock"
                return true
            end
        end
    end
    if #q.history>0 then w.activity="Work schedule complete" end
    return changed
end
return Schedule
