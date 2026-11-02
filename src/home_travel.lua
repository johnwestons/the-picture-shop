local Flow=require("src.weekend_flow")
local Layout=require("src.home_layouts")
local Config=require("src.config")
local Travel={}
function Travel.target(player,state)
    if not state or not state.home then return nil end
    local scene=player.sceneId or "warehouse"
    if scene=="home" then
        local x,y=Layout.spawn(state,1)
        return {kind="homeTravel",x=x,y=y,radius=52,prompt="E: apartment exit / return to shop",actionLabel="EXIT"}
    elseif scene=="warehouse" then
        local p=require("src.warehouse_registration").entrance
        return {kind="homeTravel",x=p.x,y=p.y,radius=38,hoverX=p.hoverX,hoverY=p.hoverY,hoverRadius=20,
            prompt="E: front entrance / go home for the weekend",actionLabel="GO HOME"}
    end
end
function Travel.clearRequest(week)
    week.travelToken,week.readyMask=nil,nil
end
function Travel.ready(week,id)
    return week.readyMask and math.floor(week.readyMask/2^(id-1))%2==1 or false
end
function Travel.guestJoined(state,id)
    local week=state.home and state.home.weekend
    if week and week.travelToken and Travel.ready(week,id) then
        week.readyMask=week.readyMask-2^(id-1);state.home.revision=state.home.revision+1
        return true
    end
    return false
end
function Travel.allReady(week,players)
    for _,p in ipairs(players) do if not Travel.ready(week,p.id or 1) then return false end end
    return true
end
function Travel.command(state,player,command,context)
    local week=Flow.ensure(state);local id=tonumber(player.id) or 1
    local action,token=command:match("^(%a+):(%d+)$")
    local function denied(message) return false,"not_allowed",message end
    if action=="ready" then
        if not week.travelToken or tonumber(token)~=week.travelToken then return denied("That travel request has ended.") end
        if not Travel.ready(week,id) then week.readyMask=week.readyMask+2^(id-1);state.home.revision=state.home.revision+1 end
        return true,"accepted","Ready to travel with the host."
    end
    if id~=1 then return denied("The host chooses when the household travels.") end
    if command=="cancel" then
        Travel.clearRequest(week);state.home.revision=state.home.revision+1
        return true,"accepted","Travel request canceled."
    end
    local target=Travel.target(player,state)
    if not target or (player.x-target.x)^2+(player.y-target.y)^2>(target.radius+10)^2 then
        return denied("Go to the exterior front entrance or your apartment exit first.")
    end
    if week.phase~="ready" and week.phase~="home" then return denied("The shop must finish its Friday shutdown first.") end
    if week.phase=="home" then
        local copy=require("src.save_schema").copy(state)
        local okay,message=Flow.returnToWork(copy,copy.home.revision)
        if not okay then return denied(message) end
    end
    if command=="request" then
        if not week.travelToken then
            state.home.revision=state.home.revision+1;week.travelToken=state.home.revision;week.readyMask=1
        end
        return true,"accepted","Travel requested. Guests can mark themselves ready; the host can also bring everyone."
    end
    if (action~="depart" and action~="force") or tonumber(token)~=week.travelToken or not week.travelToken then
        return denied("That travel request has ended.")
    end
    local players=context.players()
    if action=="depart" and not Travel.allReady(week,players) then return denied("Waiting for the other players to be ready.") end
    if week.phase=="ready" and #require("src.shop_shutdown").checklist(state,context.world)>0 then
        return denied("The shop is no longer safe to leave. Park equipment and check shutdown again.")
    end
    local goingHome=week.phase=="ready"
    if context.commuteWorld then
        local okay,trip=require('src.commute.trip').start(state,players,week.travelToken,context.commuteWorld)
        if not okay then return denied(trip) end
        require('src.home_residents').recover(state)
        Travel.clearRequest(week)
        if context.release then context.release(players) end
        for _,p in ipairs(players) do
            local part=trip.participants[require('src.home_residents').key(p)]
            local ped=part.rider.ped
            require('src.player_controller').reset(p,{x=ped.x,y=ped.z},Config.player)
            p.sceneId='commute';p.resting=false
            p.inputX,p.inputY=0,0;p.gameInputX,p.gameInputY=0,0;p.combatButtons=0
        end
        return true,'accepted','Walk to your motorcycle and put on your riding gear.'
    end
    local okay,message
    if goingHome then okay,message=Flow.depart(state,state.home.revision)
    else okay,message=Flow.returnToWork(state,state.home.revision) end
    if not okay then return denied(message) end
    require("src.home_residents").recover(state)
    Travel.clearRequest(state.home.weekend)
    if context.release then context.release(players) end
    Travel.placeArrival(state,players,goingHome,context)
    return true,"accepted",state.message
end
function Travel.placeArrival(state,players,goingHome,context)
    context=context or {}
    for _,p in ipairs(players) do
        local x,y
        if goingHome then x,y=Layout.spawn(state,p.id or 1)
        else
            local points=require("src.warehouse_registration").exitPoints
            local point=points[p.id or 1] or points[1];x,y=point.x,point.y
            if context.resolveShopSpawn then x,y=context.resolveShopSpawn(x,y,p.id or 1,players) end
        end
        require("src.player_controller").reset(p,{x=x,y=y},Config.player)
        p.sceneId=goingHome and "home" or "warehouse";p.resting=false
        p.inputX,p.inputY=0,0;p.gameInputX,p.gameInputY=0,0;p.combatButtons=0
    end
end
return Travel
