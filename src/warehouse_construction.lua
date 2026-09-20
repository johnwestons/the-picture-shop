-- Physical host-side construction visitor. Calendar progress is gated by the
-- actual actor reaching the work point, never by a route-duration estimate.
local Config = require("src.config")
local Calendar = require("src.business_calendar")
local Upgrades = require("src.warehouse_upgrades")
local Service = require("src.construction_service")
local Storage = require("src.pallet_storage")
local Gait = require("src.gait_motion")

local Construction = { SPEED=72, PIXELS_PER_FRAME=13, MAX_FRAME_TIME=0.1 }
local paths = setmetatable({}, {__mode="k"})
local headings = {"east","southeast","south","southwest","west","northwest","north","northeast"}
local gait = { walkPixelsPerFrame=13,
    gaitSpeedMultipliers={0.96,0.94,1.04,1.06,0.96,0.94,1.04,1.06},
    gaitAccelerationMultipliers={0.92,0.90,1.08,1.10,0.92,0.90,1.08,1.10} }
local fields = {projectId=true,bayId=true,x=true,y=true,phase=true,waypoint=true,route=true,
    animationDistance=true,moving=true,facingX=true,facingY=true,idleTime=true,direction=true,speed=true,
    workTime=true,workStage=true}
local function finite(v) return type(v)=="number" and v==v and v>-math.huge and v<math.huge end
local function point(p) return type(p)=="table" and finite(p.x) and finite(p.y)
    and p.x>=0 and p.x<=Config.baseWidth and p.y>=0 and p.y<=Config.baseHeight end
local function copy(v)
    if type(v)~="table" then return v end
    local out={} for k,x in pairs(v) do out[k]=copy(x) end return out
end
local function length(x,y) return math.sqrt(x*x+y*y) end

function Construction.valid(worker, warehouse)
    if worker==nil then return true end
    if not point(worker) then return false end
    for k in pairs(worker) do if not fields[k] then return false end end
    -- Optional visual-clock fields keep pre-work-animation schema 15 saves
    -- compatible. Only the authoritative simulation advances them.
    if worker.workTime~=nil and (not finite(worker.workTime) or worker.workTime<0 or worker.workTime>=3600) then return false end
    if worker.workStage~=nil and (not finite(worker.workStage) or worker.workStage~=math.floor(worker.workStage)
        or worker.workStage<0 or worker.workStage>4) then return false end
    if type(worker.projectId)~="string" or not worker.projectId:match("^WUP%-%d%d%d%d$")
        or (worker.bayId~="front_left" and worker.bayId~="front_right")
        or (worker.phase~="arriving" and worker.phase~="working" and worker.phase~="leaving" and worker.phase~="exited")
        or type(worker.route)~="table" or #worker.route<2 or #worker.route>16
        or not finite(worker.waypoint) or worker.waypoint~=math.floor(worker.waypoint)
        or worker.waypoint<0 or worker.waypoint>#worker.route+1
        or not finite(worker.animationDistance) or worker.animationDistance<0
        or not finite(worker.idleTime) or worker.idleTime<0
        or not finite(worker.speed) or worker.speed<0 or worker.speed>Construction.SPEED*1.1
        or type(worker.moving)~="boolean" or not finite(worker.facingX) or not finite(worker.facingY)
        or math.abs(worker.facingX)>1 or math.abs(worker.facingY)>1 then return false end
    local count=0
    for k,p in pairs(worker.route) do
        if type(k)~="number" or k~=math.floor(k) or k<1 or k>#worker.route or not point(p) then return false end
        for key in pairs(p) do if key~="x" and key~="y" then return false end end
        count=count+1
    end
    if count~=#worker.route then return false end
    local entranceCount=math.min(6,#Config.customer.route)
    if #worker.route~=entranceCount+1 then return false end
    for index=1,entranceCount do
        if worker.route[index].x~=Config.customer.route[index].x
            or worker.route[index].y~=Config.customer.route[index].y then return false end
    end
    if worker.phase=="arriving" and (worker.waypoint<2 or worker.waypoint>#worker.route) then return false end
    if worker.phase=="working" and (worker.waypoint~=#worker.route+1
        or length(worker.x-worker.route[#worker.route].x,worker.y-worker.route[#worker.route].y)>0.01) then return false end
    if worker.phase=="leaving" and (worker.waypoint<1 or worker.waypoint>=#worker.route) then return false end
    if worker.phase=="exited" and (worker.waypoint~=0
        or length(worker.x-worker.route[1].x,worker.y-worker.route[1].y)>0.01) then return false end
    local found=false for _,name in ipairs(headings) do if worker.direction==name then found=true end end
    if not found then return false end
    if warehouse then
        if type(warehouse.projects)~="table" or warehouse.activeProjectId~=worker.projectId then return false end
        local project
        for _,p in ipairs(warehouse.projects) do if p.id==worker.projectId then project=p end end
        if not project or project.bayId~=worker.bayId
            or (project.phase~="awaiting_arrival" and project.phase~="building" and project.phase~="complete")
            or ((worker.phase=="leaving" or worker.phase=="exited") and project.phase~="complete") then return false end
    end
    return true
end

function Construction.normalize(worker, warehouse)
    if not Construction.valid(worker,warehouse) then return nil,"Invalid construction worker state." end
    return copy(worker)
end

-- The renderer reads only; it does not advance simulation or construction.
function Construction.worker(state)
    local worker=state and state.constructionWorker
    if not worker or worker.phase=="exited" then return nil end
    return worker
end

function Construction.frame(worker)
    if worker.moving then return math.floor(worker.animationDistance/Construction.PIXELS_PER_FRAME)%8+1 end
    return math.floor(worker.idleTime*0.65)%2+1
end

local function clear(canMove,x,y,tx,ty)
    local count=math.max(1,math.ceil(length(tx-x,ty-y)/4))
    for n=1,count do if not canMove(x+(tx-x)*n/count,y+(ty-y)*n/count,x,y) then return false end end
    return true
end

-- Bounded local grid route around parked machines/stock. Every segment still
-- passes the authoritative collision callback; dynamic obstructions replan.
local function detour(worker,target,canMove)
    local step=16
    local queue,seen,first={{gx=0,gy=0,x=worker.x,y=worker.y}},{},1
    seen["0:0"]=queue[1]
    local found
    while first<=#queue and first<=6000 do
        local node=queue[first]; first=first+1
        if length(node.x-target.x,node.y-target.y)<=24 and clear(canMove,node.x,node.y,target.x,target.y) then found=node;break end
        for _,v in ipairs({{1,0},{0,1},{-1,0},{0,-1},{1,1},{-1,1},{-1,-1},{1,-1}}) do
            local gx,gy=node.gx+v[1],node.gy+v[2]
            local key=gx..":"..gy
            if not seen[key] then
                local x,y=worker.x+gx*step,worker.y+gy*step
                if x>=0 and y>=0 and x<=Config.baseWidth and y<=Config.baseHeight
                    and clear(canMove,node.x,node.y,x,y) then
                    local nextNode={gx=gx,gy=gy,x=x,y=y,parent=node}
                    seen[key]=nextNode;queue[#queue+1]=nextNode
                else seen[key]=true end
            end
        end
    end
    if not found then return nil end
    local result={{x=target.x,y=target.y}}
    while found.parent do table.insert(result,1,{x=found.x,y=found.y});found=found.parent end
    return {points=result,index=1,waypoint=worker.waypoint,phase=worker.phase}
end

local function move(worker,dt,canMove)
    worker.moving=false
    if worker.phase~="arriving" and worker.phase~="leaving" then worker.speed=0;worker.idleTime=worker.idleTime+dt;return false end
    local target=worker.route[worker.waypoint]
    if not target then
        worker.phase=worker.phase=="arriving" and "working" or "exited"
        worker.speed=0;paths[worker]=nil;return true
    end
    local cached=paths[worker]
    if cached and (cached.waypoint~=worker.waypoint or cached.phase~=worker.phase) then cached=nil;paths[worker]=nil end
    if cached and cached.failed then
        cached.retry=cached.retry-dt
        if cached.retry>0 then worker.speed=0;worker.idleTime=worker.idleTime+dt;return false end
        cached=nil;paths[worker]=nil
    end
    if not cached and not clear(canMove,worker.x,worker.y,target.x,target.y) then
        cached=detour(worker,target,canMove);paths[worker]=cached
        if not cached then
            paths[worker]={failed=true,retry=0.5,waypoint=worker.waypoint,phase=worker.phase}
            worker.speed=0;worker.idleTime=worker.idleTime+dt;return false
        end
    end
    local aim=cached and cached.points[cached.index] or target
    local dx,dy=aim.x-worker.x,aim.y-worker.y
    local distance=length(dx,dy)
    local speedScale,accelScale=Gait.sample(worker.animationDistance,gait)
    worker.speed=math.min(Construction.SPEED*speedScale,worker.speed+420*accelScale*dt)
    local travel=math.min(distance,worker.speed*dt)
    local moved=0
    if distance>0.000001 and travel>0 then
        local count=math.max(1,math.ceil(travel/4))
        local sx,sy=dx/distance*travel/count,dy/distance*travel/count
        for _=1,count do
            local nx,ny=worker.x+sx,worker.y+sy
            if not canMove(nx,ny,worker.x,worker.y) then paths[worker]=nil;worker.speed=0;break end
            worker.x,worker.y=nx,ny;moved=moved+length(sx,sy)
        end
        if moved>0 then
            worker.facingX,worker.facingY=dx/distance,dy/distance
            local angle=math.atan2(worker.facingY,worker.facingX)
            worker.direction=headings[math.floor(angle/(math.pi/4)+0.5)%8+1]
            worker.animationDistance=worker.animationDistance+moved;worker.moving=true;worker.idleTime=0
        end
    end
    if length(worker.x-aim.x,worker.y-aim.y)<0.001 then
        if cached and cached.index<#cached.points then cached.index=cached.index+1
        else worker.waypoint=worker.waypoint+(worker.phase=="arriving" and 1 or -1);paths[worker]=nil end
        if not worker.route[worker.waypoint] then
            worker.phase=worker.phase=="arriving" and "working" or "exited"
            worker.moving=false;worker.speed=0
        end
        return true
    end
    if not worker.moving then worker.idleTime=worker.idleTime+dt end
    return moved>0
end

function Construction.update(state,dt,options)
    options=options or {}
    if type(state)~="table" or type(options)~="table" or not finite(dt) or dt<0 then return false,"Invalid construction update." end
    if not Construction.valid(state.constructionWorker,state.warehouse) then return false,"Invalid construction worker state." end
    local canMove=options.canMove
    local workPoint=options.workPoint
    if type(canMove)~="function" or type(workPoint)~="function" then return false,"Construction requires collision and work-point callbacks." end
    local changed,events=false,{}
    local function append(items) for _,item in ipairs(items) do events[#events+1]=item end end
    local callbacks={
        workerStarted=function(_,project)
            local worker=state.constructionWorker
            if worker then return worker.projectId==project.id,false end
            local x,y=workPoint(project.bayId)
            if not point({x=x,y=y}) then return false end
            local route={}
            -- The first six entrance points lead out of reception; do not walk
            -- through the customer seating branch before crossing the floor.
            for index=1,math.min(6,#Config.customer.route) do route[#route+1]=copy(Config.customer.route[index]) end
            route[#route+1]={x=x,y=y}
            if not canMove(route[1].x,route[1].y) then return false end
            state.constructionWorker={projectId=project.id,bayId=project.bayId,x=route[1].x,y=route[1].y,
                route=route,waypoint=2,phase="arriving",animationDistance=0,idleTime=0,
                speed=0,moving=false,facingX=0,facingY=1,direction="south",workTime=0,workStage=0}
            return true,true
        end,
        workerArrived=function(_,project)
            local worker=state.constructionWorker
            return worker and worker.projectId==project.id and worker.phase=="working"
                and length(worker.x-worker.route[#worker.route].x,worker.y-worker.route[#worker.route].y)<0.01
        end,
        workerBlocked=function() local worker=state.constructionWorker
            return not worker or not canMove(worker.x,worker.y) end,
        workerExited=function(_,project)
            local worker=state.constructionWorker
            if not worker or worker.projectId~=project.id then return false end
            if worker.phase=="exited" then return true end
            if worker.phase~="leaving" then
                worker.phase="leaving";worker.waypoint=#worker.route-1;worker.moving=false;worker.speed=0
                paths[worker]=nil;return false,true
            end
            return false
        end,
    }
    local now=options.nowHours==nil and Calendar.absoluteHours(state) or options.nowHours
    local updated,emitted=Service.update(state,now,callbacks)
    if type(emitted)~="table" then return false,emitted end
    changed=changed or updated;append(emitted)
    local worker=state.constructionWorker
    if worker then changed=move(worker,math.min(dt,Construction.MAX_FRAME_TIME),canMove) or changed end
    -- Confirm this frame's actual arrival/departure without waiting another
    -- business-clock tick; all purchase/stage gates remain idempotent.
    updated,emitted=Service.update(state,now,callbacks)
    if type(emitted)~="table" then return changed,emitted end
    changed=changed or updated;append(emitted)
    local active=Upgrades.activeProject(state)
    worker=state.constructionWorker
    if worker and worker.phase=="working" and not worker.moving and active
        and active.id==worker.projectId and active.phase=="building" and not active.pausedAtHours then
        if worker.workStage~=active.stage then
            worker.workStage=active.stage;worker.workTime=0;changed=true
        elseif dt>0 then
            worker.workTime=((worker.workTime or 0)+math.min(dt,Construction.MAX_FRAME_TIME))%3600
            changed=true
        end
    end
    if state.constructionWorker and state.warehouse.activeProjectId~=state.constructionWorker.projectId then
        state.constructionWorker=nil;changed=true
    end
    if state.storage==nil then state.storage=Storage.defaultState() end
    for bayId,bay in pairs(state.warehouse.bays) do
        if bay.status=="complete" and bay.optionId=="storage" then
            local rack=Storage.rackDefinition(bayId)
            if not state.storage.racks[rack.id] then
                state.storage.racks[rack.id]=rack;changed=true
                events[#events+1]={kind="rack_registered",bayId=bayId,rackId=rack.id}
            end
        end
    end
    return changed,events
end

return Construction
