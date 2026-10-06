-- Actual game renderer and AI preview. Uses a fresh identity, never game saves.
local output=assert(os.getenv("PICTURE_SHOP_PREVIEW_OUTPUT"))
io.stdout:setvbuf("no")
function love.errorhandler(message)
    local detail=tostring(message).."\n"..debug.traceback()
    local f=io.open(output.."/error.txt","wb");if f then f:write(detail);f:close() end
    print(detail);return function() return 1 end
end
assert(love.filesystem.getIdentity():match("^the%-picture%-shop%-test%-[%w%-]+$"),"Fresh preview identity required")
local State=require("src.state")
local Assets=require("src.assets")
local Characters=require("src.character_assets")
local World=require("src.world")
local Calendar=require("src.business_calendar")
local Employees=require("src.employees")
local AI=require("src.employee_ai")
local Machine=require("src.machine")
local Fleet=require("src.machine_fleet")
local Jobs=require("src.jobs")
local Logistics=require("src.pallet_logistics")
local Zones=require("src.cutter_zones")
local Config=require("src.config")
local Computer=require("src.screens.computer_screen").new()
local Contracts=require("src.employment_contracts")
local Schedule=require("src.employee_schedule")
local Work=require("src.employee_work")
local scenes,shot,pending={},1,false
local state,applicant,worker
local function setHours(s,h)
    s.calendar=Calendar.dateFromTotalDay(math.floor(h/24));s.calendar.elapsed=(h%24)/24*300
    s.employment.lastAtHours=h
end
local function tick(dt)
    Calendar.update(state,dt)
    World.updateSimulation(dt,Assets,state)
    Machine.updateAll(dt,state)
end
local function add(name,s,view)
    scenes[#scenes+1]={name=name,state=State.applySave and require("src.screens.gui_projection").copy(s),view=view}
end
local function prepareScene()
    local scene=scenes[shot]
    if not scene then
        local f=assert(io.open(output.."/engine-review.txt","wb"))
        f:write("PASS: real applicant route, automatic scheduled cutter route and cut cycle, completion history, occupied breakroom seat, Hiring and Schedule pages and full computer dropdown; desktop and phone landscape captures.\n")
        f:close();love.event.quit(0);return
    end
    local phone=scene.phone
    love.window.setMode(phone and 1600 or 960,phone and 720 or 678,{vsync=0,resizable=false})
    if scene.view~="world" then
        Computer.tab=scene.view=="email" and "email" or scene.view=="schedule" and "schedule" or "hiring"
        Computer.tabDropdownOpen=scene.dropdown==true
        Computer.hiring.section=scene.section or "applications"
        Computer.hiring.view=scene.page or "detail"
        Computer.hiring.selectedId=scene.recordId
        Computer.hiring.terms=Contracts.terms(2200,31,9,17)
        Computer.selectedEmailId=scene.emailId
        Computer.schedule.view=scene.page or "queue"
        Computer.schedule.workerId=scene.recordId
        Computer.schedule.jobIndex=scene.jobIndex or 1
    end
end
function love.load()
    love.graphics.setDefaultFilter("nearest","nearest")
    love.graphics.setFont(love.graphics.newFont(13))
    Assets.load();Characters.load();assert(Characters.assertHealthy())
    state=State.new();state.screen="world";state.money=5000
    World.load({x=500,y=455});World.configureEmployees({})
    Machine.setOutputResolver(function(s,p) return World.findCutterOutput(s,Assets,p.id) end)
    for i=1,400 do tick(.05);applicant=state.employment.applications[1];if applicant and applicant.actor.phase=="waiting" then break end end
    assert(applicant and applicant.actor.phase=="waiting","Applicant route failed: "..tostring(applicant and applicant.actor.phase).." "..tostring(applicant and applicant.actor.x)..","..tostring(applicant and applicant.actor.y))
    local px,py=World.player.x,World.player.y
    World.player.x,World.player.y=applicant.actor.x-13,applicant.actor.y+19
    World.update(0,0,0,Assets,state,applicant.actor.x,applicant.actor.y)
    assert(World.selectedInteraction and World.selectedInteraction.kind=="applicant","Applicant cannot be selected at reception")
    World.player.x,World.player.y=px,py
    add("applicant-at-reception",state,"world")
    assert(Employees.requestResume(state,applicant.id,Calendar.absoluteHours(state)))
    for i=1,180 do tick(.05) end
    assert(applicant.status=="resume_received")
    add("resume",state,"hiring");scenes[#scenes].recordId=applicant.id
    add("offer",state,"hiring");scenes[#scenes].recordId=applicant.id;scenes[#scenes].page="offer"
    assert(Employees.command(state,{kind="offer_employee",applicationId=applicant.id,expectedRevision=applicant.revision,wageCents=2200,days=31,startHour=9,endHour=17}))
    for i=1,220 do tick(.05) end
    assert(Employees.command(state,{kind="hire_employee",applicationId=applicant.id,expectedRevision=applicant.revision}))
    worker=state.employment.staff[1]
    local job=assert(Jobs.createOffer({id="JOB-CAT-DEMO",company="Oak Street Prints",sourceSize={width=20,height=16},finishedSize={width=10,height=8},sheetCounts={1000}}))
    Jobs.accept(job);state.jobs.active[1]=job
    Logistics.unload(state,job.id,job.pallets[1].id,Config.palletLogistics.spawnPoints,Config.palletLogistics.unloadOrigin)
    local pallet=job.pallets[1];local x,y=Zones.inputAnchor(state,Config.cutterPlacement)
    pallet.world.x,pallet.world.y=x,y;pallet.world.fromX,pallet.world.fromY=x,y;pallet.world.spawnProgress=1
    local machine=Fleet.installedUnits(state,"polar_115")[1]
    assert(Employees.command(state,{kind="queue_employee_job",employeeId=worker.id,jobId=job.id,machineId=machine.id}))
    for i=2,3 do
        local nextJob=assert(Jobs.createOffer({id="JOB-CAT-DEMO-"..i,company=i==2 and "Maple Paper Co." or "Riverside Flyers",sourceSize={width=20,height=16},finishedSize={width=10,height=8},sheetCounts={500}}))
        Jobs.accept(nextJob);state.jobs.active[#state.jobs.active+1]=nextJob
        if i==2 then assert(Employees.command(state,{kind="queue_employee_job",employeeId=worker.id,jobId=nextJob.id,machineId=machine.id})) end
    end
    setHours(state,9)
    local m=Machine.forId(machine.id)
    for i=1,900 do tick(.05);if m.step=="cutting" and worker.workFrame==4 then break end end
    assert(m.step=="cutting","Cat cutter route failed: "..worker.activity.." "..worker.x..","..worker.y.." "..m.step)
    add("cat-working-cutter",state,"world")
    add("staff",state,"hiring");scenes[#scenes].section="staff";scenes[#scenes].recordId=worker.id
    add("assignment",state,"hiring");scenes[#scenes].section="staff";scenes[#scenes].recordId=worker.id;scenes[#scenes].page="assignment"
    add("payroll",state,"hiring");scenes[#scenes].section="payroll"
    add("email-resume",state,"email");scenes[#scenes].emailId=state.clientEmails.inbox[1].id
    add("schedule-queue",state,"schedule");scenes[#scenes].recordId=worker.id
    add("schedule-add",state,"schedule");scenes[#scenes].recordId=worker.id;scenes[#scenes].page="add";scenes[#scenes].jobIndex=3
    add("schedule-menu",state,"schedule");scenes[#scenes].recordId=worker.id;scenes[#scenes].dropdown=true
    local worldContext=World.employeeContext(state,Assets)
    local workContext={canClaim=worldContext.canClaim,operatorPoint=worldContext.operatorPoint,
        move=function(actor,goal,dt) return AI.move(actor,goal,dt,worldContext) end}
    -- Finish the actual cutter domain before capturing history; no completed
    -- job or output counts are fabricated to populate the Schedule screen.
    for i=1,1600 do
        Work.update(state,worker,.1,workContext);Machine.updateAll(.1,state)
        if pallet.status=="cut" and not worker.assignment then break end
    end
    assert(pallet.status=="cut","Schedule preview could not complete the first real job")
    Schedule.advance(state,worker,Calendar.absoluteHours(state))
    assert(worker.schedule.history[1] and worker.schedule.history[1].jobId==job.id and worker.assignment.jobId=="JOB-CAT-DEMO-2","Scheduled next job did not follow completed work")
    add("schedule-history",state,"schedule");scenes[#scenes].recordId=worker.id;scenes[#scenes].page="history"
    state.warehouse.bays.front_left={status="complete",optionId="breakroom"}
    worker.fatigue=92;worker.focus=30
    for i=1,1500 do tick(.05);if worker.phase=="break" and worker.seatBay then break end end
    assert(worker.phase=="break" and worker.seatBay,"Cat breakroom route failed: "..worker.activity.." "..worker.x..","..worker.y)
    worker.idleClock=.5;worker.breakRemaining=.2
    add("cat-breakroom",state,"world")
    local n=#scenes
    for i=1,n do local c=require("src.screens.gui_projection").copy(scenes[i]);c.phone=true;scenes[#scenes+1]=c end
    prepareScene()
end
function love.draw()
    local scene=scenes[shot];if not scene then return end
    local width,height=love.graphics.getDimensions()
    local factor=math.min(width/960,height/678)
    love.graphics.clear(.025,.035,.05)
    love.graphics.push();love.graphics.translate((width-960*factor)/2,(height-678*factor)/2);love.graphics.scale(factor)
    if scene.view=="world" then World.draw(Assets,Characters,scene.state,nil,nil,{})
    else Computer.draw(scene.state,nil,nil,Assets) end
    love.graphics.pop()
    if pending then return end
    pending=true
    local filename=output.."/"..(scene.phone and "phone-" or "desktop-")..scene.name..".png"
    love.graphics.captureScreenshot(function(data)
        local encoded=data:encode("png");local f=assert(io.open(filename,"wb"));f:write(encoded:getString());f:close()
        encoded:release();data:release();shot=shot+1;pending=false;prepareScene()
    end)
end
