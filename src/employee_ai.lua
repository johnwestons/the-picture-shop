local Employees=require("src.employees")
local Contracts=require("src.employment_contracts")
local Payroll=require("src.payroll")
local Work=require("src.employee_work")
local Calendar=require("src.business_calendar")
local PlayerController=require("src.player_controller")
local Navigation=require("src.navigation")
local Config=require("src.config")
local AI={}
local paths=setmetatable({},{__mode="k"})
local entrance={x=645,y=235}
local reception={x=759,y=358}
local motion={speed=72,acceleration=600,deceleration=850,maxFrameTime=.10,maxStepDistance=4,
    walkPixelsPerFrame=13,gaitSpeedMultipliers={.96,.94,1.04,1.06,.96,.94,1.04,1.06},
    gaitAccelerationMultipliers={.92,.90,1.08,1.10,.92,.90,1.08,1.10}}
local function distance(a,b) return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2) end
local function stop(a)
    PlayerController.stop(a);a.moving=false
end
local function face(a,x,y)
    local d=math.sqrt(x*x+y*y)
    if d>.001 then a.intentX,a.intentY=x/d,y/d end
end
local function route(a,goal,context)
    local step=14
    local obstacles=context.obstacles(a)
    local function walk(x,y) return Navigation.isWalkable(context.assets,x,y,obstacles) end
    local function key(x,y) return x..":"..y end
    local sx,sy=math.floor(a.x/step+.5),math.floor(a.y/step+.5)
    local gx,gy=math.floor(goal.x/step+.5),math.floor(goal.y/step+.5)
    local open,scores,parents,closed={{x=sx,y=sy,g=0,f=0}},{[key(sx,sy)]=0},{},{}
    local target,visited
    visited=0
    while #open>0 and visited<3400 do
        local best=1
        for i=2,#open do if open[i].f<open[best].f then best=i end end
        local node=table.remove(open,best)
        local k=key(node.x,node.y)
        if not closed[k] then
            closed[k]=true;visited=visited+1
            if (node.x-gx)^2+(node.y-gy)^2<=1 and walk(goal.x,goal.y) then target=node;break end
            for dx=-1,1 do for dy=-1,1 do if dx~=0 or dy~=0 then
                local x,y=node.x+dx,node.y+dy
                local nk=key(x,y)
                local diagonal=dx~=0 and dy~=0
                if not closed[nk] and walk(x*step,y*step)
                    and (not diagonal or (walk(node.x*step,y*step) and walk(x*step,node.y*step))) then
                    local cost=node.g+(diagonal and 1.41421356 or 1)
                    if not scores[nk] or cost<scores[nk] then
                        scores[nk]=cost;parents[nk]=node
                        open[#open+1]={x=x,y=y,g=cost,f=cost+math.sqrt((gx-x)^2+(gy-y)^2)}
                    end
                end
            end end end
        end
    end
    if not target then return nil end
    local points={goal}
    while target and (target.x~=sx or target.y~=sy) do
        table.insert(points,1,{x=target.x*step,y=target.y*step})
        target=parents[key(target.x,target.y)]
    end
    return points
end
function AI.move(a,goal,dt,context)
    if distance(a,goal)<3 then stop(a);return true end
    local cached=paths[a]
    if not cached or distance(cached.goal,goal)>2 or cached.blocked>.4 then
        cached={points=route(a,goal,context),goal={x=goal.x,y=goal.y},blocked=0}
        paths[a]=cached
    end
    if not cached.points or #cached.points==0 then
        stop(a);cached.blocked=cached.blocked+dt;return false
    end
    local target=cached.points[1]
    if distance(a,target)<5 then table.remove(cached.points,1);target=cached.points[1] or goal end
    local obstacles=context.obstacles(a)
    local beforeX,beforeY=a.x,a.y
    local beforeIntentX,beforeIntentY=a.intentX,a.intentY
    a.animationDistance=a.distance
    local priorIdle=a.idleClock
    PlayerController.update(a,target.x-a.x,target.y-a.y,dt,function(x,y,nx,ny)
        return Navigation.canMoveFrom(context.assets,x,y,nx,ny,obstacles)
    end,motion)
    local moved=math.sqrt((a.x-beforeX)^2+(a.y-beforeY)^2)
    a.distance=a.distance+moved;a.moving=moved>.0001
    if moved>.0001 then
        face(a,a.x-beforeX,a.y-beforeY);a.idleClock=0;cached.blocked=0
    else
        a.intentX,a.intentY=beforeIntentX,beforeIntentY
        a.idleClock=priorIdle+dt;cached.blocked=cached.blocked+dt
    end
    return distance(a,goal)<3
end
local function visiting(e)
    for _,a in ipairs(e.applications) do if a.actor.visible then return a end end
end
function AI.receptionOccupied(state) return visiting(Employees.ensure(state))~=nil end
local function applications(state,dt,now,context)
    local e=Employees.ensure(state)
    local present=visiting(e)
    for _,a in ipairs(e.applications) do
        local actor=a.actor
        if a.status=="visiting" and not actor.visible and not present
            and not context.receptionBusy() and not Calendar.isWeekend(state) then
            actor.visible=true;actor.phase="entering";actor.x,actor.y=entrance.x,entrance.y
            present=a;state.message=a.name.." is applying for a cutter job. Request a resume at reception or in Hiring."
        end
        if actor.visible then
            if actor.phase=="entering" and AI.move(actor,reception,dt,context) then
                actor.phase="waiting";actor.arrivedAtHours=now;face(actor,-1,0)
            elseif actor.phase=="waiting" then
                stop(actor);actor.idleClock=actor.idleClock+dt
                if now-(actor.arrivedAtHours or now)>=4 then Employees.requestResume(state,a.id,now) end
            elseif actor.phase=="leaving" and AI.move(actor,entrance,dt,context) then
                actor.visible=false;actor.phase="hidden";stop(actor)
            end
        end
    end
end
local function breakChoice(w,now)
    local elapsed=now-math.floor(now/24)*24-w.contract.startHour
    local duration=w.contract.endHour-w.contract.startHour
    for _,b in ipairs({{at=2,bit=1,kind="rest",duration=.25},{at=4,bit=2,kind="meal",duration=.5},{at=6,bit=4,kind="rest",duration=.25}}) do
        if b.at<duration and (b.kind~="meal" or duration>=6) and elapsed>=b.at
            and math.floor(w.breaksTaken/b.bit)%2==0 then return b end
    end
    if w.fatigue>=70 or w.focus<=40 then return {bit=0,kind="rest",duration=.25} end
end
local function beginBreak(state,w,b,context)
    if not Work.release(state,w) then return false end
    w.breaksTaken=w.breaksTaken+(b.bit or 0);w.breakKind=b.kind;w.breakRemaining=b.duration
    local seat=context.freeSeat(w)
    w.seatBay=seat and seat.bayId or nil;w.phase=seat and "break_walk" or "break"
    w.activity=seat and "Walking to breakroom" or "Resting beside workstation"
    return true
end
function AI.worker(state,w,dt,now,context)
    local day=math.floor(now/24)
    local onShift=w.status=="employed" and not w.terminationRequested and Contracts.onShift(w.contract,now)
    local overdue=Payroll.overdueSince(w,now)
    if overdue and now-overdue>=168 and w.status=="employed" then w.terminationRequested=true;w.resigning=true;onShift=false end
    if onShift and not w.visible then
        w.visible=true;w.phase="entering";w.x,w.y=entrance.x,entrance.y;w.clockedIn=true
        w.activity="Arriving for shift"
        if w.shiftDay~=day then w.shiftDay=day;w.breaksTaken=0;w.fatigue=math.max(0,w.fatigue-60);w.focus=math.min(100,w.focus+50) end
    end
    if not w.visible then
        if w.terminationRequested then w.status=w.resigning and "resigned" or "dismissed" end
        return false
    end
    if not onShift or w.stopRequested then
        if Work.safe(w) then
            Work.release(state,w);w.seatBay=nil;w.breakKind=nil
            if w.stopRequested then w.assignment=nil;w.stopRequested=false end
            if not onShift then w.phase="leaving";w.clockedIn=false;w.activity="Shift ended" end
        else
            w.activity="Finishing safe cutter cycle";return false
        end
    end
    if w.phase=="leaving" then
        if AI.move(w,entrance,dt,context) then
            w.visible=false;w.phase="hidden";w.clockedIn=false;stop(w)
            if w.terminationRequested then w.status=w.resigning and "resigned" or "dismissed" end
        end
        return false
    end
    local hours=dt*24/(Config.businessCalendar.secondsPerDay or 300)
    if w.phase=="break_walk" then
        local seat=context.seat(w.seatBay)
        if not seat then w.seatBay=nil;w.phase="break"
        elseif AI.move(w,seat,dt,context) then
            w.phase="break";stop(w);face(w,w.seatBay=="front_left" and -1 or 1,0)
        end
    elseif w.phase=="break" then
        stop(w);w.idleClock=w.idleClock+dt
        local recovery=w.seatBay and 1 or .5
        w.fatigue=math.max(0,w.fatigue-160*hours*recovery)
        w.focus=math.min(100,w.focus+128*hours*recovery)
        w.breakRemaining=math.max(0,w.breakRemaining-hours)
        w.activity=w.breakKind=="meal" and "Unpaid meal break" or "Paid rest break"
        if w.breakRemaining<=.000001 then w.phase="idle";w.seatBay=nil;w.breakKind=nil end
    else
        local b=breakChoice(w,now)
        if (w.fatigue>=90 or w.focus<=20) then b={bit=0,kind="rest",duration=.25} end
        if b and Work.safe(w) then beginBreak(state,w,b,context)
        elseif overdue then
            if Work.safe(w) then Work.release(state,w);w.phase="idle";stop(w);w.activity="Waiting for overdue wages" end
        elseif w.assignment then
            local workContext={canClaim=context.canClaim,operatorPoint=context.operatorPoint,
                move=function(actor,goal,seconds) return AI.move(actor,goal,seconds,context) end}
            local changed=Work.update(state,w,dt,workContext)
            w.fatigue=math.min(100,w.fatigue+hours*(w.phase=="working" and 8 or 3))
            w.focus=math.max(0,w.focus-hours*(w.phase=="working" and 6 or 2))
            return changed
        else
            local point=context.idlePoint(w)
            if AI.move(w,point,dt,context) then w.phase="idle";w.activity="Waiting for assignment";w.idleClock=w.idleClock+dt end
            w.fatigue=math.min(100,w.fatigue+hours)
        end
    end
    return false
end
function AI.update(state,dt,context)
    local e=Employees.ensure(state)
    local now=Calendar.absoluteHours(state)
    local previous=math.min(now,e.lastAtHours)
    local changed=Employees.advance(state,now)
    -- Time only advances with the active shop, never from real-world offline
    -- elapsed time. Small slices keep arrivals, breaks, and wage clipping exact.
    local secondsPerHour=(Config.businessCalendar.secondsPerDay or 300)/24
    local total=now-previous
    if total<=0 then return changed end
    local at=previous
    while at<now-1e-9 do
        local nextAt=math.min(now,at+.1/secondsPerHour)
        local realDt=(nextAt-at)*secondsPerHour
        applications(state,realDt,nextAt,context)
        for _,w in ipairs(e.staff) do
            local oldClocked=w.clockedIn
            Payroll.accrue(w,at,nextAt,not Work.safe(w))
            if AI.worker(state,w,realDt,nextAt,context) or oldClocked~=w.clockedIn then changed=true end
        end
        at=nextAt
    end
    e.lastAtHours=now
    if Payroll.pay(state,now,true) then changed=true end
    return changed
end
return AI
