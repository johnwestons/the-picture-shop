local Calendar=require("src.business_calendar")
local Objects=require("src.home_objects")
local Chores=require("src.home_chores")
local Cooking=require("src.home_cooking")
local Sleep=require("src.home_sleep")
local Utilities=require("src.home_utilities")
local Dining=require("src.home_dining")
local Residents={NEEDS={"hunger","thirst","hygiene","energy"}}
local rates={hunger=2.5,thirst=4,hygiene=1.1,energy=2.7}
Residents.ACTIONS={
    drink={label="Drink tap water",minutes=2,targets={sink=true,basin=true},gain={thirst=75}},
    wash={label="Wash hands and face",minutes=5,targets={sink=true,basin=true},gain={hygiene=18}},
    bathe={label="Take a bath / shower",minutes=20,targets={bath=true},gain={hygiene=85}},
    toilet={label="Use bathroom and wash hands",minutes=5,targets={toilet=true},gain={hygiene=5}},
    laundry={label="Old laundry action",minutes=45,targets={laundry=true},gain={hygiene=30},legacy=true},
    rest={label="Rest on the floor",minutes=60,targets={floor=true},gain={energy=22}},
    nap={label="Nap in bed",minutes=60,targets={},furnitureKind="bed",gain={energy=65}},
    sit={label="Sit and rest",minutes=30,targets={},furnitureKind="chair",gain={energy=8}},
    couchrest={label="Nap on the couch",minutes=60,targets={},furnitureKind="couch",gain={energy=42}},
    matrest={label="Nap on the guest mat",minutes=60,targets={},furnitureKind="guest_mat",gain={energy=32}},
    watch={label="Watch nearby TV",minutes=30,targets={},furnitureKinds={chair=true,couch=true,old_tv=true},gain={energy=9}},
    checktime={label="Check the clock",minutes=1,targets={},furnitureKind="clock",gain={}},
    cupfill={label="Fill cup with tap water",minutes=1,targets={},furnitureKind="cup",gain={},objectAction=true},
    cupwash={label="Wash cup",minutes=2,targets={},furnitureKind="cup",gain={},objectAction=true},
    cupdrink={label="Drink from cup",minutes=2,targets={},furnitureKind="cup",gain={thirst=75},objectAction=true},
    eat={label="Eat a basic meal",minutes=15,targets={floor=true},gain={hunger=65},item="basic_meal"},
    sandwich={label="Eat a sandwich",minutes=10,targets={floor=true},gain={hunger=40},item="sandwich"},
    cereal={label="Eat cereal",minutes=10,targets={floor=true},gain={hunger=35},item="cereal"},
    pizza={label="Eat a pizza slice",minutes=10,targets={floor=true},gain={hunger=45},item="pizza_slice"},
    takeout={label="Eat Chinese takeout",minutes=15,targets={floor=true},gain={hunger=65},item="chinese_meal"},
    bottle={label="Drink a bottled drink",minutes=2,targets={floor=true},gain={thirst=75},item="bottled_drink"},
}
for kind,action in pairs(Chores.ACTIONS) do Residents.ACTIONS[kind]=action end
for kind,action in pairs(Cooking.RECIPES) do Residents.ACTIONS[kind]=action end
for kind,action in pairs(Cooking.FOODS) do Residents.ACTIONS[kind]=action end
for kind,action in pairs(Sleep.ACTIONS) do Residents.ACTIONS[kind]=action end
function Residents.validCommand(command)
    if Dining.decode(command) then return true end
    if command=="cancel" then return true end
    if Objects.decode(command) then return true end
    if Cooking.decode(command) then return true end
    if Sleep.decode(command)~=nil then return true end
    if type(command)~="string" or #command>32 then return false end
    local action,target=command:match("^([a-z]+):([a-z0-9]+)$")
    local definition=Residents.ACTIONS[action];if not definition then return false end
    local id=target and target:match("^furniture(%d+)$")
    return definition.targets[target] or id and #id<=9 and tonumber(id)>0 and tostring(tonumber(id))==id
        and (definition.furnitureKind~=nil or definition.furnitureKinds~=nil or definition.item~=nil) or false
end
function Residents.furnitureAvailable(state,action,item)
    local available=item and item.location~="storage" and (action.furnitureKind==item.kind or action.furnitureKinds and action.furnitureKinds[item.kind]
        or action.item and (item.kind=="chair" or item.kind=="couch")) or false
    if available and require("src.home_furniture_catalog").ITEMS[item.kind].hookup then
        return require("src.home_furniture").hookedUp(state,item)
    end
    return available
end
function Residents.available(state,kind,target)
    local a=Residents.ACTIONS[kind];if a.legacy then return false end
    if a.targets[target] then return not a.chore or Chores.available(state,kind) end
    local id=target:match("^furniture(%d+)$");local item=id and require("src.home_furniture").find(state,tonumber(id))
    return Residents.furnitureAvailable(state,a,item) and (not a.chore or Chores.available(state,kind,item))
end
local function person(name)
    return {name=name,hunger=100,thirst=100,hygiene=100,energy=100,revision=0}
end
function Residents.new() return {owner=person("Host")} end
function Residents.validId(id)
    local number=type(id)=="string" and id:match("^guest%-(%d+)$")
    return number~=nil and #number<=2 and tonumber(number)>=1 and tonumber(number)<=64 and id=="guest-"..tonumber(number)
end
function Residents.valid(records)
    if records==nil then return true end
    if type(records)~="table" or type(records.owner)~="table" then return false end
    local count,credentials=0,{}
    for id,p in pairs(records) do
        count=count+1
        if count>65 or id~="owner" and not Residents.validId(id)
            or type(p)~="table" or type(p.name)~="string" or #p.name>64
            or type(p.revision)~="number" or p.revision<0 or p.revision>1e12 or p.revision~=math.floor(p.revision) then return false end
        if id~="owner" and not require("src.resident_credentials").valid(p.credentialHash) or id=="owner" and p.credentialHash~=nil then return false end
        if p.credentialHash then
            if credentials[p.credentialHash] then return false end
            credentials[p.credentialHash]=true
        end
        if not Sleep.validResident(p) then return false end
        if p.ridingGear~=nil and not require('src.commute.gear').valid(p.ridingGear) then return false end
        if p.ridingTransmission~=nil and p.ridingTransmission~='automatic' and p.ridingTransmission~='manual' then return false end
        if p.activePlayerId~=nil and (type(p.activePlayerId)~="number" or p.activePlayerId<1
            or p.activePlayerId>4 or p.activePlayerId~=math.floor(p.activePlayerId)) then return false end
        for _,need in ipairs(Residents.NEEDS) do
            local value=p[need]
            if type(value)~="number" or value~=value or value<0 or value>100 then return false end
        end
        local a=p.activity
        if a~=nil then
            if type(a)~="table" or not Residents.ACTIONS[a.kind] or not Residents.validCommand(tostring(a.kind)..":"..tostring(a.target)) then return false end
            for _,field in ipairs({"startedAt","endsAt","x","y"}) do
                if type(a[field])~="number" or a[field]~=a[field] or a[field]<0 or a[field]>24000024 then return false end
            end
            if math.abs(a.endsAt-a.startedAt-Residents.ACTIONS[a.kind].minutes/60)>1e-7 then return false end
            local id=a.target:match("^furniture(%d+)$")
            if id and (a.furnitureId~=tonumber(id) or type(a.comfort)~="number" or a.comfort~=a.comfort or a.comfort<.5 or a.comfort>1) then return false end
            if not id and (a.furnitureId~=nil or a.comfort~=nil) then return false end
            if not Chores.validActivity(a) then return false end
            if not Cooking.validActivity(a) then return false end
            if not Utilities.validActivity(a) then return false end
            if not Dining.validActivity(a) then return false end
            if a.kind=="cupfill" or a.kind=="cupwash" then
                if a.fixtureId~="sink" and a.fixtureId~="basin" then return false end
            elseif a.fixtureId~=nil then return false end
        end
    end
    return true
end
function Residents.ensure(state)
    state.home.residents=state.home.residents or Residents.new()
    return state.home.residents
end
function Residents.key(player)
    return (player.id or 1)==1 and "owner" or player.homeResidentId
end
function Residents.bind(state,player,token,players)
    if not require("src.resident_credentials").valid(token) then return nil,"A valid private resident identity is required." end
    local digest=love.data.encode("string","hex",love.data.hash("sha256",token))
    local records=Residents.ensure(state);local id,nextNumber=nil,1
    for key,row in pairs(records) do
        if key~="owner" then
            if row.credentialHash==digest then id=key end
            nextNumber=math.max(nextNumber,tonumber(key:match("%d+$"))+1)
        end
    end
    for _,other in pairs(players or {}) do
        if id and other~=player and other.homeResidentId==id then return nil,"This resident is already connected on another player slot." end
    end
    if not id then
        if nextNumber>64 then return nil,"This household has reached its saved resident limit." end
        id="guest-"..nextNumber
        records[id]=person(player.name or "Guest")
        records[id].credentialHash=digest
        state.home.revision=state.home.revision+1
    end
    player.homeResidentId=id
    -- Rejoining never inherits an unfinished interaction or a sleep vote, even
    -- if disconnect/reconnect happens before the next simulation cleanup tick.
    records[id].activity=nil
    for _,row in pairs(records) do if row.activePlayerId==player.id then row.activePlayerId=nil end end
    records[id].activePlayerId=player.id
    player.homeJoinedAtHours=Calendar.absoluteHours(state)
    return id
end
function Residents.get(state,player)
    return state.home and state.home.residents and state.home.residents[Residents.key(player)]
end
function Residents.activityEndAt(state,resident,activity)
    return Sleep.endAt(state,resident,activity)
end
function Residents.householdAllowed(state,player)
    return require("src.commute.outfit").allowed(state,player,"household")
end
function Residents.recover(state)
    for _,p in pairs(Residents.ensure(state)) do p.activity=nil;p.activePlayerId=nil end
    require("src.home_furniture").recover(state)
end
function Residents.display(state,player)
    local p=Residents.get(state,player)
    if p then return p end
    for _,row in pairs(state.home.residents or {}) do if row.activePlayerId==player.id then return row end end
end
function Residents.prepareActivity(state,player,kind,target,served)
    -- Keep the routine menu's availability view aligned with command-time gates.
    local outfitOkay,outfitMessage=Residents.householdAllowed(state,player)
    if not outfitOkay then return false,"riding_gear",outfitMessage end
    local p=Residents.get(state,player)
    if not p then return false,"resident_required","Your resident has not joined this household." end
    if player.sceneId~="home" or state.home.weekend.phase~="home" then return false,"wrong_scene","Home activities are available at your apartment." end
    if p.activity then return false,"busy","Finish or stop your current activity first." end
    if type(kind)~="string" or type(target)~="string" or not Residents.validCommand(kind..":"..target) then
        return false,"invalid_action","Choose an available home activity."
    end
    local definition=Residents.ACTIONS[kind]
    if not definition or definition.legacy then return false,"invalid_action","Choose an available home activity." end
    local servedHere=false
    if served then
        for _,meal in ipairs(state.home.dining.items or {}) do
            if meal==served and meal.food==definition.item then servedHere=true;break end
        end
        if not servedHere then return false,"unavailable","That served meal is no longer available." end
    end
    if not Residents.available(state,kind,target) and not (servedHere and target=="furniture"..served.parentId) then
        return false,"unavailable","That activity is not available on this furniture."
    end
    local furnitureId=target:match("^furniture(%d+)$");local furnishing,fixtureId
    if target~="floor" then
        local x,y,radius
        if furnitureId then
            furnishing=require("src.home_furniture").find(state,tonumber(furnitureId))
            if furnishing.editor or require("src.home_surfaces").editConflict(state,furnishing) then
                return false,"being_moved","Finish arranging this furniture before using it."
            end
            local approach,reason
            if definition.objectAction then approach,reason=Objects.activityTarget(state,player,kind,furnishing)
            else approach=require("src.home_furniture").targets(state,player)[target] end
            if not approach then return false,"unavailable",reason or "No clear approach to this furniture." end
            fixtureId=definition.objectAction and approach.fixtureId or nil
            x,y,radius=approach.x,approach.y,approach.radius
        else
            local layout=require("src.home_layouts");local fixture=layout.get(state).fixtures[target]
            x,y=layout.toWorld(unpack(fixture.approach));radius=48
        end
        if (player.x-x)^2+(player.y-y)^2>radius^2 then return false,"out_of_range","Walk closer to that fixture first." end
        for _,other in pairs(state.home.residents) do
            if other.activity and (other.activity.target==target
                or fixtureId and (other.activity.target==fixtureId or other.activity.fixtureId==fixtureId)
                or other.activity.fixtureId==target) then
                return false,"occupied","Another resident is using that fixture."
            end
        end
    end
    local tv=kind=="watch" and Utilities.findTV(state,player,furnishing)
    if kind=="watch" and not tv then return false,"unavailable","Switch on a nearby TV and choose a spot in front of its screen with a clear view." end
    local choreOkay,choreMessage=Chores.prepare(state,player,kind,furnishing)
    if not choreOkay then return false,"unavailable",choreMessage end
    local cookOkay,cookMessage=Cooking.prepare(state,kind)
    if not cookOkay then return false,"unavailable",cookMessage end
    local sleepOkay,sleepMessage=Sleep.prepare(state,kind)
    if not sleepOkay then return false,"unavailable",sleepMessage end
    if definition.item and not servedHere and (state.home.inventory[definition.item] or 0)<1 then
        return false,"no_food","None of that food or drink is stored at home."
    end
    return true,{resident=p,definition=definition,kind=kind,target=target,furnishing=furnishing,fixtureId=fixtureId,tv=tv,servedHere=servedHere}
end
function Residents.command(state,player,command,served)
    if command~='cancel' then
        local allowed,reason=Residents.householdAllowed(state,player)
        if not allowed then return false,'riding_gear',reason end
    end
    if Dining.decode(command) then return Dining.command(state,player,command) end
    if Sleep.decode(command)~=nil then return Sleep.command(state,player,command) end
    if Objects.decode(command) then return Objects.command(state,player,command) end
    if Cooking.decode(command) then return Cooking.command(state,player,command) end
    if not Residents.validCommand(command) then return false,"invalid_action","Choose an available home activity." end
    local p=Residents.get(state,player)
    if not p then return false,"resident_required","Your resident has not joined this household." end
    if command=="cancel" then
        if not p.activity then return false,"not_active","No home activity is running." end
        p.activity=nil;p.revision=p.revision+1;player.resting=false
        return true,"cancelled","Home activity stopped."
    end
    local kind,target=command:match("^([a-z]+):([a-z0-9]+)$")
    local ready,contextOrCode,message=Residents.prepareActivity(state,player,kind,target,served)
    if not ready then return false,contextOrCode,message end
    local context=contextOrCode
    p=context.resident;local definition=context.definition
    local furnishing,fixtureId,tv=context.furnishing,context.fixtureId,context.tv
    if definition.item and not context.servedHere then
        state.home.inventory[definition.item]=state.home.inventory[definition.item]-1
        state.home.revision=state.home.revision+1
    end
    local now=Calendar.absoluteHours(state)
    Objects.startActivity(state,kind,furnishing)
    Chores.started(state,kind)
    p.activity={kind=kind,target=target,startedAt=now,endsAt=now+definition.minutes/60,x=player.x,y=player.y,fixtureId=fixtureId}
    if tv then p.activity.tvId=tv.id end
    if served then p.activity.diningParentId=served.parentId;p.activity.diningSlot=served.slot end
    Chores.activityData(state,kind,p.activity)
    Cooking.start(state,p.activity)
    if furnishing then p.activity.furnitureId=furnishing.id;p.activity.comfort=.5+.5*furnishing.condition/100 end
    p.revision=p.revision+1;player.resting=kind=="rest" or kind=="nap" or kind=="sit" or kind=="couchrest" or kind=="matrest" or kind=="watch" or Sleep.ACTIONS[kind]~=nil
    if Sleep.ACTIONS[kind] then return true,"started","Sleeping. Time speeds up only when every connected resident chooses sleep. Stop or move to wake." end
    return true,"started",definition.label..(Cooking.RECIPES[kind] and ". Tend once in the green timing band. Stopping wastes the ingredients." or ". Move away or choose Stop to cancel.")
end
local function segment(p,hours,activity)
    if hours<=0 then return end
    local definition=activity and Residents.ACTIONS[activity.kind]
    for _,need in ipairs(Residents.NEEDS) do
        local gain=definition and (definition.gain[need] or 0)/(definition.minutes/60) or 0
        if activity and need=="energy" then gain=gain*(activity.comfort or 1) end
        p[need]=math.max(0,math.min(100,p[need]+hours*(gain-rates[need])))
    end
end
function Residents.advance(state,players,first,last)
    local records=Residents.ensure(state);local present={};local changed=require("src.home_furniture").recover(state,players)
    for _,player in ipairs(players) do local id=Residents.key(player);if id then present[id]=player end end
    local choreChanged,choreRewards=Chores.timeline(state,players,records,present,first,last)
    changed=choreChanged or changed
    local home=state.home.weekend.phase=="home"
    for id,p in pairs(records) do
        local player=present[id];local a=p.activity
        local cup=a and Residents.ACTIONS[a.kind].objectAction and require("src.home_surfaces").find(state,a.furnitureId)
        local lostCup=a and Residents.ACTIONS[a.kind].objectAction and (not cup or cup.location~="carried" or cup.holderId~=id)
        local activeId=player and (player.id or 1)
        if p.activePlayerId~=activeId then p.activePlayerId=activeId;changed=true end
        if a and (lostCup or not player or not home or player.sceneId~="home" or (player.x-a.x)^2+(player.y-a.y)^2>12^2
            or a.kind=="watch" and not Utilities.watchValid(state,player,a) or not Chores.accessible(state,a)) then
            p.activity=nil;p.revision=p.revision+1;changed=true
            if player then player.resting=false end
            a=nil
        end
        if player and home and player.sceneId=="home" then
            local from=math.max(first,player.homeJoinedAtHours or first)
            if a then
                local endsAt=Residents.activityEndAt(state,p,a)
                segment(p,math.max(0,math.min(last,a.startedAt)-from))
                segment(p,math.max(0,math.min(last,endsAt)-math.max(from,a.startedAt)),a)
                if choreRewards[id] then p.hygiene=math.min(100,p.hygiene+choreRewards[id]) end
                segment(p,math.max(0,last-math.max(from,endsAt)))
                if last+1e-7>=endsAt then
                    Objects.finishActivity(state,a)
                    local cooked=Cooking.finish(state,a)
                    p.activity=nil;p.revision=p.revision+1;player.resting=false;changed=true
                    if id=="owner" then state.message=cooked or Residents.ACTIONS[a.kind].label.." complete." end
                end
            else segment(p,math.max(0,last-from)) end
            changed=changed or last>from
        elseif player and state.home.weekend.phase=="working" then
            for _,need in ipairs(Residents.NEEDS) do
                if p[need]~=100 then p[need]=100;changed=true end
            end
        end
        changed=Sleep.fire(state,p,player,last) or changed
    end
    return changed
end
function Residents.speedScale(state,player)
    local p=player.sceneId=="home" and Residents.get(state,player)
    if not p then return 1 end
    return math.max(.75,(p.energy<20 and .8 or 1)*(p.thirst<15 and .9 or 1)*(p.hunger<10 and .95 or 1))
end
return Residents
