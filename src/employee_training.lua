local Fleet=require("src.machine_fleet")
local Training={}

function Training.available(state,machine)
    local model=machine.modelId
    local okay,reason=Fleet.canOperate(state,model,machine.id)
    if not okay then return false,reason end
    if model=="polar_115" then
        if machine.maintenance.cutter.technicianStatus=="waiting_for_skid" then
            return false,"Weekly blade service is waiting for the current skid to finish"
        end
        local runtime=require("src.machine").forId(machine.id)
        if runtime.emergencyStopped or not runtime.barrierClear or runtime.step=="blocked" then
            return false,"Cutter safety/service needs player attention"
        end
        if runtime.step~="idle" and runtime.step~="finished" then
            return false,"Waiting for the current cutter work to finish"
        end
    elseif model=="heidelberg_10x15" then
        local busy
        Fleet.withUnit(state,machine.id,function()
            busy=require("src.windmill").ensure(state).status~="idle"
        end)
        if busy then return false,"Waiting for the current press work to finish" end
    elseif model=="skid_wrapper" then
        if require("src.wrapper").forId(machine.id).isActive() then
            return false,"Waiting for the current wrapping cycle to finish"
        end
    end
    return true
end

return Training
