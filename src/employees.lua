local Calendar=require("src.business_calendar")
local Contracts=require("src.employment_contracts")
local Payroll=require("src.payroll")
local Inbox=require("src.inbox")
local Fleet=require("src.machine_fleet")
local Employees={}
local states={visiting=true,resume_requested=true,resume_received=true,negotiating=true,
    offer_accepted=true,hired=true,declined=true,withdrawn=true,expired=true}
local phases={hidden=true,entering=true,waiting=true,leaving=true,idle=true,walking=true,
    working=true,break_walk=true,["break"]=true}
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
        and (a.moving==nil or type(a.moving)=="boolean")
        and (a.workFrame==nil or int(a.workFrame,1,4))
        and (a.arrivedAtHours==nil or number(a.arrivedAtHours,0,1e12))
end
function Employees.defaultState(now)
    return {version=1,nextApplicantId=1,nextEmployeeId=1,recruiting=true,
        nextApplicantAtHours=now or 0,lastAtHours=now or 0,applications={},staff={}}
end
function Employees.ensure(state)
    state.employment=state.employment or Employees.defaultState(Calendar.absoluteHours(state))
    return state.employment
end
function Employees.valid(e)
    if type(e)~="table" or e.version~=1 or not int(e.nextApplicantId,1,1000000)
        or not int(e.nextEmployeeId,1,1000000) or type(e.recruiting)~="boolean"
        or not number(e.nextApplicantAtHours,0,1e12) or not number(e.lastAtHours,0,1e12) then return false end
    local ids={}
    local function profile(p)
        return type(p)=="table" and text(p.name) and #p.name>0 and p.character=="cat-worker"
            and int(p.cutterSkill,1,100) and int(p.attention,1,100) and int(p.reliability,1,100)
            and int(p.requestedWage,1000,10000) and int(p.minimumWage,1000,10000)
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
    return array(e.staff,24,function(w)
        if not profile(w) or not token(w.id) or ids[w.id] or not Contracts.valid(w.contract)
            or (w.status~="employed" and w.status~="dismissed" and w.status~="resigned")
            or not validActor(w) or type(w.clockedIn)~="boolean"
            or not number(w.fatigue,0,100) or not number(w.focus,0,100)
            or not int(w.shiftDay,-1,10000000) or not int(w.breaksTaken,0,7)
            or not number(w.breakRemaining,0,1) or not text(w.activity)
            or type(w.terminationRequested)~="boolean" or type(w.stopRequested)~="boolean"
            or (w.reserved~=nil and type(w.reserved)~="boolean")
            or (w.resigning~=nil and type(w.resigning)~="boolean")
            or (w.breakKind~=nil and w.breakKind~="meal" and w.breakKind~="rest")
            or (w.seatBay~=nil and w.seatBay~="front_left" and w.seatBay~="front_right")
            or (w.assignment~=nil and (type(w.assignment)~="table" or not token(w.assignment.jobId)
                or not token(w.assignment.palletId) or not token(w.assignment.machineId)))
            or not array(w.weeks,1000,function(r)
                return type(r)=="table" and int(r.week,-3,10000000) and number(r.dueAtHours,0,1e12)
                    and number(r.paidHours,0,200) and number(r.earnedCents,0,1e9)
                    and int(r.paidCents,0,math.floor(r.earnedCents+.5+1e-7)) and type(r.notified)=="boolean"
            end) then return false end
        ids[w.id]=true return true
    end)
end
function Employees.normalize(e,now)
    if e==nil then return Employees.defaultState(now) end
    if not Employees.valid(e) then return nil end
    local result=copy(e)
    for _,w in ipairs(result.staff) do
        w._operatorPoint,w._operatorKey,w._workClock=nil,nil,nil
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
    return {visible=false,phase="hidden",x=645,y=235,intentX=0,intentY=1,distance=0,idleClock=0}
end
function Employees.createApplicant(state,now)
    local e=Employees.ensure(state)
    local active=0
    for _,a in ipairs(e.applications) do if a.status~="hired" and a.status~="declined" and a.status~="expired" and a.status~="withdrawn" then active=active+1 end end
    if active>=3 then return nil end
    local n=e.nextApplicantId
    e.nextApplicantId=n+1
    local names={"Radio Cat","Miso Cat","Pepper Cat","Clover Cat"}
    local a={id=string.format("APP-%04d",n),name=names[(n-1)%#names+1],character="cat-worker",
        cutterSkill=n==1 and 65 or 45+(n*17)%41,attention=n==1 and 75 or 60+(n*11)%31,
        reliability=n==1 and 90 or 75+(n*7)%21,requestedWage=2200+(n-1)%3*100,
        minimumWage=2000+(n-1)%3*100,revision=1,counters=0,status="visiting",
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
            notice(state,a,"RESUME","Resume attached: cutter operator",
                string.format("Thanks for considering me. My resume is attached. Cutter skill %d/100, attention %d/100, reliability %d/100. I am available 08:00-18:00 and ask $%.2f/hr. Open my resume to discuss days and hours.",
                    a.cutterSkill,a.attention,a.reliability,a.requestedWage/100))
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
    local a=intent.applicationId and Employees.application(state,intent.applicationId)
    if intent.kind=="decline_application" then
        if not a or a.status=="hired" then return false,"That application is already closed." end
        a.status="declined";a.replyAtHours=nil;a.revision=a.revision+1
        if a.actor.visible then a.actor.phase="leaving" end
        return true,"Application declined."
    elseif intent.kind=="offer_employee" then
        local terms=Contracts.terms(intent.wageCents,intent.days,intent.startHour,intent.endHour)
        if not Contracts.validTerms(terms) then return false,"Choose $10-$100/hr and a 4-10 hour shift within 08:00-18:00." end
        if not a or (a.status~="resume_received" and a.status~="offer_accepted" and a.status~="negotiating") then return false,"Request the resume before making an offer." end
        if a.revision~=intent.expectedRevision then return false,"The applicant replied. Review the latest terms before sending." end
        if Contracts.same(terms,a.offer) then return true,"These terms were already sent; no extra negotiation round was used." end
        if a.counters>=3 then return false,"The three-offer negotiation limit has been reached." end
        a.offer=terms;a.counter=nil;a.status="negotiating";a.counters=a.counters+1
        a.revision=a.revision+1;a.replyAtHours=now+.75;a.expiresAtHours=nil
        return true,"Offer emailed. The applicant will reply shortly."
    elseif intent.kind=="hire_employee" then
        if a and a.status=="hired" then return true,"This agreement is already signed." end
        if not a or a.status~="offer_accepted" or a.revision~=intent.expectedRevision
            or (a.expiresAtHours and now>=a.expiresAtHours) then return false,"Review the current accepted offer before signing." end
        local count=0 for _,w in ipairs(e.staff) do if w.status=="employed" then count=count+1 end end
        if #e.staff>=24 then
            for i,old in ipairs(e.staff) do
                if old.status~="employed" and not old.visible and Payroll.balance(old,now,true)==0 then table.remove(e.staff,i);break end
            end
        end
        if count>=3 or #e.staff>=24 then return false,"This shop can employ three workers at once." end
        local w=copy(a)
        w.actor=nil;w.offer=nil;w.counter=nil;w.replyAtHours=nil;w.expiresAtHours=nil
        w.id=string.format("EMP-%04d",e.nextEmployeeId);e.nextEmployeeId=e.nextEmployeeId+1
        for k,v in pairs(actor()) do w[k]=v end
        w.status="employed";w.contract=copy(a.offer);w.contract.revision=a.revision
        w.contract.signedAtHours=now;w.contract.startDay=Contracts.nextDay(w.contract,now)
        w.fatigue=0;w.focus=100;w.weeks={};w.shiftDay=-1;w.breaksTaken=0;w.breakRemaining=0
        w.clockedIn=false;w.terminationRequested=false;w.stopRequested=false;w.activity="Starts next agreed shift"
        e.staff[#e.staff+1]=w;a.status="hired";a.employeeId=w.id;a.revision=a.revision+1
        notice(state,a,"SIGNED","Employment agreement signed",Contracts.summary(w.contract)..". Starting on game day "..(w.contract.startDay+1)..". Weekly pay is due Monday 09:00, with 1.5x pay after 40 paid hours. Assign a staged pallet in Hiring > Staff.")
        return true,w.name.." hired. Starts on the next agreed day."
    end
    local w=intent.employeeId and Employees.worker(state,intent.employeeId)
    if not w or w.status~="employed" then return false,"Choose a current employee." end
    if intent.kind=="dismiss_employee" then w.terminationRequested=true;w.stopRequested=true;return true,"Dismissal requested. Earned wages remain owed."
    elseif intent.kind=="unassign_employee" then w.stopRequested=true;return true,"Work will pause at the next safe cutter checkpoint."
    elseif intent.kind=="assign_employee" then
        if Payroll.balance(w,now,false)>0 then return false,"Pay overdue wages before assigning more work." end
        if w.assignment then return false,"Pause the current assignment before selecting another." end
        local job,pallet
        for _,j in ipairs(state.jobs.active or {}) do if j.id==intent.jobId then job=j end end
        for _,p in ipairs(job and job.pallets or {}) do if p.id==intent.palletId then pallet=p end end
        local machine=Fleet.byId(state,intent.machineId)
        if not job or not pallet or not pallet.paper or not machine or machine.modelId~="polar_115" or machine.status~="installed" then return false,"Choose an accepted job, its pallet, and an installed cutter." end
        if (job.difficulty=="hard" and w.cutterSkill<80) or (job.difficulty=="medium" and w.cutterSkill<50) then return false,"This job needs a more skilled cutter operator." end
        if (pallet.status=="cut" or pallet.status=="printed" or pallet.status=="wrapped") or (pallet.remainingSheets or 0)<=0 and pallet.location~="at_cutter" then return false,"This pallet no longer needs cutting." end
        for _,other in ipairs(e.staff) do if other~=w and other.assignment
            and (other.assignment.machineId==machine.id or other.assignment.palletId==pallet.id) then return false,"Another employee is assigned to that cutter or pallet." end end
        w.assignment={jobId=job.id,palletId=pallet.id,machineId=machine.id};w.stopRequested=false
        w.activity="Waiting for shift / staged stock"
        return true,"Assignment saved. Stage this pallet beside the cutter; the worker handles each lift."
    end
    return false,"Unknown employment action."
end
function Employees.isIntent(kind)
    return ({recruit_workers=true,request_resume=true,offer_employee=true,hire_employee=true,
        decline_application=true,assign_employee=true,unassign_employee=true,pay_wages=true,dismiss_employee=true})[kind]==true
end
function Employees.reservation(state,machineId,palletId)
    for _,w in ipairs(Employees.ensure(state).staff) do
        if w.visible and w.assignment and w.reserved
            and (w.assignment.machineId==machineId or (palletId and w.assignment.palletId==palletId)) then return w.id,w.name end
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
