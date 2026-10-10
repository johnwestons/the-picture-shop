local Employees=require("src.employees")
local Contracts=require("src.employment_contracts")
local Payroll=require("src.payroll")
local Work=require("src.employee_work")
local Schedule=require("src.employee_schedule")
local Fleet=require("src.machine_fleet")
local Calendar=require("src.business_calendar")
local PlayerController=require("src.player_controller")
local Navigation=require("src.navigation")
local Config=require("src.config")
local Speech=require("src.employee_speech")
local Transport=require("src.employee_pallet_jack")
local AI={}
local Navigator=require("src.npc_navigation")
local GaitMotion=require("src.gait_motion")
local entrance=Config.customer.route[1]
local reception=Config.warehouse.roomScenes and require("src.warehouse_registration").reception or {x=759,y=358}
local applicantWaitSeconds=60
local motion={speed=72,acceleration=600,walkPixelsPerFrame=13,
    gaitSpeedMultipliers={.96,.94,1.04,1.06,.96,.94,1.04,1.06},
    gaitAccelerationMultipliers={.92,.90,1.08,1.10,.92,.90,1.08,1.10}}
local speeds=setmetatable({},{__mode="k"})
local function stop(a)
    PlayerController.stop(a);speeds[a]=nil;a.moving=false
end
local function face(a,x,y)
    local d=math.sqrt(x*x+y*y)
    if d>.001 then a.intentX,a.intentY=x/d,y/d end
end
function AI.findReachablePoint(actor,goals,context)
    return Navigator.findReachablePoint(actor,goals,context)
end
function AI.move(a,goal,dt,context)
    if (a.x-goal.x)^2+(a.y-goal.y)^2<.0001
        and (not context.assets or Navigation.isWalkable(context.assets,a.x,a.y,
            context.obstacles and context.obstacles(a) or {})) then
        stop(a);return true,false
    end
    local motionDt=math.max(0,math.min(.1,dt*(tonumber(context.motionScale) or 1)))
    local gaitSpeed,gaitAcceleration=GaitMotion.sample(a.distance or 0,motion)
    speeds[a]=math.min(motion.speed*gaitSpeed,
        (speeds[a] or 0)+motion.acceleration*gaitAcceleration*motionDt)
    local reached,_,moved,blocked=Navigator.travel(a,goal,speeds[a]*motionDt,motionDt,context)
    a.distance=(a.distance or 0)+moved;a.animationDistance=a.distance
    a.moving=moved>.0001
    a.gaitSpeedMultiplier,a.gaitAccelerationMultiplier=gaitSpeed,gaitAcceleration
    if a.moving then a.idleClock=0
    else a.idleClock=(a.idleClock or 0)+motionDt end
    if reached or moved<.0001 then stop(a) end
    return reached,blocked
end
local function visiting(e)
    for _,a in ipairs(e.applications) do if a.actor.visible then return a end end
end
function AI.receptionOccupied(state) return visiting(Employees.ensure(state))~=nil end
local function applications(state,dt,now,context)
    local e=Employees.ensure(state)
    local present=visiting(e)
    local changed=false
    for _,a in ipairs(e.applications) do
        local actor=a.actor
        if a.status=="visiting" and not actor.visible and not present
            and not context.receptionBusy() and not Calendar.isWeekend(state) then
            actor.visible=true;actor.phase="entering";actor.x,actor.y=entrance.x,entrance.y
            present=a;state.message=a.name.." is applying for a cutter job. Request a resume or dismiss them; they will leave after one minute if not spoken to."
            changed=true
        end
        if actor.visible then
            if actor.phase=="entering" and AI.move(actor,reception,dt,context) then
                actor.phase="waiting";actor.arrivedAtHours=now;actor.waitTimer=0;face(actor,-1,0)
            elseif actor.phase=="waiting" then
                stop(actor);actor.idleClock=actor.idleClock+dt
                actor.waitTimer=(actor.waitTimer or 0)+dt
                if actor.waitTimer>=applicantWaitSeconds then
                    a.status="withdrawn";a.revision=a.revision+1
                    actor.phase="leaving"
                    state.message=a.name.." left after waiting one minute without being spoken to."
                    changed=true
                end
            elseif actor.phase=="leaving" and AI.move(actor,entrance,dt,context) then
                actor.visible=false;actor.phase="hidden";stop(actor)
            end
        end
    end
    return changed
end
local function breakChoice(w,now)
    local elapsed=now-Contracts.shiftDay(w.contract,now)*24-w.contract.startHour
    local duration=Contracts.duration(w.contract)
    for _,b in ipairs({{at=2,bit=1,kind="rest",duration=.25},{at=4,bit=2,kind="meal",duration=.5},
        {at=6,bit=4,kind="rest",duration=.25},{at=10,bit=8,kind="rest",duration=.25}}) do
        if b.at<duration and (b.kind~="meal" or duration>=6) and elapsed>=b.at
            and math.floor(w.breaksTaken/b.bit)%2==0 then return b end
    end
    if w.fatigue>=70 or w.focus<=40 then return {bit=0,kind="rest",duration=.25} end
end
local function beginBreak(state,w,b,context)
    if not Work.release(state,w,context) then return false end
    w._trainingMachineId=nil
    w.breaksTaken=w.breaksTaken+(b.bit or 0);w.breakKind=b.kind;w.breakRemaining=b.duration
    local seat=context.freeSeat(w)
    w.seatBay=seat and seat.bayId or nil;w.phase=seat and "break_walk" or "break"
    w.activity=seat and "Walking to breakroom" or "Resting beside workstation"
    return true
end
local function trainingStep(state,w,dt,hours,context)
    local training=w.training
    if not training then return false end
    local model=training.skill=="cutter" and "polar_115"
        or training.skill=="press" and "heidelberg_10x15" or "skid_wrapper"
    local units=Fleet.installedUnits(state,model)
    if #units==0 then
        w._trainingMachineId=nil
        w.phase="idle";w.activity="Training paused - the required machine is unavailable"
        return false
    end
    local machine,goal
    for _,candidate in ipairs(units) do
        if not Employees.reservation(state,candidate.id,nil,w.id)
            and (not context.canClaim or context.canClaim(candidate.id)) then
            local point=context.operatorPoint and context.operatorPoint(candidate.id,w)
            if point then machine,goal=candidate,point;break end
        end
    end
    if not machine then
        w._trainingMachineId=nil
        w.phase="idle";w.activity="Waiting for an available training machine"
        return false
    end
    w._trainingMachineId=machine.id
    local reached,blocked=AI.move(w,goal,dt,context)
    if not reached then
        w.phase="walking";w.activity=blocked and "Training access is blocked" or "Walking to training machine"
        return false
    end
    w.phase="working"
    local pose=context.machinePose and context.machinePose(machine.id) or machine.world
    if pose then
        local dx,dy=pose.x-w.x,pose.y-w.y
        local length=math.sqrt(dx*dx+dy*dy)
        if length>.01 then w.intentX,w.intentY=dx/length,dy/length end
    end
    w._trainingClock=(w._trainingClock or 0)+hours
    if w._trainingClock<.05 then
        local label=training.skill=="cutter" and "on the paper cutter"
            or training.skill=="press" and "on the printing press" or "on the skid wrapper"
        w.activity=string.format("Training %s: %.1f paid hours remaining",
            label,training.remainingHours)
        return false
    end
    local elapsed=w._trainingClock
    w._trainingClock=0
    training.remainingHours=math.max(0,training.remainingHours-elapsed)
    if training.remainingHours<=0.000001 then
        local field=training.skill=="cutter" and "cutterSkill"
            or training.skill=="press" and "pressSkill" or "wrappingSkill"
        w[field]=math.max(w[field],training.target)
        local label=training.skill=="cutter" and "paper cutter"
            or training.skill=="press" and "printing press" or "pallet wrapping"
        w.training=nil;w._trainingClock=nil;w._trainingMachineId=nil;w.phase="idle"
        w.activity=label:gsub("^%l",string.upper).." training complete"
        return true
    end
    local label=training.skill=="cutter" and "on the paper cutter"
        or training.skill=="press" and "on the printing press" or "on the skid wrapper"
    w.activity=string.format("Training %s: %.1f paid hours remaining",label,training.remainingHours)
    return true
end
function AI.worker(state,w,dt,now,context)
    if w.greetingUntilHours and now>=w.greetingUntilHours then
        w.greetingKind,w.greetingUntilHours=nil,nil
    end
    local day=Contracts.shiftDay(w.contract,now)
    local onShift=w.status=="employed" and not w.terminationRequested
        and w.sentHomeShiftDay~=day and Contracts.onShift(w.contract,now)
    local overdue=Payroll.overdueSince(w,now)
    if overdue and now-overdue>=168 and w.status=="employed" then w.terminationRequested=true;w.resigning=true;onShift=false end
    if onShift and not w.visible then
        w.visible=true;w.phase="entering";w.x,w.y=entrance.x,entrance.y;w.clockedIn=true
        w.greetingKind=now%24<12 and 1 or 2
        w.greetingUntilHours=now+Speech.GREETING_SECONDS*24/Calendar.secondsPerDay(state)
        w.activity=w.assignment and "Resuming unfinished job" or "Arriving for shift"
        if w.shiftDay~=day then w.shiftDay=day;w.breaksTaken=0;w.fatigue=math.max(0,w.fatigue-60);w.focus=math.min(100,w.focus+50) end
    end
    if not w.visible then
        if w.stopRequested and Work.safe(w,state) then Work.release(state,w);w.assignment=nil;w.stopRequested=false;return true end
        if w.terminationRequested then w.status=w.resigning and "resigned" or "dismissed" end
        return false
    end
    local droppedCarriedPallet=false
    if not onShift or w.stopRequested then
        if Transport.owns(state,w) then
            Transport.release(state,w,context);droppedCarriedPallet=true
        end
        if w.carryingPalletId then droppedCarriedPallet=Work.dropCarried(state,w,context)==true end
        w._trainingMachineId=nil
        if Work.safe(w,state) then
            Work.release(state,w);w.seatBay=nil;w.breakKind=nil
            if w.stopRequested then w.assignment=nil;w.stopRequested=false end
            if not onShift then
                local rolledOver=Schedule.rollover(state,w,now)
                if w.phase~="leaving" then
                    w.greetingKind=3
                    w.greetingUntilHours=now+Speech.GREETING_SECONDS*24/Calendar.secondsPerDay(state)
                end
                w.phase="leaving";w.clockedIn=false
                w.activity=rolledOver and "Handing unfinished jobs to the next shift"
                    or (w.assignment and "Off shift - unfinished job resumes next working shift" or "Shift ended")
            end
        else
            w.activity="Finishing safe machine cycle";return false
        end
    end
    if w.phase=="leaving" then
        local goal=context.exitPoint and context.exitPoint(w,dt) or entrance
        local reached,blocked=AI.move(w,goal,dt,context)
        if blocked then w.activity="Exit path blocked - clear the entrance" end
        if reached
            and (not w.greetingUntilHours or now>=w.greetingUntilHours) then
            w.visible=false;w.phase="hidden";w.clockedIn=false;stop(w)
            if w.terminationRequested then w.status=w.resigning and "resigned" or "dismissed" end
        end
        return droppedCarriedPallet
    end
    if droppedCarriedPallet then return true end
    local hours=dt*24/Calendar.secondsPerDay(state)
    if w.phase=="break_walk" then
        local seat=context.seat(w.seatBay)
        if not seat then w.seatBay=nil;w.phase="break"
        elseif AI.move(w,seat,dt,context) then
            w.phase="break";stop(w);face(w,w.seatBay=="front_left" and -1 or 1,0)
        end
    elseif w.phase=="break" then
        stop(w);w.idleClock=w.idleClock+dt
        local recovery=w.seatBay and 1 or .5
        w.fatigue=math.max(0,w.fatigue-160*hours*recovery)
        w.focus=math.min(100,w.focus+128*hours*recovery)
        w.breakRemaining=math.max(0,w.breakRemaining-hours)
        w.activity=w.breakKind=="meal" and "Unpaid meal break" or "Paid rest break"
        if w.breakRemaining<=.000001 then w.phase="idle";w.seatBay=nil;w.breakKind=nil end
    else
        local b=breakChoice(w,now)
        if (w.fatigue>=90 or w.focus<=20) then b={bit=0,kind="rest",duration=.25} end
        if b and Work.safe(w,state) then beginBreak(state,w,b,context)
        elseif overdue then
            local parked=Transport.owns(state,w)
            if parked then Transport.release(state,w,context) end
            if Work.safe(w,state) then Work.release(state,w);w.phase="idle";stop(w);w.activity="Waiting for overdue wages" end
            if parked then return true end
        elseif w.training then
            local progressed=trainingStep(state,w,dt,hours,context)
            if w.phase=="working" then w.idleClock=w.idleClock+dt end
            w.fatigue=math.min(100,w.fatigue+hours*(w.phase=="working" and 5 or 2))
            w.focus=math.max(0,w.focus-hours*(w.phase=="working" and 3 or 1))
            return progressed
        else
            local scheduleChanged=Schedule.advance(state,w,now)
            if w.assignment then
                local workContext={canClaim=context.canClaim,operatorPoint=context.operatorPoint,machinePose=context.machinePose,
                    motionScale=context.motionScale,jackNavigation=context.jackNavigation,
                    jackApproachPoint=context.jackApproachPoint,jackPickupPoint=context.jackPickupPoint,
                    jackDropPoint=context.jackDropPoint,jackDropClear=context.jackDropClear,
                    jackParkingPoint=context.jackParkingPoint,
                    jackLoadClear=context.jackLoadClear,
                    jackEmergencyDropPoint=context.jackEmergencyDropPoint,
                    palletApproachPoint=context.palletApproachPoint,palletDropPoint=context.palletDropPoint,
                    machinePalletDropPoint=context.machinePalletDropPoint,
                    palletEmergencyDropPoint=context.palletEmergencyDropPoint,
                    move=function(actor,goal,seconds) return AI.move(actor,goal,seconds,context) end}
                local changed,blockedReason=Work.update(state,w,dt,workContext)
                if w.phase=="working" then w.idleClock=w.idleClock+dt end
                local deferred=false
                if blockedReason=="Machine access is blocked" and w.assignment
                    and not w.assignment.scheduleItemId and Work.safe(w,state) then
                    Work.release(state,w)
                    w.assignment=nil
                    w._scheduleRetryAtHours=now+.1
                end
                if blockedReason and w.assignment and w.assignment.scheduleItemId then
                    w._blockedWorkHours=(w._blockedWorkHours or 0)+hours
                    local q=Schedule.ensure(w)
                    local row=q.items[1]
                    local shared=row and row.id==w.assignment.scheduleItemId and row.teamTaskId
                    local team=shared and Schedule.team(state)
                    local hasNext=(team and #team.items>1) or #q.items>1
                    if w._blockedWorkHours>=.1 and hasNext and Work.safe(w,state) then
                        if Work.release(state,w) and Schedule.deferBlocked(state,w) then
                            stop(w);deferred=true
                        end
                    end
                else
                    w._blockedWorkHours=0
                end
                w.fatigue=math.min(100,w.fatigue+hours*(w.phase=="working" and 8 or 3))
                w.focus=math.max(0,w.focus-hours*(w.phase=="working" and 6 or 2))
                return changed or scheduleChanged or deferred
            else
                local point=context.idlePoint(w)
                local q=Schedule.ensure(w)
                if q.enabled and #q.items>0 and w._waitingMachineId and context.operatorPoint then
                    point=context.operatorPoint(w._waitingMachineId,w) or point
                end
                if AI.move(w,point,dt,context) then
                    w.phase="idle";w.idleClock=w.idleClock+dt
                    if not q.enabled then w.activity="Work schedule paused"
                    elseif #q.items==0 and not w._waitingForJack then w.activity=#q.history>0 and "Work schedule complete" or "Waiting for assignment" end
                end
                w.fatigue=math.min(100,w.fatigue+hours)
                return scheduleChanged
            end
        end
    end
    return false
end
function AI.update(state,dt,context)
    local e=Employees.ensure(state)
    local now=Calendar.absoluteHours(state)
    local previous=math.min(now,e.lastAtHours)
    local changed=Employees.advance(state,now)
    local schedulesChanged=Schedule.reconcileCompleted(state,now,function(w)
        if not Work.safe(w,state) then return false end
        Work.release(state,w)
        w.assignment=nil
        w.activity="Scheduled job complete"
        return true
    end)
    if schedulesChanged then changed=true end
    -- Time only advances with the active shop, never from real-world offline
    -- elapsed time. Small slices keep arrivals, breaks, and wage clipping exact.
    local secondsPerHour=Calendar.secondsPerDay(state)/24
    local total=now-previous
    if total<=0 then return changed end
    local at=previous
    while at<now-1e-9 do
        local nextAt=math.min(now,at+.1/secondsPerHour)
        local realDt=(nextAt-at)*secondsPerHour
        if applications(state,realDt,nextAt,context) then changed=true end
        for _,w in ipairs(e.staff) do
            local oldClocked=w.clockedIn
            Payroll.accrue(w,at,nextAt,not Work.safe(w,state),state)
            if AI.worker(state,w,realDt,nextAt,context) or oldClocked~=w.clockedIn then changed=true end
        end
        at=nextAt
    end
    e.lastAtHours=now
    if Payroll.pay(state,now,true) then changed=true end
    return changed
end
return AI
