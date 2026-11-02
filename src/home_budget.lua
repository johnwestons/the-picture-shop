-- Read-only rent planning. A previous payout is evidence, never promised income.
local Calendar=require("src.business_calendar")
local Home=require("src.home")
local Budget={}
function Budget.summary(state)
    local h=state.home;local now=Calendar.absoluteHours(state)
    local due=Home.amountDue(h);local upcoming=h.lease.nextDueDay*24
    local f=h.finance;local history=f and f.history or {};local last=history[#history]
    local nextClose=require("src.weekend_flow").new(now).closesAtHours
    -- A delayed shutdown contributes one pending payout, even if several
    -- Fridays passed while closing. Those missed dates are not extra paydays.
    local pending=h.weekend.phase=="closing" and h.weekend.closesAtHours<now-1e-7
        and (not f or f.lastSettledClose<h.weekend.closesAtHours)
    while nextClose<now-1e-7 or f and nextClose<=f.lastSettledClose do nextClose=nextClose+168 end
    local paydays=0
    if now<upcoming and nextClose<upcoming then paydays=math.ceil((upcoming-nextClose)/168) end
    if pending and now<upcoming then paydays=paydays+1 end
    local shortfall=math.max(0,due+h.lease.monthlyCents-h.balanceCents)
    local reason
    if last then
        if last.eligibleCents==0 then reason="no_earnings"
        elseif last.percent==0 then reason="zero_rate"
        elseif last.paidCents<last.requestedCents then reason="reserves" end
    end
    return {dueCents=due,dueShortfallCents=math.max(0,due-h.balanceCents),
        rentShortfallCents=shortfall,paydays=paydays,
        perPaydayCents=paydays>0 and math.ceil(shortfall/paydays) or shortfall,
        lastPayCents=last and last.paidCents,lastPayReason=reason,weeklyRentCents=math.ceil(h.lease.monthlyCents*12/52)}
end
function Budget.lines(state)
    local b=Budget.summary(state);local lines={};local warning=false
    if b.dueShortfallCents>0 then
        lines[1]=string.format("Rent due now: short $%.2f",b.dueShortfallCents/100);warning=true
    elseif b.rentShortfallCents==0 then lines[1]="Rent covered through next due date."
    elseif b.paydays==0 then
        lines[1]=string.format("Before next payday: need $%.2f",b.rentShortfallCents/100);warning=true
    else lines[1]=string.format("Save $%.2f each Friday (%d left).",b.perPaydayCents/100,b.paydays) end
    lines[2]=b.lastPayCents and string.format("Last personal pay: $%.2f",b.lastPayCents/100) or "No personal pay received yet."
    if b.lastPayCents and b.lastPayCents<b.perPaydayCents and b.rentShortfallCents>0 then
        local reasons={no_earnings="Last pay: no profit after costs/losses.",
            zero_rate="Last payout used a 0% pay rate.",reserves="Last pay limited by business reserves."}
        lines[3]=reasons[b.lastPayReason] or "Review pay / earnings; allow for food.";warning=true
    else lines[3]="Rent only; food and furniture are extra." end
    return lines,warning
end
return Budget
