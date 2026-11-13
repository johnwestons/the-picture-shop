-- Saved visual and utility condition of the original warehouse. Quick Start and
-- migrated shops use the clean state; the story opening explicitly selects closed.
local Condition={VERSION=2,POWER_FEE_CENTS=6000,WATER_FEE_CENTS=3500,GRANDPA_ALLOWANCE=420}
Condition.ACTIONS={call_power=true,call_water=true,repair_breaker=true,lights_on=true,lights_off=true,
    clean_puddle1=true,clean_puddle2=true,grand_opening=true}
local regions={"west","center","east"}
local puddles={"puddle1","puddle2"}
local function integer(n) return type(n)=="number" and n==math.floor(n) and n>=0 and n<=2147483647 end
function Condition.new(mode,seed)
    local closed=mode=="story"
    return {version=Condition.VERSION,mode=closed and "story" or "quick",seed=integer(seed) and seed or 314159,
        powerConnected=not closed,waterConnected=not closed,breakerRepaired=not closed,
        repainted=true,lightsOn=not closed,grandOpened=not closed,
        grandpaAllowanceGranted=not closed,
        grandpaMet=not closed,openingSeen=not closed,
        visitedApartment=not closed,visitedShop=not closed,
        cleaned={west=not closed,center=not closed,east=not closed},
        cleanedPuddles={puddle1=not closed,puddle2=not closed},
        puddleStrokes={puddle1={},puddle2={}}}
end
-- Version 1 tied the oily puddles to the east floor segment. Preserve the
-- visible result when upgrading an existing save: old east-clean saves already
-- had no puddles, while unfinished restoration saves still have both.
function Condition.normalize(c)
    if type(c)=="table" and c.version==1 and c.cleanedPuddles==nil then
        local finished=c.mode~="story" or type(c.cleaned)=="table" and c.cleaned.east==true
        c.cleanedPuddles={puddle1=finished,puddle2=finished}
        c.version=Condition.VERSION
    end
    if type(c)=="table" and c.puddleStrokes==nil then
        c.puddleStrokes={puddle1={},puddle2={}}
    end
    if type(c)=="table" and type(c.puddleStrokes)=="table" then
        for _,name in ipairs(puddles) do
            for _,point in ipairs(c.puddleStrokes[name] or {}) do
                if type(point)=="table" and point.angle==nil then point.angle=0 end
            end
        end
    end
    -- Painting is no longer a restoration step. Keep the legacy field valid
    -- so old test shops resume without needing a save version change.
    if type(c)=="table" and c.repainted==false then c.repainted=true end
    return c
end
function Condition.valid(c)
    if type(c)~="table" or c.version~=Condition.VERSION or (c.mode~="story" and c.mode~="quick")
        or not integer(c.seed) or type(c.cleaned)~="table" then return false end
    local fields={version=true,mode=true,seed=true,powerConnected=true,waterConnected=true,
        breakerRepaired=true,repainted=true,lightsOn=true,grandOpened=true,grandpaMet=true,openingSeen=true,
        visitedApartment=true,visitedShop=true,firstDestination=true,cleaned=true,cleanedPuddles=true,
        puddleStrokes=true}
    fields.grandpaAllowanceGranted=true
    for key in pairs(c) do if not fields[key] then return false end end
    for _,key in ipairs({"powerConnected","waterConnected","breakerRepaired","repainted","lightsOn","grandOpened"}) do
        if type(c[key])~="boolean" then return false end
    end
    if c.grandpaMet~=nil and type(c.grandpaMet)~="boolean" then return false end
    if c.openingSeen~=nil and type(c.openingSeen)~="boolean" then return false end
    if c.visitedApartment~=nil and type(c.visitedApartment)~="boolean" then return false end
    if c.visitedShop~=nil and type(c.visitedShop)~="boolean" then return false end
    if c.firstDestination~=nil and c.firstDestination~="home" and c.firstDestination~="warehouse" then return false end
    if c.grandpaAllowanceGranted~=nil and type(c.grandpaAllowanceGranted)~="boolean" then return false end
    local count=0
    for key,value in pairs(c.cleaned) do
        if key~="west" and key~="center" and key~="east" or type(value)~="boolean" then return false end
        count=count+1
    end
    if count~=3 then return false end
    if type(c.cleanedPuddles)~="table" then return false end
    count=0
    for key,value in pairs(c.cleanedPuddles) do
        if key~="puddle1" and key~="puddle2" or type(value)~="boolean" then return false end
        count=count+1
    end
    if count~=2 then return false end
    if c.puddleStrokes~=nil then
        if type(c.puddleStrokes)~="table" then return false end
        if type(c.puddleStrokes.puddle1)~="table"
            or type(c.puddleStrokes.puddle2)~="table" then return false end
        for name,strokes in pairs(c.puddleStrokes) do
            if name~="puddle1" and name~="puddle2" or type(strokes)~="table" or #strokes>1600 then return false end
            for index,point in pairs(strokes) do
                if type(index)~="number" or index~=math.floor(index) or index<1 or index>#strokes
                    or type(point)~="table" or type(point.x)~="number" or type(point.y)~="number"
                    or point.x<0 or point.x>960 or point.y<0 or point.y>678
                    or point.x~=point.x or point.y~=point.y
                    or point.angle~=nil and (type(point.angle)~="number" or point.angle~=point.angle
                        or point.angle< -math.pi or point.angle>math.pi) then return false end
                for key in pairs(point) do if key~="x" and key~="y" and key~="angle" then return false end end
            end
        end
    end
    if c.mode=="quick" then
        if not (c.powerConnected and c.waterConnected and c.breakerRepaired and c.repainted and c.grandOpened) then return false end
        for _,region in ipairs(regions) do if not c.cleaned[region] then return false end end
        for _,puddle in ipairs(puddles) do if not c.cleanedPuddles[puddle] then return false end end
    end
    if c.grandOpened then
        if not (c.powerConnected and c.waterConnected and c.breakerRepaired) then return false end
        for _,region in ipairs(regions) do if not c.cleaned[region] then return false end end
        for _,puddle in ipairs(puddles) do if not c.cleanedPuddles[puddle] then return false end end
    end
    return true
end
function Condition.of(state)
    return state and state.warehouse and state.warehouse.condition
end

function Condition.ensureGrandpaAllowance(state)
    local c=Condition.of(state)
    if not c or c.mode~="story" or c.grandpaAllowanceGranted then return false end
    -- Covers utility reconnection and two purchased service kits before jobs open.
    state.money=(state.money or 0)+Condition.GRANDPA_ALLOWANCE
    c.grandpaAllowanceGranted=true
    return true
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
    return 4
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
    if not (Condition.lit(state) and Condition.waterReady(state)) then return false end
    for _,region in ipairs(regions) do if not c.cleaned[region] then return false end end
    for _,puddle in ipairs(puddles) do if not c.cleanedPuddles[puddle] then return false end end
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
    if not Condition.complete(state) then return false,"Restore utilities, repair the breaker, and mop up both floor spills first." end
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
    -- Spill art, footsteps, interaction prompts, and mop range all use these
    -- floor contacts. Keep them clear of the story machines and each other.
    puddle1={x=295,y=490,radius=205,visualRadiusX=225,visualRadiusY=85,
        hoverX=295,hoverY=490,hoverRadius=75},
    puddle2={x=690,y=540,radius=165,visualRadiusX=175,visualRadiusY=70,
        hoverX=690,hoverY=540,hoverRadius=65}}
Condition.anchors=anchors
local function withinSpill(point,x,y)
    local dx=(x-point.x)/point.visualRadiusX
    local dy=(y-point.y)/point.visualRadiusY
    local function lobe(cx,cy,rx,ry)
        local px,py=(dx-cx)/rx,(dy-cy)/ry
        return px*px+py*py<=1.12
    end
    -- Mirror the four shader lobes so mop hits and wet footprints follow the
    -- visible asymmetric spill instead of its larger rectangular bounds.
    return lobe(0,0,.77,.75) or lobe(-.49,.13,.38,.53)
        or lobe(.38,-.27,.43,.55) or lobe(.11,.46,.32,.38)
end
function Condition.spillFootprint(name,x,y)
    local point=anchors[name]
    return point~=nil and type(x)=="number" and type(y)=="number"
        and withinSpill(point,x,y) or false
end
local Wipe={radiusX=12,radiusY=7,completionCoverage=.92,maxStrokes=1600}
local progressCache=setmetatable({},{__mode="k"})
local function stampOpacity(spot,x,y)
    local angle=tonumber(spot.angle) or 0
    local c,s=math.cos(angle),math.sin(angle)
    local dx,dy=x-spot.x,y-spot.y
    local px=(dx*c+dy*s)/Wipe.radiusX
    local py=(-dx*s+dy*c)/Wipe.radiusY
    local radius=math.sqrt(px*px+py*py)
    if radius>1 then return 0 end
    local alpha=.13
    if radius<=.80 then alpha=1-(1-alpha)*(1-.22) end
    if radius<=.58 then alpha=1-(1-alpha)*(1-.30) end
    if radius<=.34 then alpha=1-(1-alpha)*(1-.36) end
    return alpha
end
local function wipeOpacity(strokes,x,y)
    local remaining=1
    for _,spot in ipairs(strokes) do
        local amount=stampOpacity(spot,x,y)
        if amount>0 then remaining=remaining*(1-amount) end
    end
    return 1-remaining
end
local function brushTouchesSpill(point,x,y,angle)
    local c,s=math.cos(angle or 0),math.sin(angle or 0)
    for index=0,11 do
        local a=index*math.pi/6
        local px=math.cos(a)*Wipe.radiusX
        local py=math.sin(a)*Wipe.radiusY
        if withinSpill(point,x+px*c-py*s,y+px*s+py*c) then return true end
    end
    return withinSpill(point,x,y)
end
function Condition.puddleProgress(state,name)
    local c=Condition.of(state)
    if not c or not anchors[name] then return 0 end
    if c.cleanedPuddles[name] then return 1 end
    local strokes=c.puddleStrokes and c.puddleStrokes[name] or {}
    local point=anchors[name]
    local byName=progressCache[c]
    if not byName then byName={};progressCache[c]=byName end
    local entry=byName[name]
    if not entry or entry.count>#strokes then
        entry={count=0,total=0,remaining=0,cells={}}
        for y=point.y-point.visualRadiusY,point.y+point.visualRadiusY,7 do
            for x=point.x-point.visualRadiusX,point.x+point.visualRadiusX,12 do
                if withinSpill(point,x,y) then
                    local remaining=1
                    for _,spot in ipairs(strokes) do
                        remaining=remaining*(1-stampOpacity(spot,x,y))
                    end
                    entry.cells[#entry.cells+1]={x=x,y=y,remaining=remaining}
                    entry.total=entry.total+1
                    entry.remaining=entry.remaining+remaining
                end
            end
        end
        entry.count=#strokes
        byName[name]=entry
    else
        for index=entry.count+1,#strokes do
            local spot=strokes[index]
            for _,cell in ipairs(entry.cells) do
                local amount=stampOpacity(spot,cell.x,cell.y)
                if amount>0 then
                    local remaining=cell.remaining*(1-amount)
                    entry.remaining=entry.remaining-(cell.remaining-remaining)
                    cell.remaining=remaining
                end
            end
        end
        entry.count=#strokes
    end
    if entry.total==0 then return 0 end
    return 1-entry.remaining/entry.total
end
function Condition.puddleAt(state,name,x,y)
    local c=Condition.of(state)
    local point=anchors[name]
    return c and point and not c.cleanedPuddles[name]
        and withinSpill(point,x,y)
        and wipeOpacity(c.puddleStrokes and c.puddleStrokes[name] or {},x,y)<.96 or false
end
function Condition.mopContact(state,name,x,y,angle,deferCompletion)
    local c=Condition.of(state)
    local point=anchors[name]
    if not Condition.valid(c) or c.mode~="story" or not point or c.cleanedPuddles[name]
        or type(x)~="number" or type(y)~="number" or type(angle)~="number"
        or x~=x or y~=y or angle~=angle or math.abs(angle)>math.pi
        or not brushTouchesSpill(point,x,y,angle) then
        return false,false
    end
    c.puddleStrokes=c.puddleStrokes or {puddle1={},puddle2={}}
    local strokes=c.puddleStrokes[name]
    if #strokes>=1600 then return false,false end
    strokes[#strokes+1]={x=math.floor(x*10+.5)/10,y=math.floor(y*10+.5)/10,
        angle=math.floor(angle*1000+.5)/1000}
    local done=Condition.puddleProgress(state,name)>=Wipe.completionCoverage
    if done and not deferCompletion then
        c.cleanedPuddles[name]=true
        if c.cleanedPuddles.puddle1 and c.cleanedPuddles.puddle2 then
            c.cleaned.west,c.cleaned.center,c.cleaned.east=true,true,true
        end
    end
    return true,done and not deferCompletion
end
function Condition.mopPoint(state,name,x,y,deferCompletion)
    return Condition.mopContact(state,name,x,y,0,deferCompletion)
end
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
        return true,"accepted",label.." paid. "..(power and "Inspect the damaged breaker before using the lights." or "Water service is restored. Mop up both floor spills.")
    end
    if action=="repair_breaker" then
        if not c.powerConnected then return false,"no_service","There is no power at the meter. Call the utility first." end
        if c.breakerRepaired then return true,"already_applied","The breaker is already repaired." end
        if not near(player,anchors.breaker) then return false,"out_of_range","Move to the breaker on the west wall." end
        c.breakerRepaired=true
        c.lightsOn=false
        return true,"accepted","Breaker repaired. Switch it on to light the warehouse."
    end
    local puddle=type(action)=="string" and action:match("^clean_(puddle%d+)$")
    if puddle and c.cleanedPuddles[puddle]~=nil then
        if c.cleanedPuddles[puddle] then return true,"already_applied","This oily puddle is already clean." end
        return false,"mop_required","Start mopping while standing in the spill, then walk across it."
    end
    return false,"not_allowed","Unknown restoration action."
end
return Condition
