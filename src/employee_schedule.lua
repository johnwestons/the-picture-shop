-- Ordered cutter jobs. Production remains owned by the actual cutter domain.
local Fleet=require("src.machine_fleet")
local Machine=require("src.machine")
local Windmill=require("src.windmill")
local Wrapper=require("src.wrapper")
local Plates=require("src.plate_service")
local Procurement=require("src.procurement")
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
function Schedule.stockArrived(job)
    if type(job)~="table" or job.status~="in_production"
        or type(job.pallets)~="table" or #job.pallets==0 then return false end
    local delivery=job.delivery
    if delivery and delivery.status and delivery.status~="received" then return false end
    for _,pallet in ipairs(job.pallets) do
        if pallet.location=="awaiting_delivery" then return false end
    end
    return true
end
local function finalPallet(p) return p and (p.status=="wrapped" or p.wrapped==true) end
function Schedule.progress(job)
    local finished,total,nextPallet=0,0,nil
    for _,p in ipairs(job and job.pallets or {}) do
        if p.status~="spoiled_discarded" then
            total=total+1
            if finalPallet(p) then finished=finished+1 elseif not nextPallet then nextPallet=p end
        end
    end
    return finished,total,nextPallet
end
function Schedule.stage(job,pallet)
    if not pallet or pallet.status=="spoiled_discarded" or finalPallet(pallet) then return nil end
    local cutComplete=pallet.status=="cut" or pallet.status=="printed" or pallet.status=="finished"
    local pressInFlight=job and job.press
        and (pallet.location=="at_press" or pallet.location=="press_output")
    if not cutComplete and not pressInFlight then return "cutter" end
    if job and job.press and not (pallet.press and pallet.press.status=="complete") then return "press" end
    return "wrapping"
end
function Schedule.skillAllows(w,job,stage)
    if stage=="press" and (w.pressSkill or 0)<60 then return false,"Press training required" end
    if stage=="wrapping" and (w.wrappingSkill or 0)<50 then return false,"Pallet-wrapping training required" end
    if stage=="cutter" and (job.difficulty=="hard" and w.cutterSkill<80
        or job.difficulty=="medium" and w.cutterSkill<50) then return false,"Required cutter skill" end
    return true
end
local function activeOther(state,w,machineId,palletId)
    for _,other in ipairs(state.employment.staff) do
        if other~=w and other.status=="employed" and other.assignment
            and (other.assignment.machineId==machineId or other.assignment.palletId==palletId) then return true end
        if other~=w and other.status=="employed" and other.training and other._trainingMachineId==machineId then return true end
    end
    return false
end
local function machineReady(state,machine,model)
    if not machine or machine.modelId~=model or machine.status~="installed" then
        return false,"Scheduled machine is unavailable"
    end
    local operable,reason=Fleet.canOperate(state,model,machine.id)
    if not operable then return false,reason or "Scheduled machine needs service" end
    if machine.world and machine.world.moving then return false,"Waiting for the machine to stop moving" end
    return true
end
local function cutterPalletReady(state,machine,pallet)
    local staged=false
    Fleet.withUnit(state,machine.id,function()
        local runtime=Machine.forId(machine.id)
        local same=runtime.pallet and runtime.pallet.id==pallet.id
        if same and runtime.step~="idle" and runtime.step~="finished" then staged=true
        else
            for _,candidate in ipairs(runtime.availablePapers(state)) do
                if candidate.pallet.id==pallet.id then staged=true;break end
            end
        end
        if runtime.emergencyStopped or not runtime.barrierClear or runtime.step=="blocked"
            or runtime.step~="idle" and runtime.step~="finished" and not same then staged=false end
    end)
    if not staged then return false,"Stage the assigned pallet beside the selected cutter" end
    return true
end
local function pressPalletReady(state,machine,pallet,job)
    local staged=false
    local blocked
    Fleet.withUnit(state,machine.id,function()
        local process,loadedJob=Windmill.current(state)
        job=loadedJob or job
        if process.palletId==pallet.id and process.status~="idle" then
            staged=true
            local stock=state.inventory and state.inventory.stock or {}
            if process.emergency then blocked="Printing press emergency stop needs attention"
            elseif process.status=="pass_complete" and (stock.press_wash or 0)<1 then
                blocked="Order press wash before the employee can unload this color"
            elseif process.status=="proof" and (process.proofQuality or 0)<.82 then
                blocked="Press proof is below approval quality; owner attention required"
            elseif process.status=="stock_shortage" or process.status=="stopped" then
                blocked="Printing press needs stock or safety attention"
            elseif process.status=="setup" then
                local plate=job and Plates.ensureJob(job)[process.colorIndex or 1]
                local inkId=plate and plate.inkColor=="Black" and "black_ink" or "color_ink"
                if not process.setup.ink and (stock[inkId] or 0)<1 then blocked="Order printing ink before press setup"
                elseif not process.setup.packing and (stock.tympan_sheets or 0)<1 then blocked="Order tympan sheets before press setup" end
            end
            return
        end
        local color=math.max(1,(pallet.press and pallet.press.completedColors or 0)+1)
        local plate=job and Plates.ensureJob(job)[color]
        if plate then
            local stock=state.inventory and state.inventory.stock or {}
            if plate.status=="unprepared" and ((stock.raw_press_plates or 0)<1
                or (stock.negative_film or 0)<1 or (stock.plate_adhesive or 0)<1
                or (stock.plate_chemistry or 0)<1) then
                blocked="Order prepress supplies before printing"
            elseif plate.status=="ordered" then blocked="Waiting for the ordered print plate" end
        end
        for _,candidate in ipairs(Windmill.candidates(state)) do
            if candidate.pallet.id==pallet.id then staged=true;break end
        end
    end)
    if blocked then return false,blocked end
    if not staged then
        if pallet.press and pallet.press.status=="drying" then return false,"Printed color is drying before its next press pass" end
        return false,"Stage the cut pallet beside the printing press"
    end
    return true
end
local function wrapperPalletReady(state,machine,pallet,job)
    local staged=false
    local blocked
    Fleet.withUnit(state,machine.id,function()
        local runtime=Wrapper.forId(machine.id)
        if runtime.pallet and runtime.pallet.id==pallet.id
            and (runtime.step=="wrapping" or runtime.step=="finished") then staged=true;return end
        local inventory=state.inventory or {}
        if (inventory.plasticWrapUses or 0)<1 then blocked="Order stretch film before shipping pallets";return end
        local packaging=pallet.packaging or (job and job.packaging)
        if packaging=="boxed" and Procurement.cartonsAvailable(state)<1 then
            blocked="Order a shipping carton before wrapping this boxed pallet";return
        end
        for _,candidate in ipairs(runtime.nearbyPallets(state)) do
            if candidate.pallet.id==pallet.id then staged=true;break end
        end
    end)
    if blocked then return false,blocked end
    if not staged then return false,"Stage the finished pallet beside the skid wrapper" end
    return true
end
function Schedule.resolve(state,w,row,preferredPalletId)
    local job=Schedule.job(state,row.jobId)
    if not job then return nil,nil,nil,"Scheduled job is no longer available" end
    if not Schedule.stockArrived(job) then return nil,nil,nil,"Waiting for job delivery at the warehouse" end
    local pallet
    if preferredPalletId then
        for _,candidate in ipairs(job.pallets or {}) do
            if candidate.id==preferredPalletId and not finalPallet(candidate) then pallet=candidate;break end
        end
    end
    if not pallet then local _,_,nextPallet=Schedule.progress(job);pallet=nextPallet end
    if not pallet then return nil,nil,nil end
    local stage=Schedule.stage(job,pallet)
    local allowed,skillReason=Schedule.skillAllows(w,job,stage)
    if not allowed then
        local reason=skillReason=="Press training required" and "Press training required before this employee can print"
            or skillReason=="Pallet-wrapping training required" and "Pallet-wrapping training required before shipping"
            or "This job needs a more skilled cutter operator"
        return stage,nil,pallet,reason
    end
    local models={cutter="polar_115",press="heidelberg_10x15",wrapping="skid_wrapper"}
    local model=models[stage]
    local machines=stage=="cutter" and {Fleet.byId(state,row.machineId)} or Fleet.installedUnits(state,model)
    local failure=stage=="cutter" and "Scheduled cutter is unavailable"
        or stage=="press" and "No Heidelberg Windmill is installed" or "No skid wrapper is installed"
    local transferMachine
    for _,machine in ipairs(machines) do
        local okay=machineReady(state,machine,model)
        if okay and not activeOther(state,w,machine.id,pallet.id) then
            local ready,reason
            if stage=="cutter" then ready,reason=cutterPalletReady(state,machine,pallet)
            elseif stage=="press" then ready,reason=pressPalletReady(state,machine,pallet,job)
            else ready,reason=wrapperPalletReady(state,machine,pallet,job) end
            if ready then return stage,machine,pallet end
            if stage=="wrapping" and reason=="Stage the finished pallet beside the skid wrapper"
                and (pallet.location=="warehouse" or pallet.location=="cutter_output"
                    or pallet.location=="press_output"
                    or pallet.location=="on_employee" and pallet.carrierEmployeeId==w.id)
            then
                transferMachine=transferMachine or machine
            end
            failure=reason or failure
        end
    end
    if transferMachine then return stage,transferMachine,pallet,nil,true end
    return stage,nil,pallet,failure
end
local function nextShiftStart(w,now)
    if Contracts.onShift(w.contract,now) then return now end
    local contract=w.contract
    local day=math.max(math.floor(now/24),contract.startDay)
    for _=0,14 do
        if Contracts.hasDay(contract.days,Contracts.weekday(day)) then
            local start=day*24+contract.startHour
            if start>now then return start end
        end
        day=day+1
    end
    return math.huge
end
local function hasQueuedJob(q,jobId)
    for _,row in ipairs(q.items) do if row.jobId==jobId then return true end end
    return false
end
function Schedule.rollover(state,w,now)
    local source=Schedule.ensure(w)
    if not source.enabled or #source.items==0 or w.status~="employed" then return false end
    if w.assignment and (not w.assignment.scheduleItemId
        or not source.items[1] or source.items[1].id~=w.assignment.scheduleItemId) then return false end
    local sourceNext=nextShiftStart(w,now)
    if w.terminationRequested then sourceNext=math.huge end
    local candidate,candidateStart
    for _,other in ipairs(state.employment.staff) do
        if other~=w and other.status=="employed" and not other.terminationRequested and not other.stopRequested
            and Payroll.balance(other,now,false)<=0 then
            local target=Schedule.ensure(other)
            if target.enabled and #target.items<Schedule.MAX_JOBS and target.nextId<1000000 then
                local first=source.items[1]
                local job=Schedule.job(state,first.jobId)
                local start=nextShiftStart(other,now)
                local _,_,unfinished=Schedule.progress(job)
                local requiredStage=Schedule.stage(job,unfinished)
                if job and Schedule.skillAllows(other,job,requiredStage) and not hasQueuedJob(target,first.jobId)
                    and start<sourceNext and (not candidateStart or start<candidateStart) then
                    candidate,candidateStart=other,start
                end
            end
        end
    end
    if not candidate then return false end
    local target=Schedule.ensure(candidate)
    local moved=0
    local insertAt=1
    if candidate.assignment and candidate.assignment.scheduleItemId
        and target.items[1] and target.items[1].id==candidate.assignment.scheduleItemId then
        insertAt=2
    end
    while #source.items>0 and #target.items<Schedule.MAX_JOBS and target.nextId<1000000 do
        local row=source.items[1]
        local job=Schedule.job(state,row.jobId)
        local _,_,unfinished=Schedule.progress(job)
        local requiredStage=Schedule.stage(job,unfinished)
        if not job or not Schedule.skillAllows(candidate,job,requiredStage) or hasQueuedJob(target,row.jobId) then break end
        table.remove(source.items,1)
        table.insert(target.items,insertAt,{id=string.format("TASK-%06d",target.nextId),jobId=row.jobId,
            machineId=row.machineId,addedAtHours=row.addedAtHours})
        target.nextId=target.nextId+1
        insertAt=insertAt+1;moved=moved+1
    end
    if moved==0 then return false end
    source.revision=source.revision+1
    target.revision=target.revision+1
    candidate._scheduleRetryAtHours=nil
    candidate._waitingMachineId=nil
    if w.assignment and w.assignment.scheduleItemId and (not source.items[1]
        or source.items[1].id~=w.assignment.scheduleItemId) then
        w.assignment=nil
        w._blockedWorkHours=0
    end
    w._waitingMachineId=nil
    w.activity="Unfinished schedule handed to the next shift"
    return true,candidate.id,moved
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
    if not Schedule.stockArrived(job) then return false,"Wait for the full job delivery to be unloaded at the warehouse." end
    if not machine or machine.modelId~="polar_115" or machine.status~="installed" then return false,"Choose an installed cutter." end
    local _,total,p=Schedule.progress(job)
    if total==0 or not p then return false,"This job's production and wrapping are already complete." end
    local stage=Schedule.stage(job,p)
    local allowed=Schedule.skillAllows(w,job,stage)
    if not allowed then return false,stage=="press" and "Train this employee on the printing press first."
        or stage=="wrapping" and "Train this employee on pallet wrapping first."
        or "This job needs a more skilled cutter operator." end
    if stage=="cutter" and (not p.paper or (p.remainingSheets or 0)<=0 and p.location~="at_cutter") then
        return false,"This job has no available cutter work order."
    end
    if Schedule.claimed(state,w,jobId) then return false,"This job is assigned to another employee." end
    for _,row in ipairs(Schedule.ensure(w).items) do if row.jobId==jobId then return false,"This job is already in the schedule." end end
    if #w.schedule.items>=Schedule.MAX_JOBS then return false,"An employee can queue up to 16 jobs." end
    return true,"Ready to add. The employee will cut, print if required, then wrap each pallet."
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
        if p.location=="at_cutter" or p.location=="at_press" then return true end
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
        w._scheduleRetryAtHours=nil
        w._waitingMachineId=nil
        return true,"Job added. The employee works through the schedule in order."
    elseif intent.kind=="set_employee_schedule" then
        if q.enabled==intent.enabled then return true,intent.enabled and "Schedule is already running." or "Schedule is already paused." end
        q.enabled=intent.enabled;q.revision=q.revision+1
        w._scheduleRetryAtHours=nil
        w._waitingMachineId=nil
        if not intent.enabled and w.assignment then w.stopRequested=true end
        return true,intent.enabled and "Schedule resumed. Work continues during the agreed shift." or "Schedule paused. The current machine cycle stops safely."
    end
    if intent.expectedRevision~=q.revision then return false,"The schedule changed. Review the current list and try again." end
    local index
    for i,row in ipairs(q.items) do if row.id==intent.itemId then index=i;break end end
    if not index then return false,"That job has already left the schedule." end
    if Schedule.isLocked(state,w,q.items[index]) then return false,"Pause work and finish or unload the current pallet before moving this job." end
    if intent.kind=="remove_employee_job" then
        finish(q,index,"removed",now);w._scheduleRetryAtHours=nil;w._waitingMachineId=nil;return true,"Job removed from this employee's schedule."
    elseif intent.kind=="move_employee_job" then
        local target=index+intent.direction
        if target<1 or target>#q.items then return false,"This job is already at the end of the list." end
        if Schedule.isLocked(state,w,q.items[target]) then return false,"The current job stays first until its cutter work stops safely." end
        q.items[index],q.items[target]=q.items[target],q.items[index];q.revision=q.revision+1
        w._scheduleRetryAtHours=nil
        w._waitingMachineId=nil
        return true,"Job order updated."
    end
    return false,"Unknown schedule action."
end
function Schedule.advance(state,w,now)
    local q=Schedule.ensure(w)
    if not q.enabled or w.status~="employed" or w.terminationRequested or w.stopRequested or w.assignment or w.training
        or not w.visible or not w.clockedIn or not Contracts.onShift(w.contract,now) then return false end
    if Payroll.balance(w,now,false)>0 then w.activity="Waiting for overdue wages";return false end
    if w._scheduleRetryAtHours and now<w._scheduleRetryAtHours then return false end
    w._scheduleRetryAtHours=nil
    local changed=false
    local scanIndex,scanned=1,0
    local scanLimit=#q.items
    local lastBlocked
    while scanIndex<=#q.items and scanned<scanLimit do
        scanned=scanned+1
        local row=q.items[scanIndex]
        local job=Schedule.job(state,row.jobId)
        if not job then
            local completed=false
            for _,old in ipairs(state.jobs.completed or {}) do if old.id==row.jobId then completed=true end end
            finish(q,scanIndex,completed and "complete" or "unavailable",now);changed=true
        else
            local _,total,p=Schedule.progress(job)
            if not p then finish(q,scanIndex,total>0 and "complete" or "unavailable",now);changed=true
            else
                local _,machine,readyPallet,reason=Schedule.resolve(state,w,row)
                if reason then
                    lastBlocked=lastBlocked or reason
                    scanIndex=scanIndex+1
                else
                    if scanIndex>1 then
                        table.remove(q.items,scanIndex)
                        table.insert(q.items,1,row)
                        q.revision=q.revision+1
                        changed=true
                    end
                    w.assignment={jobId=job.id,palletId=readyPallet.id,cutterMachineId=row.machineId,
                        machineId=machine.id,machineModel=machine.modelId,scheduleItemId=row.id}
                    w._blockedWorkHours=0
                    w._waitingMachineId=nil
                    local stage=Schedule.stage(job,readyPallet)
                    w.activity="Scheduled job - walking to "..(stage=="cutter" and "cutter"
                        or stage=="press" and "printing press" or "skid wrapper")
                    return true
                end
            end
        end
    end
    if lastBlocked then
        w.activity=lastBlocked
        w._waitingMachineId=q.items[1] and q.items[1].machineId or nil
        w._scheduleRetryAtHours=now+.05
        return changed
    end
    w._waitingMachineId=nil
    if #q.history>0 then w.activity="Work schedule complete" end
    return changed
end
function Schedule.deferBlocked(state,w)
    local q=Schedule.ensure(w)
    local assignment,row=w.assignment,q.items[1]
    if not q.enabled or not assignment or not assignment.scheduleItemId or not row
        or row.id~=assignment.scheduleItemId or #q.items<2 then return false end
    table.remove(q.items,1)
    q.items[#q.items+1]=row
    q.revision=q.revision+1
    w.assignment=nil
    w._blockedWorkHours=0
    w._scheduleRetryAtHours=nil
    w._waitingMachineId=nil
    w.phase="idle"
    w.activity="Job blocked; trying the next scheduled job"
    return true
end
return Schedule
