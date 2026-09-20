local MachineScreen = require("src.screens.machine_screen")
local PaperWork = require("src.paper_work")
local Projection = require("src.screens.gui_projection")

local Gui = {}
function Gui.new(resource, getView, presentation, send)
    local gui, machine, wrapper = {}, {}, {}
    local currentState, view
    local function find(id)
        for _, job in ipairs(currentState.jobs and currentState.jobs.active or {}) do
            for _, pallet in ipairs(job.pallets or {}) do
                if pallet.id == id then return { pallet=pallet, paper=pallet.paper, job=job, distance=0, inputDistance=0 } end
            end
        end
    end
    machine.savedMeasurements = function()
        local result={}; for _,value in ipairs(view.memoryCentiInch or {}) do result[#result+1]=value/100 end; return result
    end
    machine.paperTooltip = function() return machine.paper and PaperWork.tooltip(machine.paper) or "No paper on the cutter." end
    machine.availablePapers = function()
        local rows={}
        for _,candidate in ipairs(view.candidates or {}) do
            local item=find(candidate.palletId)
            if item then item.inputDistance=(candidate.distancePixels or 0)^2; rows[#rows+1]=item end
        end
        return rows
    end
    machine.load = function(_,id)
        return id and id~="__generic_stock__" and send("load_pallet",{palletId=id}) or send("load_stock",{})
    end
    machine.selectProgram = function(index) return send("select_program",{programIndex=math.max(1,math.min(4,index))}) end
    machine.setGauge = function(value)
        value=tonumber(value); if not value or value<0 or value>25 then return false end
        return send("set_gauge",{gaugeCentiInch=math.floor(value*100+0.5)})
    end
    machine.adjustGauge = function(delta) return machine.setGauge(machine.gauge+delta) end
    machine.autoGauge = function() return send("auto_gauge",{}) end
    machine.saveGauge = function() return send("save_gauge",{}) end
    machine.recallGauge = function() return send("recall_gauge",{}) end
    machine.keypressed = function(key)
        local action=({g="auto_gauge",m="save_gauge",v="recall_gauge",q="rotate_paper",p="position_paper",
            j="guarded_cut",k="guarded_cut",x="emergency_stop",r="reset_safety",u="return_to_pallet",t="run_next_lift"})[key]
        if action then return send(action,{}) end
        if key=="space" then return send("set_clamp",{clamp=not view.clamp}) end
        if key=="b" then return send("set_barrier",{barrierClear=not view.barrierClear}) end
        if key=="[" or key=="]" then return machine.selectProgram(machine.programIndex+(key=="]" and 1 or -1)) end
        if tonumber(key) and tonumber(key)>=1 and tonumber(key)<=4 then return machine.selectProgram(tonumber(key)) end
        return false
    end
    wrapper.nearbyPallets = function()
        local rows={}; for _,record in ipairs(view.pallets or {}) do local item=find(record.palletId); if item then rows[#rows+1]=item end end
        return rows
    end
    wrapper.nearbyPallet = function()
        local rows=wrapper.nearbyPallets()
        for _,item in ipairs(rows) do if item.pallet.id==view.selectedPalletId then return item end end
        return rows[1]
    end
    wrapper.selectPallet = function(_,id) return send("select_pallet",{palletId=id}) end
    wrapper.start = function()
        local item=wrapper.nearbyPallet(); return item and send("start_cycle",{palletId=item.pallet.id}) or false
    end
    wrapper.isActive = function() return view.step=="wrapping" end
    wrapper.filmHeight = function() return view.step=="finished" and 1 or math.min(1,(view.progress or 0)/(view.cycleTime or 3)) end
    gui.screen=MachineScreen.new({Machine=machine,Wrapper=wrapper,remoteCommand=send})
    function gui.sync(state)
        currentState=Projection.copy(state)
        currentState.machineType=resource=="skid_wrapper" and "skid_wrapper" or "paper_cutter"
        view=getView() or {}
        if resource=="cutter" then
            local model=presentation:model(currentState,view)
            for key,value in pairs(model) do machine[key]=value end
            machine.paper=model.paper
            machine.pallet=view.paper
            machine.gauge=(view.gaugeCentiInch or 0)/100
            machine.programIndex=view.programIndex or 1
            machine.clamp=view.clamp==true
            machine.barrierClear=view.barrierClear==true
            machine.emergencyStopped=view.emergencyStopped==true
            machine.multiplayerSingleControl=true
            machine.leftDown,machine.rightDown=view.step=="cutting",view.step=="cutting"
            if not gui.screen.gaugeFocused then gui.screen.syncGauge() end
        else
            wrapper.step,wrapper.progress,wrapper.cycleTime=view.step or "idle",view.progress or 0,view.cycleTime or 3
            wrapper.selectedPalletId=view.selectedPalletId
        end
        -- An already-granted service remains visible if another worker uses the
        -- last kit. Only the host decides whether final completion can consume it.
        local stock=currentState.inventory and currentState.inventory.stock
        local kits=stock and stock.maintenance_kit
        if stock and view.serviceStep and view.serviceStep~="idle" then stock.maintenance_kit=math.max(1,kits or 0) end
        gui.screen.syncRemoteService(currentState,view)
        if stock then stock.maintenance_kit=kits end
        return currentState
    end
    function gui.draw(state,assets,x,y,status)
        local projected=gui.sync(state); projected.message=status
        gui.screen.draw(projected,assets,x,y)
        if gui.screen.maintenanceView=="oil" or gui.screen.maintenanceView=="blade" or gui.screen.maintenanceView=="wrapper_task" then
            love.graphics.setColor(0.78,0.90,0.87)
            love.graphics.printf(status or "",280,640,590,"left")
        end
    end
    function gui.mousepressed(state,x,y,button)
        local projected=gui.sync(state)
        local oldMessage=projected.message
        local result=gui.screen.mousepressed(projected,x,y,button)
        gui.feedback=projected.message~=oldMessage and projected.message or nil
        return result
    end
    function gui.keypressed(state,key)
        local projected=gui.sync(state)
        if key=="x" and resource=="cutter" then return machine.keypressed(key) end
        if resource=="skid_wrapper" and key=="l" and not gui.screen.hasModal() then return wrapper.start() end
        if gui.screen.keypressed(projected,key) then return true end
        if resource=="skid_wrapper" then return key=="l" and wrapper.start() or false end
        if gui.screen.hasModal() or gui.screen.gaugeFocused then return false end
        return machine.keypressed(key)
    end
    function gui.textinput(text) return gui.screen.textinput(currentState,text) end
    return gui
end
return Gui
