local Flow=require("src.weekend_flow")
local Travel=require("src.home_travel")
local Shutdown=require("src.shop_shutdown")
local Weekend={}
function Weekend.players(R)
    local result={R.World.player}
    for _,p in ipairs(R.multiplayer:remotePlayers()) do result[#result+1]=p end
    return result
end
function Weekend.command(R,player,command)
    local okay,code,message=Travel.command(R.state,player,command,{
        world=R.World,players=function() return Weekend.players(R) end,
        commuteWorld=require('src.commute.runtime').enabled() and require('src.commute.runtime').world(R) or nil,
        resolveShopSpawn=function(x,y,id,players)
            return R.World.resolveNetworkSpawn(x,y,id,R.Assets,R.state,players)
        end,
        release=function(players)
            for _,p in ipairs(players) do
                if R.workshopAuthority then R.workshopAuthority:cleanupPlayer({id=p.id or 1},"weekend_travel",{state=R.state}) end
            end
            R.localWorkshopLease=nil;R.state._localWorkshopMachineId=nil
            R.World.selectedInteraction=nil;R.state.screen="world"
            require("src.air_hockey").clear();require("src.basketball").clear()
            require("src.critter_kombat").clear();require("src.critter_crisis").clear()
        end,
    })
    if okay then
        R.state.message=message
        R.saveCurrent()
        if R.multiplayer:isHost() then R.multiplayer:markShopDirty() end
    end
    return okay,code,message,"homeTravel"
end
function Weekend.syncUi(R)
    local week=R.state.home and R.state.home.weekend
    if not week then return end
    local scene=R.World.player.sceneId or "warehouse"
    if R._weekendScene and R._weekendScene~=scene then
        R.state.screen="world";R.World.selectedInteraction=nil
        if R.WorkshopRemoteScreen then R.WorkshopRemoteScreen.clear() end
    end
    R._weekendScene=scene
    if week.phase~="working" and (R.state.screen=="machine" or R.state.screen=="press"
        or R.state.screen=="workshop_remote" and scene~="home") then
        if R.releaseLocalWorkshop then R.releaseLocalWorkshop("closed") end
        if R.multiplayer:isClient() then R.multiplayer:releaseWorkshop("closed") end
        R.state.screen="world"
    end
    if week.travelToken and R._weekendPromptToken~=week.travelToken then
        R._weekendPromptToken=week.travelToken
        R.state.screen="home_travel"
    end
end
function Weekend.finishFrame(R)
    local week=Flow.ensure(R.state)
    if week.phase=="closing" then
        Shutdown.prepare(R.state)
        local safe=#Shutdown.checklist(R.state,R.World)==0
        if safe then Shutdown.pauseConstruction(R.state) end
        return Flow.update(R.state,safe)
    end
    return false
end
return Weekend
