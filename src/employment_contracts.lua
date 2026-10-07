-- In-game agreements. Terms are explicit and immutable after signing.
local Contracts = {}
local function finite(n) return type(n)=="number" and n==n and math.abs(n)<1e9 end
local function integer(n,low,high) return finite(n) and n==math.floor(n) and n>=low and n<=high end
local shiftPreferences={day=true,night=true,flexible=true}
function Contracts.validShiftPreference(value)
    return type(value)=="string" and shiftPreferences[value]==true
end
function Contracts.shiftPreferenceLabel(value)
    if value=="day" then return "Day shifts only" end
    if value=="night" then return "Night shifts only" end
    return "Flexible (day or night)"
end
function Contracts.shiftPreferenceDescription(value)
    if value=="day" then return "day shifts only" end
    if value=="night" then return "night shifts only" end
    return "day or night shifts"
end
function Contracts.preferenceAllows(value,startHour)
    if value==nil or value=="flexible" then return true end
    if not shiftPreferences[value] or not integer(startHour,0,23) then return false end
    local shift=(startHour>=6 and startHour<18) and "day" or "night"
    return value==shift
end
function Contracts.hasDay(mask, weekday)
    return math.floor(mask / 2^(weekday-1)) % 2 == 1
end
function Contracts.weekday(day) return (3+day)%7+1 end
function Contracts.duration(t) return (t.endHour-t.startHour)%24 end
function Contracts.paidRestHours(t)
    local rests=0
    for at=2,Contracts.duration(t)-.001,4 do rests=rests+.25 end
    return rests
end
function Contracts.productiveHours(t)
    local duration=Contracts.duration(t)
    return duration-(duration>=6 and .5 or 0)-Contracts.paidRestHours(t)
end
function Contracts.validTerms(t)
    return type(t)=="table" and t.role=="cutter"
        and integer(t.wageCents,1000,10000) and integer(t.days,1,127)
        and integer(t.startHour,0,23) and integer(t.endHour,0,23)
        and integer(t.payWeeks,1,4)
        and Contracts.duration(t)>=4 and Contracts.duration(t)<=12
end
function Contracts.valid(t)
    return Contracts.validTerms(t) and integer(t.revision,1,1000000)
        and integer(t.startDay,0,10000000) and finite(t.signedAtHours) and t.signedAtHours>=0
end
function Contracts.same(a,b)
    if not a or not b then return false end
    for _,key in ipairs({"role","wageCents","days","startHour","endHour","payWeeks"}) do
        if a[key]~=b[key] then return false end
    end
    return true
end
function Contracts.terms(wage,days,startHour,endHour,payWeeks)
    return {role="cutter",wageCents=wage,days=days,startHour=startHour,endHour=endHour,payWeeks=payWeeks or 1}
end
function Contracts.nextDay(t,now)
    local day=math.floor(now/24)
    if now-day*24>=t.startHour then day=day+1 end
    while not Contracts.hasDay(t.days,Contracts.weekday(day)) do day=day+1 end
    return day
end
function Contracts.onShift(t,hours)
    if not t then return false end
    local day=Contracts.shiftDay(t,hours)
    local startAt=day*24+t.startHour
    return day>=t.startDay and Contracts.hasDay(t.days,Contracts.weekday(day))
        and hours>=startAt and hours<startAt+Contracts.duration(t)
end
function Contracts.shiftDay(t,hours) return math.floor((hours-t.startHour)/24) end
function Contracts.formatHour(hour,twelveHour)
    if twelveHour then
        return string.format("%d:00 %s",(hour-1)%12+1,hour<12 and "AM" or "PM")
    end
    return string.format("%02d:00",hour)
end
function Contracts.summary(t,twelveHour)
    local names={"Mon","Tue","Wed","Thu","Fri","Sat","Sun"}
    local days={}
    for i,name in ipairs(names) do if Contracts.hasDay(t.days,i) then days[#days+1]=name end end
    return string.format("$%.2f/hr | %s | %s-%s%s | Pay %dw",t.wageCents/100,table.concat(days," "),
        Contracts.formatHour(t.startHour,twelveHour),Contracts.formatHour(t.endHour,twelveHour),
        t.endHour<t.startHour and " (+1 day)" or "",t.payWeeks)
end
function Contracts.paydayForWeek(t,week)
    local anchor=t.startDay-(Contracts.weekday(t.startDay)-1)
    local cycle=math.floor((week-anchor)/(7*t.payWeeks))
    return (anchor+(cycle+1)*7*t.payWeeks)*24+9
end
function Contracts.weeklyEstimate(t)
    local days=0
    for i=1,7 do if Contracts.hasDay(t.days,i) then days=days+1 end end
    local duration=Contracts.duration(t)
    local hours=(duration-(duration>=6 and .5 or 0))*days
    return (math.min(40,hours)+math.max(0,hours-40)*1.5)*t.wageCents/100,hours
end
return Contracts
