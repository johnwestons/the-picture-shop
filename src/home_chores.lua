local Calendar=require("src.business_calendar")
local Layout=require("src.home_layouts")
local Chores={}
Chores.ACTIONS={
    loadwash={label="Load and start washer",minutes=5,targets={laundry=true},gain={},chore=true},
    unload={label="Unload clean laundry",minutes=5,targets={laundry=true},gain={},chore=true},
    change={label="Put on fresh clothes",minutes=2,targets={laundry=true},furnitureKind="wardrobe",gain={},chore=true},
    dishes={label="Wash up to four dishes",minutes=5,targets={sink=true},gain={},chore=true},
    wipe={label="Wipe kitchen surfaces",minutes=5,targets={sink=true},gain={},chore=true},
    scrub={label="Clean the bathroom",minutes=8,targets={bath=true},gain={},chore=true},
    sweep={label="Sweep apartment floors",minutes=8,targets={floor=true},gain={},chore=true},
    trash={label="Take trash out at entrance",minutes=5,targets={floor=true},gain={},chore=true},
}
local function number(n,a,b) return type(n)=="number" and n==n and n>=a and n<=b end
local function integer(n,a,b) return number(n,a,b) and n==math.floor(n) end
function Chores.new(now)
    return {version=1,revision=0,lastAt=now or 0,contributions={},dishes=0,trash=0,
        soil={kitchen=0,bathroom=0,living=0},laundry={phase="idle",cycle=0,dirty=0,clean=0}}
end
function Chores.ensure(state)
    state.home.chores=state.home.chores or Chores.new(Calendar.absoluteHours(state));return state.home.chores
end
function Chores.valid(data)
    if data==nil then return true end
    if type(data)~="table" or data.version~=1 or not integer(data.revision,0,1e12) or not number(data.lastAt,0,24000100)
        or not integer(data.dishes,0,64) or not integer(data.trash,0,64) or type(data.soil)~="table" or type(data.contributions)~="table"
        or type(data.laundry)~="table" then return false end
    for _,k in ipairs({"kitchen","bathroom","living"}) do if not number(data.soil[k],0,100) then return false end end
    local count=0
    for id,hours in pairs(data.contributions) do
        count=count+1
        if count>65 or not (id=="owner" or require("src.home_residents").validId(id)) or not number(hours,0,24000100) then return false end
    end
    local l=data.laundry
    if not integer(l.cycle,0,1e9) or not integer(l.dirty,0,64) or not integer(l.clean,0,64) then return false end
    if l.phase=="idle" then return l.startedAt==nil and l.dueAt==nil end
    return (l.phase=="washing" or l.phase=="ready") and l.cycle>0 and number(l.startedAt,0,24000100)
        and number(l.dueAt,l.startedAt,24000100) and math.abs(l.dueAt-l.startedAt-.75)<1e-7
end
local function changed(state)
    -- Chore progress must not invalidate unrelated financial checkout revisions.
    local c=state.home.chores;c.revision=c.revision+1
end
function Chores.advance(state,players,first,last)
    local c=Chores.ensure(state);local dirty=false;local present={};local count,wearHours=0,0
    if require("src.weekend_flow").atHome(state) then
        local Residents=require("src.home_residents")
        for _,p in ipairs(players or {}) do
            local id=Residents.key(p)
            if p.sceneId=="home" and id and Residents.get(state,p) and not present[id] and (p.homeJoinedAtHours or first)<=last then
                present[id]=true;count=count+1
                wearHours=wearHours+math.max(0,last-math.max(first,c.lastAt,p.homeJoinedAtHours or first))
                local period=state.home.weekend.closesAtHours
                if (c.contributions[id] or -1)<period and c.laundry.dirty<64 then
                    c.contributions[id]=period;c.laundry.dirty=c.laundry.dirty+1;dirty=true
                end
            end
        end
    end
    local hours=math.max(0,last-math.max(first,c.lastAt))
    if hours>0 and count>0 then
        c.lastAt=last
        c.soil.living=math.min(100,c.soil.living+wearHours*.5)
        dirty=true
    end
    if c.laundry.phase=="washing" and last+1e-7>=c.laundry.dueAt then c.laundry.phase="ready";dirty=true end
    if dirty then changed(state) end
    return dirty
end
function Chores.available(state,kind,item)
    local c=Chores.ensure(state);local l=c.laundry
    if kind=="loadwash" then return l.phase=="idle" and l.dirty>0
    elseif kind=="unload" then return l.phase=="ready"
    elseif kind=="change" then return (item and item.contents.clean or not item and l.clean or 0)>0
    elseif kind=="dishes" then return c.dishes>0
    elseif kind=="wipe" then return c.soil.kitchen>0
    elseif kind=="scrub" then return c.soil.bathroom>0
    elseif kind=="sweep" then return c.soil.living>0
    elseif kind=="trash" then return c.trash>0 end
    return true
end
function Chores.prepare(state,player,kind,item)
    if not Chores.ACTIONS[kind] then return true end
    local c=Chores.ensure(state);local l=c.laundry
    if not Chores.available(state,kind,item) then return false,"That household task is not needed or ready yet." end
    if kind=="loadwash" and l.cycle>=1e9 then return false,"This washer has reached its service limit." end
    if kind=="unload" and l.clean>=64 then return false,"Use some clean clothes before unloading another bundle." end
    if (kind=="wipe" or kind=="scrub") and not require("src.home_wipe_art").standingPose(state,kind=="wipe" and "sink" or "bath") then
        return false,"Move furniture away from the fixture to make room for cleaning."
    end
    if kind=="trash" then
        local x,y=Layout.spawn(state,1)
        if (player.x-x)^2+(player.y-y)^2>60^2 then return false,"Carry the trash out from beside the apartment entrance." end
    end
    for _,r in pairs(state.home.residents) do
        if kind~="change" and r.activity and r.activity.kind==kind then return false,"Another resident is already doing that household task." end
    end
    return true
end
function Chores.accessible(state,activity)
    if activity.kind~="wipe" and activity.kind~="scrub" then return true end
    return require("src.home_wipe_art").standingPose(state,activity.kind=="wipe" and "sink" or "bath")~=nil
end
function Chores.activityData(state,kind,activity)
    if kind=="dishes" then activity.choreAmount=math.min(4,Chores.ensure(state).dishes)
    elseif kind=="trash" then activity.choreAmount=math.min(8,Chores.ensure(state).trash)
    elseif kind=="unload" then activity.choreCycle=Chores.ensure(state).laundry.cycle end
end
function Chores.validActivity(activity)
    if activity.kind=="dishes" or activity.kind=="trash" then
        if not integer(activity.choreAmount,1,activity.kind=="dishes" and 4 or 8) then return false end
    elseif activity.choreAmount~=nil then return false end
    if activity.kind=="unload" then return integer(activity.choreCycle,1,1e9) end
    return activity.choreCycle==nil
end
function Chores.started(state,kind)
    local c=Chores.ensure(state);local dirty=false
    if kind=="cook" or kind=="prepare" then c.dishes=math.min(64,c.dishes+2);c.trash=math.min(64,c.trash+1);c.soil.kitchen=math.min(100,c.soil.kitchen+6);dirty=true end
    if kind=="hotmeal" or kind=="goodmeal" or kind=="plainmeal" then c.dishes=math.min(64,c.dishes+1);c.soil.kitchen=math.min(100,c.soil.kitchen+3);dirty=true end
    if kind=="eat" or kind=="cereal" then c.dishes=math.min(64,c.dishes+1);c.soil.kitchen=math.min(100,c.soil.kitchen+3);dirty=true end
    if kind=="eat" or kind=="pizza" or kind=="takeout" or kind=="bottle" or kind=="sandwich" then c.trash=math.min(64,c.trash+1);dirty=true end
    if kind=="bathe" or kind=="toilet" then c.soil.bathroom=math.min(100,c.soil.bathroom+(kind=="bathe" and 5 or 2));dirty=true end
    if dirty then changed(state) end
end
function Chores.finished(state,a)
    if not Chores.ACTIONS[a.kind] then return end
    local c=Chores.ensure(state);local l=c.laundry
    if a.kind=="loadwash" then
        if l.phase~="idle" or l.dirty<1 then return end
        l.dirty=l.dirty-1;l.cycle=l.cycle+1;l.phase="washing";l.startedAt=a.endsAt;l.dueAt=a.endsAt+.75
    elseif a.kind=="unload" then
        if l.phase~="ready" or l.cycle~=a.choreCycle or l.clean>=64 then return end
        l.phase="idle";l.startedAt=nil;l.dueAt=nil;l.clean=l.clean+1
    elseif a.kind=="change" then
        local wardrobe=a.furnitureId and require("src.home_surfaces").find(state,a.furnitureId)
        if wardrobe then
            if (wardrobe.contents.clean or 0)<1 then return end
            wardrobe.contents.clean=wardrobe.contents.clean-1;require("src.home_objects").changed(state,wardrobe)
        else
            if l.clean<1 then return end
            l.clean=l.clean-1
        end
        changed(state);return 35
    elseif a.kind=="dishes" then c.dishes=math.max(0,c.dishes-a.choreAmount);c.soil.kitchen=math.max(0,c.soil.kitchen-5)
    elseif a.kind=="trash" then c.trash=math.max(0,c.trash-a.choreAmount)
    elseif a.kind=="wipe" then c.soil.kitchen=math.max(0,c.soil.kitchen-35)
    elseif a.kind=="scrub" then c.soil.bathroom=math.max(0,c.soil.bathroom-50)
    elseif a.kind=="sweep" then c.soil.living=math.max(0,c.soil.living-40) end
    changed(state)
end
function Chores.timeline(state,players,records,present,first,last)
    local events={};local rewards={};local any=false
    if require("src.weekend_flow").atHome(state) then
        for id,r in pairs(records) do
            local a=r.activity;local p=present[id]
            if a and Chores.ACTIONS[a.kind] and p and p.sceneId=="home" and (p.x-a.x)^2+(p.y-a.y)^2<=12^2 and a.endsAt<=last+1e-7 and Chores.accessible(state,a) then
                events[#events+1]={id=id,activity=a}
            end
        end
    end
    table.sort(events,function(a,b) if a.activity.endsAt==b.activity.endsAt then return a.id<b.id end;return a.activity.endsAt<b.activity.endsAt end)
    local cursor=first
    for _,event in ipairs(events) do
        local at=math.max(cursor,event.activity.endsAt)
        any=Chores.advance(state,players,cursor,at) or any
        rewards[event.id]=Chores.finished(state,event.activity);any=true;cursor=at
        if event.activity.kind=="change" and rewards[event.id] then records[event.id].dirtyClothes=false end
    end
    any=Chores.advance(state,players,cursor,last) or any
    return any,rewards
end
function Chores.minutesLeft(state)
    local l=Chores.ensure(state).laundry
    return l.dueAt and math.ceil(math.max(0,(l.dueAt-Calendar.absoluteHours(state))*60-1e-6)) or 0
end
function Chores.description(state,target)
    local c=Chores.ensure(state);local l=c.laundry
    if target=="laundry" then
        local status=l.phase=="washing" and "Washing: "..Chores.minutesLeft(state).." game min left."
            or l.phase=="ready" and "Cycle finished — unload the washer." or "Washer is empty. Load one bundle to begin a 45-minute cycle."
        return status.." Dirty bundles: "..l.dirty..". Clean bundles: "..l.clean..". Fresh clothes restore hygiene."
    elseif target=="sink" then return "Dirty dishes: "..c.dishes..". Kitchen cleanliness: "..math.floor(100-c.soil.kitchen).."%. Wash dishes or wipe surfaces when needed."
    elseif target=="bath" then return "Bathroom cleanliness: "..math.floor(100-c.soil.bathroom).."%. Cleaning removes dirt left by bathroom use."
    elseif target=="floor" then return "Floor cleanliness: "..math.floor(100-c.soil.living).."%. Trash: "..c.trash..". Sweep here; take trash out beside the entrance." end
end
return Chores
