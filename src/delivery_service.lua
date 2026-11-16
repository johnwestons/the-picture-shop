local Service={}

Service.SAME_DAY="same_day"
Service.THREE_DAY="three_day"
Service.CUTOFF_HOUR=16
Service.SAME_DAY_ARRIVAL_HOUR=18
Service.NEXT_DAY_ARRIVAL_HOUR=10
Service.THREE_DAY_ARRIVAL_HOUR=10
Service.PAPER_SHIPPING_CENTS={same_day=500,three_day=200}

function Service.normalize(value,fallback)
    if value==nil then value=fallback end
    if value==Service.SAME_DAY or value==Service.THREE_DAY then return value end
    return nil
end

function Service.homeArrival(now,service)
    now=math.max(0,tonumber(now) or 0)
    service=Service.normalize(service,Service.SAME_DAY)
    if not service then return nil end
    local day=math.floor(now/24)
    if service==Service.SAME_DAY then
        local hour=now-day*24
        if hour<Service.CUTOFF_HOUR then
            return day*24+Service.SAME_DAY_ARRIVAL_HOUR
        end
        return (day+1)*24+Service.NEXT_DAY_ARRIVAL_HOUR
    end
    return (day+3)*24+Service.THREE_DAY_ARRIVAL_HOUR
end

function Service.paperArrival(now,service)
    local Hours=require("src.business_hours")
    now=math.max(0,tonumber(now) or 0)
    service=Service.normalize(service,Service.SAME_DAY)
    if not service then return nil end
    local day=math.floor(now/24)
    local expected
    if service==Service.SAME_DAY then
        local hour=now-day*24
        expected=hour<Service.CUTOFF_HOUR
            and day*24+Service.SAME_DAY_ARRIVAL_HOUR
            or (day+1)*24+Service.NEXT_DAY_ARRIVAL_HOUR
    else
        local remaining,target=3,day
        while remaining>0 do
            target=target+1
            local opens,closes=Hours.serviceWindow(target)
            if closes>opens then remaining=remaining-1 end
        end
        expected=target*24+Service.THREE_DAY_ARRIVAL_HOUR
    end
    return Hours.nextService(expected)
end

return Service
