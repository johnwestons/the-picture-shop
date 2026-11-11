-- Durable weekly travel state. The runtime supplies the shutdown safety result;
-- this module never guesses whether a machine, lease, or transport is safe.
local Calendar=require("src.business_calendar")
local Hours=require("src.business_hours")
local Flow={CLOSE_HOUR=Hours.CLOSE_HOUR,WARNING_HOUR=18,OPEN_HOUR=Hours.OPEN_HOUR,WAKE_HOUR=7,RETURN_HOUR=7.5}
local phases={working=true,closing=true,ready=true,home=true}
local function finite(n) return type(n)=="number" and n==n and n>=0 and n<=24000000 end
local function weekday(day) return (day+3)%7+1 end
function Flow.new(at)
    local day=math.floor(at/24);local w=weekday(day)
    local friday=day+5-w
    return {phase="working",closesAtHours=friday*24+Flow.CLOSE_HOUR,
        opensAtHours=(friday+3)*24+Flow.OPEN_HOUR,warningSent=false,returnReminderSent=false,transition=0}
end
function Flow.valid(week)
    if week==nil then return true end -- Saves created before the weekly loop.
    if type(week)~="table" or not phases[week.phase] or not finite(week.closesAtHours)
        or week.closesAtHours%24~=Flow.CLOSE_HOUR or weekday(math.floor(week.closesAtHours/24))~=5
        or week.opensAtHours~=week.closesAtHours+61
        or type(week.warningSent)~="boolean" or type(week.returnReminderSent)~="boolean"
        or not finite(week.transition) or week.transition~=math.floor(week.transition) then return false end
    if week.travelToken~=nil then
        local outing=week.travelPurpose=="outing"
        if (not outing and week.phase~="ready" and week.phase~="home")
            or week.travelPurpose~=nil and week.travelPurpose~="weekend" and not outing
            or outing and week.travelOrigin~="warehouse" and week.travelOrigin~="home"
            or not outing and week.travelOrigin~=nil
            or type(week.travelToken)~="number"
            or week.travelToken<1 or week.travelToken>1e12 or week.travelToken~=math.floor(week.travelToken)
            or type(week.readyMask)~="number" or week.readyMask<1 or week.readyMask>15
            or week.readyMask~=math.floor(week.readyMask) then return false end
    elseif week.readyMask~=nil or week.travelPurpose~=nil or week.travelOrigin~=nil then return false end
    if week.phase=="ready" or week.phase=="home" then
        return finite(week.closedAtHours) and week.closedAtHours>=week.closesAtHours
    end
    return week.closedAtHours==nil
end
function Flow.returnAtHours(week)
    -- Aim to be at the shop before the 08:00 employee shift. Keep the
    -- separately scheduled 09:00 customer opening unchanged.
    return week.closesAtHours+(24-Flow.CLOSE_HOUR)+48+Flow.RETURN_HOUR
end
function Flow.ensure(state)
    if not state.home.weekend then state.home.weekend=Flow.new(Calendar.absoluteHours(state)) end
    return state.home.weekend
end
function Flow.atHome(state)
    local home=state and state.home
    if home and home.commute and home.commute.independent then
        for _,resident in pairs(home.residents or {}) do if resident.sceneId=='home' then return true end end
        return false
    end
    if home and home.visit and home.visit.kind=="outing" then return home.visit.scene~="warehouse" end
    return home~=nil and home.weekend~=nil and home.weekend.phase=="home"
end
function Flow.isOuting(state)
    local home=state and state.home
    if home and home.commute then return home.commute.purpose=="outing" end
    return home~=nil and home.visit~=nil and home.visit.kind=="outing"
end
local function changed(state,message)
    state.home.revision=state.home.revision+1
    state.message=message
    return true
end
function Flow.limitCalendarStep(state,dt)
    local week=Flow.ensure(state)
    dt=math.max(0,dt)
    if state.home.commute and state.home.commute.purpose~="outing" and state.home.commute.purpose~='delivery' then return 0 end
    if week.phase=="ready" and not Flow.isOuting(state) then return 0 end
    if week.phase=="working" then
        local remaining=math.max(0,week.closesAtHours-Calendar.absoluteHours(state))
        return math.min(dt,remaining*Calendar.secondsPerDay(state)/24)
    end
    return dt
end
function Flow.update(state,shutdownSafe)
    local week=Flow.ensure(state);local now=Calendar.absoluteHours(state)
    local didChange=false
    -- Staying to finish jobs is optional; it must not strand the shop in last
    -- Friday's closing phase when business opens again on Monday.
    if (week.phase=='working' or week.phase=='closing') and now>=week.opensAtHours then
        require('src.household_finances').settle(state,week.closesAtHours)
        local nextWeek=Flow.new(now);nextWeek.transition=week.transition+1
        state.home.weekend=nextWeek;week=nextWeek
        didChange=changed(state,'Business hours have resumed. Customers and delivery trucks can return.')
    end
    if week.phase=="working" and now>=week.closesAtHours-2 and not week.warningSent then
        week.warningSent=true
        didChange=changed(state,"The shop closes Friday at 20:00. Finish up and prepare to go home for the weekend.")
    end
    if week.phase=="working" and now+1e-7>=week.closesAtHours then
        week.phase="closing"
        didChange=changed(state,"Business is closed for the weekend. Keep working on pallets, or finish shutdown and use the front entrance to head home.")
    end
    if week.phase=="closing" and shutdownSafe==true then
        require("src.household_finances").settle(state,week.closesAtHours)
        -- The boundary comparison above allows floating-point roundoff. Keep
        -- the durable timestamp inside the same interval required by saves.
        week.phase="ready";week.closedAtHours=math.max(now,week.closesAtHours)
        didChange=changed(state,"The shop is safely shut down. Go to the front entrance to head home for the weekend.")
    end
    -- Ordinary outings do not require the owner to be indoors for Monday's
    -- opening. The existing weekend commute keeps its explicit return gate.
    if (week.phase=="ready" or week.phase=="home") and Flow.isOuting(state)
        and now>=Flow.returnAtHours(week) then
        local nextWeek=Flow.new(now);nextWeek.transition=week.transition+1
        state.home.weekend=nextWeek;week=nextWeek
        if state.home.visit and state.home.visit.scene=="warehouse" then state.home.visit=nil end
        didChange=changed(state,"The new shop week is ready. Your town visit can continue.")
    end
    if week.phase=="home" and now>=week.opensAtHours-2 and not week.returnReminderSent then
        week.returnReminderSent=true
        didChange=changed(state,"Monday morning: get ready. Return to the shop starting at 07:30, before the 08:00 employee shift. The shop opens at 09:00.")
    end
    return didChange
end
function Flow.shopClosed(state)
    local week=state.home and state.home.weekend
    return week and (week.phase=="ready" or week.phase=="home") or false
end
function Flow.acceptsNewWork(state)
    local week=state.home and state.home.weekend
    return not week or week.phase=="working"
end
function Flow.depart(state,expectedRevision)
    local week=Flow.ensure(state)
    if expectedRevision~=state.home.revision then return false,"The household changed. Review departure again." end
    if week.phase~="ready" then return false,"Finish the shop shutdown checklist first." end
    require("src.home_residents").fridayArrival(state)
    week.phase="home";week.transition=week.transition+1;state.home.visit=nil
    return changed(state,"Welcome home. The shop stays closed for the weekend.")
end
function Flow.returnToWork(state,expectedRevision)
    local week=Flow.ensure(state);local now=Calendar.absoluteHours(state)
    if expectedRevision~=state.home.revision then return false,"The household changed. Review the return trip again." end
    if week.phase~="home" then return false,"You are already at the shop." end
    local day=math.floor(now/24);local w=weekday(day)
    if now<Flow.returnAtHours(week) or w>=6 or w==5 and now%24>=Flow.CLOSE_HOUR then
        return false,"Return to the shop starting Monday at 07:30, before the 08:00 employee shift."
    end
    local lateOpening=now>week.opensAtHours+1e-7
    local nextWeek=Flow.new(now);nextWeek.transition=week.transition+1
    state.home.weekend=nextWeek
    state.home.visit=nil
    local waitingEmployees=false
    if lateOpening and state.employment then
        local speech=require("src.employee_speech")
        local untilHours=now+speech.GREETING_SECONDS*24/Calendar.secondsPerDay(state)
        for _,worker in ipairs(state.employment.staff or {}) do
            if worker.visible and worker.clockedIn and worker.phase=="waiting" then
                worker.greetingKind=speech.EMPLOYEE_LATE_OPENING
                worker.greetingUntilHours=untilHours
                waitingEmployees=true
            end
        end
    end
    return changed(state,waitingEmployees
        and "Back at the shop. Your employees have been waiting to open."
        or "Back at the shop. Your unfinished work is ready to resume.")
end
function Flow.outingArrival(state,atHome)
    -- Called while the outing still exists, so a due Monday rollover is not
    -- lost when the traveler returns to the warehouse.
    Flow.update(state,false)
    state.home.visit=(atHome or Flow.shopClosed(state)) and {kind="outing",scene=atHome and "home" or "warehouse"} or nil
    local home=state.home
    local town=require('src.commute.town')
    local townName=home and home.town and home.town.name
        or town.defaultName(home and home.town and home.town.seed)
    return changed(state,atHome and "Welcome to your apartment. The shop keeps its normal schedule."
        or "Welcome back to "..townName..". Your town outing is complete.")
end
return Flow
