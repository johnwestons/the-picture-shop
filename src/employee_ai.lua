local Employees=require("src.employees")
local Contracts=require("src.employment_contracts")
local Payroll=require("src.payroll")
local Work=require("src.employee_work")
local WorkPresentation=require("src.employee_work_presentation")
local Schedule=require("src.employee_schedule")
local Fleet=require("src.machine_fleet")
local Calendar=require("src.business_calendar")
local PlayerController=require("src.player_controller")
local Navigation=require("src.navigation")
local Config=require("src.config")
local Speech=require("src.employee_speech")
local Transport=require("src.employee_pallet_jack")
local BreakroomGames=require("src.breakroom_games")
local AI={}
local EmployeeHighFive=require("src.employee_high_five")
local Navigator=require("src.npc_navigation")
local GaitMotion=require("src.gait_motion")
local CompanyTruck=require("src.company_delivery_driver")
local entrance=Config.customer.route[1]
local reception=Config.warehouse.roomScenes and require("src.warehouse_registration").reception or {x=759,y=358}
local applicantWaitSeconds=60
local openingWaitActivity="Waiting for the shop to open"
local function afterShiftGame(state,w,day)
    local options={}
    for _,bayId in ipairs(require("src.warehouse_layout").BAY_IDS) do
        local room=require("src.warehouse_layout").bayState(state,bayId)
        if room and room.status=="complete" and room.optionId=="breakroom" then
            for _,gameId in ipairs(BreakroomGames.ORDER) do
                if BreakroomGames.owns(state,bayId,gameId) then
                    options[#options+1]={bayId=bayId,gameId=gameId}
                end
            end
        end
    end
    if #options==0 then return nil end
    local hash=day*97
    for i=1,#w.id do hash=hash+w.id:byte(i)*i end
    if hash%100>=30 then return nil end
    return options[hash%#options+1]
end
local motion=require("src.worker_catalog").motion
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
    if context.forActor then context=context.forActor(a) end
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
            present=a;state.message=a.name.." is applying for a job. Talk to them before they leave in one minute."
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
    local first,last=Contracts.shiftBounds(w.contract,Contracts.shiftDay(w.contract,now))
    if not first then return nil end
    local elapsed=now-first
    local duration=last-first
    for _,b in ipairs({{at=2,bit=1,kind="rest",duration=.25},
        {at=3,bit=2,kind="meal",duration=.75}}) do
        if b.at+b.duration<=duration and elapsed>=b.at
            and math.floor(w.breaksTaken/b.bit)%2==0 then return b end
    end
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
    local machine,goal,moveContext,moveObstacles
    local function movementSnapshot()
        if not moveContext then
            if context.forActor then
                moveContext=context.forActor(w)
                moveObstacles=moveContext.obstacles and moveContext.obstacles()
            else moveContext=context end
        end
        return moveContext,moveObstacles
    end
    for _,candidate in ipairs(units) do
        if not Employees.reservation(state,candidate.id,nil,w.id)
            and (not context.canClaim or context.canClaim(candidate.id)) then
            local _,obstacles=movementSnapshot()
            local point=context.operatorPoint and context.operatorPoint(candidate.id,w,nil,obstacles)
            if point then machine,goal=candidate,point;break end
        end
    end
    if not machine then
        w._trainingMachineId=nil
        w.phase="idle";w.activity="Waiting for an available training machine"
        return false
    end
    w._trainingMachineId=machine.id
    local reached,blocked=AI.move(w,goal,dt,moveContext or context)
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
    if EmployeeHighFive.get(w.id) then
        w.moving=false
        return false
    end
    if w.awayForDelivery then
        w.visible=false;w.clockedIn=true;w.phase="hidden";w.sceneId=nil;w.moving=false
        return false
    end
    if w.pendingSchedule and not Contracts.onShift(w.contract,now) then
        local terms=w.pendingSchedule
        terms.revision=w.contract.revision
        terms.signedAtHours=now
        terms.startDay=Contracts.nextDay(terms,now)
        w.contract,w.pendingSchedule=terms,nil
    end
    if w.greetingUntilHours and now>=w.greetingUntilHours then
        w.greetingKind,w.greetingUntilHours=nil,nil
    end
    local day=Contracts.shiftDay(w.contract,now)
    local week=state.home and state.home.weekend
    local finishingFriday=week and week.phase=="closing" and w.visible and w.clockedIn
        and w.assignment~=nil
    local onShift=w.status=="employed" and not w.terminationRequested
        and w.sentHomeShiftDay~=day
        and (Contracts.onShift(w.contract,now)
            and require("src.weekend_flow").acceptsNewWork(state) or finishingFriday)
    local overdue=Payroll.overdueSince(w,now)
    if overdue and now-overdue>=168 and w.status=="employed" then w.terminationRequested=true;w.resigning=true;onShift=false end
    if onShift and not w.visible then
        w.visible=true;w.phase="entering";w.x,w.y=entrance.x,entrance.y;w.clockedIn=true
        local highFiveCooldownHours=7*24
        if not w.lastHighFiveRequestAtHours
            or now-w.lastHighFiveRequestAtHours>=highFiveCooldownHours then
            w.greetingKind=Speech.EMPLOYEE_HIGH_FIVE_REQUEST
            w.lastHighFiveRequestAtHours=now
            w.greetingUntilHours=now+Speech.HIGH_FIVE_SECONDS*24/Calendar.secondsPerDay(state)
        else
            w.greetingKind=now%24<12 and 1 or 2
            w.greetingUntilHours=now+Speech.GREETING_SECONDS*24/Calendar.secondsPerDay(state)
        end
        w.activity=w.assignment and "Resuming unfinished job" or "Arriving for shift"
        if w.shiftDay~=day then w.shiftDay=day;w.breaksTaken=0;w.fatigue=math.max(0,w.fatigue-60);w.focus=math.min(100,w.focus+50) end
    end
    if not w.visible then
        if w.stopRequested and Work.safe(w,state) then Work.release(state,w);w.assignment=nil;w.stopRequested=false;return true end
        if w.terminationRequested then w.status=w.resigning and "resigned" or "dismissed" end
        return false
    end
    local droppedCarriedPallet=false
    if (w.sceneId or "warehouse")~="warehouse" and context.travelScene
        and (not onShift or w.stopRequested or w.training or w.assignment or breakChoice(w,now)) then
        local _,changed=context.travelScene(w,"warehouse",dt)
        return changed
    end
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
                w.clockedIn=false
                if w.phase~="break" or not (w.activity or ""):match("^Playing .+ after shift$") then
                    local game=require("src.weekend_flow").acceptsNewWork(state) and afterShiftGame(state,w,day)
                    if game then
                        local info=BreakroomGames.CATALOG[game.gameId]
                        w.phase="break";w.seatBay=game.bayId;w.breakKind="rest"
                        w.breakRemaining=1
                        w.activity="Playing "..info.name:gsub(" table$", ""):lower().." after shift"
                        state.message=w.name.." stayed after their shift to play "
                            ..info.name:gsub(" table$", "")..". Join them in the breakroom!"
                    else
                        w.phase="leaving"
                        w.activity=rolledOver and "Handing unfinished jobs to the next shift"
                            or (w.assignment and "Off shift - unfinished job resumes next working shift" or "Shift ended")
                    end
                end
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
        local afterShiftPlaying=(w.activity or ""):match("^Playing .+ after shift$")~=nil
        if not afterShiftPlaying then
            w.activity=w.breakKind=="meal" and "Unpaid meal break" or "Paid rest break"
        end
        if w.breakRemaining<=.000001 then
            w.seatBay=nil;w.breakKind=nil
            if afterShiftPlaying then
                w.phase="leaving";w.x,w.y=entrance.x,entrance.y
                w.activity="Heading home after playing a game"
            else w.phase="idle" end
        end
    else
        local b=not finishingFriday and breakChoice(w,now)
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
            if not w.assignment then
                local shipping,changed=require("src.employee_shipping").update(state,w,dt,context)
                if shipping then return changed end
            end
            local scheduleChanged=Schedule.advance(state,w,now,context.canClaim)
            if w.assignment then
                local moveContext,moveObstacles
                local function movementSnapshot(actor)
                    if not moveContext then
                        if context.forActor then
                            moveContext=context.forActor(actor)
                            moveObstacles=moveContext.obstacles and moveContext.obstacles()
                        else moveContext=context end
                    end
                    return moveContext,moveObstacles
                end
                local workContext={canClaim=context.canClaim,
                    operatorPoint=context.operatorPoint and function(machineId,worker,avoidPoint)
                        local _,obstacles=movementSnapshot(worker)
                        return context.operatorPoint(machineId,worker,avoidPoint,obstacles)
                    end or nil,
                    machinePose=context.machinePose,
                    travelScene=context.travelScene,
                    motionScale=context.motionScale,jackNavigation=context.jackNavigation,
                    jackApproachPoint=context.jackApproachPoint,jackPickupPoint=context.jackPickupPoint,
                    jackDropPoint=context.jackDropPoint,jackDropClear=context.jackDropClear,
                    jackParkingPoint=context.jackParkingPoint,
                    jackLoadClear=context.jackLoadClear,
                    jackEmergencyDropPoint=context.jackEmergencyDropPoint,
                    palletApproachPoint=context.palletApproachPoint,palletDropPoint=context.palletDropPoint,
                    machinePalletDropPoint=context.machinePalletDropPoint,
                    palletEmergencyDropPoint=context.palletEmergencyDropPoint,
                    move=function(actor,goal,seconds)
                        local scoped=movementSnapshot(actor)
                        return AI.move(actor,goal,seconds,scoped)
                    end}
                local changed,blockedReason=Work.update(state,w,dt,workContext)
                if finishingFriday and blockedReason and Work.safe(w,state) then
                    Work.release(state,w,context)
                    w.assignment=nil
                    w.activity="Handing unfinished job to the next shift"
                    return true
                end
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
                    local stocking,stockChanged=Transport.storeSupplies(state,w,dt,context)
                    if stocking then return scheduleChanged or stockChanged end
                local moveContext=context.forActor and context.forActor(w) or context
                local moveObstacles=moveContext~=context and moveContext.obstacles and moveContext.obstacles()
                local point=context.idlePoint(w)
                local q=Schedule.ensure(w)
                if q.enabled and #q.items>0 and w._waitingMachineId and context.operatorPoint then
                    point=context.operatorPoint(w._waitingMachineId,w,nil,moveObstacles) or point
                end
                if AI.move(w,point,dt,moveContext) then
                    w.phase="idle";w.idleClock=w.idleClock+dt
                    w.activity=Schedule.idleActivity(state,w)
                end
                w.fatigue=math.min(100,w.fatigue+hours)
                return scheduleChanged
            end
        end
    end
    return false
end

-- When the owner remains home after the weekend, employees still report for
-- scheduled shifts. Keep them queued at the entrance and accrue only contracted
-- time; the closed warehouse simulation continues to hold machines and jobs.
function AI.updateClosedShop(state,firstAt,lastAt)
    if not state or not state.employment or lastAt<=firstAt then return false end
    local employment=state.employment
    local changed=false
    local registration=require("src.warehouse_registration")
    local door=registration.entrance
    local fromDay=math.max(0,math.floor(firstAt/24)-1)
    local throughDay=math.floor(lastAt/24)+1
    local function waitAtDoor(w,index)
        if w.phase=="waiting" and w.activity==openingWaitActivity and w.visible and w.clockedIn then return end
        local column=(index-1)%4
        local row=math.floor((index-1)/4)
        w.x=door.x-36+column*24
        w.y=door.y+36+row*18
        w.intentX,w.intentY=0,-1
        w.visible,w.clockedIn,w.phase=true,true,"waiting"
        w.sceneId="warehouse";w.moving=false;w.idleClock=0
        w.activity=openingWaitActivity
        w.greetingKind,w.greetingUntilHours=nil,nil
        changed=true
    end
    for index,w in ipairs(employment.staff) do
        local eligible=w.status=="employed" and not w.terminationRequested
        if eligible then
            for shiftDay=fromDay,throughDay do
                if w.sentHomeShiftDay~=shiftDay then
                    local shiftStart,shiftEnd=Contracts.shiftBounds(w.contract,shiftDay)
                    if shiftStart then
                        local paidStart,paidEnd=math.max(firstAt,shiftStart),math.min(lastAt,shiftEnd)
                        if paidEnd>paidStart then
                            waitAtDoor(w,index)
                            local earned=Payroll.accrue(w,paidStart,paidEnd,false,state)
                            changed=earned>0 or changed
                        end
                    end
                end
            end
        end
        local shiftDay=Contracts.shiftDay(w.contract,lastAt)
        local currentlyScheduled=eligible and w.sentHomeShiftDay~=shiftDay
            and Contracts.onShift(w.contract,lastAt)
        if currentlyScheduled then
            waitAtDoor(w,index)
        elseif w.phase=="waiting" and w.activity==openingWaitActivity then
            w.visible,w.clockedIn,w.phase=false,false,"hidden"
            w.sceneId=nil;w.activity="Shift ended";w.moving=false
            changed=true
        end
    end
    employment.lastAtHours=lastAt
    if Payroll.pay(state,lastAt,true) then changed=true end
    return changed
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
            if not context.background then WorkPresentation.update(state,w,realDt*(context.motionScale or 1)) end
        end
        at=nextAt
    end
    e.lastAtHours=now
    if CompanyTruck.update(state,now) then changed=true end
    CompanyTruck.syncTripVehicle(state)
    if Payroll.pay(state,now,true) then changed=true end
    return changed
end
return AI
