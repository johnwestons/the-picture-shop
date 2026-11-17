-- Receiving-yard traffic control. The queue grants a single dock lease;
-- this protocol owns every movement from the entry through the exit gate.
local Rail=require('src.commute.yard_rail')
local Path=require('src.commute.driving_path')
local Watchdog=require('src.ai_watchdog')
local Yard={STOP_SECONDS=.75,REPORT_SECONDS=3,RECOVERY_SECONDS=8}
local stages={entry=true,queue_stop=true,approach=true,setup_stop=true,reverse=true,
    docked=true,exit=true,exit_stop=true,released=true}
local routes=setmetatable({},{__mode='k'})
local function finite(n)return type(n)=='number' and n==n and math.abs(n)<1e12 end
function Yard.valid(y)
    if y==nil then return true end
    if type(y)~='table' then return false end
    local exitStage=y.stage=='exit' or y.stage=='exit_stop' or y.stage=='released'
    if (y.target=='outbound')~=exitStage then return false end
    if y.target~='outbound' and y.target~='dock' and y.stage~='entry' and y.stage~='queue_stop' then return false end
    return type(y)=='table' and y.version==1 and stages[y.stage]==true
        and (y.target=='dock' or y.target=='outbound' or type(y.target)=='string'
            and y.target:match('^waiting%-%d+$')~=nil and #y.target<=16)
        and Rail.valid(y.rail) and finite(y.wait) and y.wait>=0 and y.wait<=1e6
        and finite(y.pause) and y.pause>=0 and y.pause<=1e6
        and finite(y.recoveries) and y.recoveries%1==0 and y.recoveries>=0 and y.recoveries<=1e9
end
function Yard.inside(vehicle,world)
    local site=world and world.truckAccess and world.sites and world.sites.byId.warehouse
    if not site or not vehicle then return false end
    local x,z=site:toLocal(vehicle.x,vehicle.z)
    local _,gateZ=site:toLocal(world.truckAccess.entryGate.x,world.truckAccess.entryGate.z)
    return x>=-16 and x<=26 and z>=-14 and z<=math.max(24,gateZ+3)
end
function Yard.controls(vehicle,world)
    if not world.truckAccess then return false end
    if vehicle.yard then return vehicle.yard.stage~='released' end
    return Yard.inside(vehicle,world)
end
function Yard.committed(vehicle)
    local y=vehicle and vehicle.yard
    return y and y.target=='dock' and (y.stage=='approach' or y.stage=='setup_stop'
        or y.stage=='reverse' or y.stage=='docked') or vehicle and vehicle.phase=='at_bay'
end
function Yard.exitOccupies(vehicle,world)
    return vehicle and vehicle.phase~='offmap'
        and not (vehicle.yard and vehicle.yard.stage=='released')
        and (vehicle.yard and vehicle.yard.target=='outbound' or Yard.inside(vehicle,world))
end
function Yard.setExitLine(world,outward,lanePosition)
    local cached=routes[world]
    if not cached then cached={};routes[world]=cached end
    if cached['outbound:exit'] then return end
    local gate=world.truckAccess.exitGate
    local station=Rail.project(outward,gate.x,gate.z)
    local length=Path.length(outward)
    local points={}
    for i=1,#world.truckAccess.exitPath-1 do points[#points+1]=world.truckAccess.exitPath[i] end
    -- Retain control through the turn onto the frontage street, until the
    -- entire vehicle is aligned in its road lane and clear of the driveway.
    for d=station,math.min(length,station+14),1 do
        local sample=Path.sample(outward,length,d/length)
        local lane=lanePosition({},outward,sample,world)
        points[#points+1]={x=lane.x,z=lane.z,h=sample.h}
    end
    cached['outbound:exit']={points=Rail.round(points),reverse=false}
end
local function point(site,x,z)
    local wx,wz,h=site:toWorld(x,z,0);return {x=wx,z=wz,h=h}
end
local function plan(world,target,anchor,stage)
    local cached=routes[world]
    if not cached then cached={};routes[world]=cached end
    local key=target..':'..stage
    if cached[key] then return cached[key] end
    local site=world.sites.byId.warehouse
    local access=world.truckAccess
    local layout=require('src.commute.sites').warehouseTruckLayout
    local points={}
    if stage=='exit' then
        points=access.exitPath
    elseif stage=='reverse' then
        points={point(site,layout.truckDockSetup.x,layout.truckDockSetup.z),
            point(site,site.design.truckParking.x,site.design.truckParking.z)}
    elseif stage=='approach' then
        local front=layout.truckQueueAnchors[1]
        points[1]=point(site,front.x,front.z)
        local started=false
        for _,p in ipairs(layout.truckEntryWaypoints) do
            if p.x==front.x and p.z==front.z then started=true
            elseif started then
                points[#points+1]=point(site,p.x,p.z)
                if p.x==layout.truckDockSetup.x and p.z==layout.truckDockSetup.z then break end
            end
        end
    elseif anchor and anchor.points then
        points=anchor.points
    else
        local stop=target=='dock' and layout.truckQueueAnchors[1] or anchor
        points[1]=access.entryGate
        for _,p in ipairs(layout.truckEntryWaypoints) do
            points[#points+1]=point(site,p.x,p.z)
            if p.x==stop.x and p.z==stop.z then break end
        end
    end
    local result={points=Rail.round(points),reverse=stage=='reverse',
        heading=(stage=='reverse' or stage=='approach') and site.yaw
            or stage=='entry' and (anchor and anchor.heading or site.yaw-math.pi/2) or nil}
    cached[key]=result;return result
end
local function stageTo(vehicle,stage)
    local y=vehicle.yard
    y.stage=stage;y.rail=nil;y.wait=0;y.pause=0;y.reported=nil
    Rail.stop(vehicle)
end
local function issue(vehicle)return 'delivery-yard:'..tostring(vehicle.trafficId or 'truck')end
local function reset(vehicle,target)
    vehicle.yard={version=1,target=target,stage=target=='outbound' and 'exit' or 'entry',
        wait=0,pause=0,recoveries=0}
    vehicle.pathTarget=target;vehicle.localManeuver=nil;vehicle.replanRoute=nil
    Rail.stop(vehicle)
end
local function currentPlan(vehicle,assignment,world)
    local y=vehicle.yard
    return plan(world,y.target,assignment and assignment.anchor,y.stage)
end
function Yard.recover(vehicle,assignment,world,state)
    local reason,message=require('src.commute.truck_power').reason(vehicle)
    if reason then return false,message end
    local y=vehicle.yard
    if assignment and assignment.permitted==false then return false,'Another truck owns the yard exit; holding.' end
    if not y or y.stage=='released' or y.stage=='docked' or y.stage:match('_stop$') then
        return false,'Truck is holding its assigned protocol stop.'
    end
    if y.target~='outbound' and (not assignment or assignment.target~=y.target or not assignment.anchor) then
        return false,'Waiting for a valid queue/dock reservation.'
    end
    local route=currentPlan(vehicle,assignment,world)
    local endpoint=Rail.endpoint(route.points,route.reverse,route.heading)
    if (vehicle.x-endpoint.x)^2+(vehicle.z-endpoint.z)^2<.001
        and y.rail and y.rail.station>=Path.length(route.points)-.001 then
        return false,'The assigned checkpoint is already occupied by this truck.'
    end
    if not Rail.place(vehicle,endpoint,world) then return false,'The assigned checkpoint is occupied; holding.' end
    y.rail={station=Path.length(route.points)};y.wait=0;y.reported=nil
    y.recoveries=y.recoveries+1
    Watchdog.note(state,issue(vehicle),{status='RECOVERED',system='Shop yard protocol',
        subject=vehicle.trafficId,stage=y.stage,reason='Yard movement stalled',
        action='Teleported truck to its clear reserved protocol checkpoint',attempt=y.recoveries,
        x=vehicle.x,z=vehicle.z,visible=vehicle.visible~=false,scope='world-simulation'})
    return true,'Truck moved to its clear reserved yard checkpoint.'
end
function Yard.unstick(vehicle,assignment,world,state,kind)
    local reason,message=require('src.commute.truck_power').reason(vehicle)
    if reason then return false,message end
    if assignment and assignment.permitted==false then return false,'Another truck owns the yard exit; holding.' end
    local target=kind=='outbound' and 'outbound' or assignment and assignment.target
    if not target then return false,'No reserved yard checkpoint is available.' end
    if not vehicle.yard or not Yard.valid(vehicle.yard) or vehicle.yard.target~=target then reset(vehicle,target) end
    local y=vehicle.yard
    local previous={docked='reverse',queue_stop='entry',setup_stop='approach',exit_stop='exit'}
    if previous[y.stage] then
        local route=plan(world,target,assignment and assignment.anchor,previous[y.stage])
        local endpoint=Rail.endpoint(route.points,route.reverse,route.heading)
        if (vehicle.x-endpoint.x)^2+(vehicle.z-endpoint.z)^2>.15^2 then stageTo(vehicle,previous[y.stage]) end
    end
    local moved,message=Yard.recover(vehicle,assignment,world,state)
    if moved then vehicle.phase=kind=='outbound' and 'departing' or 'approaching' end
    return moved,message
end
function Yard.update(vehicle,assignment,world,dt,state,kind)
    dt=math.max(0,math.min(.1,dt or 0))
    if dt<=0 then return false end
    local target=kind=='outbound' and 'outbound' or assignment and assignment.target
    if not target or kind~='outbound' and not assignment.anchor then Rail.stop(vehicle);return false end
    if not vehicle.yard or not Yard.valid(vehicle.yard) or vehicle.yard.target~=target then
        local wasParked=vehicle.phase=='at_bay' or vehicle.phase=='waiting_bay'
        reset(vehicle,target)
        if kind~='outbound' then
            local site=world.sites.byId.warehouse
            local x,z=site:toWorld(assignment.anchor.x,assignment.anchor.z,0)
            if (vehicle.x-x)^2+(vehicle.z-z)^2<.01 then
                stageTo(vehicle,target=='dock' and 'docked' or 'queue_stop')
            elseif target=='dock' then
                local lx,lz=site:toLocal(vehicle.x,vehicle.z)
                if lx>=site.design.truckParking.x and lx<=20.5 and math.abs(lz)<.3 then
                    stageTo(vehicle,'setup_stop')
                    -- Older saves can already be partway through backing in.
                    if lx<19.5 then stageTo(vehicle,'reverse') end
                elseif wasParked and select(2,Rail.project(plan(world,target,assignment.anchor,'entry').points,
                    vehicle.x,vehicle.z))>1.5 then
                    Watchdog.note(state,issue(vehicle),{status='STALLED',system='Shop yard protocol',
                        subject=vehicle.trafficId,stage='entry',reason='Truck moved away from its assigned protocol stop',
                        action='Restoring its reserved line and checkpoint',x=vehicle.x,z=vehicle.z,
                        visible=vehicle.visible~=false,scope='world-simulation'})
                end
            end
        end
    end
    local y=vehicle.yard
    vehicle.pathTarget=target
    local stopStage={docked='reverse',queue_stop='entry',setup_stop='approach',exit_stop='exit'}
    if stopStage[y.stage] then
        local stopPlan=plan(world,target,assignment and assignment.anchor,stopStage[y.stage])
        local p=Rail.endpoint(stopPlan.points,stopPlan.reverse,stopPlan.heading)
        if (vehicle.x-p.x)^2+(vehicle.z-p.z)^2>.15^2
            or math.abs(math.atan2(math.sin(vehicle.heading-p.heading),math.cos(vehicle.heading-p.heading)))>.1 then
            stageTo(vehicle,stopStage[y.stage])
            Watchdog.note(state,issue(vehicle),{status='STALLED',system='Shop yard protocol',
                subject=vehicle.trafficId,stage=y.stage,reason='Truck moved away from its assigned protocol stop',
                action='Restoring its reserved line and checkpoint',x=vehicle.x,z=vehicle.z,
                visible=vehicle.visible~=false,scope='world-simulation'})
        end
    end
    if y.stage=='released' then return true end
    if y.stage=='docked' then Rail.stop(vehicle);vehicle.phase='at_bay';return true end
    if require('src.commute.truck_power').report(state,vehicle,issue(vehicle),y.stage) then
        y.wait=0;y.reported=nil;return false
    end
    vehicle.phase=target=='outbound' and 'departing' or target=='dock' and 'approaching' or 'approaching_wait'
    if y.stage:match('_stop$') then
        Rail.stop(vehicle);y.pause=y.pause+dt
        if y.stage=='queue_stop' and target~='dock' then vehicle.phase='waiting_bay';return false end
        if y.pause<Yard.STOP_SECONDS then return false end
        if y.stage=='queue_stop' then stageTo(vehicle,'approach')
        elseif y.stage=='setup_stop' then stageTo(vehicle,'reverse')
        else stageTo(vehicle,'released');vehicle.pathTarget=nil;vehicle.pathIndex=nil;return true end
        return false
    end
    local route=currentPlan(vehicle,assignment,world)
    if not y.rail then y.rail={station=Rail.project(route.points,vehicle.x,vehicle.z)} end
    local arrived,moved,reason=Rail.step(vehicle,y.rail,route.points,dt,world,
        {speed=route.reverse and 1.2 or 2.4,reverse=route.reverse,heading=route.heading})
    if arrived then
        Watchdog.resolve(state,issue(vehicle),{reason='Truck reached its protocol checkpoint'})
        if y.stage=='entry' then stageTo(vehicle,'queue_stop')
        elseif y.stage=='approach' then stageTo(vehicle,'setup_stop')
        elseif y.stage=='reverse' then stageTo(vehicle,'docked');vehicle.phase='at_bay';return true
        else stageTo(vehicle,'exit_stop') end
    elseif moved>.001 then
        y.wait=0;y.reported=nil
        Watchdog.resolve(state,issue(vehicle),{reason='Truck resumed its prescribed yard line'})
    else
        y.wait=y.wait+dt
        if y.wait>=Yard.REPORT_SECONDS and not y.reported then
            y.reported=true
            Watchdog.note(state,issue(vehicle),{status='STALLED',system='Shop yard protocol',
                subject=vehicle.trafficId,stage=y.stage,reason='No progress on the prescribed yard line',
                action='Stopped; checking the reserved checkpoint for recovery',detail=reason,
                elapsed=y.wait,x=vehicle.x,z=vehicle.z,visible=vehicle.visible~=false,scope='world-simulation'})
        end
        if y.wait>=Yard.RECOVERY_SECONDS then
            local recovered,detail=Yard.recover(vehicle,assignment,world,state)
            if not recovered then
                y.wait=Yard.REPORT_SECONDS
                Watchdog.note(state,issue(vehicle),{status='STALLED',system='Shop yard protocol',
                    subject=vehicle.trafficId,stage=y.stage,reason='Reserved recovery checkpoint is unavailable',
                    action=detail,x=vehicle.x,z=vehicle.z,visible=vehicle.visible~=false,scope='world-simulation'})
            end
        end
    end
    return false
end
return Yard
