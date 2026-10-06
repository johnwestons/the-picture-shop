local Machine=require("src.machine")
local Fleet=require("src.machine_fleet")
local Pallets=require("src.pallet_state")
local Paper=require("src.paper_work")
local Config=require("src.config")
local Labor=require("src.employee_labor")
local Work={}
local busy={armed=true,cutting=true,loading=true,positioning=true,unloading=true,lift_returning=true,resetting=true}
function Work.machine(w) return w.assignment and Machine.forId(w.assignment.machineId) end
function Work.safe(w)
    local m=Work.machine(w)
    return not (w.reserved and m and busy[m.step])
end
function Work.release(state,w)
    if not Work.safe(w) then return false end
    local m=Work.machine(w)
    if w.reserved and m then Fleet.withUnit(state,w.assignment.machineId,function() m.releaseOperator(state) end) end
    w.reserved=false;w.workFrame=nil;w._workClock=0
    return true
end
function Work.update(state,w,dt,context)
    if not w.assignment then return false end
    local assignment=w.assignment
    local item=Pallets.find(state,assignment.palletId)
    local machine=Fleet.byId(state,assignment.machineId)
    if not item or not item.job or item.job.id~=assignment.jobId or not machine or machine.status~="installed" then
        if Work.safe(w) then Work.release(state,w);w.assignment=nil;w.activity="Assignment no longer available" end
        return true
    end
    local pallet=item.pallet
    if pallet.status=="cut" or pallet.status=="printed" or pallet.status=="wrapped" then
        if Work.safe(w) then Work.release(state,w);w.assignment=nil;w.activity="Cutting complete - ready for next stage" end
        return true
    end
    if not w.reserved then
        local eligible=false
        Fleet.withUnit(state,machine.id,function()
            for _,candidate in ipairs(Machine.forId(machine.id).availablePapers(state)) do
                if candidate.pallet.id==pallet.id then eligible=true;break end
            end
        end)
        if not eligible then w.phase="idle";w.activity="Stage assigned pallet beside this cutter";return false end
    end
    if not w.reserved then
        if context.canClaim and not context.canClaim(machine.id) then
            w.activity="Waiting for a player to release the cutter";return false
        end
        local m=Machine.forId(machine.id)
        -- Preserve another pallet's live cutter session. NPC assignment never
        -- resets a human's production or borrows a human player ID.
        if m.pallet and m.pallet.id~=pallet.id and m.step~="idle" and m.step~="finished" then
            w.activity="Another pallet is on the cutter";return false
        end
        w.reserved=true
    end
    local goal=context.operatorPoint(machine.id,w)
    if not goal then w.activity="Cutter access is blocked";return false end
    if not context.move(w,goal,dt) then
        w.phase="walking";w.activity="Walking to cutter";return false
    end
    w.phase="working";w.activity="Operating cutter"
    local pose=machine.world or state.cutter
    local dx,dy=pose.x-w.x,pose.y-w.y
    local length=math.sqrt(dx*dx+dy*dy)
    if length>.01 then w.intentX,w.intentY=dx/length,dy/length end
    w._workClock=(w._workClock or 0)+dt
    local delay=Labor.actionDelay(w)
    local changed=false
    Fleet.withUnit(state,machine.id,function()
        local m=Machine.forId(machine.id)
        if not m.pallet then m.open(state) end
        if m.emergencyStopped or not m.barrierClear or m.step=="blocked" then
            w.activity="Cutter safety/service needs player attention";w.workFrame=1;return
        end
        if m.pallet and m.pallet.id~=pallet.id and m.step~="idle" and m.step~="finished" then
            w.activity="Another pallet is on the cutter";return
        end
        if m.step=="armed" or m.step=="cutting" then w.workFrame=4;return end
        if m.step=="loading" or m.step=="positioning" or m.step=="unloading" or m.step=="lift_returning" then w.workFrame=3;return end
        if m.step=="clamped" then w.workFrame=4
        elseif m.step=="loaded" then w.workFrame=2
        elseif m.step=="cut_complete" or m.step=="repeat_ready" then w.workFrame=1
        else w.workFrame=3 end
        if w._workClock<delay then return end
        w._workClock=0
        local prior=state.message
        if m.step=="idle" or m.step=="finished" then
            changed=m.load(state,pallet.id)
            if not changed then w.activity="Stage assigned pallet beside this cutter" end
        elseif m.step=="repeat_ready" then changed=m.repeatLift(state)
        elseif m.step=="loaded" then
            local cut=Paper.currentCut(m.paper)
            if not cut then w.activity="Cut program needs player attention";return end
            if m.paper.orientation~=cut.orientation then changed=m.rotate(state)
            elseif m.programIndex~=m.paper.activeCut then changed=m.selectProgram(m.paper.activeCut,state)
            elseif math.abs(m.gauge-cut.gauge)>.001 then changed=m.setGauge(cut.gauge,state)
            else changed=m.position(state) end
        elseif m.step=="positioned" then changed=m.toggleClamp(state)
        elseif m.step=="clamped" then changed=m.pressBothControls(state)
        elseif m.step=="cut_complete" then
            changed=m.unload(state)
            if not changed then w.activity="Clear the cutter's output area" end
        end
        -- Cutter operations use the same domain messages as player operations.
        -- Keep background employee steps from replacing the owner's menu text.
        state.message=prior
    end)
    return changed
end
return Work
