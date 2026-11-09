-- Customer turnaround promises use weekday hours; calendar bills do not.
local Hours=require("src.business_hours")
local Deadlines={POLICY="shop-week-v1"}
local function finite(n) return type(n)=="number" and n==n and n>=0 and n<=24000000 end
local function weekday(day) return (day+3)%7+1 end -- January 1, 2026 is Thursday.
local function nextWeekday(hours)
    local day=math.floor(hours/24);local w=weekday(day)
    if w>=6 then return (day+8-w)*24 end
    return hours
end
function Deadlines.addWeekdayHours(start,hours)
    local at=nextWeekday(start)
    local remaining=hours
    -- Bound long promises by removing whole weeks, preserving weekday/time.
    local weeks=math.floor(remaining/120)
    at=at+weeks*168;remaining=remaining-weeks*120
    while remaining>0 do
        at=nextWeekday(at)
        local endOfDay=(math.floor(at/24)+1)*24
        local step=math.min(remaining,endOfDay-at)
        at=at+step;remaining=remaining-step
    end
    return nextWeekday(at)
end
local function elapsedWeekdayHours(at)
    local day=math.floor(at/24);local hour=at-day*24
    local weeks=math.floor(day/7);local total=weeks*120
    for i=weeks*7,day-1 do if weekday(i)<=5 then total=total+24 end end
    if weekday(day)<=5 then total=total+hour end
    return total
end
function Deadlines.weekdayHoursBetween(first,last)
    return math.max(0,elapsedWeekdayHours(last)-elapsedWeekdayHours(first))
end
function Deadlines.daysFromText(text)
    local lower=string.lower(tostring(text or ""))
    local days=tonumber(lower:match("(%d+)%s*%-?business%-day"))
        or tonumber(lower:match("(%d+)%s*business day"))
    if not days then
        days=({one=1,two=2,three=3,four=4,five=5,six=6,seven=7,eight=8,nine=9,ten=10})[
            lower:match("(%a+)%s+business day")]
    end
    return days and days>=1 and days<=365 and days==math.floor(days) and days or nil
end
function Deadlines.ensure(job)
    if job.deadline~=nil then
        local old=job.deadline
        if type(old)=="table" and old.policy=="weekdays-v1" and Deadlines.valid(old) then
            old.policy=Deadlines.POLICY;old.dueAtHours=Hours.nextOpen(old.dueAtHours)
        end
        return job.deadline
    end
    local accepted=job.acceptedGameHours or type(job.delivery)=="table" and job.delivery.acceptedGameHours
    if not finite(accepted) then return nil end
    local days=Deadlines.daysFromText(type(job.details)=="table" and job.details.dueDate)
    job.deadline=days and {policy=Deadlines.POLICY,acceptedAtHours=accepted,businessDays=days,
        dueAtHours=Hours.nextOpen(Deadlines.addWeekdayHours(accepted,days*24))} or {policy="flexible"}
    return job.deadline
end
function Deadlines.valid(record)
    if record==nil then return true end -- Older jobs are stamped during normalization.
    if type(record)~="table" then return false end
    if record.policy=="flexible" then return record.dueAtHours==nil
        and record.acceptedAtHours==nil and record.businessDays==nil end
    local known=record.policy==Deadlines.POLICY or record.policy=="weekdays-v1"
    if not (known and finite(record.acceptedAtHours) and finite(record.dueAtHours)
        and type(record.businessDays)=="number" and record.businessDays==math.floor(record.businessDays)
        and record.businessDays>=1 and record.businessDays<=365) then return false end
    local expected=Deadlines.addWeekdayHours(record.acceptedAtHours,record.businessDays*24)
    if record.policy==Deadlines.POLICY then expected=Hours.nextOpen(expected) end
    return math.abs(record.dueAtHours-expected)<.000001
end
function Deadlines.lateByHours(job)
    local record=Deadlines.ensure(job)
    local completed=job.completedAtHours
    if not record or not Deadlines.valid(record) or record.policy=="flexible" or not finite(completed) then return 0 end
    return Hours.between(record.dueAtHours,completed)
end
return Deadlines
