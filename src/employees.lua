local Calendar=require("src.business_calendar")
local Contracts=require("src.employment_contracts")
local Payroll=require("src.payroll")
local Inbox=require("src.inbox")
local Fleet=require("src.machine_fleet")
local Schedule=require("src.employee_schedule")
local Labor=require("src.employee_labor")
local WorkerCatalog=require("src.worker_catalog")
local Employees={}
Employees.MAX_STAFF=10
local trainingSkills={
    cutter={field="cutterSkill",label="paper cutter",model="polar_115",minimum=0},
    press={field="pressSkill",label="printing press",model="heidelberg_10x15",minimum=40},
    wrapping={field="wrappingSkill",label="pallet wrapping",model="skid_wrapper",minimum=25},
}
local trainingHoursPerPoint=.16
local states={visiting=true,resume_requested=true,resume_received=true,negotiating=true,
    offer_accepted=true,hired=true,declined=true,withdrawn=true,expired=true}
local phases={hidden=true,entering=true,waiting=true,leaving=true,idle=true,walking=true,
    working=true,pushing=true,break_walk=true,["break"]=true}
local function finite(n) return type(n)=="number" and n==n and math.abs(n)<1e12 end
local function number(n,low,high) return finite(n) and n>=low and n<=high end
local function int(n,low,high) return number(n,low,high) and n==math.floor(n) end
local function token(s) return type(s)=="string" and #s>0 and #s<=64 and s:match("^[%w_.%-]+$") end
local function text(s) return type(s)=="string" and #s<=600 end
local function copy(t)
    if type(t)~="table" then return t end
    local r={} for k,v in pairs(t) do r[k]=copy(v) end return r
end
local function array(t,max,check)
    if type(t)~="table" or #t>max then return false end
    local n=0
    for k,v in pairs(t) do
        if not int(k,1,max) or not check(v) then return false end n=n+1
    end
    return n==#t
end
local function validActor(a)
    return type(a)=="table" and phases[a.phase] and type(a.visible)=="boolean"
        and number(a.x,0,960) and number(a.y,0,678)
        and number(a.intentX,-1,1) and number(a.intentY,-1,1)
        and number(a.distance,0,1e12) and number(a.idleClock,0,1e12)
        and (a.waitTimer==nil or number(a.waitTimer,0,1e12))
        and (a.moving==nil or type(a.moving)=="boolean")
        and (a.workFrame==nil or int(a.workFrame,1,4))
        and (a.arrivedAtHours==nil or number(a.arrivedAtHours,0,1e12))
        and (a.greetingKind==nil or int(a.greetingKind,1,3))
        and (a.greetingUntilHours==nil or number(a.greetingUntilHours,0,1e12))
end
function Employees.defaultState(now)
    return {version=6,nextApplicantId=1,nextEmployeeId=1,recruiting=true,
        teamSchedule=Schedule.defaultState(true),
        nextApplicantAtHours=now or 0,lastAtHours=now or 0,applications={},staff={}}
end
function Employees.ensure(state)
    state.employment=state.employment or Employees.defaultState(Calendar.absoluteHours(state))
    return state.employment
end
function Employees.employedCount(state)
    local count=0
    for _,worker in ipairs(Employees.ensure(state).staff) do
        if worker.status=="employed" then count=count+1 end
    end
    return count
end
function Employees.trainingPlan(worker,skill)
    local option=trainingSkills[skill]
    local current=worker and option and worker[option.field]
    if type(current)~="number" or current>=100 then return nil end
    local target=math.min(100,math.max(option.minimum,current+25))
    if target<=current then return nil end
    return {field=option.field,label=option.label,current=current,target=target,
        model=option.model,points=target-current,
        remainingHours=math.max(1,(target-current)*trainingHoursPerPoint),
        expectedWageCents=math.ceil(math.max(1,(target-current)*trainingHoursPerPoint)
            *(worker.contract and worker.contract.wageCents or 0))}
end
function Employees.valid(e)
    if type(e)~="table" or e.version~=6 or not int(e.nextApplicantId,1,1000000)
        or not int(e.nextEmployeeId,1,1000000) or type(e.recruiting)~="boolean"
        or not number(e.nextApplicantAtHours,0,1e12) or not number(e.lastAtHours,0,1e12)
        or (e.teamSchedule~=nil and not Schedule.valid(e.teamSchedule,true)) then return false end
    local ids={}
    local function profile(p)
        return type(p)=="table" and text(p.name) and #p.name>0 and WorkerCatalog.valid(p.character)
            and int(p.cutterSkill,1,100) and int(p.pressSkill,0,100) and int(p.wrappingSkill,0,100)
            and int(p.attention,1,100) and int(p.reliability,1,100)
            and int(p.requestedWage,1000,10000) and int(p.minimumWage,1000,10000)
            and (p.shiftPreference==nil or Contracts.validShiftPreference(p.shiftPreference))
    end
    if not array(e.applications,24,function(a)
        if not profile(a) or not token(a.id) or ids[a.id] or not states[a.status]
            or not int(a.revision,1,1000000) or not int(a.counters,0,3)
            or not number(a.createdAtHours,0,1e12) or not validActor(a.actor)
            or (a.replyAtHours~=nil and not number(a.replyAtHours,0,1e12))
            or (a.expiresAtHours~=nil and not number(a.expiresAtHours,0,1e12))
            or (a.offer~=nil and not Contracts.validTerms(a.offer))
            or (a.counter~=nil and not Contracts.validTerms(a.counter)) then return false end
        ids[a.id]=true return true
    end) then return false end
    local employedCount=0
    local staffValid=array(e.staff,24,function(w)
        if not profile(w) or not token(w.id) or ids[w.id] or not Contracts.valid(w.contract)
            or (w.status~="employed" and w.status~="dismissed" and w.status~="resigned")
            or not validActor(w) or type(w.clockedIn)~="boolean"
            or not number(w.fatigue,0,100) or not number(w.focus,0,100)
            or (w.carryingPalletId~=nil and not token(w.carryingPalletId))
            or not int(w.shiftDay,-1,10000000) or not int(w.breaksTaken,0,15)
            or not int(w.sentHomeShiftDay,-1,10000000)
            or not number(w.breakRemaining,0,1) or not text(w.activity)
            or type(w.terminationRequested)~="boolean" or type(w.stopRequested)~="boolean"
            or (w.reserved~=nil and type(w.reserved)~="boolean")
            or (w.resigning~=nil and type(w.resigning)~="boolean")
            or (w.breakKind~=nil and w.breakKind~="meal" and w.breakKind~="rest")
            or (w.seatBay~=nil and w.seatBay~="front_left" and w.seatBay~="front_right")
            or (w.training~=nil and (type(w.training)~="table"
                or not trainingSkills[w.training.skill]
                or not int(w.training.target,1,100)
                or not number(w.training.remainingHours,0,200)
                or w.training.target<=w[trainingSkills[w.training.skill].field]))
            or (w.assignment~=nil and (type(w.assignment)~="table" or not token(w.assignment.jobId)
                or not token(w.assignment.palletId) or not token(w.assignment.machineId)
                or (w.assignment.cutterMachineId~=nil and not token(w.assignment.cutterMachineId))
                or (w.assignment.machineModel~=nil and w.assignment.machineModel~="polar_115"
                    and w.assignment.machineModel~="heidelberg_10x15" and w.assignment.machineModel~="skid_wrapper")
                or (w.assignment.scheduleItemId~=nil and not token(w.assignment.scheduleItemId))))
            or not Schedule.valid(w.schedule)
            or not Labor.validTotals(w.laborTotals)
            or not array(w.weeks,1000,function(r)
                return type(r)=="table" and int(r.week,-3,10000000) and number(r.dueAtHours,0,1e12)
                    and number(r.paidHours,0,200) and number(r.earnedCents,0,1e9)
                    and int(r.paidCents,0,math.floor(r.earnedCents+.5+1e-7)) and type(r.notified)=="boolean"
            end) then return false end
        if w.assignment and w.assignment.scheduleItemId then
            local row=w.schedule.items[1]
            if not row or row.id~=w.assignment.scheduleItemId or row.jobId~=w.assignment.jobId
                or (w.assignment.cutterMachineId and row.machineId~=w.assignment.cutterMachineId) then return false end
        end
        if w.carryingPalletId and (not w.assignment or w.assignment.palletId~=w.carryingPalletId) then return false end
        if w.status=="employed" then employedCount=employedCount+1 end
        ids[w.id]=true return true
    end)
    return staffValid and employedCount<=Employees.MAX_STAFF
end
local function migrateSchedulesToTeam(employment)
    local team=employment.teamSchedule
    if type(employment.staff)~="table" or not Schedule.valid(team,true) then return false end
    local byJob,usedIds,pending={}, {}, {}
    for _,row in ipairs(team.items) do byJob[row.jobId]=row;usedIds[row.id]=true end
    for _,row in ipairs(team.history) do usedIds[row.id]=true end
    local function allocateId(preferred)
        local serial=type(preferred)=="string" and tonumber(preferred:match("^TEAM%-TASK%-(%d+)$"))
        if serial and serial>=1 and serial<1000000 and not usedIds[preferred] then
            team.nextId=math.max(team.nextId,serial+1)
            usedIds[preferred]=true
            return preferred
        end
        if team.nextId>=1000000 then return nil end
        local id=string.format("TEAM-TASK-%06d",team.nextId)
        team.nextId=team.nextId+1;usedIds[id]=true
        return id
    end
    for workerIndex,w in ipairs(employment.staff) do
        local q=w.schedule or Schedule.defaultState()
        w.schedule=q
        if not Schedule.valid(q) then return false end
        local kept,removed={},false
        for itemIndex,row in ipairs(q.items) do
            if type(row)~="table" then return false end
            local shared=byJob[row.jobId]
            if not shared then
                local id=allocateId(row.teamTaskId)
                if not id then return false end
                shared={id=id,jobId=row.jobId,machineId=row.machineId,addedAtHours=row.addedAtHours}
                byJob[row.jobId]=shared
                pending[#pending+1]={row=shared,addedAtHours=row.addedAtHours,
                    workerIndex=workerIndex,itemIndex=itemIndex}
            end
            local assigned=w.assignment and w.assignment.scheduleItemId==row.id
            if assigned then
                row.teamTaskId=shared.id;row.teamWorkerId=w.id
                kept[#kept+1]=row
            else
                removed=true
            end
        end
        if removed then q.items=kept;q.revision=q.revision+1 end
    end
    table.sort(pending,function(a,b)
        if a.addedAtHours~=b.addedAtHours then return a.addedAtHours<b.addedAtHours end
        if a.workerIndex~=b.workerIndex then return a.workerIndex<b.workerIndex end
        return a.itemIndex<b.itemIndex
    end)
    for _,entry in ipairs(pending) do team.items[#team.items+1]=entry.row end
    if #pending>0 then team.revision=team.revision+1 end
    return #team.items<=Schedule.MAX_TEAM_JOBS
end
function Employees.normalize(e,now)
    if e==nil then return Employees.defaultState(now) end
    if type(e)~="table" then return nil end
    local result=copy(e)
    if result.version==1 then
        if type(result.staff)~="table" then return nil end
        result.version=2
        for _,w in pairs(result.staff) do
            if type(w)~="table" then return nil end
            w.schedule=w.schedule or Schedule.defaultState()
        end
    end
    if result.version==2 then
        if type(result.staff)~="table" then return nil end
        result.version=3
        for _,w in pairs(result.staff) do
            if type(w)~="table" then return nil end
            w.laborTotals=w.laborTotals or Labor.fromWeeks(w.weeks)
        end
    end
    if result.version==3 then
        if type(result.staff)~="table" or type(result.applications)~="table" then return nil end
        result.version=4
        local function weekly(t) if type(t)=="table" and t.payWeeks==nil then t.payWeeks=1 end end
        for _,w in pairs(result.staff) do if type(w)~="table" then return nil end;weekly(w.contract) end
        for _,a in pairs(result.applications) do if type(a)~="table" then return nil end;weekly(a.offer);weekly(a.counter) end
    end
    if result.version==4 then
        if type(result.staff)~="table" then return nil end
        result.version=5
        for _,w in pairs(result.staff) do
            if type(w)~="table" then return nil end
            w.sentHomeShiftDay = -1
        end
    end
    if result.version==5 then
        if type(result.staff)~="table" or type(result.applications)~="table" then return nil end
        result.version=6
        local function skills(person)
            if type(person)~="table" then return false end
            if person.pressSkill==nil then person.pressSkill=0 end
            if person.wrappingSkill==nil then person.wrappingSkill=0 end
            return true
        end
        for _,w in pairs(result.staff) do if not skills(w) then return nil end end
        for _,a in pairs(result.applications) do if not skills(a) then return nil end end
    end
    if result.version==6 and result.teamSchedule==nil then
        result.teamSchedule=Schedule.defaultState(true)
    end
    if result.version==6 and not migrateSchedulesToTeam(result) then return nil end
    if result.version==6 then
        local function normalizePreferences(people)
            if type(people)~="table" then return end
            for _,person in ipairs(people) do
                if type(person)=="table" and person.shiftPreference==nil then
                    person.shiftPreference="flexible"
                end
            end
        end
        normalizePreferences(result.applications)
        normalizePreferences(result.staff)
    end
    if not Employees.valid(result) then return nil end
    for _,w in ipairs(result.staff) do
        w._operatorPoint,w._operatorKey,w._workClock,w._trainingClock,w._trainingMachineId=nil,nil,nil,nil,nil
        w._jackNavigator,w._jackTarget,w.jackDistance,w._waitingForJack=nil,nil,nil,nil
        w.greetingKind,w.greetingUntilHours=nil,nil
        w._scheduleRetryAtHours,w._blockedWorkHours,w._waitingMachineId=nil,nil,nil
        w._palletApproachKey,w._palletApproachPoint,w._palletDropKey,w._palletDropPoint=nil,nil,nil,nil
        if w.assignment then
            w.assignment.cutterMachineId=w.assignment.cutterMachineId or w.assignment.machineId
            w.assignment.machineModel=w.assignment.machineModel or "polar_115"
        end
        w.velocityX,w.velocityY,w.animationDistance=nil,nil,nil
        w.gaitSpeedMultiplier,w.gaitAccelerationMultiplier,w.interactionClock=nil,nil,nil
    end
    return result
end
function Employees.application(state,id)
    for _,a in ipairs(Employees.ensure(state).applications) do if a.id==id then return a end end
end
function Employees.worker(state,id)
    for _,w in ipairs(Employees.ensure(state).staff) do if w.id==id then return w end end
end
local function notice(state,a,suffix,subject,body)
    Inbox.addNotice(state,{id=a.id.."-"..suffix,sender=a.name,subject=subject,body=body,
        noticeKind="employment",applicationId=a.id,attachmentKind="resume"},0)
end
local function actor()
    local entrance=require("src.config").customer.route[1]
    return {visible=false,phase="hidden",x=entrance.x,y=entrance.y,intentX=0,intentY=1,distance=0,idleClock=0}
end
function Employees.createApplicant(state,now)
    local e=Employees.ensure(state)
    local active=0
    for _,a in ipairs(e.applications) do if a.status~="hired" and a.status~="declined" and a.status~="expired" and a.status~="withdrawn" then active=active+1 end end
    if active>=3 then return nil end
    local n=e.nextApplicantId
    e.nextApplicantId=n+1
    local profile=WorkerCatalog.profiles[(n-1)%#WorkerCatalog.profiles+1]
    local a={id=string.format("APP-%04d",n),name=profile.name,character=profile.character,
        cutterSkill=profile.cutterSkill,attention=profile.attention,
        pressSkill=profile.pressSkill,wrappingSkill=profile.wrappingSkill,
        reliability=profile.reliability,shiftPreference=profile.shiftPreference or "flexible",
        requestedWage=profile.requestedWage,
        minimumWage=profile.minimumWage,revision=1,counters=0,status="visiting",
        createdAtHours=now,actor=actor()}
    e.applications[#e.applications+1]=a
    e.nextApplicantAtHours=now+72+(n%3)*24
    -- Archive only closed applications; active negotiations are never evicted.
    if #e.applications>24 then
        for i,old in ipairs(e.applications) do if not old.actor.visible and (old.status=="hired" or old.status=="declined" or old.status=="expired" or old.status=="withdrawn") then table.remove(e.applications,i);break end end
    end
    return a
end
function Employees.requestResume(state,id,now)
    local a=Employees.application(state,id)
    if not a then return false,"That application is no longer available." end
    if a.status~="visiting" then return true,"The resume has already been requested." end
    a.status="resume_requested";a.replyAtHours=now+.5;a.revision=a.revision+1
    if a.actor.visible then a.actor.phase="leaving" end
    return true,a.name.." will email a resume shortly."
end
function Employees.advance(state,now)
    local e=Employees.ensure(state)
    local changed=false
    if e.recruiting and now>=e.nextApplicantAtHours then changed=Employees.createApplicant(state,now)~=nil end
    for _,a in ipairs(e.applications) do
        if a.status=="resume_requested" and a.replyAtHours<=now then
            a.status="resume_received";a.replyAtHours=nil;a.revision=a.revision+1
            notice(state,a,"RESUME","Resume attached: production operator",
                string.format("Thanks for considering me. My resume is attached. Cutter skill %d/100, press skill %d/100, pallet-wrapping skill %d/100, attention %d/100, reliability %d/100. I prefer %s and ask $%.2f/hr. Open my resume to discuss days, hours and pay cycle.",
                    a.cutterSkill,a.pressSkill,a.wrappingSkill,a.attention,a.reliability,
                    Contracts.shiftPreferenceDescription(a.shiftPreference),a.requestedWage/100))
            changed=true
        elseif a.status=="negotiating" and a.replyAtHours<=now then
            a.replyAtHours=nil;a.revision=a.revision+1;a.expiresAtHours=now+72
            if a.offer.wageCents>=a.minimumWage then
                a.status="offer_accepted";a.counter=nil
                notice(state,a,"ACCEPT-"..a.revision,"I accept your offer",
                    Contracts.summary(a.offer)..". Please sign the agreement in Hiring. I will start on the next agreed day after signing.")
            elseif a.counters>=3 then
                a.status="withdrawn"
                notice(state,a,"WITHDRAWN","Application withdrawn","We could not agree on pay after three offers. Thank you for your time.")
            else
                a.status="resume_received";a.counter=copy(a.offer);a.counter.wageCents=a.requestedWage
                notice(state,a,"COUNTER-"..a.revision,"Counteroffer attached",
                    "I can agree to those days and hours at $"..string.format("%.2f",a.requestedWage/100).." per hour. Open Hiring to respond.")
            end
            changed=true
        elseif a.expiresAtHours and a.expiresAtHours<=now and (a.status=="offer_accepted" or a.status=="resume_received") then
            a.status="expired";a.revision=a.revision+1
            notice(state,a,"EXPIRED","Offer expired","The three-day offer window has passed. I am withdrawing this application.")
            changed=true
        end
    end
    return changed
end
function Employees.command(state,intent,now)
    now=now or Calendar.absoluteHours(state)
    local e=Employees.ensure(state)
    if intent.kind=="recruit_workers" then
        e.recruiting=intent.enabled
        if intent.enabled then e.nextApplicantAtHours=now;Employees.advance(state,now) end
        return true,intent.enabled and "Recruitment open. An applicant will visit reception." or "Recruitment paused."
    elseif intent.kind=="request_resume" then return Employees.requestResume(state,intent.applicationId,now)
    elseif intent.kind=="pay_wages" then return Payroll.pay(state,now,false)
    end
    if Schedule.isTeamIntent(intent.kind) then return Schedule.teamCommand(state,intent,now) end
    local a=intent.applicationId and Employees.application(state,intent.applicationId)
    if intent.kind=="decline_application" then
        if not a or a.status=="hired" then return false,"That application is already closed." end
        a.status="declined";a.replyAtHours=nil;a.revision=a.revision+1
        if a.actor.visible then a.actor.phase="leaving" end
        return true,"Application declined."
    elseif intent.kind=="offer_employee" then
        local terms=Contracts.terms(intent.wageCents,intent.days,intent.startHour,intent.endHour,intent.payWeeks)
        if not Contracts.validTerms(terms) then return false,"Choose $10-$100/hr, a 4-12 hour shift and a 1-4 week pay cycle." end
        if not a or (a.status~="resume_received" and a.status~="offer_accepted" and a.status~="negotiating") then return false,"Request the resume before making an offer." end
        if a.revision~=intent.expectedRevision then return false,"The applicant replied. Review the latest terms before sending." end
        if not Contracts.preferenceAllows(a.shiftPreference,terms.startHour) then
            return false,a.name.." prefers "..Contracts.shiftPreferenceDescription(a.shiftPreference)
                ..". Adjust the offer's start time to match."
        end
        if Contracts.same(terms,a.offer) then return true,"These terms were already sent; no extra negotiation round was used." end
        if a.counters>=3 then return false,"The three-offer negotiation limit has been reached." end
        a.offer=terms;a.counter=nil;a.status="negotiating";a.counters=a.counters+1
        a.revision=a.revision+1;a.replyAtHours=now+.75;a.expiresAtHours=nil
        return true,"Offer emailed. The applicant will reply shortly."
    elseif intent.kind=="hire_employee" then
        if a and a.status=="hired" then return true,"This agreement is already signed." end
        if not a or a.status~="offer_accepted" or a.revision~=intent.expectedRevision
            or (a.expiresAtHours and now>=a.expiresAtHours) then return false,"Review the current accepted offer before signing." end
        if Employees.employedCount(state)>=Employees.MAX_STAFF then
            return false,"The payroll is full (10/10 employees). Dismiss an employee before hiring another."
        end
        if #e.staff>=24 then
            for i,old in ipairs(e.staff) do
                if old.status~="employed" and not old.visible and Payroll.balance(old,now,true)==0 then table.remove(e.staff,i);break end
            end
        end
        if #e.staff>=24 then return false,"Employee history is full. Clear an archived employee record before hiring." end
        local w=copy(a)
        w.actor=nil;w.offer=nil;w.counter=nil;w.replyAtHours=nil;w.expiresAtHours=nil
        w.id=string.format("EMP-%04d",e.nextEmployeeId);e.nextEmployeeId=e.nextEmployeeId+1
        for k,v in pairs(actor()) do w[k]=v end
        w.status="employed";w.contract=copy(a.offer);w.contract.revision=a.revision
        w.contract.signedAtHours=now;w.contract.startDay=Contracts.nextDay(w.contract,now)
        w.fatigue=0;w.focus=100;w.weeks={};w.shiftDay=-1;w.breaksTaken=0;w.breakRemaining=0
        w.sentHomeShiftDay=-1
        w.clockedIn=false;w.terminationRequested=false;w.stopRequested=false;w.activity="Starts next agreed shift"
        w.schedule=Schedule.defaultState()
        w.laborTotals=Labor.defaultTotals()
        e.staff[#e.staff+1]=w;a.status="hired";a.employeeId=w.id;a.revision=a.revision+1
        notice(state,a,"SIGNED","Employment agreement signed",Contracts.summary(w.contract)..". Starting on game day "..(w.contract.startDay+1)..". Pay every "..w.contract.payWeeks.." week(s), Monday 09:00, with 1.5x pay after 40 paid hours in each week. Build ordered production jobs in Schedule, or assign one staged pallet in Hiring > Staff. Employees can train on the paper cutter, press, and pallet wrapper during paid shift hours in Hiring > Staff.")
        return true,w.name.." hired. Starts on the next agreed day."
    end
    local w=intent.employeeId and Employees.worker(state,intent.employeeId)
    if not w or w.status~="employed" then return false,"Choose a current employee." end
    if Schedule.isIntent(intent.kind) then return Schedule.command(state,w,intent,now) end
    if intent.kind=="train_employee" then
        if w.assignment and w.reserved then
            return false,"Let the current machine cycle finish before starting training."
        end
        if w.training then return false,"This employee is already in a training course." end
        local plan=Employees.trainingPlan(w,intent.skill)
        if not plan then
            return false,"Choose a skill below 100: paper cutter, printing press, or pallet wrapping."
        end
        if not Fleet.installedUnits(state,plan.model)[1] then
            local machineName=plan.model=="polar_115" and "Polar cutter"
                or plan.model=="heidelberg_10x15" and "Heidelberg Windmill" or "skid wrapper"
            return false,"Install a "..machineName.." before this employee can train."
        end
        w.training={skill=intent.skill,target=plan.target,remainingHours=plan.remainingHours}
        w.activity="Training for the "..plan.label
        return true,string.format("%s started paid on-shift %s training (%g paid hours). Normal wages apply.",
            w.name,plan.label,plan.remainingHours)
    end
    if intent.kind=="cancel_employee_training" then
        if not w.training then return false,"This employee does not have an active training course." end
        local label=w.training.skill=="cutter" and "paper-cutter"
            or w.training.skill=="press" and "printing-press" or "pallet-wrapping"
        w.training=nil;w._trainingClock=nil;w._trainingMachineId=nil
        w.phase="idle";w.activity="Training cancelled"
        return true,w.name.." cancelled "..label.." training. Earned wages remain due."
    end
    if intent.kind=="send_employee_home" then
        local shiftDay=Contracts.shiftDay(w.contract,now)
        if w.sentHomeShiftDay==shiftDay then return true,"This employee is already heading home for today." end
        if not w.visible or not w.clockedIn then return false,"This employee is not clocked in right now." end
        w.sentHomeShiftDay=shiftDay
        w.activity="Going home for the day"
        return true,"Shift ended. A safe machine cycle will finish before the employee leaves; unfinished work resumes next shift."
    elseif intent.kind=="dismiss_employee" then w.terminationRequested=true;w.stopRequested=true;return true,"Dismissal requested. Earned wages remain owed."
    elseif intent.kind=="unassign_employee" then
        w.stopRequested=true
        if #w.schedule.items>0 then w.schedule.enabled=false;w.schedule.revision=w.schedule.revision+1 end
        return true,"Work will pause at the next safe machine checkpoint."
    elseif intent.kind=="assign_employee" then
        if Payroll.balance(w,now,false)>0 then return false,"Pay overdue wages before assigning more work." end
        if w.assignment then return false,"Pause the current assignment before selecting another." end
        local job,pallet
        for _,j in ipairs(state.jobs.active or {}) do if j.id==intent.jobId then job=j end end
        for _,p in ipairs(job and job.pallets or {}) do if p.id==intent.palletId then pallet=p end end
        local machine=Fleet.byId(state,intent.machineId)
        if not job or not pallet or not pallet.paper or not machine or machine.modelId~="polar_115" or machine.status~="installed" then return false,"Choose an accepted job, its pallet, and an installed cutter." end
        if not Schedule.stockArrived(job) then return false,"Wait until every skid for this job has been unloaded at the shop." end
        if (pallet.status=="cut" or pallet.status=="printed" or pallet.status=="wrapped") or (pallet.remainingSheets or 0)<=0 and pallet.location~="at_cutter" then return false,"This pallet no longer needs cutting." end
        local skilled,skillReason=Schedule.skillAllows(w,job,"cutter")
        if not skilled then return false,skillReason=="Required cutter skill"
            and "This employee needs more paper-cutting skill for this job." or "This employee is not trained for this cutter job." end
        for _,other in ipairs(e.staff) do if other~=w and other.assignment
            and (other.assignment.machineId==machine.id or other.assignment.palletId==pallet.id) then return false,"Another employee is assigned to that cutter or pallet." end end
        if Schedule.claimed(state,w,job.id) then return false,"This job is queued for another employee." end
        if w.schedule.enabled and #w.schedule.items>0 then return false,"Pause the work schedule before assigning a separate pallet." end
        w.assignment={jobId=job.id,palletId=pallet.id,machineId=machine.id,
            cutterMachineId=machine.id,machineModel=machine.modelId};w.stopRequested=false
        w.activity="Waiting for shift / staged stock"
        return true,"Assignment saved. Stage this pallet beside the cutter; the worker handles each lift."
    end
    return false,"Unknown employment action."
end
function Employees.isIntent(kind)
    return Schedule.isIntent(kind) or ({recruit_workers=true,request_resume=true,offer_employee=true,hire_employee=true,
        decline_application=true,assign_employee=true,unassign_employee=true,pay_wages=true,dismiss_employee=true,
        send_employee_home=true,train_employee=true,cancel_employee_training=true})[kind]==true
end
function Employees.reservation(state,machineId,palletId,excludeEmployeeId)
    for _,w in ipairs(Employees.ensure(state).staff) do
        if w.id~=excludeEmployeeId and w.visible then
            if machineId and w.training and w._trainingMachineId==machineId then return w.id,w.name end
            if w.assignment and w.reserved
                and (w.assignment.machineId==machineId or (palletId and w.assignment.palletId==palletId)) then
                return w.id,w.name
            end
        end
    end
end
function Employees.actors(state)
    local list={}
    local poses=state._employeePoses
    for _,a in ipairs(Employees.ensure(state).applications) do
        local actor=poses and poses[a.id] or not poses and a.actor
        if actor and actor.visible then list[#list+1]={actor=actor,name=a.name,application=a} end
    end
    for _,w in ipairs(state.employment.staff) do
        local actor=poses and poses[w.id] or not poses and w
        if actor and actor.visible then list[#list+1]={actor=actor,name=w.name,worker=w} end
    end
    return list
end
return Employees
