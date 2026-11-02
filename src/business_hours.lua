-- Monday-Thursday overnight work stays available. The weekly closure is
-- Friday 20:00 through Monday 09:00; calendar obligations use their own clock.
local Hours={OPEN_HOUR=9,CLOSE_HOUR=20}
function Hours.weekday(day) return (day+3)%7+1 end
function Hours.window(day)
    local weekday=Hours.weekday(day)
    if weekday>=6 then return 0,0 end
    return weekday==1 and Hours.OPEN_HOUR or 0,weekday==5 and Hours.CLOSE_HOUR or 24
end
function Hours.nextOpen(at)
    local day=math.floor(at/24);local hour=at-day*24;local weekday=Hours.weekday(day)
    if weekday>=6 or weekday==5 and hour>=Hours.CLOSE_HOUR then
        return (day+8-weekday)*24+Hours.OPEN_HOUR
    end
    if weekday==1 and hour<Hours.OPEN_HOUR then return day*24+Hours.OPEN_HOUR end
    return at
end
local function elapsed(at)
    local day=math.floor(at/24);local hour=at-day*24
    local weeks=math.floor(day/7);local total=weeks*(4*24+Hours.CLOSE_HOUR-Hours.OPEN_HOUR)
    for d=weeks*7,day-1 do local a,b=Hours.window(d);total=total+b-a end
    local a,b=Hours.window(day)
    return total+math.max(0,math.min(hour,b)-a)
end
function Hours.between(first,last) return math.max(0,elapsed(last)-elapsed(first)) end
return Hours
