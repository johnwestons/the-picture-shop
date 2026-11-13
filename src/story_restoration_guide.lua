-- Local tutorial notices for the pre-opening story phase. Authoritative shop
-- condition controls progression; no quest flags need to be saved separately.
local Condition=require("src.warehouse_condition")
local Guide={}
local function nextStep(state)
    local c=Condition.of(state)
    if not c or c.mode~="story" or c.grandOpened then return nil end
    if not c.powerConnected then return "power","Reconnect the shop power",
        "Call the power company and pay the one-time connection fee.",
        "Grandpa says the building is sound, but the shop has been closed too long to have active service. Use the wall phone in the shop to call the power company; the phone works while the building power is off." end
    if not c.breakerRepaired then return "breaker","Repair the wall breaker",
        "Inspect the existing breaker box at the upper-left wall.",
        "Power reaches the meter now, but the breaker is damaged. Move to the original wall box and repair it before using the lights and machines." end
    if not c.lightsOn then return "lights","Turn on the warehouse lights",
        "Use the repaired breaker box on the west wall.",
        "The breaker is repaired and power reaches the shop. Use the box again to switch on the warehouse lights." end
    if not c.waterConnected then return "water","Reconnect the shop water",
        "Call the water utility and pay the one-time connection fee.",
        "Water service has been off since the shop closed. Reconnect it before the grand opening. The old water on the floor is a cleanup task, not an active pipe leak." end
    for _,puddle in ipairs({"puddle1","puddle2"}) do
        if not c.cleanedPuddles[puddle] then
            local place=puddle=="puddle1" and "on the middle-left floor" or "on the middle-right floor"
            return "clean-"..puddle,"Clean the oily puddle "..place,
                "Start mopping at the puddle, then walk through it to erase it.",
                "The two spills are the floor cleanup. Use the interaction prompt while standing in a puddle, then steer your worker across the oil. Each pass clears part of it and saves progress."
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
