-- Cash-backed owner draws. Stock purchases carry cost until consumed; bill and
-- wage payments never book a second expense. All amounts below are cents.
local Calendar=require("src.business_calendar")
local Finance={}
local categories={"revenue","materials","wages","operating","refunds","interest","services"}
local function copy(value)
    if type(value)~="table" then return value end
    local result={};for k,v in pairs(value) do result[k]=copy(v) end;return result
end
local function number(n,low,high) return type(n)=="number" and n==n and n>=low and n<=high end
local function integer(n,low,high) return number(n,low,high) and n==math.floor(n) end
local function zeroes() local t={};for _,key in ipairs(categories) do t[key]=0 end;return t end
local function cents(dollars) return math.floor(dollars*100+.5+1e-7) end
function Finance.new(at)
    return {version=1,totals=zeroes(),checkpoint=zeroes(),fractions=zeroes(),stock={},stockSeeded=false,
        lastAccruedHours=at or 0,lastSettledClose=-1,lossCarryCents=0,reserveCents=20000,history={}}
end
function Finance.valid(f)
    if f==nil then return true end -- Existing households start accounting now.
    if type(f)~="table" or f.version~=1 or type(f.stockSeeded)~="boolean"
        or not number(f.lastAccruedHours,0,24000024) or not number(f.lastSettledClose,-1,24000024)
        or not integer(f.lossCarryCents,-1e12,0) or not integer(f.reserveCents,0,100000000)
        or type(f.stock)~="table" or type(f.history)~="table" or #f.history>52 then return false end
    for _,name in ipairs({"totals","checkpoint","fractions"}) do if type(f[name])~="table" then return false end end
    for _,key in ipairs(categories) do
        if not integer(f.totals[key],0,1e12) or not integer(f.checkpoint[key],0,f.totals[key])
            or not number(f.fractions[key],0,.9999999999999999) then return false end
    end
    local count=0
    for key,pool in pairs(f.stock) do
        count=count+1
        if count>32 or type(key)~="string" or #key>48 or not key:match("^[a-z_]+$")
            or type(pool)~="table" or not number(pool.quantity,0,1e12)
            or not integer(pool.basisCents,0,1e12) or pool.quantity==0 and pool.basisCents~=0 then return false end
    end
    local previous=-1
    for index,row in pairs(f.history) do
        if not integer(index,1,#f.history) or type(row)~="table" then return false end
    end
    for _,row in ipairs(f.history) do
        if not number(row.closeHours,0,f.lastSettledClose) or row.closeHours<=previous
            or not integer(row.percent,0,100) or not integer(row.netCents,-1e12,1e12)
            or not integer(row.lossBeforeCents,-1e12,0) or not integer(row.eligibleCents,0,1e12)
            or row.eligibleCents~=math.max(0,row.netCents+row.lossBeforeCents)
            or not integer(row.requestedCents,0,1e12)
            or row.requestedCents~=math.floor(row.eligibleCents*row.percent/100)
            or not integer(row.reserveCents,0,1e12) or not integer(row.availableCents,0,1e12)
            or row.paidCents~=math.min(row.requestedCents,row.availableCents)
            or type(row.costs)~="table" then return false end
        local net=0
        for _,key in ipairs(categories) do
            if not integer(row.costs[key],0,1e12) then return false end
            net=net+(key=="revenue" and 1 or -1)*row.costs[key]
        end
        if net~=row.netCents then return false end
        previous=row.closeHours
    end
    if not f.stockSeeded and next(f.stock)~=nil then return false end
    local last=f.history[#f.history]
    return not last and f.lastSettledClose==-1 and f.lossCarryCents==0
        or last~=nil and previous==f.lastSettledClose and f.lossCarryCents==math.min(0,last.netCents+last.lossBeforeCents)
end
local function seedStock(state,f)
    local delivered={}
    local function add(id,quantity,basis)
        if quantity<=0 or id=="pallet_jack" then return end
        local pool=f.stock[id] or {quantity=0,basisCents=0};f.stock[id]=pool
        pool.quantity=pool.quantity+quantity;pool.basisCents=pool.basisCents+basis
    end
    for _,order in ipairs(state.procurement and state.procurement.orders or {}) do
        local original=0
        for _,p in ipairs(order.pallets or {}) do original=original+(p.quantity or 0) end
        for _,p in ipairs(order.pallets or {}) do
            local left=p.location=="none" and 0 or (p.remainingQuantity or p.quantity or 0)
            if original>0 and p.productId then
                add(p.productId,left,cents((order.price or 0)*left/original))
                if p.location~="awaiting_delivery" then delivered[p.productId]=(delivered[p.productId] or 0)+left end
            end
        end
    end
    local inventory=state.inventory or {};local stock=inventory.stock or {}
    for _,category in ipairs(require("src.procurement").categories) do
        for _,item in ipairs(category.items) do
            local quantity=stock[item.id] or 0
            if item.id=="stretch_film" then quantity=inventory.plasticWrapRolls or 0 end
            if item.id=="plate_room_kit" then
                quantity=math.min(stock.raw_press_plates or 0,stock.negative_film or 0,
                    stock.plate_adhesive or 0,stock.plate_chemistry or 0)
            end
            add(item.id,math.max(0,quantity-(delivered[item.id] or 0)),0)
        end
    end
    add("abstract_paper",inventory.paper or 0,0)
    local film=f.stock.stretch_film;local uses=inventory.plasticWrapUses or 0
    if film and film.quantity>0 and uses>0 and uses<11 then
        local used=math.min(film.quantity,(11-uses)/11)
        film.basisCents=film.basisCents-math.floor(film.basisCents*used/film.quantity)
        film.quantity=film.quantity-used
    end
    f.stockSeeded=true
end
function Finance.ensure(state)
    if not state or not state.home then return nil end
    local f=state.home.finance
    if not f then f=Finance.new(Calendar.absoluteHours(state));state.home.finance=f end
    if not f.stockSeeded then seedStock(state,f) end
    return f
end
function Finance.record(state,category,amount)
    local f=Finance.ensure(state)
    if not f or amount<=0 then return end
    assert(f.totals[category],"Unknown household accounting category")
    local exact=amount+f.fractions[category]
    local whole=math.floor(exact+1e-8)
    f.fractions[category]=math.max(0,exact-whole)
    f.totals[category]=f.totals[category]+whole
end
function Finance.purchase(state,id,quantity,costCents)
    local f=Finance.ensure(state)
    if not f or id=="pallet_jack" then return end -- Capital equipment, not supplies.
    local pool=f.stock[id] or {quantity=0,basisCents=0};f.stock[id]=pool
    pool.quantity=pool.quantity+quantity;pool.basisCents=pool.basisCents+costCents
end
function Finance.consume(state,id,quantity)
    local f=Finance.ensure(state);local pool=f and f.stock[id]
    if not pool or quantity<=0 or pool.quantity<=0 then return end
    local used=math.min(quantity,pool.quantity)
    if pool.quantity-used<1e-7 then used=pool.quantity end
    local cost=used==pool.quantity and pool.basisCents or math.floor(pool.basisCents*used/pool.quantity)
    pool.quantity=pool.quantity-used;pool.basisCents=pool.basisCents-cost
    Finance.record(state,"materials",cost)
end
-- Multi-product withdrawals may roll back after a later stock allocation fails.
function Finance.stockCheckpoint(state)
    local f=Finance.ensure(state)
    return f and {stock=copy(f.stock),materials=f.totals.materials,fraction=f.fractions.materials}
end
function Finance.restoreStock(state,before)
    if not before then return end
    local f=state.home.finance
    f.stock=before.stock;f.totals.materials=before.materials;f.fractions.materials=before.fraction
end
function Finance.accrue(state)
    local f=Finance.ensure(state);if not f then return end
    local at,now=f.lastAccruedHours,Calendar.absoluteHours(state)
    if now<=at then return end
    local _,monthly=Calendar.monthlyCharges()
    local amount=0
    while at<now do
        local date=Calendar.dateFromTotalDay(math.floor(at/24))
        local days=Calendar.daysInMonth(date.year,date.month)
        local boundary=(date.totalDays+days-date.day+1)*24
        local ending=math.min(now,boundary)
        amount=amount+monthly*100*(ending-at)/(days*24)
        at=ending
    end
    Finance.record(state,"operating",amount);f.lastAccruedHours=now
end
function Finance.reserves(state)
    local f=state.home.finance or Finance.new(Calendar.absoluteHours(state))
    local now=Calendar.absoluteHours(state);local date=Calendar.dateFromTotalDay(math.floor(now/24))
    local wages=state.employment and require("src.payroll").total(state,now,true) or 0
    local result={buffer=f.reserveCents,unpaid=cents(state.bills and state.bills.balance or 0)+math.ceil(wages),payroll=0,operating=0,loans=0}
    -- A conservative next-week payroll reserve; forecasts never enter profit.
    local Contracts=require("src.employment_contracts")
    for _,w in ipairs(state.employment and state.employment.staff or {}) do
        if w.status=="employed" and not w.terminationRequested then
            result.payroll=result.payroll+cents(Contracts.weeklyEstimate(w.contract))
        end
    end
    local _,monthly=Calendar.monthlyCharges()
    local days=Calendar.daysInMonth(date.year,date.month)
    result.operating=math.ceil(monthly*100*math.min(1,(date.day-1+now%24/24+7)/days))
    for _,loan in ipairs(state.credit and state.credit.loans or {}) do
        if loan.status=="active" or loan.status=="defaulted" then
            result.unpaid=result.unpaid+cents((loan.amountDue or 0)+(loan.feesDue or 0))
            if loan.nextDueDay*24<=now+168 then
                local interest=math.floor(loan.balance*loan.aprBasisPoints/120000+.5)
                local outstanding=math.max(0,loan.balance+interest-(loan.amountDue or 0))
                local installment=loan.scheduledCount+1>=loan.termMonths and outstanding or math.min(outstanding,loan.monthlyPayment)
                result.loans=result.loans+cents(installment)
            end
        end
    end
    result.total=result.buffer+result.unpaid+result.payroll+result.operating+result.loans
    return result
end
function Finance.preview(state)
    local f=state.home.finance or Finance.new(Calendar.absoluteHours(state))
    local result={costs={},netCents=0,lossBeforeCents=f.lossCarryCents,percent=state.home.payPercent}
    for _,key in ipairs(categories) do
        local amount=f.totals[key]-f.checkpoint[key];result.costs[key]=amount
        result.netCents=result.netCents+(key=="revenue" and 1 or -1)*amount
    end
    result.eligibleCents=math.max(0,result.netCents+f.lossCarryCents)
    result.requestedCents=math.floor(result.eligibleCents*result.percent/100)
    result.reserves=Finance.reserves(state);result.reserveCents=result.reserves.total
    result.availableCents=math.max(0,math.floor((state.money or 0)*100+1e-7)-result.reserveCents)
    result.paidCents=math.min(result.requestedCents,result.availableCents)
    return result
end
function Finance.settle(state,closeHours)
    local f=Finance.ensure(state)
    if not f or closeHours<=f.lastSettledClose then return false end
    Finance.accrue(state)
    local row=Finance.preview(state);row.closeHours=closeHours;row.reserves=nil
    -- No yield between these mutations: the normal save/snapshot captures both
    -- accounts, the source checkpoint and the settlement receipt together.
    state.money=state.money-row.paidCents/100
    state.home.balanceCents=state.home.balanceCents+row.paidCents
    f.lossCarryCents=math.min(0,row.netCents+f.lossCarryCents)
    f.checkpoint=copy(f.totals);f.lastSettledClose=closeHours
    f.history[#f.history+1]=row;if #f.history>52 then table.remove(f.history,1) end
    state.home.revision=state.home.revision+1
    require("src.inbox").addNotice(state,{id="HOME-PAY-"..closeHours,sender="My Home Accounts",noticeKind="household_pay",
        subject=string.format("Friday personal pay: $%.2f",row.paidCents/100),total=row.paidCents/100,
        body=string.format("This period collected $%.2f in sales and earned $%.2f after costs. Prior losses: $%.2f. "..
            "Your %d%% rate requested $%.2f. After protecting $%.2f for business obligations and reserves, $%.2f "..
            "moved to your household account. Retained earnings stay in the shop and are not owed as future pay. "..
            "Review earnings, reserves and pay history in My Home.",row.costs.revenue/100,row.netCents/100,
            row.lossBeforeCents<0 and -row.lossBeforeCents/100 or 0,row.percent,row.requestedCents/100,row.reserveCents/100,row.paidCents/100)})
    return true,row
end
return Finance
