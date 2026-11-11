-- Saved visual and utility condition of the original warehouse. Quick Start and
-- migrated shops use the clean state; the story opening explicitly selects closed.
local Condition={VERSION=1,POWER_FEE_CENTS=6000,WATER_FEE_CENTS=3500}
Condition.ACTIONS={call_power=true,call_water=true,repair_breaker=true,
    clean_west=true,clean_center=true,clean_east=true,repaint=true,lights_on=true,lights_off=true,
    grand_opening=true}
local regions={"west","center","east"}
local function integer(n) return type(n)=="number" and n==math.floor(n) and n>=0 and n<=2147483647 end
function Condition.new(mode,seed)
    local closed=mode=="story"
    return {version=Condition.VERSION,mode=closed and "story" or "quick",seed=integer(seed) and seed or 314159,
        powerConnected=not closed,waterConnected=not closed,breakerRepaired=not closed,
        repainted=not closed,lightsOn=true,grandOpened=not closed,
        grandpaMet=not closed,openingSeen=not closed,
        visitedApartment=not closed,visitedShop=not closed,
        cleaned={west=not closed,center=not closed,east=not closed}}
end
function Condition.valid(c)
    if type(c)~="table" or c.version~=Condition.VERSION or (c.mode~="story" and c.mode~="quick")
        or not integer(c.seed) or type(c.cleaned)~="table" then return false end
    local fields={version=true,mode=true,seed=true,powerConnected=true,waterConnected=true,
        breakerRepaired=true,repainted=true,lightsOn=true,grandOpened=true,grandpaMet=true,openingSeen=true,
        visitedApartment=true,visitedShop=true,firstDestination=true,cleaned=true}
    for key in pairs(c) do if not fields[key] then return false end end
    for _,key in ipairs({"powerConnected","waterConnected","breakerRepaired","repainted","lightsOn","grandOpened"}) do
        if type(c[key])~="boolean" then return false end
    end
    if c.grandpaMet~=nil and type(c.grandpaMet)~="boolean" then return false end
    if c.openingSeen~=nil and type(c.openingSeen)~="boolean" then return false end
    if c.visitedApartment~=nil and type(c.visitedApartment)~="boolean" then return false end
    if c.visitedShop~=nil and type(c.visitedShop)~="boolean" then return false end
    if c.firstDestination~=nil and c.firstDestination~="home" and c.firstDestination~="warehouse" then return false end
    local count=0
    for key,value in pairs(c.cleaned) do
        if key~="west" and key~="center" and key~="east" or type(value)~="boolean" then return false end
        count=count+1
    end
    if count~=3 then return false end
    if c.mode=="quick" then
        if not (c.powerConnected and c.waterConnected and c.breakerRepaired and c.repainted and c.grandOpened) then return false end
        for _,region in ipairs(regions) do if not c.cleaned[region] then return false end end
    end
    if c.grandOpened then
        if not (c.powerConnected and c.waterConnected and c.breakerRepaired and c.repainted) then return false end
        for _,region in ipairs(regions) do if not c.cleaned[region] then return false end end
    end
    return true
end
function Condition.of(state)
    return state and state.warehouse and state.warehouse.condition
end
function Condition.powered(state)
    local c=Condition.of(state)
    return c==nil or c.powerConnected and c.breakerRepaired
end
function Condition.lit(state)
    local c=Condition.of(state)
    return Condition.powered(state) and (not c or c.lightsOn)
end
function Condition.stage(state)
    local c=Condition.of(state)
    if not c or c.mode=="quick" then return 4 end
    if not c.cleaned.west then return 0 end
    if not c.cleaned.center then return 1 end
    if not c.cleaned.east then return 2 end
    return c.repainted and 4 or 3
end
function Condition.variant(state)
    return "stage"..Condition.stage(state)..(Condition.lit(state) and "On" or "Off")
end
function Condition.waterReady(state)
    local c=Condition.of(state)
    return c==nil or c.waterConnected
end
function Condition.complete(state)
    local c=Condition.of(state)
    if not c or c.mode=="quick" then return true end
    if not (Condition.powered(state) and Condition.waterReady(state) and c.repainted) then return false end
    for _,region in ipairs(regions) do if not c.cleaned[region] then return false end end
    return true
end
function Condition.openForBusiness(state)
    local c=Condition.of(state)
    return c==nil or c.grandOpened==true
end
function Condition.readyForOpening(state)
    local c=Condition.of(state)
    if not c or c.mode=="quick" then return true end
    if c.grandpaMet==false then return false,"Visit Grandpa at the farm before opening the shop." end
    if not Condition.complete(state) then return false,"Restore utilities, repair the breaker, clean all floors, and repaint first." end
    local fleet=require("src.machine_fleet")
    local cutter=fleet.installed(state,"polar_115")
    local wrapper=fleet.installed(state,"skid_wrapper")
    if not cutter or not wrapper then return false,"The cutter and skid wrapper must be installed." end
    if (cutter.maintenance.serviceCount or 0)<1 or (cutter.variables.bladeSharpness or 0)<75 then
        return false,"Service the cutter and restore its blade before opening."
    end
    if (wrapper.maintenance.serviceCount or 0)<1 then
        return false,"Service the skid wrapper before opening."
    end
    return true
end
local anchors={breaker={x=218,y=185,radius=66,hoverX=218,hoverY=114},
    west={x=145,y=510,radius=155},center={x=475,y=495,radius=155},
    east={x=760,y=495,radius=155},paint={x=470,y=245,radius=160}}
Condition.anchors=anchors
local function near(player,point)
    return type(player)=="table" and player.sceneId=="warehouse"
        and type(player.x)=="number" and type(player.y)=="number"
        and (player.x-point.x)^2+(player.y-point.y)^2<=point.radius^2
end
function Condition.perform(state,player,action)
    if not Condition.ACTIONS[action] then return false,"not_allowed","Unknown restoration action." end
    local c=Condition.of(state)
    if not Condition.valid(c) then return false,"unavailable","The shop lighting state is unavailable." end
    if action=="lights_on" or action=="lights_off" then
        if not near(player,anchors.breaker) then return false,"out_of_range","Move to the west-wall light switch." end
        if not Condition.powered(state) then return false,"no_power","Repair the power feed and breaker first." end
        local on=action=="lights_on"
        if c.lightsOn==on then return true,"already_applied",on and "Lights are already on." or "Lights are already off." end
        c.lightsOn=on
        return true,"accepted",on and "Warehouse lights on." or "Warehouse lights off."
    end
    if c.mode~="story" then return false,"unavailable","This shop does not need restoration." end
    if action=="grand_opening" then
        if c.grandOpened then return true,"already_applied","The Picture Shop is already open for business." end
        if type(player)~="table" or player.sceneId~="warehouse" then
            return false,"wrong_scene","Return to the shop to hold its grand opening."
        end
        local ready,reason=Condition.readyForOpening(state)
        if not ready then return false,"not_ready",reason end
        c.grandOpened=true
        return true,"accepted","Grand opening complete! Clients can now call and visit the shop."
    end
    if action=="call_power" or action=="call_water" then
        local power=action=="call_power"
        local field=power and "powerConnected" or "waterConnected"
        if c[field] then return true,"already_applied",power and "Power service is already connected." or "Water service is already connected." end
        local fee=power and Condition.POWER_FEE_CENTS or Condition.WATER_FEE_CENTS
        local label=power and "Power reconnection" or "Water reconnection"
        local okay=require("src.business_calendar").recordPaidExpenseCents(state,label,fee,
            power and "power_reconnection" or "water_reconnection")
        if not okay then return false,"insufficient_funds",("%s costs $%.2f. The shop needs more funds."):format(label,fee/100) end
        c[field]=true
        return true,"accepted",label.." paid. "..(power and "Inspect the damaged breaker before using the lights." or "Water service is restored. Clean the old damp area.")
    end
    if action=="repair_breaker" then
        if not c.powerConnected then return false,"no_service","There is no power at the meter. Call the utility first." end
        if c.breakerRepaired then return true,"already_applied","The breaker is already repaired." end
        if not near(player,anchors.breaker) then return false,"out_of_range","Move to the breaker on the west wall." end
        c.breakerRepaired=true
        return true,"accepted","Breaker repaired. Workshop lights and power are on."
    end
    local region=type(action)=="string" and action:match("^clean_(%a+)$")
    if region and c.cleaned[region]~=nil then
        if c.cleaned[region] then return true,"already_applied","This floor region is already clean." end
        if region=="center" and not c.cleaned.west then
            return false,"not_ready","Clean the west dock area first."
        end
        if region=="east" and not c.cleaned.center then
            return false,"not_ready","Clean the center rack area first."
        end
        if not near(player,anchors[region]) then return false,"out_of_range","Move into this floor region before cleaning." end
        c.cleaned[region]=true
        return true,"accepted","Floor cleaned: "..region.."."
    end
    if action=="repaint" then
        if c.repainted then return true,"already_applied","The wall and shelves are already repainted." end
        if not (c.cleaned.west and c.cleaned.center and c.cleaned.east) then
            return false,"not_ready","Clean all three floor areas before repainting."
        end
        if not near(player,anchors.paint) then return false,"out_of_range","Move near the worn wall and shelving." end
        c.repainted=true
        return true,"accepted","Wall and shelving touched up."
    end
    return false,"not_allowed","Unknown restoration action."
end
return Condition
