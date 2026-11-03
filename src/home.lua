-- Durable household ownership, rent and host-controlled pay preferences.
local Catalog=require("src.home_catalog")
local Calendar=require("src.business_calendar")
local Town=require("src.commute.town")
local Home={}
local function integer(n,minimum,maximum)
    return type(n)=="number" and n==n and n==math.floor(n) and n>=minimum and n<=maximum
end
local function copy(value)
    if type(value)~="table" then return value end
    local result={};for k,v in pairs(value) do result[k]=copy(v) end;return result
end
local function nextMonth(day)
    local date=Calendar.dateFromTotalDay(day)
    repeat day=day+1 until Calendar.dateFromTotalDay(day).month~=date.month
    return day
end
function Home.new(options,day)
    options=options or {};day=day or 0
    if type(options)~="table" or not integer(day,0,1000000) then return nil,"Invalid home setup." end
    local id=options.apartmentId or "brick-walkup"
    local preset=options.furnishingPreset or "empty"
    if not Catalog.APARTMENTS[id] then return nil,"Choose one of the four apartments." end
    if not Catalog.PRESETS[preset] then return nil,"Choose Empty or Modestly furnished." end
    local town,townError=options.town
    if town==nil then
        if options.townSeed~=nil then town,townError=Town.generate(options.townSeed)
        else town=Town.legacy() end
    end
    if townError then return nil,townError end
    if not Town.valid(town) then return nil,"Invalid town layout. Generate a town again." end
    local due=nextMonth(day)
    if due-day<7 then due=nextMonth(due) end
    local result={version=1,revision=0,apartmentId=id,furnishingPreset=preset,town=Town.copy(town),
        balanceCents=Catalog.ALLOWANCE_CENTS,allowanceGranted=true,payPercent=25,
        weekend=require("src.weekend_flow").new(day*24),
        finance=require("src.household_finances").new(day*24),
        residents=require("src.home_residents").new(),
        shopping=require("src.home_shopping").new(),
        chores=require("src.home_chores").new(day*24),
        dining=require("src.home_dining").new(),
        -- Starter contents are owned immediately; scene setup will place these
        -- through the same inventory-to-instance path used by later deliveries.
        inventory=copy(Catalog.PRESETS[preset].contents),
        lease={monthlyCents=Catalog.APARTMENTS[id].rentCents,startedDay=day,
            firstDueDay=due,nextDueDay=due,chargedCents=0,paidCents=0,invoiceCount=0}}
    require("src.home_furniture").ensure({home=result})
    return result
end
function Home.valid(home)
    if type(home)~="table" or home.version~=1 or not Catalog.APARTMENTS[home.apartmentId]
        or (home.town~=nil and not Town.valid(home.town))
        or not Catalog.PRESETS[home.furnishingPreset] or home.allowanceGranted~=true
        or not integer(home.revision,0,1e12) or not integer(home.balanceCents,0,1e12)
        or not integer(home.payPercent,0,100) or type(home.inventory)~="table"
        or not require("src.weekend_flow").valid(home.weekend)
        or not require("src.household_finances").valid(home.finance)
        or not require("src.home_residents").valid(home.residents)
        or not require('src.commute.trip').valid(home.commute,home)
        or not require("src.home_shopping").valid(home.shopping)
        or not require("src.home_chores").valid(home.chores)
        or not require("src.home_furniture").valid(home.furniture) then return false end
    if home.visit~=nil then
        if type(home.visit)~="table" or home.visit.kind~="outing"
            or home.visit.scene~=nil and home.visit.scene~="home" and home.visit.scene~="warehouse" then return false end
        for key in pairs(home.visit) do if key~="kind" and key~="scene" then return false end end
    end
    local kinds={};for _,preset in pairs(Catalog.PRESETS) do for kind in pairs(preset.contents) do kinds[kind]=true end end
    for kind in pairs(require("src.home_food_catalog").ITEMS) do kinds[kind]=true end
    for kind in pairs(require("src.home_furniture_catalog").ITEMS) do kinds[kind]=true end
    for kind,count in pairs(home.inventory) do
        if not kinds[kind] or not integer(count,0,10000) then return false end
    end
    if not require("src.home_cooking").valid({home=home}) then return false end
    if not require("src.home_dining").valid({home=home}) then return false end
    for _,item in ipairs(home.furniture and home.furniture.items or {}) do
        if item.holderId and not (home.residents and home.residents[item.holderId]) then return false end
    end
    for id,period in pairs(home.chores and home.chores.contributions or {}) do
        if not (home.residents and home.residents[id]) or period>home.weekend.closesAtHours then return false end
    end
    local lease=home.lease
    local valid=type(lease)=="table" and integer(lease.monthlyCents,1,1e9)
        and integer(lease.startedDay,0,1000000) and integer(lease.firstDueDay,lease.startedDay+7,1000032)
        and integer(lease.nextDueDay,lease.firstDueDay,1000032)
        and integer(lease.chargedCents,0,1e12) and integer(lease.paidCents,0,lease.chargedCents)
        and integer(lease.invoiceCount,0,1000000)
        and lease.chargedCents==lease.invoiceCount*lease.monthlyCents
    if not valid then return false end
    local first=Calendar.dateFromTotalDay(lease.firstDueDay)
    local upcoming=Calendar.dateFromTotalDay(lease.nextDueDay)
    local expectedFirst=nextMonth(lease.startedDay)
    if expectedFirst-lease.startedDay<7 then expectedFirst=nextMonth(expectedFirst) end
    return first.day==1 and upcoming.day==1 and lease.firstDueDay==expectedFirst
        and (upcoming.year-first.year)*12+upcoming.month-first.month==lease.invoiceCount
end
function Home.normalize(home,day)
    if home==nil then return Home.new(nil,day) end
    if not Home.valid(home) then return nil,"Invalid household or apartment lease." end
    local result=copy(home);require("src.home_furniture").ensure({home=result})
    require('src.home_residents').ensure({home=result})
    -- Existing shops keep their original geography. Saved layouts are copied,
    -- never regenerated from a seed when generator code changes.
    result.town=Town.copy(home.town or Town.legacy())
    if result.commute then result.commute=require('src.commute.trip').snapshot(result.commute) end
    result.chores=result.chores or require("src.home_chores").new((day or 0)*24)
    result.dining=result.dining or require("src.home_dining").new()
    for _,resident in pairs(result.residents or {}) do
        if resident.ridingGear then resident.ridingGear=require('src.commute.gear').snapshot(resident.ridingGear) end
        if resident.activity and resident.activity.kind=="laundry" then resident.activity=nil end
    end
    return result
end
function Home.amountDue(home) return home.lease.chargedCents-home.lease.paidCents end
function Home.advance(state)
    local home=state.home
    if not home then return false end
    local lease,changed=home.lease,false
    local day=state.calendar.totalDays
    while day>=lease.nextDueDay do
        lease.chargedCents=lease.chargedCents+lease.monthlyCents
        lease.invoiceCount=lease.invoiceCount+1
        lease.nextDueDay=nextMonth(lease.nextDueDay)
        changed=true
    end
    if changed then home.revision=home.revision+1 end
    return changed
end
function Home.setPayPercent(home,percent,expectedRevision)
    if expectedRevision~=home.revision then return false,"Home details changed. Please try again." end
    if not integer(percent,0,100) then return false,"Personal pay must be 0 to 100 percent." end
    if home.payPercent==percent then return false,"Personal pay is already set to that percentage." end
    home.payPercent=percent;home.revision=home.revision+1
    return true,"Personal pay preference saved."
end
function Home.payRent(home,expectedRevision)
    if expectedRevision~=home.revision then return false,"Home details changed. Please try again." end
    local due=Home.amountDue(home)
    if due==0 then return false,"No apartment rent is due." end
    if home.balanceCents<due then return false,"Not enough household money to pay the rent yet." end
    home.balanceCents=home.balanceCents-due
    home.lease.paidCents=home.lease.paidCents+due
    home.revision=home.revision+1
    return true,"Apartment rent paid from your household account."
end
function Home.isIntent(kind) return kind=="home_pay_rent" or kind=="home_set_pay" or kind=="home_set_reserve"
    or kind=="home_order_food" or kind=="home_order_furniture" or kind=="home_set_food_limit" end
function Home.ownerOnly(kind) return Home.isIntent(kind) and kind~="home_order_food" and kind~="home_order_furniture" end
function Home.command(state,intent,player)
    player=player or {id=1}
    if intent.kind=="home_order_food" or intent.kind=="home_order_furniture" then return require("src.home_shopping").order(state,player,intent) end
    if intent.kind=="home_set_food_limit" then return require("src.home_shopping").setLimit(state,player,intent) end
    if intent.kind=="home_pay_rent" then return Home.payRent(state.home,intent.expectedRevision) end
    if intent.kind=="home_set_pay" then return Home.setPayPercent(state.home,intent.percent,intent.expectedRevision) end
    if intent.kind=="home_set_reserve" then
        if intent.expectedRevision~=state.home.revision then return false,"Home details changed. Please try again." end
        if not integer(intent.reserveCents,0,100000000) then return false,"Choose a cash reserve from $0 to $1,000,000." end
        local finance=require("src.household_finances").ensure(state)
        if finance.reserveCents==intent.reserveCents then return false,"That cash reserve is already set." end
        finance.reserveCents=intent.reserveCents;state.home.revision=state.home.revision+1
        return true,"Business cash reserve saved."
    end
    return false,"Unknown household action."
end
return Home
