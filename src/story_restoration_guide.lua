-- Local tutorial notices for the pre-opening story phase. Authoritative shop
-- condition controls progression; no quest flags need to be saved separately.
local Condition=require("src.warehouse_condition")
local Guide={}
local function nextStep(state)
    local c=Condition.of(state)
    if not c or c.mode~="story" or c.grandOpened then return nil end
    if not c.powerConnected then return "power","Reconnect the shop power",
        "Call the power company and pay the one-time connection fee.",
        "Grandpa says the building is sound, but the shop has been closed too long to have active service. Use the portable utilities phone from the farm, apartment, or shop, or the restoration checklist at the breaker box." end
    if not c.breakerRepaired then return "breaker","Repair the wall breaker",
        "Inspect the existing breaker box at the upper-left wall.",
        "Power reaches the meter now, but the breaker is damaged. Move to the original wall box and repair it before using the lights and machines." end
    if not c.waterConnected then return "water","Reconnect the shop water",
        "Call the water utility and pay the one-time connection fee.",
        "Water service has been off since the shop closed. Reconnect it before the grand opening. The old water on the floor is a cleanup task, not an active pipe leak." end
    for _,region in ipairs({"west","center","east"}) do
        if not c.cleaned[region] then return "clean-"..region,"Clean the "..region.." floor",
            "Move through the "..region.." floor area and clean it.",
            "The mottled floor grime clears one region at a time. Stand in the area, choose it in the restoration checklist, and the mop will clean it before the floor changes. The oily puddles are separate cleanup tasks." end
    end
    if not c.repainted then return "paint","Touch up the shop",
        "Repair the worn wall and shelf paint.",
        "The shop's neglected surfaces still need attention. Stand near the shelving and repaint before inviting clients inside." end
    for _,puddle in ipairs({"puddle1","puddle2"}) do
        if not c.cleanedPuddles[puddle] then
            local place=puddle=="puddle1" and "by the racks" or "by the office"
            return "clean-"..puddle,"Clean the oily puddle "..place,
                "Stand beside the puddle and clean it separately.",
                "The oil-water spill is a separate cleanup from the three floor areas. Walk up to the puddle and use its interaction prompt to mop it up."
        end
    end
    local ready,reason=Condition.readyForOpening(state)
    if not ready then return "machines","Service the production machines",
        reason,
        "Grandpa wants the cutter and skid wrapper safe before the reopening. Complete one maintenance service for each machine and make sure the cutter blade is sharp enough. Then check the restoration list again." end
    return "grand-opening","Hold the grand opening",
        "The shop is ready. Announce that clients may return.",
        "The repairs and cleaning are complete. Use HOLD GRAND OPENING in the restoration checklist to reopen The Picture Shop. Client calls, visits, and job requests begin after this step."
end
function Guide.update(feedback)
    local state=feedback and feedback.context and feedback.context.state
    if not state or not state.tutorial or not state.tutorial.enabled then return false end
    local id,title,detail,body=nextStep(state)
    if not id then return false end
    local key="story-restoration:"..id
    if require("src.notifications").findKey(state,key) then return false end
    feedback:enqueue("tutorial",title,detail,body,key)
    feedback.dirty=true
    return true
end
Guide.nextStep=nextStep
return Guide
