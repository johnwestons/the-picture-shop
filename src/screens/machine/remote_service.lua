-- Remote service input and host-view synchronization.
-- Runtime is private to this screen instance; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.Screen.remoteServiceInput(state, x, y, button)
        if button ~= 1 or Runtime.Screen.helpOpen then return nil end
        local send = Runtime.dependencies.remoteCommand
        local function action(name, args) send(name, args or {}); return true end
        local view = Runtime.Screen.remoteView or {}
        if Runtime.Screen.maintenanceView == "hub" then
            if Runtime.inside(Runtime.maintenanceBack, x, y) then Runtime.Screen.maintenanceView = nil; return true end
            if Runtime.inside(Runtime.oilServiceButton, x, y) then return action("begin_lubrication") end
            if Runtime.inside(Runtime.bladeServiceButton, x, y) then return action("begin_blade") end
            if Runtime.inside(Runtime.technicianButton, x, y) then return action("book_blade_technician") end
            if Runtime.inside(Runtime.weeklyButton, x, y) then
                local _, cutter = Runtime.MachineMaintenance.cutterStatus(state)
                return action("set_weekly_technician", { enabled = not cutter.weeklyTechnician })
            end
            return true
        elseif Runtime.Screen.maintenanceView == "oil" then
            if Runtime.inside(Runtime.maintenanceBack, x, y) then return action("cancel_service") end
            local session = Runtime.Screen.oilSession
            if session.stage == "lockout" or session.stage == "prep" then
                local expected = ({ lockout_disconnect = "disconnect", lockout_key = "key", lockout_tag = "tag",
                    prep_cartridge = "cartridge", prep_prime = "prime" })[view.serviceStep]
                local rect = Runtime.lockoutButtons[expected] or Runtime.prepButtons[expected]
                if rect and Runtime.inside(rect, x, y) then return action("service_advance") end
            else
                for index in ipairs(Runtime.lubricationViews) do
                    if Runtime.inside({ x=42+(index-1)*113,y=112,width=105,height=34 },x,y) then return action("service_view",{itemIndex=index}) end
                end
                for index in ipairs(Runtime.lubricationTools) do
                    if Runtime.inside({x=650,y=176+(index-1)*48,width=234,height=39},x,y) then return action("service_tool",{itemIndex=index}) end
                end
                if Runtime.inside(Runtime.pumpButton,x,y) then return action("service_pump") end
                if Runtime.inside(Runtime.finishLubricationButton,x,y) then return action("finish_lubrication") end
                if session.activeView == "gear" and (x-490)^2+(y-340)^2 <= 55^2 then return action("service_gear") end
                if session.activeView == "central" and (x-370)^2+(y-330)^2 <= 45^2 then return action("service_point",{itemIndex=7}) end
                for index, point in ipairs(session.points) do
                    if point.view == session.activeView and (x-point.x)^2+(y-point.y)^2 <= 38^2 then return action("service_point",{itemIndex=index}) end
                end
            end
            return true
        elseif Runtime.Screen.maintenanceView == "blade" then
            if Runtime.inside(Runtime.maintenanceBack,x,y) then return action("cancel_service") end
            if Runtime.Screen.bladeStage == "bolts" then
                for index,pos in ipairs(Runtime.bladeBoltPositions()) do
                    if (x-pos[1])^2+(y-pos[2])^2 <= 24^2 then return action("remove_blade_bolt",{itemIndex=index}) end
                end
            elseif Runtime.Screen.bladeStage == "blade" and x>=304 and x<=656 and y>=280 and y<=342 then return action("lift_blade")
            elseif Runtime.Screen.bladeStage == "sleeve" and x>=330 and x<=630 and y>=445 and y<=505 then return action("sleeve_blade") end
            return true
        elseif Runtime.Screen.maintenanceView == "wrapper_hub" then
            if Runtime.inside(Runtime.maintenanceBack,x,y) then Runtime.Screen.maintenanceView=nil; return true end
            if Runtime.inside(Runtime.wrapperServiceButton,x,y) then return action("begin_service") end
            return true
        elseif Runtime.Screen.maintenanceView == "wrapper_task" then
            if Runtime.inside(Runtime.maintenanceBack,x,y) then return action("cancel_service") end
            local phase = view.servicePhase or 1
            local tx,ty = Runtime.MachineMaintenance.wrapperTarget(Runtime.Screen.wrapperSession,phase)
            if tx and (x-tx)^2+(y-ty)^2 <= 38^2 then return action("service_target",{itemIndex=phase}) end
            if x>=54 and x<=574 and y>=104 and y<=542 then return action("service_miss") end
            return true
        end
    end

    function Runtime.Screen.syncRemoteService(state, view)
        Runtime.Screen.remoteView = view
        local step = view.serviceStep or "idle"
        if state.machineType == "skid_wrapper" then
            if step == "task" then
                local session = Runtime.Screen.wrapperSession or Runtime.MachineMaintenance.beginWrapperService(state)
                if not session then return end
                session.activeIndex = view.serviceTaskIndex or 1
                local task = session.tasks[session.activeIndex]
                session.taskState[task.id] = { phase=view.servicePhase or 1, attempts=view.serviceAttempts or 0,
                    misses=view.serviceMisses or 0, hits=(view.servicePhase or 1)-1, completed=false }
                Runtime.Screen.wrapperSession, Runtime.Screen.maintenanceView = session,"wrapper_task"
            elseif Runtime.Screen.maintenanceView == "wrapper_task" then Runtime.Screen.wrapperSession,Runtime.Screen.maintenanceView=nil,"wrapper_hub" end
        elseif step:sub(1,6) == "blade_" then
            Runtime.Screen.maintenanceView = "blade"
            Runtime.Screen.bladeStage = step == "blade_lift" and "blade" or step:sub(7)
            Runtime.Screen.bladeBolts = {}
            for index=1,4 do
                Runtime.Screen.bladeBolts[index]=view.bladeBoltMask and math.floor(view.bladeBoltMask/2^(index-1))%2==1
                    or (view.bladeBoltMask==nil and index <= (view.bladeBoltsDone or 0))
            end
        elseif step ~= "idle" then
            local session = Runtime.Screen.oilSession or Runtime.MachineMaintenance.beginCutterLubrication(state)
            if not session then return end
            session.stage = step:find("lockout",1,true) and "lockout" or step:find("prep",1,true) and "prep" or "service"
            session.lockout = { disconnect=step~="lockout_disconnect",key=step~="lockout_disconnect" and step~="lockout_key",tag=session.stage~="lockout" }
            session.prep = { cartridge=step=="prep_prime" or session.stage=="service",primed=session.stage=="service" }
            session.activeView=Runtime.lubricationViews[view.serviceView or 1]
            session.activeTool=Runtime.lubricationTools[view.serviceTool or 1]
            session.centralInstalled=view.centralInstalled==true
            session.gear.inspected,session.gear.level=view.gearInspected==true,(view.gearLevelPermille or 480)/1000
            session.coupledPoint=nil
            for _,item in ipairs(view.serviceItems or {}) do
                local point=item.itemIndex==7 and session.central or session.points[item.itemIndex]
                if point then
                    point.cleaned,point.coupled,point.strokes,point.complete=item.cleaned,item.coupled,item.strokes,item.complete
                    if point.coupled then session.coupledPoint=item.itemIndex==7 and "central" or point.id end
                end
            end
            Runtime.Screen.oilSession,Runtime.Screen.maintenanceView=session,"oil"
        elseif Runtime.Screen.maintenanceView == "oil" or Runtime.Screen.maintenanceView == "blade" then
            Runtime.Screen.oilSession,Runtime.Screen.bladeStage,Runtime.Screen.bladeBolts,Runtime.Screen.maintenanceView=nil,nil,nil,"hub"
        end
    end
end

return Component
