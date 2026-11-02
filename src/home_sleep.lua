local Calendar=require("src.business_calendar")
local Sleep={SPEED=32}
Sleep.ACTIONS={
    sleepmat={label="Sleep on guest mat (8 hours / shared fast sleep)",minutes=480,targets={},furnitureKind="guest_mat",gain={energy=256},sleep=true},
    workmat={label="Guest mat: sleep until Monday 07:00",minutes=660,targets={},furnitureKind="guest_mat",gain={energy=352},sleep=true,untilWork=true},
    sleepfloor={label="Sleep on floor (8 hours / shared fast sleep)",minutes=480,targets={floor=true},gain={energy=176},sleep=true},
    sleepbed={label="Sleep in bed (8 hours / shared fast sleep)",minutes=480,targets={},furnitureKind="bed",gain={energy=520},sleep=true},
    sleepcouch={label="Sleep on couch (8 hours / shared fast sleep)",minutes=480,targets={},furnitureKind="couch",gain={energy=336},sleep=true},
    workfloor={label="Floor: sleep until Monday 07:00",minutes=660,targets={floor=true},gain={energy=242},sleep=true,untilWork=true},
    workbed={label="Bed: sleep until Monday 07:00",minutes=660,targets={},furnitureKind="bed",gain={energy=715},sleep=true,untilWork=true},
    workcouch={label="Couch: sleep until Monday 07:00",minutes=660,targets={},furnitureKind="couch",gain={energy=462},sleep=true,untilWork=true},
}
local function finite(n) return type(n)=="number" and n==n and n>=0 and n<=24000024 end
function Sleep.validResident(r) return (r.alarmAt==nil or finite(r.alarmAt)) and (r.lastAlarmAt==nil or finite(r.lastAlarmAt)) end
function Sleep.decode(command)
    if command=="alarm:off" or command=="alarm:work" then return command:sub(7) end
    local hour=type(command)=="string" and command:match("^alarm:(%d+)$")
    if hour and tostring(tonumber(hour))==hour and tonumber(hour)<=23 then return tonumber(hour) end
end
function Sleep.command(state,player,command)
    local choice=Sleep.decode(command);local r=require("src.home_residents").get(state,player)
    if choice==nil or not r or player.sceneId~="home" or state.home.weekend.phase~="home" then return false,"unavailable","Set your alarm while at home." end
    local now=Calendar.absoluteHours(state);local at
    if choice=="work" then
        at=state.home.weekend.opensAtHours-2
        if at<=now then return false,"past_alarm","Monday's 07:00 wake time has passed. Return opens at 07:30, before the 08:00 employee shift." end
    elseif type(choice)=="number" then
        at=math.floor(now/24)*24+choice;if at<=now+1e-7 then at=at+24 end
    end
    if r.alarmAt==at then return false,"unchanged","Your alarm is already set that way." end
    r.alarmAt=at;r.revision=r.revision+1
    return true,"changed",at and "Your alarm: "..Calendar.dateTimeTextAtHours(at)..". Other residents keep their own alarms." or "Your alarm is off. Monday's household wake reminder still applies."
end
function Sleep.prepare(state,kind)
    if Sleep.ACTIONS[kind] and Sleep.ACTIONS[kind].untilWork and Calendar.absoluteHours(state)<state.home.weekend.opensAtHours-13 then
        return false,"Sleep until Monday morning is available from Sunday at 20:00."
    end
    if Sleep.ACTIONS[kind] and Calendar.absoluteHours(state)>=state.home.weekend.opensAtHours-2 then
        return false,"Monday morning has arrived. Get ready for work; short naps are still available."
    end
    return true
end
function Sleep.endAt(state,resident,a)
    if not Sleep.ACTIONS[a.kind] then return a.endsAt end
    local at=math.min(a.endsAt,state.home.weekend.opensAtHours-2)
    if resident.alarmAt then at=math.min(at,resident.alarmAt) end
    return math.max(a.startedAt,at)
end
function Sleep.fire(state,r,player,now)
    if player and r.alarmAt and now+1e-7>=r.alarmAt then
        r.lastAlarmAt=r.alarmAt;r.alarmAt=nil;r.revision=r.revision+1
        state.message=r.name.."'s alarm: time to wake up. Check your needs before work.";return true
    end
    return false
end
function Sleep.status(state,players,display)
    local now=Calendar.absoluteHours(state);local sleeping,total,seen=0,0,{}
    local boundary=state.home.weekend.opensAtHours-2
    for _,p in ipairs(players or {}) do
        local Residents=require("src.home_residents");local r=display and Residents.display(state,p) or Residents.get(state,p);local id=Residents.key(p)
        if not seen[id or p] then
            seen[id or p]=true;total=total+1
            local a=r and r.activity
            if p.sceneId=="home" and a and Sleep.ACTIONS[a.kind] and (p.x-a.x)^2+(p.y-a.y)^2<=12^2 and now+1e-7<Sleep.endAt(state,r,a) then
                sleeping=sleeping+1;boundary=math.min(boundary,Sleep.endAt(state,r,a))
            end
        end
    end
    return total>0 and sleeping==total and state.home.weekend.phase=="home" and not state.home.weekend.travelToken and now+1e-7<boundary,sleeping,total,boundary
end
function Sleep.calendarStep(state,players,dt)
    local all,_,_,boundary=Sleep.status(state,players)
    local now=Calendar.absoluteHours(state);local seconds=Calendar.secondsPerDay(state)/24
    local result=math.max(0,dt)*(all and Sleep.SPEED or 1)
    -- A bounded game-time step keeps deliveries, midnight rent and laundry
    -- chronological while still using the normal closed-shop simulation path.
    if all then result=math.min(result,seconds/12,math.max(0,boundary-now)*seconds) end
    for _,p in ipairs(players or {}) do
        local r=require("src.home_residents").get(state,p)
        if p.sceneId=="home" and r and r.alarmAt and r.alarmAt>now+1e-7 then result=math.min(result,(r.alarmAt-now)*seconds) end
    end
    return result,all
end
function Sleep.readiness(state,players)
    local rows={}
    for _,p in ipairs(players or {}) do
        local r=require("src.home_residents").display(state,p)
        if r then rows[#rows+1]={name=r.name,hunger=r.hunger,thirst=r.thirst,hygiene=r.hygiene,energy=r.energy,
            ready=r.hunger>=35 and r.thirst>=35 and r.hygiene>=35 and r.energy>=35,
            sleeping=r.activity and Sleep.ACTIONS[r.activity.kind]~=nil or false} end
    end
    return rows
end
return Sleep
