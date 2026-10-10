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
    up=rect(636,500,104,40),down=rect(750,500,108,40),remove=rect(636,548,222,42),
    previous=rect(98,568,90,38),next=rect(522,568,90,38),
    jobPrev=rect(98,352,44,40),jobNext=rect(568,352,44,40),
    machinePrev=rect(98,442,44,40),machineNext=rect(568,442,44,40),confirm=rect(98,524,514,46)}
local function rowRect(i) return rect(98,330+(i-1)*43,514,38) end
function Screen.new() return {workerId=nil,team=true,view="queue",page=1,itemId=nil,jobId=nil,jobIndex=1,machineIndex=1} end
function Screen.buttonCenter(name) local r=buttons[name];if not r then return nil end;return r.x+r.width/2,r.y+r.height/2 end
function Screen.rowCenter(i) local r=rowRect(i);return r.x+r.width/2,r.y+r.height/2 end
local function workers(state)
    local all={}
    for _,w in ipairs(Employees.ensure(state).staff) do if w.status=="employed" then all[#all+1]=w end end
    return all
end
local function teamWorker(state,teamTaskId)
    for _,w in ipairs(Employees.ensure(state).staff) do
        for _,row in ipairs(Schedule.ensure(w).items) do
            if row.teamTaskId==teamTaskId and w.assignment
                and w.assignment.scheduleItemId==row.id then return w end
        end
    end
end
local function selected(state,ui)
    local all=workers(state)
    for i,w in ipairs(all) do if w.id==ui.workerId then return w,i,all end end
    ui.workerId=all[1] and all[1].id or nil
    return all[1],1,all
end
local function selectJob(ui,jobs,index)
    ui.jobIndex=math.min(math.max(index or 1,1),math.max(1,#jobs))
    local job=jobs[ui.jobIndex]
    ui.jobId=job and job.id or nil
    return job
end
local function cutterAssignment(state,machineId)
    local machines=Fleet.installedUnits(state,"polar_115")
    for index,machine in ipairs(machines) do
        if machine.id==machineId then
            return string.format("CUTTER %d · %s",index,machine.id),index
        end
    end
    local machine=machineId and Fleet.byId(state,machineId)
    if machine then return "CUTTER OFFLINE · "..machine.id,nil end
    return "CUTTER UNAVAILABLE · "..tostring(machineId or "UNKNOWN"),nil
end
local function choices(state,ui)
    local jobs,index={},ui.jobIndex
    for _,job in ipairs(state.jobs.active or {}) do
        if Schedule.stockArrived(job) then
            jobs[#jobs+1]=job
            if job.id==ui.jobId then index=#jobs end
        end
    end
    local machines=Fleet.installedUnits(state,"polar_115")
    local job=selectJob(ui,jobs,index)
    ui.machineIndex=math.min(math.max(ui.machineIndex,1),math.max(1,#machines))
    return job,machines[ui.machineIndex],#jobs,#machines,jobs
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
local function qualifiedCount(state,field,minimum)
    if minimum==nil then return nil end
    local count=0
    for _,worker in ipairs(workers(state)) do
        if (worker[field] or 0)>=minimum then count=count+1 end
    end
    return count
end
function Screen.mousepressed(state,ui,x,y,command,readOnly)
    ui.team=true
    local function hit(name) return Ui.contains(buttons[name],x,y) end
    local function send(intent)
        if readOnly then state.message="Schedule changes are not available from this screen.";return {action="blocked"} end
        return command(intent)
    end
    local w,index,all=selected(state,ui)
    if ui.team then
        local team=Schedule.team(state)
        if hit("run") then return send({kind="set_team_schedule",enabled=not team.enabled}) end
        for _,view in ipairs({"queue","add","history"}) do if hit(view) then
            ui.view=view;ui.page=1;ui.itemId=nil;return {action="schedule_view"}
        end end
        if ui.view=="add" then
            local job,machine,_,nm,jobs=choices(state,ui)
            if hit("jobPrev") then selectJob(ui,jobs,ui.jobIndex-1)
            elseif hit("jobNext") then selectJob(ui,jobs,ui.jobIndex+1)
            elseif hit("machinePrev") then ui.machineIndex=math.max(1,ui.machineIndex-1)
            elseif hit("machineNext") then ui.machineIndex=math.min(nm,ui.machineIndex+1)
            elseif hit("confirm") and job and machine then
                local okay,message=Schedule.canQueueTeam(state,job.id,machine.id)
                if not okay then state.message=message;return {action="blocked"} end
                local result=send({kind="queue_team_job",jobId=job.id,machineId=machine.id})
                if result and result.action~="blocked" then
                    ui.view="queue";ui.page=1;ui.itemId=team.items[#team.items] and team.items[#team.items].id
                end
                return result
            else return nil end
            return {action="schedule_choice"}
        end
        local rows=list(team,ui)
        ui.page=math.min(ui.page,math.max(1,math.ceil(#rows/5)))
        if hit("previous") then ui.page=math.max(1,ui.page-1);return {action="schedule_page"} end
        if hit("next") then ui.page=math.min(math.max(1,math.ceil(#rows/5)),ui.page+1);return {action="schedule_page"} end
        if ui.view=="history" then return nil end
        for i=1,5 do local row=rows[(ui.page-1)*5+i]
            if row and Ui.contains(rowRect(i),x,y) then ui.itemId=row.id;return {action="schedule_selected"} end
        end
        local row=chosenItem(team,ui)
        if row and (hit("up") or hit("down") or hit("remove")) then
            local intent={kind=hit("remove") and "remove_team_job" or "move_team_job",
                itemId=row.id,expectedRevision=team.revision}
            if intent.kind=="move_team_job" then intent.direction=hit("up") and -1 or 1 end
            return send(intent)
        end
        return nil
    end
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
        local job,machine,_,nm,jobs=choices(state,ui)
        if hit("jobPrev") then selectJob(ui,jobs,ui.jobIndex-1)
        elseif hit("jobNext") then selectJob(ui,jobs,ui.jobIndex+1)
        elseif hit("machinePrev") then ui.machineIndex=math.max(1,ui.machineIndex-1)
        elseif hit("machineNext") then ui.machineIndex=math.min(nm,ui.machineIndex+1)
        elseif hit("confirm") and job and machine then
            local okay,message=Schedule.canQueue(state,w,job.id,machine.id)
            if not okay then
                state.message=message
                return {action="blocked"}
            end
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
    love.graphics.setColor(color or {.86,.91,.92,1});love.graphics.printf(text,x,y,width,"left")
end
local function short(text,x,y,width,color) line(fit(text,width),x,y,width,color) end
local function drawMinimumSkills(state,job,x,y,width)
    if not job then
        line("Unload a job into the shop to see its skill requirements.",x,y,width)
        return
    end
    local minimum=Schedule.minimumSkills(job)
    short("MINIMUM SKILLS / QUALIFIED STAFF",x,y,width,{1,.86,.43,1})
    local function entry(label,field,value,offset)
        if value==nil then
            short(label..": Not required",x,y+offset,width,{.61,.69,.69,1})
            return
        end
        local qualified=qualifiedCount(state,field,value)
        local color=qualified>0 and {.62,.79,.67,1} or {1,.56,.48,1}
        short(string.format("%s min %d | %d qualified",label,value,qualified),x,y+offset,width,color)
    end
    entry("CUTTER","cutterSkill",minimum.cutter,20)
    entry("PRINTING","pressSkill",minimum.press,38)
    entry("WRAPPING","wrappingSkill",minimum.wrapping,56)
end
local scheduleButtonRenderer
local function button(name,label,x,y,disabled,active)
    local r=buttons[name]
    local hover=x and y and Ui.contains(r,x,y)
    local primary=active or name=="run" or name=="confirm"
    if scheduleButtonRenderer then
        local style=disabled and "disabled"
            or name=="remove" and (hover and "dangerHover" or "danger")
            or primary and (hover and "primaryHover" or "primary")
            or hover and "hover" or "secondary"
        scheduleButtonRenderer(r,label,style)
        return
    end
    local edge,face,highlight,shadow,textColor
    if disabled then
        edge,face,highlight,shadow,textColor={.10,.14,.16,1},{.22,.28,.30,1},
            {.39,.47,.47,1},{.12,.17,.18,1},{.70,.76,.75,1}
    elseif name=="remove" then
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
    love.graphics.setColor(edge);love.graphics.rectangle("fill",r.x,r.y,r.width,r.height,3,3)
    love.graphics.setColor(face);love.graphics.rectangle("fill",r.x+2,r.y+2,r.width-4,r.height-4,2,2)
    love.graphics.setColor(highlight);love.graphics.rectangle("fill",r.x+4,r.y+3,r.width-8,1)
    love.graphics.setColor(shadow);love.graphics.rectangle("fill",r.x+4,r.y+r.height-4,r.width-8,1)
    love.graphics.setColor(textColor)
    love.graphics.printf(label,r.x+4,r.y+(r.height-love.graphics.getFont():getHeight())/2,r.width-8,"center")
end
local function panel(x,y,w,h)
    love.graphics.setColor(.015,.025,.035,1);love.graphics.rectangle("fill",x,y+2,w,h,4,4)
    love.graphics.setColor(.045,.075,.095,1);love.graphics.rectangle("fill",x,y,w,h,4,4)
    love.graphics.setColor(.29,.52,.56,1);love.graphics.setLineWidth(1)
    love.graphics.rectangle("line",x+.5,y+.5,w-1,h-1,4,4)
    love.graphics.setColor(.39,.62,.65,1);love.graphics.line(x+5,y+2,x+w-6,y+2)
end
function Screen.draw(state,ui,x,y,readOnly,buttonRenderer,twelveHourTime)
    ui.team=true
    scheduleButtonRenderer=buttonRenderer
    panel(84,186,792,434)
    short("WORK SCHEDULE",98,196,215,{1,.86,.43,1})
    local w,index,all=selected(state,ui)
    if not w and not ui.team then
        line("Hire an employee in HIRING, then build their ordered production list here.",98,248,714)
        return
    end
    local q=ui.team and Schedule.team(state) or Schedule.ensure(w)
    panel(92,326,528,280)
    panel(626,326,238,280)
    short(ui.team and "ONE SHOP SCHEDULE  |  DAY + NIGHT" or w.activity,
        320,196,535,{.62,.79,.67,1})
    short(ui.team and ("ALL WORKERS  |  DAY + NIGHT SHIFTS  |  "..#all.." employed")
        or w.name.."  |  "..index.."/"..#all,154,234,420)
    short(ui.team and "The next available worker takes the next ready job. Night shift continues where day shift stopped."
        or Contracts.summary(w.contract,twelveHourTime),154,253,420,{.58,.73,.65,1})
    button("run",q.enabled and "PAUSE SCHEDULE" or "RESUME SCHEDULE",x,y,readOnly)
    button("queue","SCHEDULED JOBS ("..#q.items..")",x,y,false,ui.view=="queue")
    button("add","ADD JOB",x,y,readOnly,ui.view=="add")
    button("history","JOB HISTORY",x,y,false,ui.view=="history")
    if ui.view=="add" then
        local job,machine,nj,nm=choices(state,ui)
        local okay,message=false,"Install a cutter to schedule this job."
        if not job then message="Jobs appear here after every skid has been unloaded into the shop." end
        if job and machine then
            if ui.team then okay,message=Schedule.canQueueTeam(state,job.id,machine.id)
            else okay,message=Schedule.canQueue(state,w,job.id,machine.id) end
        end
        line("Job on shop floor",98,330,514)
        button("jobPrev","<",x,y,ui.jobIndex<=1);button("jobNext",">",x,y,ui.jobIndex>=nj)
        short(job and job.id or "No jobs on the shop floor",154,351,400)
        short(job and job.company or "",154,371,400,{.62,.79,.67,1})
        local done,total=Schedule.progress(job)
        line(string.format("Finished pallets: %d/%d",done,total),98,404,514)
        local _,cutterIndex=cutterAssignment(state,machine and machine.id)
        line("Assigned cutter",98,425,514)
        button("machinePrev","<",x,y,ui.machineIndex<=1);button("machineNext",">",x,y,ui.machineIndex>=nm)
        short(machine and ("CUTTER "..tostring(cutterIndex or "?").." · "..(machine.shortName or machine.name)) or "No installed cutter",154,441,400)
        short(machine and machine.id or "",154,461,400,{.62,.79,.67,1})
        line(message,98,493,514,{1,.86,.43,1})
        button("confirm","ADD TO SCHEDULE",x,y,readOnly or not okay)
        drawMinimumSkills(state,job,636,332,222)
        line(ui.team and "Qualified staff can complete the listed stages on either shift. Night shift continues where day shift stopped."
            or "Jobs run from top to bottom. Employees cut every skid and complete any required printing before wrapping the order for shipping.\n\nStage pallets at each machine. Train workers in HIRING before they reach press or wrapping work.\n\nUnfinished jobs pass to the next qualified shift.",636,430,222)
        return
    end
    local rows=list(q,ui)
    ui.page=math.min(ui.page,math.max(1,math.ceil(#rows/5)))
    local selectedRow,selectedIndex=chosenItem(q,ui)
    if #rows==0 then line(ui.view=="history" and "Completed and removed jobs will appear here."
        or ui.team and "No jobs scheduled. Add jobs here once; day and night workers will share the same list."
        or "No queued jobs. Choose ADD JOB to build this employee's schedule.",98,344,508) end
    for i=1,5 do
        local row=rows[(ui.page-1)*5+i]
        if row then
            local r=rowRect(i);local n=(ui.page-1)*5+i
            love.graphics.setColor(.025,.045,.06,1);love.graphics.rectangle("fill",r.x,r.y,r.width,r.height,3,3)
            love.graphics.setColor(row.id==ui.itemId and {.015,.34,.37,1} or {.09,.14,.16,1})
            love.graphics.rectangle("fill",r.x+2,r.y+2,r.width-4,r.height-4,2,2)
            love.graphics.setColor(row.id==ui.itemId and {.42,.83,.79,1} or {.23,.39,.42,1})
            love.graphics.rectangle("line",r.x+1.5,r.y+1.5,r.width-3,r.height-3,3,3)
            local job=Schedule.job(state,row.jobId)
            short((ui.view=="queue" and n..". " or "")..row.jobId..(job and "  |  "..job.company or ""),r.x+10,r.y+3,r.width-20)
            local status
            if ui.view=="history" then
                local assignedCutter=cutterAssignment(state,row.machineId)
                status=assignedCutter.." | "..(row.result=="complete" and "Production complete" or row.result=="removed" and "Removed from schedule" or "Job no longer available").." | Game day "..(math.floor(row.finishedAtHours/24)+1)
                if ui.team and row.workerId then
                    local worker=Employees.worker(state,row.workerId)
                    status=status.." | "..(worker and worker.name or "Worker")
                end
            else
                local done,total=Schedule.progress(job)
                local _,_,nextPallet=Schedule.progress(job)
                local stage=Schedule.stage(job,nextPallet)
                local stageName=stage=="cutter" and "cutting" or stage=="press" and "printing"
                    or stage=="wrapping" and "wrapping" or "finished"
                local assignedCutter=cutterAssignment(state,row.machineId)
                status=assignedCutter..string.format(" | %d/%d finished | %s",done,total,stageName)
                if ui.team then
                    local assigned=teamWorker(state,row.id)
                    if assigned then status=status.." | WITH "..assigned.name end
                end
                if w and w.assignment and w.assignment.scheduleItemId==row.id then status="CURRENT | "..status end
            end
                short(status,r.x+10,r.y+20,r.width-20,{.61,.82,.82,1})
        end
    end
    local pages=math.max(1,math.ceil(#rows/5))
    button("previous","<",x,y,ui.page<=1);button("next",">",x,y,ui.page>=pages)
    line("Page "..ui.page.." / "..pages,236,580,270)
    if ui.view=="history" then
        line("This history records completed production and pallet wrapping. Customer pickup remains a separate step.",636,334,222)
        return
    end
    if selectedRow then
        local _,cutterIndex=cutterAssignment(state,selectedRow.machineId)
        line("Selected job #"..selectedIndex..(cutterIndex and " · CUTTER "..cutterIndex or ""),636,334,222,{1,.86,.43,1})
        short(selectedRow.jobId,636,356,222)
        local job=Schedule.job(state,selectedRow.jobId)
        local done,total=Schedule.progress(job)
        local _,_,nextPallet=Schedule.progress(job)
        local stage=Schedule.stage(job,nextPallet)
        local stageName=stage=="cutter" and "Cutting" or stage=="press" and "Printing"
            or stage=="wrapping" and "Wrapping" or "Complete"
        line(string.format("%d / %d pallets finished",done,total),636,380,222)
        line("Next stage: "..stageName,636,400,222,{.62,.79,.67,1})
        drawMinimumSkills(state,job,636,420,222)
    end
    local active=selectedRow and (ui.team and teamWorker(state,selectedRow.id)~=nil or not ui.team and Schedule.isLocked(state,w,selectedRow))
    local previous=q.items[selectedIndex-1];local following=q.items[selectedIndex+1]
    local previousLocked=ui.team and previous and teamWorker(state,previous.id)~=nil
        or not ui.team and Schedule.isLocked(state,w,previous)
    local followingLocked=ui.team and following and teamWorker(state,following.id)~=nil
        or not ui.team and Schedule.isLocked(state,w,following)
    button("up","MOVE UP",x,y,readOnly or not selectedRow or selectedIndex<=1 or active or previousLocked)
    button("down","MOVE DOWN",x,y,readOnly or not selectedRow or selectedIndex>=#q.items or active or followingLocked)
    button("remove",ui.team and "REMOVE FROM SCHEDULE" or "REMOVE JOB",x,y,readOnly or not selectedRow or active)
end
return Screen
