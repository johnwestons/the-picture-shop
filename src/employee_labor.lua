-- Labor allowances are estimates; the payroll ledger owns every cash payment.
local Contracts=require("src.employment_contracts")
local Config=require("src.config")
local Press=require("src.press_economics")
local Labor={}
local function finite(n) return type(n)=="number" and n==n and n>=0 and n<1e12 end
local function rounded(n) return math.floor(n*100+.5+1e-7)/100 end
function Labor.defaultTotals() return {version=1,jobHours=0,jobCents=0,shopHours=0,shopCents=0} end
function Labor.validTotals(t)
    return type(t)=="table" and t.version==1 and finite(t.jobHours) and finite(t.jobCents)
        and finite(t.shopHours) and finite(t.shopCents)
end
function Labor.fromWeeks(weeks)
    if type(weeks)~="table" then return nil end
    local t=Labor.defaultTotals()
    for _,r in pairs(weeks) do
        if type(r)~="table" or not finite(r.paidHours) or not finite(r.earnedCents) then return nil end
        t.shopHours=t.shopHours+r.paidHours;t.shopCents=t.shopCents+r.earnedCents
    end
    return t
end
function Labor.validJob(t)
    return t==nil or type(t)=="table" and t.version==1 and finite(t.paidHours) and finite(t.wageCents)
end
function Labor.record(state,w,hours,cents)
    if cents<=0 then return end
    w.laborTotals=w.laborTotals or Labor.fromWeeks(w.weeks) or Labor.defaultTotals()
    local job
    if state and w.assignment and w.reserved and (w.phase=="working" or w.phase=="walking") then
        for _,candidate in ipairs(state.jobs.active or {}) do
            if candidate.id==w.assignment.jobId then job=candidate;break end
        end
    end
    local t=w.laborTotals
    if job then
        job.labor=job.labor or {version=1,paidHours=0,wageCents=0}
        job.labor.paidHours=job.labor.paidHours+hours;job.labor.wageCents=job.labor.wageCents+cents
        t.jobHours=t.jobHours+hours;t.jobCents=t.jobCents+cents
    else t.shopHours=t.shopHours+hours;t.shopCents=t.shopCents+cents end
end
function Labor.actionDelay(w,focus)
    return .32+(100-w.cutterSkill)/100*.70+(100-(focus or w.focus))/100*.40
end
local function qualified(w,job)
    return w.status=="employed" and not w.terminationRequested
        and not (job.difficulty=="hard" and w.cutterSkill<80 or job.difficulty=="medium" and w.cutterSkill<50)
end
local function estimate(job,w)
    local cutter=require("src.machine").forId(nil)
    local seconds=0
    for _,p in ipairs(job.pallets or {}) do
        if not p.replacementFor then
            local cuts=#(p.paper and p.paper.cuts or {})
            local lifts=p.requiredLifts or 1
            -- Program setup/handling and real blade/transfer times, plus a
            -- short approach allowance. Actual payroll records the real time.
            seconds=seconds+lifts*((cuts*6+2)*Labor.actionDelay(w,80)
                +cuts*(cutter.cycleTime+cutter.transferTime)+2*cutter.transferTime)
        end
    end
    local hours=seconds*24/(Config.businessCalendar.secondsPerDay or 300)+.25
    local t=w.contract;local days=0
    for day=1,7 do if Contracts.hasDay(t.days,day) then days=days+1 end end
    local duration=t.endHour-t.startHour
    local productive=(duration-(duration>=6 and .5 or 0)-(duration>6 and .5 or .25))*days
    local weekly=Contracts.weeklyEstimate(t)
    local rate=weekly/math.max(.25,productive)
    local laborCost=hours*rate
    local overhead=hours*Press.assumptions.machineOverheadPerHour
    local minimum=math.ceil((laborCost+overhead)/(1-Press.assumptions.targetGrossMargin)/5)*5
    return {version=1,employeeId=w.id,employeeName=w.name,wagePerHour=t.wageCents/100,
        budgetRate=rounded(rate),productiveHours=rounded(hours),laborCost=rounded(laborCost),
        machineCost=rounded(overhead),minimumCuttingCharge=minimum}
end
function Labor.price(state,job,servicePrice)
    local budget
    for _,w in ipairs(state.employment and state.employment.staff or {}) do
        if qualified(w,job) then
            local candidate=estimate(job,w)
            if not budget or candidate.minimumCuttingCharge>budget.minimumCuttingCharge then budget=candidate end
        end
    end
    if not budget then return servicePrice,nil end
    local baseCut=job.quote.totalLifts*require("src.jobs").PRICE_PER_LIFT
    local press=job.quote.pressBudget and job.quote.pressBudget.recommendedCharge or 0
    local multiplier=servicePrice/math.max(1,baseCut+press)
    local extra=math.max(0,budget.minimumCuttingCharge-baseCut*multiplier)
    local recommended=math.floor(servicePrice+extra+.5)
    budget.servicePrice=servicePrice;budget.recommendedPrice=recommended
    return recommended,budget
end
function Labor.validBudget(t)
    if t==nil then return true end
    if type(t)~="table" or t.version~=1 or type(t.employeeId)~="string" or #t.employeeId>64
        or not t.employeeId:match("^EMP%-%d+$") or type(t.employeeName)~="string" or #t.employeeName>600 then return false end
    for _,key in ipairs({"wagePerHour","budgetRate","productiveHours","laborCost","machineCost",
        "minimumCuttingCharge","servicePrice","recommendedPrice"}) do if not finite(t[key]) then return false end end
    return t.recommendedPrice>=t.servicePrice
end
return Labor
