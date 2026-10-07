-- Isolated visual authoring preview; normal App and game saves are not loaded.
local Assets=require("src.assets")
local Characters=require("src.character_assets")
local Config=require("src.config")
local State=require("src.state")
local World=require("src.world")
local Employees=require("src.employees")
local Calendar=require("src.business_calendar")
local AI=require("src.employee_ai")
local Pose=require("src.employee_pose")
local Schema=require("src.save_schema")
local root=love.filesystem.getSource():gsub("\\","/"):gsub("/$","")
local runId=os.date("%Y%m%d-%H%M%S")
local pending=true
function love.errorhandler(message)
    print("BUBBLE REVIEW ERROR "..tostring(message));io.stdout:flush()
    return function() return 1 end
end
function love.load()
    Assets.load();Characters.load()
    World.load({id=1,x=480,y=470,character=Config.player.character})
end
function love.update()
    if not pending then return end
    pending=false
    local state=State.new()
    state.employment.recruiting=false
    state.warehouse.bays.front_left={status="complete",optionId="breakroom"}
    local applicant=Employees.createApplicant(state,0)
    Employees.requestResume(state,applicant.id,0)
    Employees.advance(state,.5)
    Employees.command(state,{kind="offer_employee",applicationId=applicant.id,
        expectedRevision=applicant.revision,wageCents=2200,days=31,startHour=9,endHour=17},.5)
    Employees.advance(state,1.25)
    Employees.command(state,{kind="hire_employee",applicationId=applicant.id,
        expectedRevision=applicant.revision},1.25)
    local worker=state.employment.staff[1]
    applicant.actor.visible=false
    World.updateWarehouse(0,state,Assets)
    local function capture(name)
        local canvas=love.graphics.newCanvas(960,678)
        love.graphics.push("all")
        love.graphics.setCanvas({canvas,stencil=true})
        love.graphics.clear(.015,.019,.025,1)
        World.draw(Assets,Characters,state)
        love.graphics.setCanvas()
        love.graphics.pop()
        local encoded=canvas:newImageData():encode("png")
        local path=root.."/output/employee-bubble-review/"..runId.."-"..name..".png"
        local file=assert(io.open(path,"wb"));file:write(encoded:getString());file:close()
        canvas:release();print("CAPTURE "..path)
    end
    local context=World.employeeContext(state,Assets)
    AI.worker(state,worker,.1,9,context)
    capture("shift-arrival")
    worker.x,worker.y=620,305
    AI.worker(state,worker,.1,17,context)
    capture("shift-goodbye")
    worker.greetingKind,worker.greetingUntilHours=nil,nil
    worker.phase,worker.visible,worker.clockedIn="working",true,true
    worker.x,worker.y=564,437
    worker.workFrame,worker.idleClock,worker.moving=4,0,false
    worker.activity="Operating paper cutter"
    worker.assignment={machineModel="polar_115"}
    local wrapper=Schema.copy(worker)
    wrapper.id,wrapper.character,wrapper.x,wrapper.y="EMP-0002","tinker-fox-worker",778,454
    wrapper.assignment={machineModel="skid_wrapper"};wrapper.activity="Wrapping finished pallet"
    local resting=Schema.copy(worker)
    resting.id,resting.x,resting.y="EMP-0003",95,639
    resting.assignment=nil;resting.phase="break";resting.seatBay="front_left"
    resting.breakRemaining,resting.idleClock,resting.breakKind=.2,.5,"rest"
    state.employment.staff={worker,wrapper,resting}
    capture("actions-host")
    state._employeePoses=Pose.actors(Pose.capture(Employees.actors(state)))
    capture("actions-guest")
    state._employeePoses=nil
    worker.assignment={machineModel="heidelberg_10x15"};worker.activity="Running the Heidelberg printing press"
    wrapper.activity="Machine access is blocked"
    resting.breakKind="meal"
    capture("printing-blocked-lunch")
    io.stdout:flush();love.event.quit(0)
end
