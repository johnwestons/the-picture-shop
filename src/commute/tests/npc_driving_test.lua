-- Exercise the production follower and vehicle physics on measured flat roads.
local Network=require('src.commute.delivery_traffic')
local Truck=require('src.commute.delivery_truck')
local Bike=require('src.commute.motorcycle')
local Rules=require('src.commute.traffic_rules')
local Scheduled=require('src.commute.scheduled_driving')
local Test={}

local function road(ax,az,bx,bz,lanes,width,turnLane)
    local dx,dz=bx-ax,bz-az
    return {a={x=ax,z=az,h=0},b={x=bx,z=bz,h=0},dx=dx,dz=dz,
        length2=dx*dx+dz*dz,len=math.sqrt(dx*dx+dz*dz),lanes=lanes,width=width,
        turnLane=turnLane,surface='paved',role='main'}
end

local function flatWorld(segments,junctions,fixtures,side)
    local roads={segments=segments,bins={},junctions=junctions or {},junctionBins={},binSize=16}
    for ix=0,16 do for iz=0,16 do
        roads.bins[ix..':'..iz]=segments
        roads.junctionBins[ix..':'..iz]=roads.junctions
    end end
    function roads:nearest(x,z)
        local best,at,u=math.huge,nil,0
        for _,s in ipairs(segments) do
            local t=math.max(0,math.min(1,((x-s.a.x)*s.dx+(z-s.a.z)*s.dz)/s.length2))
            local distance=math.sqrt((x-s.a.x-t*s.dx)^2+(z-s.a.z-t*s.dz)^2)
            if distance<best then best,at,u=distance,s,t end
        end
        for _,j in ipairs(self.junctions) do
            local d=math.max(0,math.sqrt((x-j.x)^2+(z-j.z)^2)-j.outerRadius)
            if d<best then best,at,u=d,j,0 end
        end
        return best,at,u
    end
    function roads:sample(x,z)local d,s=self:nearest(x,z);return d,s,0 end
    function roads:blocked()return false end
    local world={roads=roads,town={trafficSide=side or 'right'},townId='driving-test',trafficActors={},
        infrastructure={fixtures=fixtures or {},blocksTruck=function()return false end,sweep=function()end}}
    function world:supportHeight()return 0,'road' end
    function world:height()return 0 end
    return world
end

local function vehicle(kind,x,z,heading,world)
    if kind~='bike' then return Truck.new(x,z,heading,'plain',kind) end
    local bike=Bike.new(x,z,heading)
    bike.trafficKind='motorcycle';bike.aiKind='motorcycle'
    Bike.resetContact(bike,world);Bike.resetHorizontal(bike)
    return bike
end

local function line(ax,az,bx,bz)
    local points={}
    local steps=math.ceil(math.sqrt((bx-ax)^2+(bz-az)^2)/3)
    for i=0,steps do points[#points+1]={x=ax+(bx-ax)*i/steps,z=az+(bz-az)*i/steps,h=0} end
    return points
end

function Test.run(check)
    local validation={}
    require('src.save_schema.primitives').install(validation)
    require('src.save_schema.paper').install(validation)
    local saved=Truck.new(20,60,0);saved.phase='approaching';saved.pathIndex=700
    local delivery={status='pending_arrival',route={vehicle=saved}}
    local denseRouteValid=validation.delivery(delivery)
    saved.pathIndex=4097
    check('npc_dense_route_cursor_saves_with_a_bounded_limit',denseRouteValid and not validation.delivery(delivery))
    for _,kind in ipairs({'box','kei','bike'}) do
        for _,dt in ipairs({.05,.1}) do
            local junction={x=80,z=60,junction=true,width=14,outerRadius=7,surface='paved'}
            local world=flatWorld({road(0,60,200,60,2,7.2),road(80,0,80,160,2,7.2)},{junction})
            local points=line(20,60,180,60)
            -- Authored guidance must not change the lane-following geometry.
            points[12].speedLimit=6.8
            local p=vehicle(kind,20,61.8,0,world)
            local error,maxSpeed,firstSecond,peakAcceleration=0,0,0,0
            for frame=1,math.floor(30/dt) do
                local before=p.speed
                Network.driveRoute(p,points,dt,world,'straight')
                error=math.max(error,math.abs(p.z-61.8))
                maxSpeed=math.max(maxSpeed,p.speed)
                peakAcceleration=math.max(peakAcceleration,(p.speed-before)/dt)
                if frame*dt<=1.001 then firstSecond=p.speed end
                if p.x>125 then break end
            end
            check('npc_'..kind..'_keeps_lane_through_junction_'..dt,
                p.x>125 and error<.35,
                ('x=%.2f laneError=%.3f'):format(p.x,error))
            check('npc_'..kind..'_uses_gentle_acceleration_and_cruise_'..dt,
                firstSecond>0 and firstSecond<1.7 and maxSpeed>5.5 and maxSpeed<7
                    and peakAcceleration<2.1,
                ('firstSecond=%.2f peak=%.2f acceleration=%.2f'):format(firstSecond,maxSpeed,peakAcceleration))
            local arrived=false
            for _=1,math.floor(25/dt) do
                if Network.driveRoute(p,points,dt,world,'straight') then arrived=true;break end
            end
            check('npc_'..kind..'_leaves_lane_to_stop_at_destination_'..dt,
                arrived and (p.x-180)^2+(p.z-60)^2<1 and p.speed<.3,
                ('arrived=%s x=%.2f z=%.2f speed=%.2f'):format(tostring(arrived),p.x,p.z,p.speed))

            world=flatWorld({road(0,60,220,60,2,7.2)},nil,{
                {kind='stop',stopX=80,stopZ=60,fx=-1,fz=0,roadWidth=7.2,junctionX=92,junctionZ=60},
                {kind='stop',stopX=140,stopZ=60,fx=-1,fz=0,roadWidth=7.2,junctionX=152,junctionZ=60}})
            points=line(20,60,200,60)
            p=vehicle(kind,20,61.8,0,world);p.speed=6.8
            if kind=='bike' then Bike.resetHorizontal(p) end
            local dwell={0,0};local crossed={false,false};local safe=true
            local minimumGap=math.huge
            for _=1,math.floor(65/dt) do
                Network.driveRoute(p,points,dt,world,'stops')
                for i,stopX in ipairs({80,140}) do
                    local gap=stopX-p.x-Rules.dimensions(p).halfLength
                    if not crossed[i] then
                        if p.speed<.05 and gap<.8 and gap>=0 then dwell[i]=dwell[i]+dt end
                        if dwell[i]<Rules.STOP_DWELL_SECONDS-.11 then minimumGap=math.min(minimumGap,gap) end
                        if gap<0 then crossed[i]=true;safe=safe and dwell[i]>=Rules.STOP_DWELL_SECONDS-.11 end
                    end
                end
                if crossed[2] then break end
            end
            check('npc_'..kind..'_fully_stops_at_successive_signs_'..dt,
                safe and crossed[2] and minimumGap>=0,
                ('dwell=%.2f/%.2f minGap=%.3f x=%.2f speed=%.2f'):format(dwell[1],dwell[2],minimumGap,p.x,p.speed))
        end
        local world=flatWorld({road(0,60,200,60,2,7.2)},nil,{
            {kind='stop',stopX=80,stopZ=60,fx=-1,fz=0,roadWidth=7.2,junctionX=92,junctionZ=60}})
        local points=line(20,60,180,60)
        local p=vehicle(kind,50,61.8,0,world)
        world.trafficActors={{kind='vehicle',actor=Truck.new(92,60,math.pi*.5)}}
        local waited=true;local laneError=0
        for _=1,260 do
            Network.driveRoute(p,points,.05,world,'occupied-junction')
            waited=waited and p.x+Rules.dimensions(p).halfLength<80
            laneError=math.max(laneError,math.abs(p.z-61.8))
        end
        waited=waited and p.speed<.05 and p.x>74
        world.trafficActors={}
        for _=1,100 do Network.driveRoute(p,points,.05,world,'occupied-junction') end
        check('npc_'..kind..'_waits_in_lane_for_occupied_junction',waited and laneError<.35 and p.x>80,
            ('waited=%s laneError=%.3f resumedX=%.2f'):format(tostring(waited),laneError,p.x))
        local scheduledRoute={points=points}
        local plan=Scheduled.sample(scheduledRoute,0,world,p)
        local pause,peak,laneError,lastX=0,0,0,0
        local monotonic=true
        for time=0,plan.duration,.05 do
            local pose=Scheduled.sample(scheduledRoute,time/plan.duration,world,p)
            peak=math.max(peak,pose.speed)
            monotonic=monotonic and pose.x>=lastX-.0001;lastX=pose.x
            if pose.x>35 and pose.x<145 then laneError=math.max(laneError,math.abs(pose.z-61.8)) end
            if pose.x>74 and pose.x+Rules.dimensions(p).halfLength<80 and pose.speed<.05 then pause=pause+.05 end
        end
        local finish=Scheduled.sample(scheduledRoute,1,world,p)
        check('scheduled_'..kind..'_shares_lanes_stops_and_variable_speed',
            plan.speed==0 and finish.speed==0 and math.abs(finish.x-180)<.001
                and pause>=.95 and peak<=6.8 and peak>5.5 and laneError<.35 and monotonic,
            ('pause=%.2f peak=%.2f laneError=%.3f duration=%.2f'):format(pause,peak,laneError,plan.duration))
        world=flatWorld({road(0,80,100,80,3,9.6,true),road(100,80,100,160,3,12,true)})
        points=line(20,80,100,80)
        local exit=line(100,80,100,140)
        for i=2,#exit do points[#points+1]=exit[i] end
        scheduledRoute={points=points};plan=Scheduled.sample(scheduledRoute,0,world,p)
        local lastX,lastZ=plan.x,plan.z
        local forward=true
        for time=.05,plan.duration,.05 do
            local pose=Scheduled.sample(scheduledRoute,time/plan.duration,world,p)
            forward=forward and pose.x>=lastX-.01 and pose.z>=lastZ-.01
            lastX,lastZ=pose.x,pose.z
        end
        check('scheduled_'..kind..'_joins_inside_corner_without_backtracking',forward)
        for _,direction in ipairs({-1,1}) do
            local finishZ=80+direction*60
            world=flatWorld({road(0,80,100,80,2,5.8),road(100,80,80,finishZ,2,5.8)},
                {{x=100,z=80,junction=true,width=14,outerRadius=7,surface='paved'}})
            points=line(20,80,100,80)
            local exit=line(100,80,80,finishZ)
            for i=2,#exit do points[#points+1]=exit[i] end
            p=vehicle(kind,20,81.45,0,world)
            local arrived,reversed=false,false
            for _=1,1200 do
                arrived=Network.driveRoute(p,points,.05,world,'tight-turn')
                reversed=reversed or p.reverse==true
                if arrived then break end
            end
            check('npc_'..kind..'_completes_tight_turn_without_circling_'..direction,
                arrived and not reversed,
                ('arrived=%s reversed=%s x=%.2f z=%.2f index=%d'):format(
                    tostring(arrived),tostring(reversed),p.x,p.z,p.pathIndex))
        end
        for _,side in ipairs({'right','left'}) do
            local turnDirection=side=='right' and -1 or 1
            local world=flatWorld({road(0,80,200,80,3,9.6,true),road(100,0,100,160,2,7.2)},
                {{x=100,z=80,junction=true,width=18,outerRadius=9,surface='paved'}},nil,side)
            local points=line(20,80,100,80)
            local outgoing=line(100,80,100,80+turnDirection*60)
            for i=2,#outgoing do points[#points+1]=outgoing[i] end
            local lane=side=='right' and 3.2 or -3.2
            local p=vehicle(kind,20,80+lane,0,world)
            local entered,joined,turnSpeed=false,false,0
            for _=1,1200 do
                Network.driveRoute(p,points,.05,world,'turn')
                if p.x>92 and p.x<99 and math.abs(p.z-80)<1.5 then entered=true end
                if math.abs(p.x-100)<5 and math.abs(p.z-80)<6 then turnSpeed=math.max(turnSpeed,p.speed) end
                if (p.z-80)*turnDirection>20 then
                    local wantedX=100+(side=='right' and 1 or -1)*(-turnDirection)*1.8
                    joined=math.abs(p.x-wantedX)<.8
                    break
                end
            end
            check('npc_'..kind..'_uses_center_turn_lane_'..side,entered and joined and turnSpeed<4.5,
                ('entered=%s joined=%s speed=%.2f pose=%.2f,%.2f'):format(tostring(entered),tostring(joined),turnSpeed,p.x,p.z))
        end
    end
end

return Test
