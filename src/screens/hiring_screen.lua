local Employees=require("src.employees")
local Contracts=require("src.employment_contracts")
local Payroll=require("src.payroll")
local Calendar=require("src.business_calendar")
local Fleet=require("src.machine_fleet")
local Schedule=require("src.employee_schedule")
local Ui=require("src.screens.ui")
local CharacterAssets=require("src.character_assets")
local Finances=require("src.staff_finances")
local Hiring={}
local function rect(x,y,w,h) return {x=x,y=y,width=w,height=h} end
local buttons={applications=rect(92,192,186,40),staff=rect(288,192,186,40),payroll=rect(484,192,166,40),
    recruit=rect(660,192,184,40),resume=rect(410,512,208,46),decline=rect(632,512,208,46),
    offer=rect(410,512,208,46),sign=rect(410,512,208,46),edit=rect(632,512,208,46),
    back=rect(96,572,130,42),send=rect(606,572,234,42),pay=rect(590,554,250,46),
    finances=rect(364,554,214,46),liftsMinus=rect(490,424,48,40),liftsPlus=rect(788,424,48,40),
    assign=rect(410,518,208,46),pause=rect(410,572,208,42),dismiss=rect(632,572,208,42),
    sendHome=rect(632,518,208,46),
    train=rect(632,478,208,34),trainingPress=rect(410,518,208,46),
    trainingWrap=rect(632,518,208,46),trainingCutter=rect(410,572,208,42),
    cancelTraining=rect(410,518,430,46),trainingBack=rect(632,572,208,42),
    confirmDismiss=rect(410,518,430,46),cancelDismiss=rect(410,572,430,42),
    wageMinus=rect(412,290,48,44),wagePlus=rect(788,290,48,44),
    startMinus=rect(412,350,48,44),startPlus=rect(562,350,48,44),
    endMinus=rect(638,350,48,44),endPlus=rect(788,350,48,44),
    dayShift=rect(412,398,204,28),nightShift=rect(632,398,204,28),
    payMinus=rect(412,490,48,36),payPlus=rect(788,490,48,36),
    jobPrev=rect(410,294,48,44),jobNext=rect(788,294,48,44),
    palletPrev=rect(410,362,48,44),palletNext=rect(788,362,48,44),
    machinePrev=rect(410,430,48,44),machineNext=rect(788,430,48,44),
    assignConfirm=rect(410,546,430,46),previous=rect(96,572,90,42),next=rect(270,572,90,42)}
local labels={visiting="Applying at reception",resume_requested="Resume requested",resume_received="Resume received",
    negotiating="Awaiting email reply",offer_accepted="Accepted - sign to hire",hired="Hired",declined="Declined",withdrawn="Withdrawn",expired="Expired"}
function Hiring.new()
    return {section="applications",view="detail",selectedId=nil,page=1,terms=nil,jobIndex=1,palletIndex=1,machineIndex=1,lifts=20}
end
function Hiring.employeeCountText(state)
    local count=Employees.employedCount(state)
    local text=string.format("%d/%d employees",count,Employees.MAX_STAFF)
    return count>=Employees.MAX_STAFF and text.." — payroll full" or text
end
function Hiring.open(ui,id) ui.section="applications";ui.view="detail";ui.selectedId=id;ui.terms=nil end
function Hiring.buttonCenter(name)
    local b=buttons[name]
    if b then return b.x+b.width/2,b.y+b.height/2 end
end
local function dayRect(i) return rect(412+(i-1)*61,446,55,36) end
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
function Hiring.mousepressed(state,ui,x,y,command,readOnly,canPayWages)
    if canPayWages==nil then canPayWages=true end
    local e=Employees.ensure(state)
    local function hit(name) return Ui.contains(buttons[name],x,y) end
    local function send(intent)
        if readOnly then state.message="Hiring changes are not available from this screen.";return {action="blocked"} end
        return command(intent)
    end
    for _,section in ipairs({"applications","staff","payroll"}) do
        if hit(section) then ui.section=section;ui.view="detail";ui.selectedId=nil;ui.page=1;return {action="hiring_view"} end
    end
    if hit("recruit") then return send({kind="recruit_workers",enabled=not e.recruiting}) end
    if ui.section=="payroll" then
        if hit("finances") then ui.view=ui.view=="finances" and "detail" or "finances";return {action="hiring_view"} end
        if ui.view=="finances" then
            if hit("liftsMinus") then ui.lifts=math.max(0,(ui.lifts or 20)-1);return {action="hiring_plan"} end
            if hit("liftsPlus") then ui.lifts=math.min(500,(ui.lifts or 20)+1);return {action="hiring_plan"} end
            return nil
        end
        if hit("pay") then
            if not canPayWages then
                state.message="Only the shop owner can pay employee wages."
                return {action="blocked"}
            end
            return send({kind="pay_wages"})
        end
        if hit("previous") then ui.page=math.max(1,ui.page-1);return {action="hiring_page"} end
        if hit("next") then ui.page=math.min(math.max(1,math.ceil(#e.staff/4)),ui.page+1);return {action="hiring_page"} end
        return nil
    end
    local all=rows(state,ui)
    for i=1,ui.view=="offer" and 3 or 5 do
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
    if ui.view=="training" then
        if hit("trainingBack") then ui.view="detail";return {action="hiring_view"} end
        if hit("cancelTraining") and current.training then
            local result=send({kind="cancel_employee_training",employeeId=current.id})
            if result and result.action~="blocked" then ui.view="detail" end
            return result
        end
        local skill=hit("trainingCutter") and "cutter"
            or hit("trainingPress") and "press"
            or hit("trainingWrap") and "wrapping"
        if skill then
            local plan=Employees.trainingPlan(current,skill)
            if not plan then state.message="That employee has already reached 100 in this skill.";return {action="blocked"} end
            if current.training then state.message="Let the existing on-shift course finish first.";return {action="blocked"} end
            local result=send({kind="train_employee",employeeId=current.id,skill=skill})
            return result
        end
        return nil
    end
    if ui.view=="offer" then
        local t=ui.terms
        if hit("wageMinus") then t.wageCents=math.max(1000,t.wageCents-100)
        elseif hit("wagePlus") then t.wageCents=math.min(10000,t.wageCents+100)
        elseif hit("startMinus") then t.startHour=(t.startHour-1)%24
        elseif hit("startPlus") then t.startHour=(t.startHour+1)%24
        elseif hit("endMinus") then t.endHour=(t.endHour-1)%24
        elseif hit("endPlus") then t.endHour=(t.endHour+1)%24
        elseif hit("dayShift") or hit("nightShift") then
            local startHour=hit("dayShift") and 8 or 20
            if not Contracts.preferenceAllows(current.shiftPreference,startHour) then
                state.message=current.name.." prefers "
                    ..Contracts.shiftPreferenceDescription(current.shiftPreference)
                    ..". Choose a matching shift."
                return {action="blocked"}
            end
            t.startHour,t.endHour=hit("dayShift") and 8 or 20,hit("dayShift") and 20 or 8
        elseif hit("payMinus") then t.payWeeks=math.max(1,t.payWeeks-1)
        elseif hit("payPlus") then t.payWeeks=math.min(4,t.payWeeks+1)
        elseif hit("send") then
            local result=send({kind="offer_employee",applicationId=current.id,expectedRevision=current.revision,
                wageCents=t.wageCents,days=t.days,startHour=t.startHour,endHour=t.endHour,payWeeks=t.payWeeks})
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
        if current.status=="offer_accepted" and hit("sign") then
            if Employees.employedCount(state)>=Employees.MAX_STAFF then
                state.message="Payroll is full. Dismiss an employee before hiring another."
                return {action="blocked"}
            end
            return send({kind="hire_employee",applicationId=current.id,expectedRevision=current.revision})
        end
        if (current.status=="resume_received" and hit("offer")) or (current.status=="offer_accepted" and hit("edit")) then
            local startHour=current.shiftPreference=="night" and 21 or 9
            local endHour=current.shiftPreference=="night" and 5 or 17
            local t=current.counter or current.offer
                or Contracts.terms(current.requestedWage,31,startHour,endHour)
            ui.terms={role="cutter",wageCents=t.wageCents,days=t.days,startHour=t.startHour,endHour=t.endHour,payWeeks=t.payWeeks}
            ui.view="offer";return {action="hiring_view"}
        end
    elseif current.status=="employed" then
        if hit("train") then ui.view="training";return {action="hiring_view"} end
        if hit("assign") and not current.assignment then ui.view="assignment";return {action="hiring_view"} end
        if hit("sendHome") then return send({kind="send_employee_home",employeeId=current.id}) end
        if hit("pause") and current.assignment then return send({kind="unassign_employee",employeeId=current.id}) end
        if hit("dismiss") then ui.view="dismiss";return {action="hiring_view"} end
    end
end
local hiringButtonRenderer
local function button(name,label,x,y,disabled,selectedFlag)
    local r=buttons[name]
    local hover=x and Ui.contains(r,x,y)
    local primary=selectedFlag or name=="recruit" or name=="resume" or name=="offer"
        or name=="sign" or name=="send" or name=="assignConfirm" or name=="pay"
        or name=="confirmDismiss" or name=="trainingCutter" or name=="trainingPress" or name=="trainingWrap"
    local danger=name=="decline" or name=="dismiss" or name=="cancelTraining"
    if hiringButtonRenderer then
        local style=disabled and "disabled"
            or danger and (hover and "dangerHover" or "danger")
            or primary and (hover and "primaryHover" or "primary")
            or hover and "hover" or "secondary"
        hiringButtonRenderer(r,label,style)
        return
    end
    local edge,face,highlight,shadow,textColor
    if disabled then
        edge,face,highlight,shadow,textColor={.10,.14,.16,1},{.22,.28,.30,1},
            {.39,.47,.47,1},{.12,.17,.18,1},{.70,.76,.75,1}
    elseif danger then
        edge,face,highlight,shadow,textColor={.20,.06,.05,1},{.43,.14,.13,1},
            {.80,.42,.35,1},{.27,.08,.07,1},{1,.95,.91,1}
    elseif primary then
        edge,face,highlight,shadow,textColor={.015,.12,.14,1},{.02,.36,.39,1},
            {.45,.79,.77,1},{.015,.20,.22,1},{.98,.99,.94,1}
    else
        edge,face,highlight,shadow,textColor={.055,.085,.10,1},{.25,.31,.33,1},
            {.64,.70,.69,1},{.12,.16,.17,1},{.94,.96,.91,1}
        if hover then face={.32,.40,.42,1};highlight={.75,.84,.81,1} end
    end
    love.graphics.setColor(edge);love.graphics.rectangle("fill",r.x,r.y,r.width,r.height,4,4)
    love.graphics.setColor(face);love.graphics.rectangle("fill",r.x+2,r.y+2,r.width-4,r.height-4,3,3)
    love.graphics.setColor(highlight);love.graphics.rectangle("fill",r.x+4,r.y+3,r.width-8,1)
    love.graphics.setColor(shadow);love.graphics.rectangle("fill",r.x+4,r.y+r.height-4,r.width-8,1)
    love.graphics.setColor(textColor)
    love.graphics.printf(label,r.x+5,r.y+(r.height-love.graphics.getFont():getHeight())/2,r.width-10,"center")
end
local function line(text,x,y,width,color)
    color=color or {.86,.91,.92}
    love.graphics.setColor(color[1],color[2],color[3],1)
    love.graphics.printf(text,x,y,width or 428,"left")
end
function Hiring.staffScheduleStatus(state,w)
    local team=Schedule.team(state)
    if w.assignment then return w.activity,nil end
    local count=#team.items
    local noun=count==1 and "job" or "jobs"
    if count>0 then
        local title
        if not w.training then
            title=team.enabled and ("Shared schedule | "..count.." "..noun) or "Shared schedule paused"
        end
        return title,count.." "..noun.." are on the shared day/night schedule. Qualified workers on either shift take the next ready job."
    end
    if w.training then return nil,#team.history>0 and "No jobs remain on the shared day/night schedule."
        or "No jobs are currently scheduled." end
    if #team.history>0 then
        return "Work schedule complete","No jobs remain on the shared day/night schedule."
    end
    return team.enabled and "No scheduled work" or "Shared schedule paused",
        "Add jobs to the shared day/night schedule."
end
local function panel(x,y,w,h)
    love.graphics.setColor(.015,.025,.035,1);love.graphics.rectangle("fill",x,y+2,w,h,4,4)
    love.graphics.setColor(.045,.075,.095,1);love.graphics.rectangle("fill",x,y,w,h,4,4)
    love.graphics.setColor(.29,.52,.56,1);love.graphics.setLineWidth(1)
    love.graphics.rectangle("line",x+.5,y+.5,w-1,h-1,4,4)
    love.graphics.setColor(.39,.62,.65,1);love.graphics.line(x+5,y+2,x+w-6,y+2)
end
function Hiring.draw(state,ui,pointerX,pointerY,readOnly,buttonRenderer,canPayWages,twelveHourTime)
    if canPayWages==nil then canPayWages=true end
    hiringButtonRenderer=buttonRenderer
    local e=Employees.ensure(state)
    local now=Calendar.absoluteHours(state)
    local employedCount=Employees.employedCount(state)
    local payrollFull=employedCount>=Employees.MAX_STAFF
    panel(82,182,770,444)
    button("applications","APPLICANTS",pointerX,pointerY,false,ui.section=="applications")
    button("staff","STAFF",pointerX,pointerY,false,ui.section=="staff")
    button("payroll","PAYROLL",pointerX,pointerY,false,ui.section=="payroll")
    button("recruit",e.recruiting and "PAUSE RECRUITING" or "INVITE APPLICANT",pointerX,pointerY,readOnly)
    local employeeCountText=Hiring.employeeCountText(state)
    line(employeeCountText,100,232,730,payrollFull and {1,.62,.46} or {1,.85,.45})
    if ui.section=="payroll" then
        if ui.view=="finances" then
            local f=Finances.summary(state)
            local plan=Finances.plan(f,ui.lifts or 20)
            line("WEEKLY SHOP BUDGET",100,250,740,{1,.85,.45})
            line(string.format("Wages incl. rest / overtime: $%.2f",f.weeklyWages),100,284,370)
            line(string.format("Shop bills allowance: $%.2f",f.weeklyOperating),100,310,370)
            line(string.format("Machine payments: $%.2f",f.weeklyLoans),100,336,370)
            line(string.format("Full payroll cycle reserve: $%.2f",f.cycleReserve),100,374,370)
            line(string.format("Cash after earned wages / bills: $%.2f",f.freeCash),100,410,370,
                f.freeCash<0 and {1,.55,.40} or {.65,.9,.72})
            line(string.format("Break-even: %d cutting lifts / week",f.breakEvenLifts),490,284,350,{1,.85,.45})
            line(string.format("Standard charge: $%.2f / lift",f.pricePerLift),490,310,350)
            line(string.format("Estimated staff capacity: %d lifts / week",f.capacity),490,336,350)
            line("PLAN COMPLETED LIFTS PER WEEK",490,394,350)
            button("liftsMinus","-",pointerX,pointerY);button("liftsPlus","+",pointerX,pointerY)
            line(tostring(ui.lifts or 20).." lifts",562,436,206)
            line(string.format("Income $%.2f | Machine reserve $%.2f",plan.revenue,plan.machineReserve),490,474,350)
            line(string.format("Money for growth: $%.2f / week",plan.profit),490,504,350,
                plan.profit<0 and {1,.55,.40} or {.65,.9,.72})
            line("500-sheet cutting lifts; client supplies stock. Budget includes the full shift, even idle time.",100,526,740,{.61,.78,.67})
            line(plan.withinCapacity and "Estimates assume staged stock, working equipment and completed, paid orders."
                or "Plan exceeds capacity. Use more shifts / cutters, help, or lower the plan.",100,606,740,{.61,.78,.67})
            button("finances","BACK TO PAYROLL",pointerX,pointerY)
            return
        end
        line(string.format("Wages due: $%.2f",Payroll.total(state,now,false)/100),100,252,700,{1,.85,.45})
        line(string.format("Total earned and unpaid: $%.2f",Payroll.total(state,now,true)/100),100,278,700)
        local jobCents,shopCents=0,0
        for _,w in ipairs(e.staff) do jobCents=jobCents+w.laborTotals.jobCents;shopCents=shopCents+w.laborTotals.shopCents end
        line(string.format("Tracked job labor: $%.2f  |  Idle / breaks / shop labor: $%.2f",jobCents/100,shopCents/100),100,304,730)
        line(string.format("Cash after earned wages / bills: $%.2f  |  Payday every 1-4 weeks.",Finances.summary(state).freeCash),100,330,730)
        for i=1,4 do
            local w=e.staff[(ui.page-1)*4+i]
            if w then
                local hours=w.laborTotals.jobHours+w.laborTotals.shopHours
                line(string.format("%s  |  %s  |  %.2f paid hours",w.name,w.status,hours),100,358+(i-1)*45,730)
                line(string.format("Due $%.2f  /  earned unpaid $%.2f",Payroll.balance(w,now,false)/100,Payroll.balance(w,now,true)/100),116,378+(i-1)*45,700,{.6,.76,.69})
            end
        end
        button("pay",canPayWages and "PAY DUE WAGES" or "OWNER PAYS WAGES",pointerX,pointerY,
            readOnly or not canPayWages or Payroll.total(state,now,false)==0)
        button("finances","SHOP BUDGET",pointerX,pointerY)
        button("previous","<",pointerX,pointerY);button("next",">",pointerX,pointerY)
        return
    end
    local all=rows(state,ui)
    local current=selected(state,ui)
    if ui.section~="payroll" then
        panel(90,244,278,320)
        panel(402,244,444,320)
    end
    for i=1,ui.view=="offer" and 3 or 5 do
        local row=all[(ui.page-1)*5+i]
        if row then
            local r=rect(96,252+(i-1)*61,264,55)
            love.graphics.setColor(.025,.045,.06,1);love.graphics.rectangle("fill",r.x,r.y,r.width,r.height,3,3)
            love.graphics.setColor(row==current and {.015,.34,.37,1} or {.09,.14,.16,1})
            love.graphics.rectangle("fill",r.x+2,r.y+2,r.width-4,r.height-4,2,2)
            love.graphics.setColor(row==current and {.42,.83,.79,1} or {.23,.39,.42,1})
            love.graphics.rectangle("line",r.x+1.5,r.y+1.5,r.width-3,r.height-3,3,3)
            line(row.name,r.x+10,r.y+7,244,{.92,.95,.93})
            if ui.section=="staff" then
                local statusText,statusColor
                if row.status=="employed" then
                    statusText=row.clockedIn and "CLOCKED IN" or "OFF SHIFT"
                    statusColor=row.clockedIn and {.42,.83,.58,1} or {.72,.69,.55,1}
                else
                    statusText=tostring(row.status or "unknown"):upper()
                    statusColor={.68,.72,.70,1}
                end
                local badge=rect(r.x+r.width-122,r.y+28,112,20)
                love.graphics.setColor(.025,.05,.055,.95)
                love.graphics.rectangle("fill",badge.x,badge.y,badge.width,badge.height,3,3)
                love.graphics.setColor(statusColor)
                love.graphics.rectangle("line",badge.x+.5,badge.y+.5,badge.width-1,badge.height-1,3,3)
                line(statusText,badge.x+3,badge.y+3,badge.width-6,statusColor)
            else
                line(labels[row.status] or row.status,r.x+10,r.y+30,244,{.55,.80,.80})
            end
        end
    end
    if ui.view=="detail" then button("previous","<",pointerX,pointerY);button("next",">",pointerX,pointerY)
    else button("back","BACK",pointerX,pointerY) end
    if not current then
        line(ui.section=="applications" and "Applicants visit reception while recruitment is open.\n\nUse INVITE APPLICANT to request a visit. Ask for an emailed resume, then negotiate here."
            or "No employees yet. Hire an applicant after accepting their emailed contract terms.",410,272,426)
        return
    end
    line(current.name.."  |  Production worker",410,252,426,{1,.86,.50})
    if ui.view=="offer" then
        local t=ui.terms
        local f=Finances.summary(state,t,current.cutterSkill)
        local shiftAllowed=Contracts.preferenceAllows(current.shiftPreference,t.startHour)
        line("SHOP AFTER THIS HIRE",104,448,250,{1,.85,.45})
        line(string.format("All wages + bills: $%.2f / week",f.weeklyFixed),104,472,250)
        line(string.format("Break-even: %d lifts / week",f.breakEvenLifts),104,496,250)
        line(string.format("Payroll reserve: $%.2f",f.cycleReserve),104,520,250)
        line("See PAYROLL > SHOP BUDGET.",104,544,250,{.61,.78,.67})
        button("wageMinus","-",pointerX,pointerY);button("wagePlus","+",pointerX,pointerY)
        line("Applicant preference: "..Contracts.shiftPreferenceLabel(current.shiftPreference),412,276,426,{.62,.79,.67,1})
        line(string.format("Hourly wage: $%.2f",t.wageCents/100),478,302,292)
        button("startMinus","-",pointerX,pointerY);button("startPlus","+",pointerX,pointerY)
        button("endMinus","-",pointerX,pointerY);button("endPlus","+",pointerX,pointerY)
        line("START",478,338,76);line("END",704,338,76)
        line(Contracts.formatHour(t.startHour,twelveHourTime),478,364,76)
        line(Contracts.formatHour(t.endHour,twelveHourTime)
            ..(t.endHour<t.startHour and " +1d" or ""),698,364,86)
        button("dayShift","DAY "..Contracts.formatHour(8,twelveHourTime).."-"
            ..Contracts.formatHour(20,twelveHourTime),pointerX,pointerY,
            not Contracts.preferenceAllows(current.shiftPreference,8))
        button("nightShift","NIGHT "..Contracts.formatHour(20,twelveHourTime).."-"
            ..Contracts.formatHour(8,twelveHourTime),pointerX,pointerY,
            not Contracts.preferenceAllows(current.shiftPreference,20))
        line("Days when the shift starts",412,430,420)
        for i,name in ipairs({"MON","TUE","WED","THU","FRI","SAT","SUN"}) do
            local r=dayRect(i)
            love.graphics.setColor(.16,Contracts.hasDay(t.days,i) and .43 or .22,.28,1)
            love.graphics.rectangle("fill",r.x,r.y,r.width,r.height,3,3)
            line(name,r.x+7,r.y+14,45)
        end
        local estimate,hours=Contracts.weeklyEstimate(t)
        button("payMinus","-",pointerX,pointerY);button("payPlus","+",pointerX,pointerY)
        line(string.format("Pay every %d week%s",t.payWeeks,t.payWeeks==1 and "" or "s"),478,500,292)
        line(string.format("Weekly $%.2f | Cycle estimate $%.2f",estimate,estimate*t.payWeeks),412,534,426)
        line(shiftAllowed and "4-12h shifts. Meals unpaid; rest and overtime paid."
            or "Offer hours do not match this applicant's shift preference.",412,552,426,
            shiftAllowed and {.61,.78,.67} or {1,.56,.48})
        button("send","EMAIL OFFER",pointerX,pointerY,readOnly or not Contracts.validTerms(t) or not shiftAllowed)
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
        line("Dismiss this employee?\n\nThey will stop at a safe machine checkpoint. Earned wages stay on payroll until paid.",412,298,426)
        button("confirmDismiss","CONFIRM DISMISSAL",pointerX,pointerY,readOnly)
        button("cancelDismiss","KEEP EMPLOYEE",pointerX,pointerY)
        return
    elseif ui.view=="training" then
        local pressInstalled=#Fleet.installedUnits(state,"heidelberg_10x15")>0
        local wrapperInstalled=#Fleet.installedUnits(state,"skid_wrapper")>0
        local cutterInstalled=#Fleet.installedUnits(state,"polar_115")>0
        local machineBusy=current.assignment~=nil and current.reserved==true
        local cutterPlan=Employees.trainingPlan(current,"cutter")
        local pressPlan=Employees.trainingPlan(current,"press")
        local wrapPlan=Employees.trainingPlan(current,"wrapping")
        local function price(plan)
            return plan and string.format("+%d  ~ $%.2f",plan.points,plan.expectedWageCents/100) or "SKILL MAX"
        end
        line("EMPLOYEE SKILL TRAINING",412,276,426,{1,.86,.50,1})
        line("Courses advance during paid shift hours at the installed machine. The employee earns normal wages while training.",412,306,416)
        line(string.format("Paper cutter %d/100 | Press %d/100 | Wrapping %d/100",
            current.cutterSkill,current.pressSkill,current.wrappingSkill),412,394,416,{.62,.79,.67,1})
        if current.training then
            line(string.format("Existing on-shift course: %s, %.1f paid hours remaining",current.training.skill,current.training.remainingHours),412,436,416,{1,.85,.45,1})
            line(current.clockedIn and current.activity or "Course progresses during paid hours on the next agreed shift.",412,464,416,{.61,.78,.67,1})
        else
            line("Choose a course. Each raises skill by up to 25 points.",412,436,416)
            line(machineBusy and "Finish the current machine cycle before training." or "Wage estimate is shown for each course.",
                412,464,416,machineBusy and {1,.72,.48,1} or {.61,.78,.67,1})
        end
        if current.training then
            button("cancelTraining","CANCEL TRAINING",pointerX,pointerY,readOnly)
        else
            button("trainingCutter","CUTTER "..price(cutterPlan),pointerX,pointerY,
                readOnly or machineBusy or (cutterPlan and not cutterInstalled))
            button("trainingPress","PRESS "..price(pressPlan),pointerX,pointerY,
                readOnly or machineBusy or (pressPlan and not pressInstalled))
            button("trainingWrap","WRAP "..price(wrapPlan),pointerX,pointerY,
                readOnly or machineBusy or (wrapPlan and not wrapperInstalled))
        end
        button("trainingBack","BACK TO STAFF",pointerX,pointerY)
        return
    end
    if ui.section=="applications" then
        local image,quad=CharacterAssets.get(current.character,"idle",1)
        if image then
            local ax,ay=CharacterAssets.getAnchor(current.character,"idle",1)
            love.graphics.setColor(1,1,1,1);love.graphics.draw(image,quad,784,370,0,.39,.39,ax,ay)
        end
        line("RESUME ATTACHED",410,288,300)
        line(string.format("Cutter %d/100  |  Press %d/100\nPallet wrapping %d/100  |  Attention %d  |  Reliability %d",
            current.cutterSkill,current.pressSkill,current.wrappingSkill,current.attention,current.reliability),410,316,326)
        line(string.format("Requested pay: $%.2f/hr",current.requestedWage/100),410,386,426)
        line("Shift preference: "..Contracts.shiftPreferenceLabel(current.shiftPreference),410,412,426)
        line(labels[current.status] or current.status,410,466,426,{1,.85,.45})
        if current.status=="visiting" then button("resume","REQUEST EMAIL RESUME",pointerX,pointerY,readOnly)
        elseif current.status=="resume_received" then button("offer","NEGOTIATE OFFER",pointerX,pointerY,readOnly)
        elseif current.status=="offer_accepted" then
            line(Contracts.summary(current.offer,twelveHourTime),410,488,426)
            button("sign",payrollFull and "PAYROLL FULL" or "SIGN & HIRE",pointerX,pointerY,readOnly or payrollFull)
            button("edit","RENEGOTIATE",pointerX,pointerY,readOnly)
        end
        if current.status~="hired" and current.status~="offer_accepted" then button("decline","DECLINE APPLICATION",pointerX,pointerY,readOnly) end
        if current.counter then line(string.format("Counteroffer: $%.2f/hr",current.counter.wageCents/100),410,574,426,{1,.85,.45}) end
    else
        local w=current
        line(Contracts.summary(w.contract,twelveHourTime),410,290,426)
        line("Shift preference: "..Contracts.shiftPreferenceLabel(w.shiftPreference),410,316,426,{.61,.78,.67})
        line(string.format("Cutter %d/100 | Press %d/100 | Wrapping %d/100",w.cutterSkill,w.pressSkill,w.wrappingSkill),410,340,426)
        local scheduleStatus,scheduleDetail=Hiring.staffScheduleStatus(state,w)
        line(w.training and string.format("Training: %s (%.1f paid hours left)",w.training.skill,w.training.remainingHours)
            or scheduleStatus or w.activity,410,374,426,{1,.85,.45})
        local assignedMachine=w.assignment and Fleet.byId(state,w.assignment.machineId)
        line(w.assignment and ("Job "..w.assignment.jobId.."\nPallet "..w.assignment.palletId.."\n"
            ..(assignedMachine and assignedMachine.name or "Machine").." "..w.assignment.machineId)
            or scheduleDetail,410,404,426)
        local payday=Calendar.shortDate({calendar=Calendar.dateFromHours(Payroll.nextPayday(w,now))})
        line("Payday: "..payday.." at 09:00 (every "..w.contract.payWeeks.."w)",410,458,426,{.61,.78,.67})
        line(string.format("Wages due $%.2f | Earned unpaid $%.2f",Payroll.balance(w,now,false)/100,Payroll.balance(w,now,true)/100),410,484,214)
        if w.status=="employed" then
            button("train",w.training and "MANAGE TRAINING" or "IMPROVE EMPLOYEE SKILLS",pointerX,pointerY,readOnly)
            button("assign",w.assignment and "WORK ASSIGNED" or "ASSIGN JOB",pointerX,pointerY,readOnly or w.assignment~=nil)
            local sentHomeToday=w.sentHomeShiftDay==Contracts.shiftDay(w.contract,now)
            line("Ends today's shift safely; unfinished work resumes next shift.",410,502,426,{.61,.78,.67})
            button("sendHome",sentHomeToday and "SENT HOME" or "SEND HOME",pointerX,pointerY,
                readOnly or sentHomeToday or not (w.visible and w.clockedIn))
            button("pause","PAUSE ASSIGNMENT",pointerX,pointerY,readOnly or w.assignment==nil)
            button("dismiss","DISMISS",pointerX,pointerY,readOnly)
        end
    end
end
return Hiring
