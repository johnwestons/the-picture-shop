-- Planning allowances never move cash. Bills, Credit and Payroll settle their
-- own ledgers; this view reserves earned obligations and budgets whole shifts.
local Calendar=require("src.business_calendar")
local Contracts=require("src.employment_contracts")
local Payroll=require("src.payroll")
local Labor=require("src.employee_labor")
local Jobs=require("src.jobs")
local Fleet=require("src.machine_fleet")
local Finances={}
local function cents(n) return math.floor(n*100+.5+1e-7)/100 end
function Finances.summary(state,proposed,skill)
    local result={weeklyWages=0,cycleReserve=0,capacity=0,pricePerLift=Jobs.PRICE_PER_LIFT,machinePerLift=0}
    local operators={}
    -- A standard cutting lift has 500 customer-supplied sheets and four trims.
    local standard={pallets={{requiredLifts=1,paper={cuts={1,2,3,4}}}}}
    local function budget(w)
        local weekly=Contracts.weeklyEstimate(w.contract)
        local allowance=Labor.estimate(state,standard,w)
        result.weeklyWages=result.weeklyWages+weekly
        result.cycleReserve=result.cycleReserve+weekly*w.contract.payWeeks
        result.pricePerLift=math.max(result.pricePerLift,allowance.minimumCuttingCharge)
        result.machinePerLift=math.max(result.machinePerLift,allowance.machineCost)
        local days=0
        for day=1,7 do if Contracts.hasDay(w.contract.days,day) then days=days+1 end end
        operators[#operators+1]={terms=w.contract,
            perHour=Contracts.productiveHours(w.contract)/Contracts.duration(w.contract)/allowance.productiveHours}
    end
    for _,w in ipairs(state.employment and state.employment.staff or {}) do
        if w.status=="employed" and not w.terminationRequested then budget(w) end
    end
    if proposed and Contracts.validTerms(proposed) then
        budget({id="EMP-PREVIEW",name="Proposed employee",contract=proposed,cutterSkill=skill or 60,focus=80})
    end
    -- Workers sharing the same hours still need separate installed cutters.
    -- Overnight shifts anchor their weekday to the day they start.
    local cutters=#Fleet.installedUnits(state,"polar_115")
    for at=.25,168,.5 do
        local available={}
        for _,operator in ipairs(operators) do
            local t=operator.terms
            local shiftDay=math.floor((at-t.startHour)/24)
            local elapsed=at-(shiftDay*24+t.startHour)
            if Contracts.hasDay(t.days,shiftDay%7+1) and elapsed<Contracts.duration(t) then
                available[#available+1]=operator.perHour
            end
        end
        table.sort(available,function(a,b) return a>b end)
        for i=1,math.min(cutters,#available) do result.capacity=result.capacity+available[i]*.5 end
    end
    local date=state.calendar or Calendar.defaultCalendar()
    local days=Calendar.daysInMonth(date.year,date.month)
    local _,monthly=Calendar.monthlyCharges()
    result.weeklyOperating=cents(monthly*7/days)
    local payments,loanDue=0,0
    for _,loan in ipairs(state.credit and state.credit.loans or {}) do
        if loan.status=="active" or loan.status=="defaulted" then
            payments=payments+loan.monthlyPayment
            loanDue=loanDue+(loan.amountDue or 0)+(loan.feesDue or 0)
        end
    end
    result.weeklyLoans=cents(payments*7/days)
    result.weeklyFixed=cents(result.weeklyWages+result.weeklyOperating+result.weeklyLoans)
    result.earnedUnpaid=state.employment and Payroll.total(state,Calendar.absoluteHours(state),true)/100 or 0
    result.billsDue=(state.bills and state.bills.balance or 0)+loanDue
    result.freeCash=cents((state.money or 0)-result.earnedUnpaid-result.billsDue)
    result.contributionPerLift=result.pricePerLift-result.machinePerLift
    result.breakEvenLifts=math.ceil(result.weeklyFixed/math.max(.01,result.contributionPerLift))
    result.capacity=math.floor(result.capacity)
    return result
end
function Finances.plan(summary,lifts)
    local revenue=lifts*summary.pricePerLift
    local machineReserve=lifts*summary.machinePerLift
    return {revenue=cents(revenue),machineReserve=cents(machineReserve),
        profit=cents(revenue-machineReserve-summary.weeklyFixed),
        withinCapacity=lifts<=summary.capacity}
end
return Finances
