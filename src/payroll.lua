local Contracts=require("src.employment_contracts")
local Inbox=require("src.inbox")
local Labor=require("src.employee_labor")
local Payroll={}
local function rounded(n) return math.floor(n+0.5+1e-7) end
local function weekFor(day) return day-(Contracts.weekday(day)-1) end
local function bucket(worker,day)
    local week=weekFor(day)
    for _,row in ipairs(worker.weeks) do if row.week==week then return row end end
    local row={week=week,dueAtHours=(week+7)*24+9,paidHours=0,earnedCents=0,paidCents=0,notified=false}
    worker.weeks[#worker.weeks+1]=row
    -- Keep settled history bounded while retaining every unpaid obligation.
    if #worker.weeks>54 and worker.weeks[1].paidCents>=rounded(worker.weeks[1].earnedCents) then
        table.remove(worker.weeks,1)
    end
    return row
end
function Payroll.accrue(worker,startAt,endAt,finishingCycle,state)
    if not worker.visible or not worker.clockedIn or worker.phase=="hidden"
        or (worker.phase=="break" and worker.breakKind=="meal") then return 0 end
    local t=worker.contract
    local accrued,paidHours=0,0
    worker.laborTotals=worker.laborTotals or Labor.fromWeeks(worker.weeks) or Labor.defaultTotals()
    -- Clip shifts and weeks. Time spent finishing an already-running safe
    -- machine cycle after the scheduled end remains paid work.
    local first,last=math.floor(startAt/24),math.floor((endAt-1e-9)/24)
    for day=first,last do
        if finishingCycle or day>=t.startDay and Contracts.hasDay(t.days,Contracts.weekday(day)) then
            local a=math.max(startAt,day*24+(finishingCycle and 0 or t.startHour))
            local b=math.min(endAt,day*24+(finishingCycle and 24 or t.endHour))
            if b>a then
                local row=bucket(worker,day)
                local hours=b-a
                local regular=math.min(hours,math.max(0,40-row.paidHours))
                local cents=(regular+(hours-regular)*1.5)*t.wageCents
                row.paidHours=row.paidHours+hours
                row.earnedCents=row.earnedCents+cents
                accrued=accrued+cents
                paidHours=paidHours+hours
            end
        end
    end
    Labor.record(state,worker,paidHours,accrued)
    return accrued,paidHours
end
function Payroll.balance(worker,now,includeAccrued)
    local cents=0
    for _,row in ipairs(worker.weeks) do
        if includeAccrued or row.dueAtHours<=now then cents=cents+math.max(0,rounded(row.earnedCents)-row.paidCents) end
    end
    return cents
end
function Payroll.total(state,now,includeAccrued)
    local cents=0
    for _,worker in ipairs(state.employment.staff) do cents=cents+Payroll.balance(worker,now,includeAccrued) end
    return cents
end
function Payroll.pay(state,now,automatic)
    local cash=math.max(0,math.floor((state.money or 0)*100+1e-7))
    local spent=0
    for _,worker in ipairs(state.employment.staff) do
        for _,row in ipairs(worker.weeks) do
            local owed=math.max(0,rounded(row.earnedCents)-row.paidCents)
            if row.dueAtHours<=now and owed>0 then
                local paid=math.min(cash,owed)
                row.paidCents=row.paidCents+paid;cash=cash-paid;spent=spent+paid
                if not row.notified then
                    Inbox.addNotice(state,{id=worker.id.."-PAY-"..row.week,sender="Shop Payroll",
                        subject=paid==owed and "Weekly wages paid: "..worker.name or "Unpaid wages: "..worker.name,
                        body=string.format("Week's pay: $%.2f. Paid: $%.2f. Remaining wages stay owed. Payroll is due Monday at 09:00; overdue wages pause new work.",
                            rounded(row.earnedCents)/100,row.paidCents/100),noticeKind="payroll"},0)
                    row.notified=true
                end
            end
        end
    end
    if spent>0 then state.money=math.max(0,state.money-spent/100) end
    if not automatic then
        return spent>0,spent>0 and string.format("Paid $%.2f in wages.",spent/100)
            or "No cash is available, or no wages are due yet."
    end
    return spent>0
end
function Payroll.overdueSince(worker,now)
    local oldest
    for _,row in ipairs(worker.weeks) do
        if row.dueAtHours<=now and rounded(row.earnedCents)>row.paidCents then
            oldest=not oldest and row.dueAtHours or math.min(oldest,row.dueAtHours)
        end
    end
    return oldest
end
return Payroll
