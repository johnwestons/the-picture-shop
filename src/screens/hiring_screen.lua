local Employees=require("src.employees")
local Contracts=require("src.employment_contracts")
local Payroll=require("src.payroll")
local Calendar=require("src.business_calendar")
local Fleet=require("src.machine_fleet")
local Ui=require("src.screens.ui")
local CharacterAssets=require("src.character_assets")
local Hiring={}
local function rect(x,y,w,h) return {x=x,y=y,width=w,height=h} end
local buttons={applications=rect(92,192,186,40),staff=rect(288,192,186,40),payroll=rect(484,192,166,40),
    recruit=rect(660,192,184,40),resume=rect(410,512,208,46),decline=rect(632,512,208,46),
    offer=rect(410,512,208,46),sign=rect(410,512,208,46),edit=rect(632,512,208,46),
    back=rect(96,572,130,42),send=rect(606,572,234,42),pay=rect(590,554,250,46),
    assign=rect(410,518,208,46),pause=rect(410,572,208,42),dismiss=rect(632,572,208,42),
    confirmDismiss=rect(410,518,430,46),cancelDismiss=rect(410,572,430,42),
    wageMinus=rect(412,290,48,44),wagePlus=rect(788,290,48,44),
    startMinus=rect(412,350,48,44),startPlus=rect(562,350,48,44),
    endMinus=rect(638,350,48,44),endPlus=rect(788,350,48,44),
    jobPrev=rect(410,294,48,44),jobNext=rect(788,294,48,44),
    palletPrev=rect(410,362,48,44),palletNext=rect(788,362,48,44),
    machinePrev=rect(410,430,48,44),machineNext=rect(788,430,48,44),
    assignConfirm=rect(410,546,430,46),previous=rect(96,572,90,42),next=rect(270,572,90,42)}
local labels={visiting="Applying at reception",resume_requested="Resume requested",resume_received="Resume received",
    negotiating="Awaiting email reply",offer_accepted="Accepted - sign to hire",hired="Hired",declined="Declined",withdrawn="Withdrawn",expired="Expired"}
function Hiring.new()
    return {section="applications",view="detail",selectedId=nil,page=1,terms=nil,jobIndex=1,palletIndex=1,machineIndex=1}
end
function Hiring.open(ui,id) ui.section="applications";ui.view="detail";ui.selectedId=id;ui.terms=nil end
function Hiring.buttonCenter(name)
    local b=buttons[name]
    if b then return b.x+b.width/2,b.y+b.height/2 end
end
local function dayRect(i) return rect(412+(i-1)*61,438,55,44) end
function Hiring.dayCenter(i) local r=dayRect(i);return r.x+r.width/2,r.y+r.height/2 end
local function rows(state,ui)
    local e=Employees.ensure(state)
    return ui.section=="applications" and e.applications or e.staff
end
local function selected(state,ui)
    local all=rows(state,ui)
    for _,r in ipairs(all) do if r.id==ui.selectedId then return r end end
    ui.selectedId=all[1] and all[1].id or nil
    return all[1]
end
local function choices(state,ui)
    local jobs=state.jobs.active or {}
    ui.jobIndex=math.min(math.max(1,ui.jobIndex),math.max(1,#jobs))
    local job=jobs[ui.jobIndex]
    local pallets=job and job.pallets or {}
    ui.palletIndex=math.min(math.max(1,ui.palletIndex),math.max(1,#pallets))
    local machines=Fleet.installedUnits(state,"polar_115")
    ui.machineIndex=math.min(math.max(1,ui.machineIndex),math.max(1,#machines))
    return job,pallets[ui.palletIndex],machines[ui.machineIndex],#jobs,#pallets,#machines
end
function Hiring.mousepressed(state,ui,x,y,command,readOnly)
    local e=Employees.ensure(state)
    local function hit(name) return Ui.contains(buttons[name],x,y) end
    local function send(intent)
        if readOnly then state.message="Only the shop owner can change hiring and payroll.";return {action="blocked"} end
        return command(intent)
    end
    for _,section in ipairs({"applications","staff","payroll"}) do
        if hit(section) then ui.section=section;ui.view="detail";ui.selectedId=nil;ui.page=1;return {action="hiring_view"} end
    end
    if hit("recruit") then return send({kind="recruit_workers",enabled=not e.recruiting}) end
    if ui.section=="payroll" then
        if hit("pay") then return send({kind="pay_wages"}) end
        if hit("previous") then ui.page=math.max(1,ui.page-1);return {action="hiring_page"} end
        if hit("next") then ui.page=math.min(math.max(1,math.ceil(#e.staff/4)),ui.page+1);return {action="hiring_page"} end
        return nil
    end
    local all=rows(state,ui)
    for i=1,5 do
        local row=all[(ui.page-1)*5+i]
        if row and Ui.contains(rect(96,252+(i-1)*61,264,55),x,y) then
            ui.selectedId=row.id;ui.view="detail";ui.terms=nil;return {action="hiring_selected"}
        end
    end
    if ui.view=="detail" and hit("previous") then ui.page=math.max(1,ui.page-1);return {action="hiring_page"} end
    if ui.view=="detail" and hit("next") then ui.page=math.min(math.max(1,math.ceil(#all/5)),ui.page+1);return {action="hiring_page"} end
    local current=selected(state,ui)
    if not current then return nil end
    if ui.view~="detail" and hit("back") then ui.view="detail";return {action="hiring_view"} end
    if ui.view=="offer" then
        local t=ui.terms
        if hit("wageMinus") then t.wageCents=math.max(1000,t.wageCents-100)
        elseif hit("wagePlus") then t.wageCents=math.min(10000,t.wageCents+100)
        elseif hit("startMinus") then t.startHour=math.max(8,t.startHour-1)
        elseif hit("startPlus") then t.startHour=math.min(14,t.startHour+1)
        elseif hit("endMinus") then t.endHour=math.max(12,t.endHour-1)
        elseif hit("endPlus") then t.endHour=math.min(18,t.endHour+1)
        elseif hit("send") then
            local result=send({kind="offer_employee",applicationId=current.id,expectedRevision=current.revision,
                wageCents=t.wageCents,days=t.days,startHour=t.startHour,endHour=t.endHour})
            if result and result.action~="blocked" then ui.view="detail" end
            return result
        else
            for i=1,7 do if Ui.contains(dayRect(i),x,y) then
                local bit=2^(i-1);t.days=t.days+(Contracts.hasDay(t.days,i) and -bit or bit)
                return {action="hiring_terms"}
            end end
            return nil
        end
        return {action="hiring_terms"}
    elseif ui.view=="assignment" then
        local job,pallet,machine,nj,np,nm=choices(state,ui)
        if hit("jobPrev") then ui.jobIndex=math.max(1,ui.jobIndex-1);ui.palletIndex=1
        elseif hit("jobNext") then ui.jobIndex=math.min(nj,ui.jobIndex+1);ui.palletIndex=1
        elseif hit("palletPrev") then ui.palletIndex=math.max(1,ui.palletIndex-1)
        elseif hit("palletNext") then ui.palletIndex=math.min(np,ui.palletIndex+1)
        elseif hit("machinePrev") then ui.machineIndex=math.max(1,ui.machineIndex-1)
        elseif hit("machineNext") then ui.machineIndex=math.min(nm,ui.machineIndex+1)
        elseif hit("assignConfirm") and job and pallet and machine then
            local result=send({kind="assign_employee",employeeId=current.id,jobId=job.id,palletId=pallet.id,machineId=machine.id})
            if result and result.action~="blocked" then ui.view="detail" end
            return result
        else return nil end
        return {action="hiring_assignment"}
    elseif ui.view=="dismiss" then
        if hit("confirmDismiss") then ui.view="detail";return send({kind="dismiss_employee",employeeId=current.id}) end
        if hit("cancelDismiss") then ui.view="detail";return {action="hiring_view"} end
        return nil
    elseif ui.section=="applications" then
        if current.status=="visiting" and hit("resume") then return send({kind="request_resume",applicationId=current.id}) end
        if current.status~="hired" and current.status~="offer_accepted" and hit("decline") then return send({kind="decline_application",applicationId=current.id}) end
        if current.status=="offer_accepted" and hit("sign") then return send({kind="hire_employee",applicationId=current.id,expectedRevision=current.revision}) end
        if (current.status=="resume_received" and hit("offer")) or (current.status=="offer_accepted" and hit("edit")) then
            local t=current.counter or current.offer or Contracts.terms(current.requestedWage,31,9,17)
            ui.terms={role="cutter",wageCents=t.wageCents,days=t.days,startHour=t.startHour,endHour=t.endHour}
            ui.view="offer";return {action="hiring_view"}
        end
    elseif current.status=="employed" then
        if hit("assign") and not current.assignment then ui.view="assignment";return {action="hiring_view"} end
        if hit("pause") and current.assignment then return send({kind="unassign_employee",employeeId=current.id}) end
        if hit("dismiss") then ui.view="dismiss";return {action="hiring_view"} end
    end
end
local function button(name,label,x,y,disabled,selectedFlag)
    local r=buttons[name]
    local hover=x and Ui.contains(r,x,y)
    love.graphics.setColor(disabled and .13 or selectedFlag and .20 or hover and .23 or .16,
        disabled and .17 or selectedFlag and .45 or hover and .39 or .29,.27,1)
    love.graphics.rectangle("fill",r.x,r.y,r.width,r.height,4,4)
    love.graphics.setColor(disabled and .48 or .94,disabled and .55 or .97,disabled and .52 or .91,1)
    love.graphics.printf(label,r.x+3,r.y+(r.height-16)/2,r.width-6,"center")
end
local function line(text,x,y,width,color)
    color=color or {.82,.89,.85}
    love.graphics.setColor(color[1],color[2],color[3],1)
    love.graphics.printf(text,x,y,width or 428,"left")
end
function Hiring.draw(state,ui,pointerX,pointerY,readOnly)
    local e=Employees.ensure(state)
    local now=Calendar.absoluteHours(state)
    love.graphics.setColor(.08,.13,.12,1);love.graphics.rectangle("fill",82,182,770,444,4,4)
    button("applications","APPLICANTS",pointerX,pointerY,false,ui.section=="applications")
    button("staff","STAFF",pointerX,pointerY,false,ui.section=="staff")
    button("payroll","PAYROLL",pointerX,pointerY,false,ui.section=="payroll")
    button("recruit",e.recruiting and "PAUSE RECRUITING" or "INVITE APPLICANT",pointerX,pointerY,readOnly)
    if ui.section=="payroll" then
        line(string.format("Wages due: $%.2f",Payroll.total(state,now,false)/100),100,252,700,{1,.85,.45})
        line(string.format("Total earned and unpaid: $%.2f",Payroll.total(state,now,true)/100),100,278,700)
        local jobCents,shopCents=0,0
        for _,w in ipairs(e.staff) do jobCents=jobCents+w.laborTotals.jobCents;shopCents=shopCents+w.laborTotals.shopCents end
        line(string.format("Tracked job labor: $%.2f  |  Idle / breaks / shop labor: $%.2f",jobCents/100,shopCents/100),100,304,730)
        line("Weekly payday: Monday 09:00. 1.5x pay after 40 paid hours.",100,330,700)
        for i=1,4 do
            local w=e.staff[(ui.page-1)*4+i]
            if w then
                local hours=w.laborTotals.jobHours+w.laborTotals.shopHours
                line(string.format("%s  |  %s  |  %.2f paid hours",w.name,w.status,hours),100,358+(i-1)*45,730)
                line(string.format("Due $%.2f  /  earned unpaid $%.2f",Payroll.balance(w,now,false)/100,Payroll.balance(w,now,true)/100),116,378+(i-1)*45,700,{.6,.76,.69})
            end
        end
        button("pay","PAY DUE WAGES",pointerX,pointerY,readOnly or Payroll.total(state,now,false)==0)
        button("previous","<",pointerX,pointerY);button("next",">",pointerX,pointerY)
        return
    end
    local all=rows(state,ui)
    local current=selected(state,ui)
    for i=1,5 do
        local row=all[(ui.page-1)*5+i]
        if row then
            local r=rect(96,252+(i-1)*61,264,55)
            love.graphics.setColor(row==current and .20 or .12,row==current and .32 or .21,.23,1)
            love.graphics.rectangle("fill",r.x,r.y,r.width,r.height,3,3)
            line(row.name,r.x+10,r.y+7,244)
            line(ui.section=="applications" and labels[row.status] or row.status,r.x+10,r.y+30,244,{.61,.78,.67})
        end
    end
    if ui.view=="detail" then button("previous","<",pointerX,pointerY);button("next",">",pointerX,pointerY)
    else button("back","BACK",pointerX,pointerY) end
    if not current then
        line(ui.section=="applications" and "Applicants visit reception while recruitment is open.\n\nUse INVITE APPLICANT to request a visit. Ask for an emailed resume, then negotiate here."
            or "No employees yet. Hire an applicant after accepting their emailed contract terms.",410,272,426)
        return
    end
    line(current.name.."  |  Cutter operator",410,252,426,{1,.86,.50})
    if ui.view=="offer" then
        local t=ui.terms
        button("wageMinus","-",pointerX,pointerY);button("wagePlus","+",pointerX,pointerY)
        line(string.format("Hourly wage: $%.2f",t.wageCents/100),478,302,292)
        button("startMinus","-",pointerX,pointerY);button("startPlus","+",pointerX,pointerY)
        button("endMinus","-",pointerX,pointerY);button("endPlus","+",pointerX,pointerY)
        line(string.format("%02d:00",t.startHour),478,364,76);line(string.format("%02d:00",t.endHour),704,364,76)
        line("Agreed working days",412,414,420)
        for i,name in ipairs({"MON","TUE","WED","THU","FRI","SAT","SUN"}) do
            local r=dayRect(i)
            love.graphics.setColor(.16,Contracts.hasDay(t.days,i) and .43 or .22,.28,1)
            love.graphics.rectangle("fill",r.x,r.y,r.width,r.height,3,3)
            line(name,r.x+7,r.y+14,45)
        end
        local estimate,hours=Contracts.weeklyEstimate(t)
        line(string.format("Estimated weekly pay: $%.2f (%.1f paid hours)",estimate,hours),412,494,426)
        line("Two paid 15-minute rests on an 8-hour shift; a 30-minute unpaid meal on shifts of 6+ hours.",412,518,426,{.61,.78,.67})
        button("send","EMAIL OFFER",pointerX,pointerY,readOnly or not Contracts.validTerms(t))
        return
    elseif ui.view=="assignment" then
        local job,pallet,machine=choices(state,ui)
        line("Accepted job",412,276,426)
        button("jobPrev","<",pointerX,pointerY);button("jobNext",">",pointerX,pointerY)
        line(job and job.id or "No accepted jobs",474,306,300)
        line("Exact pallet",412,344,426)
        button("palletPrev","<",pointerX,pointerY);button("palletNext",">",pointerX,pointerY)
        line(pallet and pallet.id or "No pallet",474,374,300)
        line("Installed cutter",412,412,426)
        button("machinePrev","<",pointerX,pointerY);button("machineNext",">",pointerX,pointerY)
        line(machine and machine.name.." ("..machine.id..")" or "No installed cutter",474,442,300)
        line("Stage this pallet beside the chosen cutter. The employee loads, programs, cuts and returns each lift.",412,490,426,{.61,.78,.67})
        button("assignConfirm","ASSIGN CUTTING WORK",pointerX,pointerY,readOnly or not (job and pallet and machine))
        return
    elseif ui.view=="dismiss" then
        line("Dismiss this employee?\n\nThey will stop at a safe cutter checkpoint. Earned wages stay on payroll until paid.",412,298,426)
        button("confirmDismiss","CONFIRM DISMISSAL",pointerX,pointerY,readOnly)
        button("cancelDismiss","KEEP EMPLOYEE",pointerX,pointerY)
        return
    end
    if ui.section=="applications" then
        local image,quad=CharacterAssets.get("cat-worker","idle",1)
        if image then
            local ax,ay=CharacterAssets.getAnchor("cat-worker","idle",1)
            love.graphics.setColor(1,1,1,1);love.graphics.draw(image,quad,784,370,0,.39,.39,ax,ay)
        end
        line("RESUME ATTACHED",410,288,300)
        line(string.format("Cutter skill: %d/100\nAttention: %d/100\nReliability: %d/100",current.cutterSkill,current.attention,current.reliability),410,316,292)
        line(string.format("Requested pay: $%.2f/hr",current.requestedWage/100),410,386,426)
        line("Experience: staged stock, programmed trims, safe two-hand cutter controls. Available 08:00-18:00.",410,412,426)
        line(labels[current.status] or current.status,410,466,426,{1,.85,.45})
        if current.status=="visiting" then button("resume","REQUEST EMAIL RESUME",pointerX,pointerY,readOnly)
        elseif current.status=="resume_received" then button("offer","NEGOTIATE OFFER",pointerX,pointerY,readOnly)
        elseif current.status=="offer_accepted" then
            line(Contracts.summary(current.offer),410,488,426)
            button("sign","SIGN & HIRE",pointerX,pointerY,readOnly)
            button("edit","RENEGOTIATE",pointerX,pointerY,readOnly)
        end
        if current.status~="hired" and current.status~="offer_accepted" then button("decline","DECLINE APPLICATION",pointerX,pointerY,readOnly) end
        if current.counter then line(string.format("Counteroffer: $%.2f/hr",current.counter.wageCents/100),410,574,426,{1,.85,.45}) end
    else
        local w=current
        line(Contracts.summary(w.contract),410,290,426)
        line(string.format("Cutter skill %d/100 | Focus %d | Tiredness %d",w.cutterSkill,math.floor(w.focus),math.floor(w.fatigue)),410,334,426)
        line(w.activity,410,374,426,{1,.85,.45})
        line(w.assignment and ("Job "..w.assignment.jobId.."\nPallet "..w.assignment.palletId.."\nCutter "..w.assignment.machineId) or "No work assigned",410,404,426)
        line(string.format("Wages due $%.2f | Earned unpaid $%.2f",Payroll.balance(w,now,false)/100,Payroll.balance(w,now,true)/100),410,484,426)
        if w.status=="employed" then
            button("assign",w.assignment and "WORK ASSIGNED" or "ASSIGN JOB",pointerX,pointerY,readOnly or w.assignment~=nil)
            button("pause","PAUSE ASSIGNMENT",pointerX,pointerY,readOnly or w.assignment==nil)
            button("dismiss","DISMISS",pointerX,pointerY,readOnly)
        end
    end
end
return Hiring
