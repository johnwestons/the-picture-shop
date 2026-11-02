local Shopping=require("src.home_shopping")
local Controls={}
function Controls.command(R,player)
    local okay,message=Shopping.collect(R.state,player,require("src.weekend_runtime").players(R))
    if okay then
        R.state.message=message;R.saveCurrent()
        if R.multiplayer:isHost() then R.multiplayer:markShopDirty() end
    end
    return okay,okay and "received" or "blocked",message,"homeDelivery"
end
function Controls.keypressed(key,R)
    if key~="e" or R.state.screen~="world" then return false end
    local selected=R.World.getInteraction()
    if not selected or selected.kind~="homeDelivery" then return false end
    local okay,message
    if R.multiplayer:isClient() then okay,message=R.multiplayer:requestInteraction("homeDelivery","collect")
    else local code;okay,code,message=Controls.command(R,R.World.player) end
    R.state.message=message or (okay and "Waiting for the host..." or "Delivery unavailable.")
    return true
end
return Controls
