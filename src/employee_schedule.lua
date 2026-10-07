-- Ordered cutter jobs. Production remains owned by the actual cutter domain.
local Fleet=require("src.machine_fleet")
local Machine=require("src.machine")
local Windmill=require("src.windmill")
local Wrapper=require("src.wrapper")
local Plates=require("src.plate_service")
local Procurement=require("src.procurement")
local Payroll=require("src.payroll")
local Contracts=require("src.employment_contracts")
local Config=require("src.config")
local CutterZones=require("src.cutter_zones")
local Footprint=require("src.floor_footprint")
local PalletStorage=require("src.pallet_storage")
local WindmillPlacement=require("src.windmill_placement")
-- A shop can have 24 employees with up to 16 previously queued jobs each.
-- The shared queue must be large enough to migrate every existing schedule.
local Schedule={MAX_JOBS=16,MAX_TEAM_JOBS=384,MAX_HISTORY=32}
local kinds={queue_employee_job=true,remove_employee_job=true,move_employee_job=true,set_employee_schedule=true,
    queue_team_job=true,remove_team_job=true,move_team_job=true,set_team_schedule=true}
local function int(n,lo,hi) return type(n)=="number" and n==math.floor(n) and n>=lo and n<=hi end
local function token(s) return type(s)=="string" and #s>0 and #s<=64 and s:match("^[%w_.%-]+$") end
local function hours(n) return type(n)=="number" and n==n and n>=0 and n<1e12 end
local function array(t,max,check)
    if type(t)~="table" or #t>max then return false end
    local count=0
    for k,v in pairs(t) do if not int(k,1,max) or not check(v) then return false end;count=count+1 end
    return count==#t
end
function Schedule.defaultState(team)
    return {version=1,nextId=1,revision=1,enabled=true,items={},history={},
        taskPrefix=team and "TEAM-TASK" or nil}
end
function Schedule.valid(q,team)
    if type(q)~="table" or q.version~=1 or not int(q.nextId,1,1000000)
        or not int(q.revision,1,1000000000) or type(q.enabled)~="boolean"
        or (team and q.taskPrefix~="TEAM-TASK") or (not team and q.taskPrefix~=nil) then return false end
    local ids,jobs={},{}
    local function item(r,history)
        if type(r)~="table" or not token(r.id) or ids[r.id] or not token(r.jobId)
            or not token(r.machineId) or not hours(r.addedAtHours) then return false end
        local prefix=team and "TEAM%-TASK" or "TASK"
        local serial=tonumber(r.id:match("^"..prefix.."%-(%d+)$"))
        if not int(serial,1,q.nextId-1) then return false end
        if not team and (r.teamTaskId~=nil
            and (not token(r.teamTaskId) or not r.teamTaskId:match("^TEAM%-TASK%-%d+$"))) then return false end
        if r.teamWorkerId~=nil and (r.teamTaskId==nil or not token(r.teamWorkerId)) then return false end
        if team and r.workerId~=nil and not token(r.workerId) then return false end
        if history then
            if not hours(r.finishedAtHours) or r.finishedAtHours<r.addedAtHours
                or (r.result~="complete" and r.result~="unavailable" and r.result~="removed") then return false end
        elseif jobs[r.jobId] then return false
        else jobs[r.jobId]=true end
        ids[r.id]=true;return true
    end
    return array(q.items,team and Schedule.MAX_TEAM_JOBS or Schedule.MAX_JOBS,function(r) return item(r,false) end)
        and array(q.history,Schedule.MAX_HISTORY,function(r) return item(r,true) end)
end
function Schedule.ensure(w) w.schedule=w.schedule or Schedule.defaultState();return w.schedule end
function Schedule.team(state)
    local employment=state.employment
    if type(employment)~="table" then return nil end
    employment.teamSchedule=employment.teamSchedule or Schedule.defaultState(true)
    return employment.teamSchedule
end
function Schedule.isIntent(kind) return kinds[kind]==true end
function Schedule.isTeamIntent(kind)
    return kind=="queue_team_job" or kind=="remove_team_job"
        or kind=="move_team_job" or kind=="set_team_schedule"
end
function Schedule.job(state,id)
    for _,job in ipairs(state.jobs.active or {}) do if job.id==id then return job end end
end
function Schedule.stockArrived(job)
    if type(job)~="table" or job.status~="in_production"
        or type(job.pallets)~="table" or #job.pallets==0 then return false end
    local delivery=job.delivery
    if delivery and delivery.status and delivery.status~="received" then return false end
    local quotedPallets=job.quote and job.quote.pallets
    if type(quotedPallets)=="table" then
        if #job.pallets<#quotedPallets then return false end
        for index,quoted in ipairs(quotedPallets) do
            if type(quoted)~="table" then return false end
            local pallet
            for _,candidate in ipairs(job.pallets) do
                if type(candidate)~="table" then return false end
                if not candidate.replacementFor and candidate.number==index then pallet=candidate;break end
            end
            if not pallet or pallet.initialSheets~=quoted.sheetCount then return false end
        end
    end
    local atShop={warehouse=true,on_pallet_jack=true,on_forklift=true,at_cutter=true,
        cutter_output=true,at_press=true,press_output=true,on_employee=true}
    for _,pallet in ipairs(job.pallets) do
        if type(pallet)~="table" then return false end
        if not atShop[pallet.location]
            and not (pallet.status=="spoiled_discarded" and pallet.location=="none") then return false end
    end
    return true
end
local function finalPallet(p) return p and (p.status=="wrapped" or p.wrapped==true) end
function Schedule.progress(job)
    local finished,total,nextPallet,productionPallet=0,0,nil,nil
    for _,p in ipairs(job and job.pallets or {}) do
        if p.status~="spoiled_discarded" then
            total=total+1
            if finalPallet(p) then
                finished=finished+1
            else
                if not nextPallet then nextPallet=p end
                local stage=Schedule.stage(job,p)
                if stage and stage~="wrapping" and not productionPallet then productionPallet=p end
            end
        end
    end
    return finished,total,productionPallet or nextPallet
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
function Schedule.minimumSkills(job)
    local difficulty=job and job.difficulty
    local pressMinimum=difficulty=="hard" and 80 or difficulty=="medium" and 60 or 40
    if job and job.press and (job.press.colors or 1)>=2 then
        pressMinimum=math.max(60,pressMinimum)
    end
    return {
        cutter=difficulty=="hard" and 80 or difficulty=="medium" and 50 or 0,
        press=job and job.press and pressMinimum or nil,
        wrapping=difficulty=="hard" and 70 or difficulty=="medium" and 50 or 25,
    }
end
function Schedule.skillAllows(w,job,stage)
    local minimum=Schedule.minimumSkills(job)
    if stage=="press" and minimum.press and (w.pressSkill or 0)<minimum.press then
        return false,"Press training required"
    end
    if stage=="wrapping" and (w.wrappingSkill or 0)<minimum.wrapping then
        return false,"Pallet-wrapping training required"
    end
    if stage=="cutter" and (w.cutterSkill or 0)<minimum.cutter then
        return false,"Required cutter skill"
    end
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
    local blockedKind
    Fleet.withUnit(state,machine.id,function()
        local runtime=Wrapper.forId(machine.id)
        if runtime.pallet and runtime.pallet.id==pallet.id
            and (runtime.step=="wrapping" or runtime.step=="finished") then staged=true;return end
        local inventory=state.inventory or {}
        if (inventory.plasticWrapUses or 0)<1 then
            blocked="Order stretch film before shipping pallets";blockedKind="packaging";return
        end
        local packaging=pallet.packaging or (job and job.packaging)
        if packaging=="boxed" and Procurement.cartonsAvailable(state)<1 then
            blocked="Order a shipping carton before wrapping this boxed pallet"
            blockedKind="packaging";return
        end
        for _,candidate in ipairs(runtime.nearbyPallets(state)) do
            if candidate.pallet.id==pallet.id then staged=true;break end
        end
    end)
    if blocked then return false,blocked,blockedKind end
    if not staged then return false,"Stage the finished pallet beside the skid wrapper" end
    return true
end
local function employeeCanCarry(w,pallet)
    return pallet.location=="warehouse" or pallet.location=="cutter_output"
        or pallet.location=="press_output"
        or pallet.location=="on_employee" and pallet.carrierEmployeeId==w.id
end
local function needsMachinePalletTransfer(state,w,stage,machine,pallet,reason)
    if not employeeCanCarry(w,pallet) or PalletStorage.isSupporting(state,pallet.id) then return false end
    if pallet.location=="on_employee" then
        return pallet.carrierEmployeeId==w.id and (stage=="cutter"
            and reason=="Stage the assigned pallet beside the selected cutter"
            or stage=="press" and reason=="Stage the cut pallet beside the printing press")
    end
    if stage=="cutter" and reason=="Stage the assigned pallet beside the selected cutter" then
        local inRange=false
        Fleet.withUnit(state,machine.id,function()
            inRange=CutterZones.inInputZone(state,pallet,Config.cutterPlacement,
                Config.cutterPlacement.palletInputZoneRadius)
        end)
        return not inRange
    elseif stage=="press" and reason=="Stage the cut pallet beside the printing press" then
        if not pallet.world then return false end
        local inRange=false
        Fleet.withUnit(state,machine.id,function()
            local pose=machine.world or WindmillPlacement.ensure(state,Config.windmillPlacement)
            inRange=pose and Footprint.distanceSquared(
                Footprint.at(pose.x,pose.y,Config.windmillPlacement),
                Footprint.at(pallet.world.x,pallet.world.y,Config.palletLogistics))
                    <= Config.windmillPlacement.palletReach^2 or false
        end)
        return not inRange
    end
    return false
end
function Schedule.resolve(state,w,row,preferredPalletId)
    local job=Schedule.job(state,row.jobId)
    if not job then return nil,nil,nil,"Scheduled job is no longer available" end
    if not Schedule.stockArrived(job) then return nil,nil,nil,"Waiting until every skid for this job reaches the shop" end
    local pallet,nextPallet
    local _,_,scheduledPallet=Schedule.progress(job)
    if preferredPalletId then
        for _,candidate in ipairs(job.pallets or {}) do
            if candidate.id==preferredPalletId and not finalPallet(candidate) then pallet=candidate;break end
        end
    end
    nextPallet=scheduledPallet
    if pallet and Schedule.stage(job,pallet)=="wrapping"
        and nextPallet and Schedule.stage(job,nextPallet)~="wrapping"
        and w.carryingPalletId~=pallet.id then
        pallet=nil
    end
    if not pallet then pallet=nextPallet end
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
    local blockedKind
    for _,machine in ipairs(machines) do
        local okay=machineReady(state,machine,model)
        if okay and not activeOther(state,w,machine.id,pallet.id) then
            local ready,reason,reasonKind
            if stage=="cutter" then ready,reason=cutterPalletReady(state,machine,pallet)
            elseif stage=="press" then ready,reason=pressPalletReady(state,machine,pallet,job)
            else ready,reason,reasonKind=wrapperPalletReady(state,machine,pallet,job) end
            if ready then return stage,machine,pallet end
            blockedKind=blockedKind or reasonKind
            if stage=="wrapping" and reason=="Stage the finished pallet beside the skid wrapper"
                and (pallet.location=="warehouse" or pallet.location=="cutter_output"
                    or pallet.location=="press_output"
                    or pallet.location=="on_employee" and pallet.carrierEmployeeId==w.id)
            then
                transferMachine=transferMachine or machine
            elseif needsMachinePalletTransfer(state,w,stage,machine,pallet,reason) then
                transferMachine=transferMachine or machine
            end
            failure=reason or failure
        end
    end
    if transferMachine then return stage,transferMachine,pallet,nil,true,blockedKind end
    return stage,nil,pallet,failure,nil,blockedKind
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
    if w.status~="employed" then return false end
    local releasedShared=0
    for index=#source.items,1,-1 do
        local row=source.items[index]
        if row.teamTaskId then
            table.remove(source.items,index)
            if w.assignment and w.assignment.scheduleItemId==row.id then
                w.assignment=nil;w.reserved=false;w._blockedWorkHours=0
            end
            releasedShared=releasedShared+1
        end
    end
    if releasedShared>0 then
        source.revision=source.revision+1
        w._scheduleRetryAtHours=nil;w._waitingMachineId=nil
        w.activity="Unfinished shared jobs returned to the day and night queue"
        return true,nil,releasedShared
    end
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
            machineId=row.machineId,addedAtHours=row.addedAtHours,
            teamTaskId=row.teamTaskId,teamWorkerId=row.teamTaskId and candidate.id or nil})
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
function Schedule.claimed(state,w,jobId,ignoreTeam)
    local team=Schedule.team(state)
    if not ignoreTeam then
        for _,row in ipairs(team and team.items or {}) do
            if row.jobId==jobId then return true end
        end
    end
    for _,other in ipairs(state.employment.staff) do
        if other~=w and other.status=="employed" then
            if other.assignment and other.assignment.jobId==jobId then return true end
            for _,row in ipairs(Schedule.ensure(other).items) do if row.jobId==jobId then return true end end
        end
    end
    return false
end

function Schedule.canQueueTeam(state,jobId,machineId)
    local team=Schedule.team(state)
    local job=Schedule.job(state,jobId)
    local machine=Fleet.byId(state,machineId)
    if not team then return false,"The shop schedule is unavailable." end
    if not job then return false,"Choose an accepted job." end
    if not Schedule.stockArrived(job) then return false,"Wait until every skid for this job has been unloaded at the shop." end
    if not machine or machine.modelId~="polar_115" or machine.status~="installed" then
        return false,"Choose an installed cutter."
    end
    local _,total,pallet=Schedule.progress(job)
    if total==0 or not pallet then return false,"This job's production and wrapping are already complete." end
    if pallet.status=="spoiled_discarded" or not pallet.paper then
        return false,"This job has no available production work."
    end
    if Schedule.claimed(state,nil,jobId) then return false,"This job is already queued or assigned." end
    if #team.items>=Schedule.MAX_TEAM_JOBS then return false,"The shared schedule can queue up to 384 jobs." end
    if team.nextId>=1000000 then return false,"The shop schedule is full." end
    return true,"Ready to add. Any qualified worker can take this job on their next shift."
end

local finish
function Schedule.teamCommand(state,intent,now)
    local team=Schedule.team(state)
    if not team then return false,"The shop schedule is unavailable." end
    if intent.kind=="set_team_schedule" then
        if team.enabled==intent.enabled then
            return true,intent.enabled and "Schedule is already running." or "Schedule is already paused."
        end
        team.enabled=intent.enabled
        team.revision=team.revision+1
        return true,intent.enabled and "Schedule resumed for both shifts." or "Schedule paused. Current jobs finish safely."
    elseif intent.kind=="queue_team_job" then
        for _,row in ipairs(team.items) do
            if row.jobId==intent.jobId then return true,"This job is already on the schedule." end
        end
        local okay,message=Schedule.canQueueTeam(state,intent.jobId,intent.machineId)
        if not okay then return false,message end
        team.items[#team.items+1]={id=string.format("TEAM-TASK-%06d",team.nextId),
            jobId=intent.jobId,machineId=intent.machineId,addedAtHours=now}
        team.nextId=team.nextId+1
        team.revision=team.revision+1
        return true,"Job added to the shop schedule. Day and night shifts share this list."
    end
    if intent.expectedRevision~=team.revision then
        return false,"The schedule changed. Review the current list and try again."
    end
    local index
    for i,row in ipairs(team.items) do if row.id==intent.itemId then index=i;break end end
    if not index then return false,"That job has already left the schedule." end
    if intent.kind=="remove_team_job" then
        if Schedule.claimed(state,nil,team.items[index].jobId,true) then
            return false,"An employee is working on this job. It will stay in the shared schedule and continue across shifts."
        end
        finish(state,team,index,"removed",now)
        return true,"Job removed from the schedule."
    elseif intent.kind=="move_team_job" then
        if Schedule.claimed(state,nil,team.items[index].jobId,true) then
            return false,"An employee is working on this job. Its place in the shared schedule is locked until handoff."
        end
        local target=index+intent.direction
        if target<1 or target>#team.items then return false,"This job is already at the end of the list." end
        if Schedule.claimed(state,nil,team.items[target].jobId,true) then
            return false,"An employee is working on the neighboring job. Its place in the shared schedule is locked until handoff."
        end
        team.items[index],team.items[target]=team.items[target],team.items[index]
        team.revision=team.revision+1
        return true,"Schedule order updated."
    end
    return false,"Unknown schedule action."
end

local function returnIneligibleTeamJobs(state,w)
    local q=Schedule.ensure(w)
    local removed=0
    for index=#q.items,1,-1 do
        local row=q.items[index]
        if row.teamTaskId then
            local job=Schedule.job(state,row.jobId)
            local _,_,pallet=Schedule.progress(job)
            local allowed=job and Schedule.skillAllows(w,job,Schedule.stage(job,pallet))
            if job and pallet and not allowed then
                table.remove(q.items,index);removed=removed+1
            end
        end
    end
    if removed>0 then
        q.revision=q.revision+1
        w._scheduleRetryAtHours=nil;w._waitingMachineId=nil
        w.activity="Advanced job returned to the shared schedule for a skilled worker"
    end
    return removed>0
end
local function claimTeamJob(state,w,now,allowQueued)
    local team=Schedule.team(state)
    local q=Schedule.ensure(w)
    if not team or not team.enabled or (#q.items>0 and not allowQueued)
        or #q.items>=Schedule.MAX_JOBS then return false end
    for index,row in ipairs(team.items) do
        if not hasQueuedJob(q,row.jobId) and not Schedule.claimed(state,w,row.jobId,true) then
            local job=Schedule.job(state,row.jobId)
            local _,_,pallet=Schedule.progress(job)
            local stage=Schedule.stage(job,pallet)
            local allowed=job and Schedule.skillAllows(w,job,stage)
            if allowed and #q.items<Schedule.MAX_JOBS and q.nextId<1000000 then
                local _,machine,readyPallet,reason=Schedule.resolve(state,w,row)
                if not reason and machine and readyPallet then
                    local mirror={id=string.format("TASK-%06d",q.nextId),jobId=row.jobId,
                        machineId=row.machineId,addedAtHours=row.addedAtHours,
                        teamTaskId=row.id,teamWorkerId=w.id}
                    table.insert(q.items,allowQueued and 1 or (#q.items+1),mirror)
                    q.nextId=q.nextId+1
                    q.revision=q.revision+1
                    w._scheduleRetryAtHours=nil
                    w._waitingMachineId=nil
                    return true,mirror,job,machine,readyPallet
                end
            end
        end
    end
    return false
end
function Schedule.canQueue(state,w,jobId,machineId)
    if w.status~="employed" or w.terminationRequested then return false,"Choose a current employee." end
    local job=Schedule.job(state,jobId)
    local machine=Fleet.byId(state,machineId)
    if not job then return false,"Choose an accepted job." end
    if not Schedule.stockArrived(job) then return false,"Wait until every skid for this job has been unloaded at the shop." end
    if not machine or machine.modelId~="polar_115" or machine.status~="installed" then return false,"Choose an installed cutter." end
    local _,total,p=Schedule.progress(job)
    if total==0 or not p then return false,"This job's production and wrapping are already complete." end
    local stage=Schedule.stage(job,p)
    if stage=="cutter" and (not p.paper or (p.remainingSheets or 0)<=0 and p.location~="at_cutter") then
        return false,"This job has no available cutter work order."
    end
    if Schedule.claimed(state,w,jobId) then return false,"This job is assigned to another employee." end
    for _,row in ipairs(Schedule.ensure(w).items) do if row.jobId==jobId then return false,"This job is already in the schedule." end end
    if #w.schedule.items>=Schedule.MAX_JOBS then return false,"An employee can queue up to 16 jobs." end
    return true,"Ready to add. The employee will finish production for every skid, then wrap the whole order."
end
finish=function(state,q,index,result,now)
    local row=table.remove(q.items,index)
    row.result=result;row.finishedAtHours=math.max(now,row.addedAtHours)
    q.history[#q.history+1]=row
    if #q.history>Schedule.MAX_HISTORY then table.remove(q.history,1) end
    q.revision=q.revision+1
    if row.teamTaskId then
        local team=Schedule.team(state)
        local recorded,removedMaster=false,false
        if team then
            for index,shared in ipairs(team.items) do
                if shared.id==row.teamTaskId then table.remove(team.items,index);removedMaster=true;break end
            end
            for _,old in ipairs(team.history) do if old.id==row.teamTaskId then recorded=true;break end end
        end
        if team and not recorded then
            team.history[#team.history+1]={id=row.teamTaskId,jobId=row.jobId,machineId=row.machineId,
                addedAtHours=row.addedAtHours,finishedAtHours=row.finishedAtHours,
                result=row.result,workerId=row.teamWorkerId}
            if #team.history>Schedule.MAX_HISTORY then table.remove(team.history,1) end
        end
        if team and (removedMaster or not recorded) then team.revision=team.revision+1 end
    end
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
        finish(state,q,index,"removed",now);w._scheduleRetryAtHours=nil;w._waitingMachineId=nil;return true,"Job removed from this employee's schedule."
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
    local team=Schedule.team(state)
    local hasTeamMirror=false
    for _,row in ipairs(q.items) do if row.teamTaskId then hasTeamMirror=true;break end end
    if w.status~="employed" or w.terminationRequested or w.stopRequested or w.assignment or w.training
        or not w.visible or not w.clockedIn or not Contracts.onShift(w.contract,now) then return false end
    if Payroll.balance(w,now,false)>0 then w.activity="Waiting for overdue wages";return false end
    if w._scheduleRetryAtHours and now<w._scheduleRetryAtHours then return false end
    local releasedIneligible=returnIneligibleTeamJobs(state,w)
    if not q.enabled and not (team and team.enabled and (#team.items>0 or hasTeamMirror)) then
        return releasedIneligible
    end
    claimTeamJob(state,w,now)
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
            finish(state,q,scanIndex,completed and "complete" or "unavailable",now);changed=true
        else
            local _,total,p=Schedule.progress(job)
            if not p then finish(state,q,scanIndex,total>0 and "complete" or "unavailable",now);changed=true
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
                    local stage=Schedule.stage(job,readyPallet)
                    w.assignment={jobId=job.id,palletId=readyPallet.id,cutterMachineId=row.machineId,
                        machineId=machine.id,machineModel=machine.modelId,scheduleItemId=row.id}
                    w._blockedWorkHours=0
                    w._waitingMachineId=nil
                    w.activity="Scheduled job - walking to "..(stage=="cutter" and "cutter"
                        or stage=="press" and "printing press" or "skid wrapper")
                    return true
                end
            end
        end
    end
    if lastBlocked then
        local claimed,row,job,machine,readyPallet=claimTeamJob(state,w,now,true)
        if claimed and row and job and machine and readyPallet then
            local stage=Schedule.stage(job,readyPallet)
            w.assignment={jobId=job.id,palletId=readyPallet.id,cutterMachineId=row.machineId,
                machineId=machine.id,machineModel=machine.modelId,scheduleItemId=row.id}
            w._blockedWorkHours=0
            w._waitingMachineId=nil
            w.activity="Scheduled job - walking to "..(stage=="cutter" and "cutter"
                or stage=="press" and "printing press" or "skid wrapper")
            return true
        end
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
    if not assignment or not assignment.scheduleItemId or not row
        or row.id~=assignment.scheduleItemId then return false end
    if row.teamTaskId then
        local team=Schedule.team(state)
        if not team or not team.enabled or #team.items<2 then return false end
        local sharedIndex
        for index,shared in ipairs(team.items) do
            if shared.id==row.teamTaskId then sharedIndex=index;break end
        end
        if not sharedIndex then return false end
        local shared=table.remove(team.items,sharedIndex)
        team.items[#team.items+1]=shared
        team.revision=team.revision+1
        table.remove(q.items,1)
        q.revision=q.revision+1
    else
        if not q.enabled or #q.items<2 then return false end
        table.remove(q.items,1)
        q.items[#q.items+1]=row
        q.revision=q.revision+1
    end
    w.assignment=nil
    w._blockedWorkHours=0
    w._scheduleRetryAtHours=nil
    w._waitingMachineId=nil
    w.phase="idle"
    w.activity="Job blocked; trying the next scheduled job"
    return true
end
function Schedule.releaseBlockedTeamMirror(w,itemId)
    local q=Schedule.ensure(w)
    for index,row in ipairs(q.items) do
        if row.id==itemId and row.teamTaskId and row.teamWorkerId==w.id then
            table.remove(q.items,index)
            q.revision=q.revision+1
            w.assignment=nil
            w._blockedWorkHours=0
            w._scheduleRetryAtHours=nil
            w._waitingMachineId=nil
            w.phase="idle"
            w.activity="Packaging out of stock; trying the next team job"
            return true
        end
    end
    return false
end
return Schedule
