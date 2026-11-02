-- In-game agreements. Terms are explicit and immutable after signing.
local Contracts = {}
local Hours=require("src.business_hours")
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
    return Contracts.duration(t)>=2.25 and .25 or 0
end
function Contracts.productiveHours(t)
    local duration=Contracts.duration(t)
    return duration-.75-Contracts.paidRestHours(t)
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
-- Terms keep their signed start-day identity. Actual attendance is their
-- intersection with opening hours, including the tail of an overnight shift.
function Contracts.shiftBounds(t,day)
    if not Contracts.hasDay(t.days,Contracts.weekday(day)) then return nil end
    local first=day*24+t.startHour;local last=first+Contracts.duration(t)
    local startAt,endAt
    for d=day,day+1 do
        local a,b=Hours.window(d);a,b=math.max(first,d*24+a),math.min(last,d*24+b)
        if b>a then startAt=startAt or a;endAt=b end
    end
    return startAt,endAt
end
function Contracts.shiftMetrics(t,day)
    local a,b=Contracts.shiftBounds(t,day);local duration=a and b-a or 0
    local meal=duration>=3.75 and .75 or 0;local rest=duration>=2.25 and .25 or 0
    return duration,duration-meal,duration-meal-rest
end
function Contracts.weeklyHours(t)
    local duration,paid,productive=0,0,0
    for day=4,10 do -- A canonical Monday through Sunday; dates do not alter terms.
        local d,p,w=Contracts.shiftMetrics(t,day);duration,paid,productive=duration+d,paid+p,productive+w
    end
    return duration,paid,productive
end
function Contracts.hasOpenHours(t) return Contracts.validTerms(t) and Contracts.weeklyHours(t)>0 end
function Contracts.nextStart(t,now)
    local firstDay=math.max(0,t.startDay or 0,math.floor(now/24)-1)
    for day=firstDay,firstDay+14 do
        local first=Contracts.shiftBounds(t,day)
        if first and first>now then return first,day end
    end
end
function Contracts.nextDay(t,now)
    local _,day=Contracts.nextStart(t,now)
    -- Old weekend-only agreements remain valid but have no attendance. New
    -- offers/changes reject zero open hours before reaching this fallback.
    return day or math.max(0,t.startDay or 0,math.floor(now/24)+7)
end
function Contracts.onShift(t,hours)
    if not t then return false end
    local day=Contracts.shiftDay(t,hours)
    local first,last=Contracts.shiftBounds(t,day)
    return day>=(t.startDay or 0) and first~=nil and hours>=first and hours<last
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
    local _,hours=Contracts.weeklyHours(t)
    return (math.min(40,hours)+math.max(0,hours-40)*1.5)*t.wageCents/100,hours
end
return Contracts
