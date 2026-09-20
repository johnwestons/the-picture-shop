local Projection = require("src.screens.gui_projection")
local PressScreen = require("src.screens.press_screen")
local Windmill = require("src.windmill")
local Plates = require("src.plate_service")
local Fleet = require("src.machine_fleet")
local SetupView = require("src.press_setup_view")
local Gui = {}

function Gui.new(getView,send)
    local gui={}
    local windmill=setmetatable({}, {__index=Windmill})
    local plates=setmetatable({}, {__index=Plates})
    local controls={motor="toggle_motor",feeder="toggle_feeder",impression="toggle_impression",
        emergency="emergency_stop",reset="reset_safety",speed_up="speed_up",speed_down="speed_down"}
    windmill.control=function(_,action) return send(controls[action],{}) end
    for method,action in pairs({takeProof="take_proof",verifyArtwork="verify_artwork",approveProof="approve_proof",
        startProduction="start_run",stopProduction="stop_run",cleanAndUnload="clean_unload"}) do
        windmill[method]=function() return send(action,{}) end
    end
    windmill.load=function(_,id) return send("load_pallet",{palletId=id}) end
    windmill.candidates=function(state)
        local candidates={}
        for _,record in ipairs((getView() or {}).candidates or {}) do
            for _,job in ipairs(state.jobs and state.jobs.active or {}) do
                for _,pallet in ipairs(job.pallets or {}) do
                    if pallet.id==record.palletId then candidates[#candidates+1]={job=job,pallet=pallet,color=record.colorIndex} end
                end
            end
        end
        return candidates
    end
    plates.order=function(_,job,index) return send("order_plate",{plateId=Plates.ensureJob(job)[index].id}) end
    plates.beginInHouse=function(_,job,index) return send("begin_plate",{plateId=Plates.ensureJob(job)[index].id}) end
    plates.process=function(plate) return send("process_plate",{plateId=plate.id}) end
    gui.screen=PressScreen.new({Windmill=windmill,Plates=plates,remoteCommand=send})
    gui.screen.enter()
    function gui.sync(state)
        local projected=Projection.copy(state)
        local view=getView() or {}
        local p=Windmill.ensure(projected)
        for _,key in ipairs({"status","speed","motor","feeder","impression","emergency","counter","goodSheets",
            "spoilage","targetSheets","feedStart","feedRemaining","proofApproved","artworkVerified",
            "jobId","palletId","colorIndex","warning"}) do p[key]=view[key] end
        p.proofQuality=view.proofPermille and view.proofPermille/1000 or nil
        p.setup={}
        for index,task in ipairs(Windmill.setupTasks()) do
            local score=(view.setupPermille or {})[index] or 0
            if score>0 then p.setup[task]=score/1000 end
        end
        local _,job=Windmill.current(projected)
        gui.screen.remoteView=view
        gui.screen.activeSetup=view.setupTask
        gui.screen.setupGame=view.setupTask and SetupView.project(view.setupTask,view.setupVisual,job,view.setupSummary) or nil
        local step=view.serviceStep or "idle"
        gui.screen.maintenance=nil
        if step~="idle" then
            local machine=Fleet.installed(projected,"heidelberg_10x15")
            local plan=machine and Fleet.maintenancePlan(projected,machine.id)
            if plan then
                local session={machineId=plan.machineId,modelId=plan.modelId,tasks=plan.tasks,activeIndex=1,scores={}}
                for index,task in ipairs(plan.tasks) do
                    if task.label==view.serviceTask or task.id==view.serviceTask then session.activeIndex=index end
                end
                gui.screen.maintenance=session
                gui.screen.lockoutStep=({lockout_disconnect=1,lockout_key=2,lockout_tag=3,task=4})[step] or 1
            end
        end
        return projected
    end
    function gui.draw(state,assets,x,y,status)
        local projected=gui.sync(state)
        gui.screen.feedbackText=status
        gui.screen.draw(projected,assets,x,y)
    end
    function gui.mousepressed(state,x,y,button) return gui.screen.mousepressed(gui.sync(state),x,y,button) end
    function gui.keypressed(state,key) return gui.screen.keypressed(gui.sync(state),key) end
    return gui
end
return Gui
