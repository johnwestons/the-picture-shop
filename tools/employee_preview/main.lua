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
local Service=require("src.job_service")
local Payroll=require("src.payroll")
local scenes,shot,pending={},1,false
local state,applicant,worker
local function setHours(s,h)
    local pace=Calendar.secondsPerDay(s)
    s.calendar=Calendar.dateFromTotalDay(math.floor(h/24));s.calendar.secondsPerDay=pace;s.calendar.elapsed=(h%24)/24*pace
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
        f:write("PASS: Radio Cat, Tinker Fox and Ferret Engineer hiring and real scheduled cutter jobs; correct finished-pallet placement; resumes, contracts, 12h overnight offers, payroll and weekly shop budget; clocks, shop setup, cutter margin rotations and six-slot staging layout. Desktop and phone landscape captures.\n")
        f:close();love.event.quit(0);return
    end
    local phone=scene.phone
    Assets.activatePack(scene.view=="cut_guide" and "cutter" or scene.view=="shop_setup" and "menu" or nil)
    love.window.setMode(phone and 1600 or 960,phone and 720 or 678,{vsync=0,resizable=false})
    if scene.view~="world" then
        Computer.tab=scene.view
        Computer.tabDropdownOpen=scene.dropdown==true
        Computer.hiring.section=scene.section or "applications"
        Computer.hiring.view=scene.page or "detail"
        Computer.hiring.selectedId=scene.recordId
        Computer.hiring.terms=scene.terms or Contracts.terms(2200,31,9,17)
        Computer.selectedEmailId=scene.emailId
        Computer.selectedJobId=scene.jobId
        Computer.quoteText=scene.quoteText or ""
        Computer.schedule.view=scene.page or "queue"
        Computer.schedule.workerId=scene.recordId
        Computer.schedule.jobIndex=scene.jobIndex or 1
    end
end
function love.load()
    love.graphics.setDefaultFilter("nearest","nearest")
    love.graphics.setFont(love.graphics.newFont(13))
    Assets.load();Characters.load();assert(Characters.assertHealthy())
    state=State.new();state.calendar.secondsPerDay=300;state.screen="world";state.money=5000
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
    assert(job.labor and job.labor.wageCents>0,"Preview did not allocate real cutter wages")
    add("employee-job-cost",state,"active");scenes[#scenes].jobId=job.id
    local billing=require("src.screens.gui_projection").copy(state)
    setHours(billing,105);Calendar.addCharge(billing,"Preview customer stock claim",100,job.id)
    assert(Payroll.total(billing,105,false)>0,"Preview has no actual wages due")
    add("employee-bills",billing,"bills")
    for _,printing in ipairs({false,true}) do
        local estimates=require("src.screens.gui_projection").copy(state)
        local request=assert(Jobs.createOffer({id=printing and "JOB-STAFF-PRINT-QUOTE" or "JOB-STAFF-CUT-QUOTE",company="Staff estimate client",
            sourceSize={width=20,height=16},finishedSize={width=10,height=8},sheetCounts={500},
            press=printing and {colors=1,colorSequence={"Black"},artworkSize={width=5,height=7},coverage=.4} or nil}))
        assert(Service.requestEstimateDetails(estimates,request,1))
        local email=estimates.clientEmails.pending[#estimates.clientEmails.pending]
        setHours(estimates,email.readyAtHours);Service.updateClientEmails(estimates)
        local ready
        for _,e in ipairs(Service.estimateInbox(estimates)) do if e.job and e.job.id==request.id then ready=e end end
        assert(ready,"Preview estimate did not reach inbox")
        local terms=Service.quoteTerms(estimates,ready.job)
        assert(terms.employeeBudget,"Preview estimate has no employee allowance")
        add(printing and "employee-estimate-print" or "employee-estimate-cut",estimates,"estimating")
        scenes[#scenes].emailId=ready.id;scenes[#scenes].quoteText=tostring(terms.recommendedPrice)
    end
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
    -- Exercise both added characters through the real hiring and machine flow.
    for profileIndex=2,3 do
        local profile=require("src.worker_catalog").profiles[profileIndex]
        state=State.new();state.screen="world";state.money=12000
        state.employment.nextApplicantId=profileIndex;state.employment.recruiting=false
        applicant=Employees.createApplicant(state,0)
        assert(Employees.requestResume(state,applicant.id,0));Employees.advance(state,.5)
        add(profile.character.."-resume",state,"hiring");scenes[#scenes].recordId=applicant.id
        add(profile.character.."-night-offer",state,"hiring");scenes[#scenes].recordId=applicant.id;scenes[#scenes].page="offer"
        scenes[#scenes].terms=Contracts.terms(profile.requestedWage,31,20,8,4)
        assert(Employees.command(state,{kind="offer_employee",applicationId=applicant.id,expectedRevision=applicant.revision,
            wageCents=profile.requestedWage,days=31,startHour=8,endHour=20,payWeeks=4},.5))
        Employees.advance(state,1.25)
        assert(Employees.command(state,{kind="hire_employee",applicationId=applicant.id,expectedRevision=applicant.revision},1.25))
        worker=state.employment.staff[1]
        local nextJob=assert(Jobs.createOffer({id="JOB-"..profile.character,company="New worker review",sourceSize={width=20,height=16},
            finishedSize={width=10,height=8},sheetCounts={500}}))
        Jobs.accept(nextJob);state.jobs.active[1]=nextJob
        Logistics.unload(state,nextJob.id,nextJob.pallets[1].id,Config.palletLogistics.spawnPoints,Config.palletLogistics.unloadOrigin)
        local x,y=Zones.inputAnchor(state,Config.cutterPlacement)
        local p=nextJob.pallets[1];p.world.x,p.world.y=x,y;p.world.fromX,p.world.fromY=x,y;p.world.spawnProgress=1
        local unit=Fleet.installedUnits(state,"polar_115")[1]
        Machine.reset(state)
        assert(Employees.command(state,{kind="queue_employee_job",employeeId=worker.id,jobId=nextJob.id,machineId=unit.id},1.25))
        setHours(state,8)
        local cutter=Machine.forId(unit.id)
        for i=1,1400 do tick(.05);if cutter.step=="cutting" then break end end
        assert(cutter.step=="cutting",profile.name.." could not operate cutter: "..worker.activity)
        add(profile.character.."-working",state,"world")
        add(profile.character.."-staff",state,"hiring");scenes[#scenes].section="staff";scenes[#scenes].recordId=worker.id
        add(profile.character.."-budget",state,"hiring");scenes[#scenes].section="payroll";scenes[#scenes].page="finances"
        for i=1,2400 do tick(.05);if p.status=="cut" and not worker.assignment then break end end
        assert(p.status=="cut" and p.location=="cutter_output",profile.name.." did not finish actual pallet")
        add(profile.character.."-output",state,"world")
    end
    state.calendar.secondsPerDay=1200;setHours(state,3.5)
    add("shop-clock",state,"clock")
    add("wall-clock-popup",state,"shop_clock")
    add("shop-setup-options",state,"shop_setup")
    local layout=State.new();layout.screen="world";layout.calendar.secondsPerDay=3600;setHours(layout,15.5)
    for i,slot in ipairs(require("src.cutter_staging").slots()) do
        local j=assert(Jobs.createOffer({id="JOB-STAGING-VIEW-"..i,company="Staging layout preview",sourceSize={width=20,height=16},
            finishedSize={width=10,height=8},sheetCounts={500}}))
        Jobs.accept(j);layout.jobs.active[#layout.jobs.active+1]=j
        local p=j.pallets[1];p.location="warehouse"
        p.world={x=slot.x,y=slot.y,fromX=slot.x,fromY=slot.y,direction=slot.direction,rotation=slot.rotation,spawnProgress=1}
    end
    add("six-slot-staging-layout",layout,"world")
    local paper=require("src.paper_work").createStockPaper()
    for rotation=0,1 do
        local cutState=State.new();cutState.screen="machine";cutState.machineType="cutter"
        add(rotation==0 and "active-cut-needs-rotation" or "active-cut-correct-rotation",cutState,"cut_guide")
        scenes[#scenes].paper=require("src.save_schema").copy(paper);scenes[#scenes].paper.orientation=rotation*90
    end
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
    if scene.view=="world" then
        World.draw(Assets,Characters,scene.state,nil,nil,{})
        require("src.screens.hud").draw(scene.state,World.getInteraction())
    elseif scene.view=="shop_clock" then
        World.draw(Assets,Characters,scene.state,nil,nil,{})
        require("src.screens.shop_clock").draw(scene.state)
    elseif scene.view=="shop_setup" then
        require("src.screens.title_screen").draw(Assets)
        require("src.screens.shop_setup_screen").draw({dayLengthMinutes=33},1)
    elseif scene.view=="cut_guide" then
        local machine=Machine.forId(nil)
        machine.paper=scene.paper;machine.programIndex=1;machine.step="loaded";machine.loaded=true
        require("src.screens.machine_screen").draw(scene.state,Assets)
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
