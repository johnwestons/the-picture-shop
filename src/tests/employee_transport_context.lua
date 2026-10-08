-- Fast production-workflow fixtures. Physical route/collision coverage lives in
-- employee_transport_test, which uses World.employeeContext and the real floor.
local Jack=require("src.pallet_jack")
local Config=require("src.config")
local Zones=require("src.cutter_zones")
return function(context,state)
    local mask={getDimensions=function() return 960,678 end,getPixel=function() return 1,1,1,1 end}
    context.assets=context.assets or {getData=function() return mask end}
    context.obstacles=context.obstacles or function() return {} end
    context.jackNavigation=function() return {assets={getData=function() return mask end},obstacles=function() return {} end} end
    context.jackApproachPoint=function() local x,y=Jack.operatorPosition(state,Config.palletJack);return {x=x,y=y} end
    context.jackPickupPoint=function(_,pallet) return {x=pallet.world.x+40,y=pallet.world.y} end
    context.jackDropPoint=function(machineId,worker,pallet,stage)
        if stage=="wrapping" then
            return context.palletDropPoint and context.palletDropPoint(machineId,worker,pallet)
                or {x=state.wrapper.x+80,y=state.wrapper.y}
        end
        if context.machinePalletDropPoint then return context.machinePalletDropPoint(machineId,worker,pallet,stage) end
        local x,y=Zones.inputAnchor(state,Config.cutterPlacement)
        return {x=x,y=y}
    end
    context.jackDropClear=function() return true end
    context.jackEmergencyDropPoint=function() return {x=state.palletJack.x,y=state.palletJack.y} end
    return context
end
