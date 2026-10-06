-- In-game agreements. Terms are explicit and immutable after signing.
local Contracts = {}
local function finite(n) return type(n)=="number" and n==n and math.abs(n)<1e9 end
local function integer(n,low,high) return finite(n) and n==math.floor(n) and n>=low and n<=high end
function Contracts.hasDay(mask, weekday)
    return math.floor(mask / 2^(weekday-1)) % 2 == 1
end
function Contracts.weekday(day) return (3+day)%7+1 end
function Contracts.validTerms(t)
    return type(t)=="table" and t.role=="cutter"
        and integer(t.wageCents,1000,10000) and integer(t.days,1,127)
        and integer(t.startHour,8,14) and integer(t.endHour,12,18)
        and t.endHour-t.startHour>=4 and t.endHour-t.startHour<=10
end
function Contracts.valid(t)
    return Contracts.validTerms(t) and integer(t.revision,1,1000000)
        and integer(t.startDay,0,10000000) and finite(t.signedAtHours) and t.signedAtHours>=0
end
function Contracts.same(a,b)
    if not a or not b then return false end
    for _,key in ipairs({"role","wageCents","days","startHour","endHour"}) do
        if a[key]~=b[key] then return false end
    end
    return true
end
function Contracts.terms(wage,days,startHour,endHour)
    return {role="cutter",wageCents=wage,days=days,startHour=startHour,endHour=endHour}
end
function Contracts.nextDay(t,now)
    local day=math.floor(now/24)
    if now-day*24>=t.startHour then day=day+1 end
    while not Contracts.hasDay(t.days,Contracts.weekday(day)) do day=day+1 end
    return day
end
function Contracts.onShift(t,hours)
    if not t then return false end
    local day=math.floor(hours/24)
    local hour=hours-day*24
    return day>=t.startDay and Contracts.hasDay(t.days,Contracts.weekday(day))
        and hour>=t.startHour and hour<t.endHour
end
function Contracts.summary(t)
    local names={"Mon","Tue","Wed","Thu","Fri","Sat","Sun"}
    local days={}
    for i,name in ipairs(names) do if Contracts.hasDay(t.days,i) then days[#days+1]=name end end
    return string.format("$%.2f/hr | %s | %02d:00-%02d:00",t.wageCents/100,table.concat(days," "),t.startHour,t.endHour)
end
function Contracts.weeklyEstimate(t)
    local days=0
    for i=1,7 do if Contracts.hasDay(t.days,i) then days=days+1 end end
    local duration=t.endHour-t.startHour
    local hours=(duration-(duration>=6 and .5 or 0))*days
    return (math.min(40,hours)+math.max(0,hours-40)*1.5)*t.wageCents/100,hours
end
return Contracts
