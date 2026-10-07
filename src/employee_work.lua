local Machine=require("src.machine")
local Fleet=require("src.machine_fleet")
local Pallets=require("src.pallet_state")
local Paper=require("src.paper_work")
local Labor=require("src.employee_labor")
local Schedule=require("src.employee_schedule")
local Windmill=require("src.windmill")
local Plates=require("src.plate_service")
local Wrapper=require("src.wrapper")
local Work={}
local cutterBusy={armed=true,cutting=true,loading=true,positioning=true,unloading=true,lift_returning=true,resetting=true}
local stageModel={cutter="polar_115",press="heidelberg_10x15",wrapping="skid_wrapper"}

function Work.machine(w) return w.assignment and Machine.forId(w.assignment.machineId) end
function Work.safe(w,state)
    local assignment=w.assignment
    if not (w.reserved and assignment) then return true end
    local fleet=state and Fleet.byId(state,assignment.machineId)
    local model=assignment.machineModel or (fleet and fleet.modelId) or "polar_115"
    if model=="polar_115" and cutterBusy[Machine.forId(assignment.machineId).step] then return false end
    if model=="heidelberg_10x15" then
        if state then
            local busy=false
            Fleet.withUnit(state,assignment.machineId,function()
                busy=Windmill.ensure(state).status=="production"
            end)
            if busy then return false end
        end
    elseif model=="skid_wrapper" then
        if state then
            local busy=false
            Fleet.withUnit(state,assignment.machineId,function()
                busy=Wrapper.forId(assignment.machineId).isActive()
            end)
            if busy then return false end
        end
    end
    return true
end

function Work.release(state,w)
    if not Work.safe(w,state) then return false end
    local assignment=w.assignment
    local machine=assignment and Fleet.byId(state,assignment.machineId)
    if w.reserved and machine then
        Fleet.withUnit(state,assignment.machineId,function()
            if machine.modelId=="polar_115" then Machine.forId(machine.id).releaseOperator(state)
            elseif machine.modelId=="heidelberg_10x15" then Windmill.releaseOperator(state)
            elseif machine.modelId=="skid_wrapper" then
                local runtime=Wrapper.forId(machine.id)
                if not runtime.isActive() then
                    local prior=state.message;runtime.reset(state);state.message=prior
                end
            end
        end)
    end
    w.reserved=false;w.workFrame=nil;w._workClock=0
    return true
end

local function actionReady(w,dt,skill)
    w._workClock=(w._workClock or 0)+dt
    local delay=.32+(100-(skill or 50))/100*.70+(100-(w.focus or 100))/100*.40
    if w._workClock<delay then return false end
    w._workClock=0
    return true
end

local function cutterStep(state,w,dt,machine,pallet)
    local changed,blocked=false,nil
    Fleet.withUnit(state,machine.id,function()
        local m=Machine.forId(machine.id)
        if not m.pallet then m.open(state) end
        if m.emergencyStopped or not m.barrierClear or m.step=="blocked" then
            w.activity="Cutter safety/service needs player attention";w.workFrame=1
            blocked="Cutter safety/service needs player attention";return
        end
        if m.pallet and m.pallet.id~=pallet.id and m.step~="idle" and m.step~="finished" then
            w.activity="Another pallet is on the cutter";blocked="Another pallet is on the cutter";return
        end
        if m.step=="armed" or m.step=="cutting" then w.workFrame=4;return end
        if m.step=="loading" or m.step=="positioning" or m.step=="unloading" or m.step=="lift_returning" then
            w.workFrame=3;return
        end
        if m.step=="clamped" then w.workFrame=4
        elseif m.step=="loaded" then w.workFrame=2
        elseif m.step=="cut_complete" or m.step=="repeat_ready" then w.workFrame=1
        else w.workFrame=3 end
        if not actionReady(w,dt,w.cutterSkill) then return end
        local prior=state.message
        if m.step=="idle" or m.step=="finished" then
            changed=m.load(state,pallet.id)
            if not changed then
                w.activity="Stage assigned pallet beside this cutter";blocked="Assigned pallet is not staged beside this cutter"
                state.message=prior;return
            end
        elseif m.step=="repeat_ready" then changed=m.repeatLift(state)
        elseif m.step=="loaded" then
            local cut=Paper.currentCut(m.paper)
            if not cut then
                w.activity="Cut program needs player attention";blocked="Cut program needs player attention"
                state.message=prior;return
            end
            if m.paper.orientation~=cut.orientation then changed=m.rotate(state)
            elseif m.programIndex~=m.paper.activeCut then changed=m.selectProgram(m.paper.activeCut,state)
            elseif math.abs(m.gauge-cut.gauge)>.001 then changed=m.setGauge(cut.gauge,state)
            else changed=m.position(state) end
        elseif m.step=="positioned" then changed=m.toggleClamp(state)
        elseif m.step=="clamped" then changed=m.pressBothControls(state)
        elseif m.step=="cut_complete" then
            changed=m.unload(state)
            if not changed then
                w.activity="Clear the cutter's output area";blocked="Clear the cutter output area"
                state.message=prior;return
            end
        end
        state.message=prior
    end)
    return changed,blocked
end

local function plateStep(state,w,job,color,dt)
    local plates=Plates.ensureJob(job)
    local plate=plates[color]
    if not plate then return false,"No print plate is available for this color" end
    if plate.status=="unprepared" then
        local ok,reason=Plates.beginInHouse(state,job,color)
        if not ok then return false,reason end
        return false
    elseif plate.status=="ordered" then
        return false,"Waiting for the ordered print plate"
    elseif plate.status=="processing" then
        local action=Plates.actionFor(plate)
        if not action then return false,"Print plate needs prepress attention" end
        if not actionReady(w,dt,w.pressSkill) then return false end
        local quality=math.min(.99,.70+(w.pressSkill or 0)/350)
        local ok,reason=Plates.process(plate,action,quality)
        if not ok then return false,reason end
        Windmill.bumpNetworkRevision()
        return plate.status=="ready"
    end
    return plate.status=="ready" and plate.mounted,"Mount the print plate before running the press"
end

local function pressStep(state,w,machine,pallet,job,dt)
    local changed,blocked=false,nil
    w.workFrame=3
    Fleet.withUnit(state,machine.id,function()
        local process,currentJob,currentPallet=Windmill.current(state)
        if process.palletId and process.palletId~=pallet.id then
            blocked="Another pallet is loaded in the printing press";return
        end
        if process.emergency then blocked="Printing press emergency stop needs attention";return end
        if not process.palletId then
            w.activity="Preparing the next print plate"
            local color=math.max(1,(pallet.press and pallet.press.completedColors or 0)+1)
            local okay,reason=plateStep(state,w,job,color,dt)
            if not okay then blocked=reason;return end
            if not actionReady(w,dt,w.pressSkill) then return end
            local loaded,detail=Windmill.load(state,pallet.id)
            if not loaded then blocked=detail;return end
            changed=true;return
        end
        if process.status=="production" then
            w.activity="Running the Heidelberg printing press";w.workFrame=4;return
        end
        if process.status=="pass_complete" then
            w.activity="Cleaning the press after a color pass"
            if not actionReady(w,dt,w.pressSkill) then return end
            changed,blocked=Windmill.cleanAndUnload(state)
            return
        end
        if process.status=="stock_shortage" then blocked="Press stock is exhausted; owner attention required";return end
        if process.status=="stopped" then blocked="Press safety needs owner attention";return end
        if process.status=="proof" and (process.proofQuality or 0)<.82 then
            blocked="Press proof is below approval quality; owner attention required";return
        end
        if process.status=="proof" then
            w.activity="Checking the print proof"
            if not actionReady(w,dt,w.pressSkill) then return end
            local ok,reason=Windmill.verifyArtwork(state)
            if not ok then blocked=reason;return end
            changed,blocked=Windmill.approveProof(state)
            return
        end
        if process.status=="approved" then
            w.activity="Setting up the printing press"
            if not process.motor then changed,blocked=Windmill.control(state,"motor");return end
            if not process.feeder then changed,blocked=Windmill.control(state,"feeder");return end
            if not process.impression then changed,blocked=Windmill.control(state,"impression");return end
            if not actionReady(w,dt,w.pressSkill) then return end
            changed,blocked=Windmill.startProduction(state)
            return
        end
        if process.status=="idle" then
            blocked="Loaded press session needs owner attention";return
        end
        if process.status~="setup" then
            blocked="Printing press needs service or owner attention";return
        end
        w.activity="Setting up the printing press"
        if not Windmill.setupComplete(state) then
            if not actionReady(w,dt,w.pressSkill) then return end
            local score=math.min(.98,.78+(w.pressSkill or 0)/500)
            for _,task in ipairs(Windmill.setupTasks()) do
                if not process.setup[task] then
                    changed,blocked=Windmill.completeSetup(state,task,score)
                    return
                end
            end
        end
        if not process.motor then changed,blocked=Windmill.control(state,"motor");return end
        if not process.feeder then changed,blocked=Windmill.control(state,"feeder");return end
        if not process.impression then changed,blocked=Windmill.control(state,"impression");return end
        if not actionReady(w,dt,w.pressSkill) then return end
        changed,blocked=Windmill.takeProof(state)
    end)
    return changed,blocked
end

local function wrappingStep(state,w,machine,pallet,dt)
    local changed,blocked=false,nil
    w.workFrame=3
    Fleet.withUnit(state,machine.id,function()
        local runtime=Wrapper.forId(machine.id)
        if runtime.pallet and runtime.pallet.id==pallet.id and runtime.isActive() then
            w.activity="Wrapping finished pallet";w.workFrame=4;return
        end
        w.activity="Preparing finished pallet for wrapping"
        if not actionReady(w,dt,w.wrappingSkill) then return end
        if runtime.step=="finished" then runtime.reset(state) end
        if runtime.selectedPalletId~=pallet.id then
            changed=runtime.selectPallet(state,pallet.id)
            if not changed then blocked=state.message or "Select the finished pallet for wrapping";return end
        end
        changed,blocked=runtime.start(state)
    end)
    return changed,blocked
end

function Work.update(state,w,dt,context)
    if not w.assignment then return false end
    local assignment=w.assignment
    local item=Pallets.find(state,assignment.palletId)
    if not item or not item.job or item.job.id~=assignment.jobId then
        if Work.safe(w,state) then Work.release(state,w);w.assignment=nil;w.activity="Assignment no longer available" end
        return true
    end
    local pallet,job=item.pallet,item.job
    if pallet.status=="wrapped" or pallet.wrapped then
        if Work.safe(w,state) then Work.release(state,w);w.assignment=nil;w.activity="Pallet wrapped and ready for shipping" end
        return true
    end
    local stage=Schedule.stage(job,pallet)
    local model=stageModel[stage]
    if not model then
        if Work.safe(w,state) then Work.release(state,w);w.assignment=nil end
        return true
    end
    local row={jobId=job.id,machineId=assignment.cutterMachineId or assignment.machineId}
    local resolvedStage,resolvedMachine,_,stageBlocked=Schedule.resolve(state,w,row,pallet.id)
    if stageBlocked then
        w.activity=stageBlocked
        if Work.safe(w,state) then
            Work.release(state,w)
            -- A one-off assignment should wait for its pallet to be staged.
            -- Scheduled work can clear the active assignment so the queue can
            -- try another ready job and resume this item on a later pass.
            if assignment.scheduleItemId then w.assignment=nil end
        end
        return false,stageBlocked
    end
    if resolvedStage then stage=resolvedStage;model=stageModel[stage] end
    local machine=Fleet.byId(state,assignment.machineId)
    if not machine or machine.status~="installed" or machine.modelId~=model
        or resolvedMachine and resolvedMachine.id~=machine.id then
        if not Work.safe(w,state) then w.activity="Finishing a safe machine cycle";return false end
        Work.release(state,w)
        local nextMachine=resolvedMachine
        if not nextMachine then
            w.activity="Waiting for the next production machine"
            if not assignment.scheduleItemId then w.assignment=nil end
            return false,"Waiting for the next production machine"
        end
        assignment.machineId=nextMachine.id;assignment.machineModel=model
        machine=nextMachine
    end
    if not w.reserved then
        if context.canClaim and not context.canClaim(machine.id) then
            w.activity="Waiting for the player to release this machine";return false,"Waiting for the player to release this machine"
        end
        if stage=="cutter" then
            local runtime=Machine.forId(machine.id)
            if runtime.pallet and runtime.pallet.id~=pallet.id and runtime.step~="idle" and runtime.step~="finished" then
                w.activity="Another pallet is on the cutter";return false,"Another pallet is on the cutter"
            end
        elseif stage=="press" then
            local process
            Fleet.withUnit(state,machine.id,function() process=Windmill.ensure(state) end)
            if process.palletId and process.palletId~=pallet.id and process.status~="idle" then
                w.activity="Another pallet is in the printing press";return false,"Another pallet is in the printing press"
            end
        elseif stage=="wrapping" then
            local busy=false
            Fleet.withUnit(state,machine.id,function() busy=Wrapper.forId(machine.id).isActive() end)
            if busy then w.activity="Another pallet is being wrapped";return false,"Another pallet is being wrapped" end
        end
        assignment.machineModel=model
        w.reserved=true
    end
    local goal=context.operatorPoint(machine.id,w)
    if not goal then
        w.activity="Machine access is blocked";return false,"Machine access is blocked"
    end
    local reached,pathBlocked=context.move(w,goal,dt)
    if not reached then
        w.phase="walking"
        if pathBlocked then w.activity="Machine access is blocked";return false,"Machine access is blocked" end
        w.activity="Walking to "..(stage=="cutter" and "cutter" or stage=="press" and "printing press" or "skid wrapper")
        return false
    end
    w.phase="working"
    local pose=machine.world or goal
    local dx,dy=pose.x-w.x,pose.y-w.y
    local length=math.sqrt(dx*dx+dy*dy)
    if length>.01 then w.intentX,w.intentY=dx/length,dy/length end
    local priorMessage=state.message
    local changed,blocked
    if stage=="cutter" then changed,blocked=cutterStep(state,w,dt,machine,pallet)
    elseif stage=="press" then changed,blocked=pressStep(state,w,machine,pallet,job,dt)
    else changed,blocked=wrappingStep(state,w,machine,pallet,dt) end
    state.message=priorMessage
    return changed,blocked
end

return Work
