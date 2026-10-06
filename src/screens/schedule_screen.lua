local Employees=require("src.employees")
local Schedule=require("src.employee_schedule")
local Contracts=require("src.employment_contracts")
local Calendar=require("src.business_calendar")
local Fleet=require("src.machine_fleet")
local Ui=require("src.screens.ui")
local Screen={}
local function rect(x,y,w,h) return {x=x,y=y,width=w,height=h} end
local buttons={workerPrev=rect(98,232,44,40),workerNext=rect(586,232,44,40),run=rect(642,232,218,40),
    queue=rect(98,280,158,36),add=rect(266,280,164,36),history=rect(440,280,164,36),
    up=rect(636,430,104,40),down=rect(750,430,108,40),remove=rect(636,480,222,42),
    previous=rect(98,568,90,38),next=rect(522,568,90,38),
    jobPrev=rect(98,352,44,40),jobNext=rect(568,352,44,40),
    machinePrev=rect(98,442,44,40),machineNext=rect(568,442,44,40),confirm=rect(98,524,514,46)}
local function rowRect(i) return rect(98,330+(i-1)*43,514,38) end
function Screen.new() return {workerId=nil,view="queue",page=1,itemId=nil,jobIndex=1,machineIndex=1} end
function Screen.buttonCenter(name) local r=buttons[name];return r.x+r.width/2,r.y+r.height/2 end
function Screen.rowCenter(i) local r=rowRect(i);return r.x+r.width/2,r.y+r.height/2 end
local function workers(state)
    local all={}
    for _,w in ipairs(Employees.ensure(state).staff) do if w.status=="employed" then all[#all+1]=w end end
    return all
end
local function selected(state,ui)
    local all=workers(state)
    for i,w in ipairs(all) do if w.id==ui.workerId then return w,i,all end end
    ui.workerId=all[1] and all[1].id or nil
    return all[1],1,all
end
local function choices(state,ui)
    local jobs=state.jobs.active or {}
    local machines=Fleet.installedUnits(state,"polar_115")
    ui.jobIndex=math.min(math.max(ui.jobIndex,1),math.max(1,#jobs))
    ui.machineIndex=math.min(math.max(ui.machineIndex,1),math.max(1,#machines))
    return jobs[ui.jobIndex],machines[ui.machineIndex],#jobs,#machines
end
local function list(q,ui)
    if ui.view~="history" then return q.items end
    local all={};for i=#q.history,1,-1 do all[#all+1]=q.history[i] end;return all
end
local function chosenItem(q,ui)
    for i,row in ipairs(q.items) do if row.id==ui.itemId then return row,i end end
    ui.itemId=q.items[1] and q.items[1].id or nil
    return q.items[1],1
end
function Screen.mousepressed(state,ui,x,y,command,readOnly)
    local function hit(name) return Ui.contains(buttons[name],x,y) end
    local function send(intent)
        if readOnly then state.message="Only the shop owner can change work schedules.";return {action="blocked"} end
        return command(intent)
    end
    local w,index,all=selected(state,ui)
    if hit("workerPrev") or hit("workerNext") then
        index=math.max(1,math.min(#all,index+(hit("workerPrev") and -1 or 1)))
        ui.workerId=all[index] and all[index].id or nil;ui.page=1;ui.itemId=nil
        return {action="schedule_view"}
    end
    for _,view in ipairs({"queue","add","history"}) do if hit(view) then
        ui.view=view;ui.page=1;ui.itemId=nil;return {action="schedule_view"}
    end end
    if not w then return nil end
    local q=Schedule.ensure(w)
    if hit("run") then return send({kind="set_employee_schedule",employeeId=w.id,enabled=not q.enabled}) end
    if ui.view=="add" then
        local job,machine,nj,nm=choices(state,ui)
        if hit("jobPrev") then ui.jobIndex=math.max(1,ui.jobIndex-1)
        elseif hit("jobNext") then ui.jobIndex=math.min(nj,ui.jobIndex+1)
        elseif hit("machinePrev") then ui.machineIndex=math.max(1,ui.machineIndex-1)
        elseif hit("machineNext") then ui.machineIndex=math.min(nm,ui.machineIndex+1)
        elseif hit("confirm") and job and machine then
            local result=send({kind="queue_employee_job",employeeId=w.id,jobId=job.id,machineId=machine.id})
            if result and result.action~="blocked" then ui.view="queue";ui.page=1;ui.itemId=q.items[#q.items] and q.items[#q.items].id end
            return result
        else return nil end
        return {action="schedule_choice"}
    end
    local rows=list(q,ui)
    ui.page=math.min(ui.page,math.max(1,math.ceil(#rows/5)))
    if hit("previous") then ui.page=math.max(1,ui.page-1);return {action="schedule_page"} end
    if hit("next") then ui.page=math.min(math.max(1,math.ceil(#rows/5)),ui.page+1);return {action="schedule_page"} end
    if ui.view=="history" then return nil end
    for i=1,5 do local row=rows[(ui.page-1)*5+i]
        if row and Ui.contains(rowRect(i),x,y) then ui.itemId=row.id;return {action="schedule_selected"} end
    end
    local row=chosenItem(q,ui)
    if row and (hit("up") or hit("down") or hit("remove")) then
        local intent={kind=hit("remove") and "remove_employee_job" or "move_employee_job",
            employeeId=w.id,itemId=row.id,expectedRevision=q.revision}
        if intent.kind=="move_employee_job" then intent.direction=hit("up") and -1 or 1 end
        return send(intent)
    end
end
local function fit(text,width)
    local font=love.graphics.getFont()
    text=tostring(text or "")
    if font:getWidth(text)<=width then return text end
    while #text>0 and font:getWidth(text.."...")>width do text=text:sub(1,-2) end
    return text.."..."
end
local function line(text,x,y,width,color)
    love.graphics.setColor(color or {.80,.88,.83,1});love.graphics.printf(text,x,y,width,"left")
end
local function short(text,x,y,width,color) line(fit(text,width),x,y,width,color) end
local function button(name,label,x,y,disabled,active)
    local r=buttons[name]
    local hover=x and y and Ui.contains(r,x,y)
    love.graphics.setColor(disabled and {.13,.19,.18,1} or active and {.19,.43,.28,1} or hover and {.24,.39,.34,1} or {.15,.28,.26,1})
    love.graphics.rectangle("fill",r.x,r.y,r.width,r.height,3,3)
    love.graphics.setColor(disabled and {.40,.48,.45,1} or {.90,.95,.91,1})
    love.graphics.printf(label,r.x+4,r.y+(r.height-love.graphics.getFont():getHeight())/2,r.width-8,"center")
end
function Screen.draw(state,ui,x,y,readOnly)
    love.graphics.setColor(.075,.13,.115,1);love.graphics.rectangle("fill",84,186,792,434,4,4)
    short("WORK SCHEDULE",98,196,215,{1,.86,.43,1})
    local w,index,all=selected(state,ui)
    if not w then
        line("Hire an employee in HIRING, then build their ordered list of cutter jobs here.",98,248,714)
        return
    end
    local q=Schedule.ensure(w)
    short(w.activity,320,196,535,{.62,.79,.67,1})
    button("workerPrev","<",x,y,index<=1);button("workerNext",">",x,y,index>=#all)
    short(w.name.."  |  "..index.."/"..#all,154,234,420)
    short(Contracts.summary(w.contract),154,253,420,{.58,.73,.65,1})
    button("run",q.enabled and "PAUSE SCHEDULE" or "RESUME SCHEDULE",x,y,readOnly)
    button("queue","QUEUED JOBS ("..#q.items..")",x,y,false,ui.view=="queue")
    button("add","ADD JOB",x,y,readOnly,ui.view=="add")
    button("history","COMPLETED / REMOVED",x,y,false,ui.view=="history")
    if ui.view=="add" then
        local job,machine=choices(state,ui)
        local okay,message=false,"Accept a job and install a cutter first."
        if job and machine then okay,message=Schedule.canQueue(state,w,job.id,machine.id) end
        line("Accepted job",98,330,514)
        button("jobPrev","<",x,y);button("jobNext",">",x,y)
        short(job and job.id or "No accepted jobs",154,351,400)
        short(job and job.company or "",154,371,400,{.62,.79,.67,1})
        local done,total=Schedule.progress(job)
        line(string.format("Cutting progress: %d/%d pallets complete",done,total),98,404,514)
        line("Installed cutter",98,425,514)
        button("machinePrev","<",x,y);button("machineNext",">",x,y)
        short(machine and machine.name or "No installed cutter",154,441,400)
        short(machine and machine.id or "",154,461,400,{.62,.79,.67,1})
        line(message,98,493,514,{1,.86,.43,1})
        button("confirm","ADD TO END OF SCHEDULE",x,y,readOnly or not okay)
        line("Jobs run from top to bottom. Every pallet in a job is cut before the next job starts.\n\nStage each pallet beside its selected cutter and keep the output clear.\n\nWork follows the employee's agreed shifts and breaks.",636,332,222)
        return
    end
    local rows=list(q,ui)
    ui.page=math.min(ui.page,math.max(1,math.ceil(#rows/5)))
    local selectedRow,selectedIndex=chosenItem(q,ui)
    if #rows==0 then line(ui.view=="history" and "Completed and removed jobs will appear here." or "No queued jobs. Choose ADD JOB to build this employee's schedule.",98,344,508) end
    for i=1,5 do
        local row=rows[(ui.page-1)*5+i]
        if row then
            local r=rowRect(i);local n=(ui.page-1)*5+i
            love.graphics.setColor(row.id==ui.itemId and {.20,.36,.26,1} or {.12,.23,.19,1})
            love.graphics.rectangle("fill",r.x,r.y,r.width,r.height,3,3)
            local job=Schedule.job(state,row.jobId)
            short((ui.view=="queue" and n..". " or "")..row.jobId..(job and "  |  "..job.company or ""),r.x+10,r.y+3,r.width-20)
            local status
            if ui.view=="history" then
                status=(row.result=="complete" and "Cutting complete" or row.result=="removed" and "Removed from schedule" or "Job no longer available").." | Game day "..(math.floor(row.finishedAtHours/24)+1)
            else
                local done,total=Schedule.progress(job)
                status=string.format("%d/%d pallets cut | %s",done,total,row.machineId)
                if w.assignment and w.assignment.scheduleItemId==row.id then status="CURRENT | "..status end
            end
            short(status,r.x+10,r.y+20,r.width-20,{.61,.79,.66,1})
        end
    end
    local pages=math.max(1,math.ceil(#rows/5))
    button("previous","<",x,y,ui.page<=1);button("next",">",x,y,ui.page>=pages)
    line("Page "..ui.page.." / "..pages,236,580,270)
    if ui.view=="history" then
        line("This history records cutter work. Printing, wrapping and customer pickup remain separate job stages.",636,334,222)
        return
    end
    if selectedRow then
        line("Selected job #"..selectedIndex,636,334,222,{1,.86,.43,1})
        short(selectedRow.jobId,636,356,222)
        local job=Schedule.job(state,selectedRow.jobId)
        local done,total=Schedule.progress(job)
        line(string.format("%d / %d pallets cut",done,total),636,380,222)
    end
    local active=selectedRow and Schedule.isLocked(state,w,selectedRow)
    button("up","MOVE UP",x,y,readOnly or not selectedRow or selectedIndex<=1 or active or Schedule.isLocked(state,w,q.items[selectedIndex-1]))
    button("down","MOVE DOWN",x,y,readOnly or not selectedRow or selectedIndex>=#q.items or active or Schedule.isLocked(state,w,q.items[selectedIndex+1]))
    button("remove","REMOVE JOB",x,y,readOnly or not selectedRow or active)
    line(q.enabled and "Runs automatically during agreed shifts. Stage stock and clear the cutter output." or "Schedule paused. Resume when ready. Loaded work stays safe.",636,538,222,{.62,.79,.67,1})
end
return Screen
