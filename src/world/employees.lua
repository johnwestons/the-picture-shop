-- Employee reservations, applications, and work context.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    local jackFloors=setmetatable({}, {__mode="k"})
    local exitContacts=setmetatable({}, {__mode="k"})
    function Runtime.World.configureEmployees(options) Runtime.World._employeeOptions=options or {} end

    function Runtime.World.employeeCutterReserved(state,machineId)
        local first=Runtime.MachineFleet.installedUnits(state,"polar_115")[1]
        return Runtime.Employees.reservation(state,machineId or (first and first.id))~=nil
    end
    function Runtime.World.employeeMachineReserved(state,machineId)
        return Runtime.Employees.reservation(state,machineId)~=nil
    end

    function Runtime.World.requestEmployeeResume(state,applicationId)
        local ok,message=Runtime.Employees.requestResume(state,applicationId,Runtime.BusinessCalendar.absoluteHours(state))
        state.message=message
        return ok
    end

    function Runtime.World.dismissApplicant(state,applicationId)
        local applicant=Runtime.Employees.application(state,applicationId)
        if not applicant or applicant.status~="visiting" or not applicant.actor.visible
            or applicant.actor.phase~="waiting" then
            state.message="That applicant is no longer waiting at reception."
            return false
        end
        local ok,message=Runtime.Employees.command(state,
            {kind="decline_application",applicationId=applicationId},
            Runtime.BusinessCalendar.absoluteHours(state))
        state.message=message
        return ok
    end

    function Runtime.World.employeeContext(state,assets)
        local options=Runtime.World._employeeOptions or {}
        local context={assets=Runtime.WarehouseGameplay.assets(assets,state)}
        assets=context.assets
        local function players()
            local result={Runtime.World.player}
            for _,p in ipairs(options.players and options.players() or {}) do result[#result+1]=p end
            return result
        end
        function context.obstacles(actor,excludedPalletId)
            local result={}
            local scene=actor and actor.sceneId or "warehouse"
            for _,o in ipairs(Runtime.movementObstacles(state,false,{x=5,y=4},false,false,excludedPalletId)) do
                if o.actor~=actor and (not o.actor or (o.actor.sceneId or "warehouse")==scene) then
                    result[#result+1]=o
                end
            end
            for _,p in ipairs(players()) do
                if p~=actor and (p.sceneId or "warehouse")==scene then
                    result[#result+1]={x=p.x,y=p.y,radius=18,actor=p}
                end
            end
            return result
        end
        function context.receptionBusy()
            local technician=state.technicianVisit
            return Runtime.World.customer:isPresent() or Runtime.World.vendor:isPresent()
                or (technician and technician.visible) or Runtime.WarehouseConstruction.worker(state)~=nil
        end
        function context.exitPoint(worker,dt)
            local primary=Runtime.Config.customer.route[1]
            if not Runtime.Config.warehouse.roomScenes then return primary end
            local cached=exitContacts[worker]
            local obstacles=context.obstacles(worker)
            if cached then
                cached.retry=math.max(0,cached.retry-(dt or .1))
                if Runtime.Navigation.isWalkable(assets,cached.goal.x,cached.goal.y,obstacles)
                    or cached.retry>0 then return cached.goal end
            end
            local goal
            if Runtime.Navigation.isWalkable(assets,primary.x,primary.y,obstacles) then goal=primary
            else goal=Runtime.EmployeeAI.findReachablePoint(worker,
                require("src.warehouse_registration").exitPoints,context) end
            goal=goal or primary
            exitContacts[worker]={goal=goal,retry=.75}
            return goal
        end
        function context.canClaim(machineId)
            local pose=Runtime.MachineFleet.byId(state,machineId)
            pose=pose and (pose.world or state.cutter)
            return pose and not pose.moving and (not options.canClaim or options.canClaim(machineId))
        end
        function context.jackNavigation(worker,excludedPalletId,loaded)
            local jack=Runtime.PalletJack.ensure(state,Runtime.Config.palletJack)
            loaded=loaded or jack.carriedPalletId~=nil
            local width=loaded and Runtime.Config.palletJack.loadedCollisionHalfWidth or Runtime.Config.palletJack.collisionHalfWidth
            local height=loaded and Runtime.Config.palletJack.loadedCollisionHalfHeight or Runtime.Config.palletJack.collisionHalfHeight
            local footprint={x=width,y=height,shape="diamond"}
            local floors=jackFloors[assets] or {}
            jackFloors[assets]=floors
            local floorKey=width..":"..height
            local routeAssets=floors[floorKey]
            if not routeAssets then
            routeAssets=setmetatable({}, {__index=assets})
            local mask=assets.getData("walkmask")
            local mw,mh=Runtime.Config.baseWidth,Runtime.Config.baseHeight
            if mask then mw,mh=mask:getDimensions() end
            local floorMask={}
            local cache={}
            function floorMask:getDimensions() return mw,mh end
            function floorMask:getPixel(px,py)
                local key=py*mw+px
                local value=cache[key]
                if value==nil then
                    value=Runtime.Navigation.isAreaWalkable(assets,px/mw*Runtime.Config.baseWidth,
                        py/mh*Runtime.Config.baseHeight,width,height) and 1 or 0
                    cache[key]=value
                end
                return value,value,value,1
            end
            routeAssets.getData=function(name) return name=="walkmask" and floorMask or assets.getData(name) end
            floors[floorKey]=routeAssets
            end
            return {assets=routeAssets,obstacles=function()
                local result={}
                for _,obstacle in ipairs(Runtime.movementObstacles(state,true,footprint,false,false,excludedPalletId)) do
                    if obstacle.actor~=worker then result[#result+1]=obstacle end
                end
                for _,p in ipairs(players()) do
                    if (p.sceneId or "warehouse")=="warehouse" then
                        result[#result+1]=Runtime.Footprint.expand({x=p.x,y=p.y,radius=18},footprint)
                    end
                end
                return result
            end}
        end
        function context.jackActor(worker)
            worker._jackNavigator=worker._jackNavigator or {}
            local jack=Runtime.PalletJack.ensure(state,Runtime.Config.palletJack)
            worker._jackNavigator.x,worker._jackNavigator.y=jack.x,jack.y
            return worker._jackNavigator
        end
        function context.jackApproachPoint(worker)
            local x,y=Runtime.PalletJack.operatorPosition(state,Runtime.Config.palletJack)
            local candidates={{x=x,y=y}}
            local jack=state.palletJack
            -- The previous operator's feet can end up beside another skid or
            -- machine after parking. Approach a clear side of the same handle.
            for index=0,15 do
                local angle=index*math.pi/8
                local radius=Runtime.Config.palletJack.interactionRadius*.98
                candidates[#candidates+1]={x=jack.x+math.cos(angle)*radius,y=jack.y+math.sin(angle)*radius}
            end
            return Runtime.EmployeeAI.findReachablePoint(worker,candidates,context)
        end
        function context.jackPickupPoint(worker,pallet)
            local origin=pallet.world
            if not origin then return nil end
            local candidates={}
            local loaded=context.jackNavigation(worker,pallet.id,true)
            local loadedObstacles=loaded.obstacles()
            for _,ratio in ipairs({.999,.85,.7}) do
                for index=0,15 do
                    local angle=index*math.pi/8
                    local radius=Runtime.Config.palletJack.pickupRadius*ratio
                    local x,y=origin.x+math.cos(angle)*radius,origin.y+math.sin(angle)*radius
                    if Runtime.Navigation.isWalkable(loaded.assets,x,y,loadedObstacles) then
                        candidates[#candidates+1]={x=x,y=y}
                    end
                end
            end
            return Runtime.EmployeeAI.findReachablePoint(context.jackActor(worker),candidates,
                context.jackNavigation(worker))
        end
        function context.jackLoadClear(worker,palletId,x,y)
            local nav=context.jackNavigation(worker,palletId,true)
            return Runtime.Navigation.isWalkable(nav.assets,x,y,nav.obstacles())
        end
        function context.jackDropClear(worker,palletId,x,y)
            local width,height=Runtime.Config.palletLogistics.collisionHalfWidth,Runtime.Config.palletLogistics.collisionHalfHeight
            if not Runtime.Navigation.isAreaWalkable(assets,x,y,width,height) then return false end
            local footprint={x=width,y=height,shape="diamond"}
            local jack=state.palletJack
            if jack and jack.operating and jack.operatorEmployeeId==worker.id then
                local clearance=Runtime.Footprint.expand({x=jack.x,y=jack.y-5,
                    halfWidth=Runtime.Config.palletJack.loadedCollisionHalfWidth,
                    halfHeight=Runtime.Config.palletJack.loadedCollisionHalfHeight,shape="diamond"},footprint)
                if Runtime.Footprint.penetration(clearance,x,y)>0 then return false end
            end
            for _,obstacle in ipairs(Runtime.movementObstacles(state,true,footprint,false,false,palletId)) do
                if obstacle.actor~=worker and Runtime.Footprint.penetration(obstacle,x,y)>0 then return false end
            end
            for _,p in ipairs(players()) do
                if (p.sceneId or "warehouse")=="warehouse"
                    and Runtime.Footprint.penetration(Runtime.Footprint.expand({x=p.x,y=p.y,radius=18},footprint),x,y)>0 then return false end
            end
            return true
        end
        function context.jackEmergencyDropPoint(worker)
            local jack=state.palletJack
            for _,distance in ipairs({0,36,72,108}) do
                for index=0,15 do
                    local angle=index*math.pi/8
                    local x,y=jack.x+math.cos(angle)*distance,jack.y+math.sin(angle)*distance
                    if context.jackDropClear(worker,jack.carriedPalletId,x,y) then return {x=x,y=y} end
                end
            end
        end
        function context.jackParkingPoint(worker)
            local route=context.jackNavigation(worker,nil,false)
            local obstacles=route.obstacles()
            local minimumClearance=24
            local function clear(x,y)
                if not Runtime.Navigation.isWalkable(route.assets,x,y,obstacles) then return false end
                for _,obstacle in ipairs(obstacles) do
                    if Runtime.Footprint.pointDistanceSquared(x,y,obstacle)<minimumClearance^2 then
                        return false
                    end
                end
                return true
            end
            local parking={x=Runtime.Config.palletJack.spawnX,y=Runtime.Config.palletJack.spawnY}
            if clear(parking.x,parking.y) then
                local point=Runtime.EmployeeAI.findReachablePoint(context.jackActor(worker),{parking},route)
                if point then return point end
            end
            local candidates={}
            for y=112,Runtime.Config.baseHeight-72,40 do
                for x=72,Runtime.Config.baseWidth-72,40 do
                    if clear(x,y) then candidates[#candidates+1]={x=x,y=y} end
                end
            end
            return Runtime.EmployeeAI.findReachablePoint(context.jackActor(worker),candidates,route)
        end
        function context.machinePose(machineId)
            local item=Runtime.MachineFleet.byId(state,machineId)
            if not item then return nil end
            if item.world then return item.world end
            if item.modelId=="polar_115" then return Runtime.CutterPlacement.ensure(state,Runtime.Config.cutterPlacement) end
            if item.modelId=="skid_wrapper" then return Runtime.WrapperPlacement.ensure(state,Runtime.Config.wrapperPlacement) end
            if item.modelId=="heidelberg_10x15" then return Runtime.WindmillPlacement.ensure(state,Runtime.Config.windmillPlacement) end
        end
        function context.operatorPoint(machineId,worker,avoidPoint)
            local item=Runtime.MachineFleet.byId(state,machineId)
            local pose=item and item.world
            if item and not pose then
                local key=item.modelId=="polar_115" and "cutter"
                    or item.modelId=="skid_wrapper" and "wrapper"
                    or item.modelId=="heidelberg_10x15" and "windmill"
                local config=key and Runtime.Config[key.."Placement"]
                if item.modelId=="polar_115" then pose=Runtime.CutterPlacement.ensure(state,config)
                elseif item.modelId=="skid_wrapper" then pose=Runtime.WrapperPlacement.ensure(state,config)
                elseif item.modelId=="heidelberg_10x15" then pose=Runtime.WindmillPlacement.ensure(state,config) end
            end
            if not pose or pose.moving then return nil end
            local obstacles=context.obstacles(worker)
            local key=string.format("%g:%g:%s",pose.x,pose.y,pose.direction)
            if not avoidPoint and worker._operatorKey==key and worker._operatorPoint
                and Runtime.Navigation.isWalkable(assets,worker._operatorPoint.x,worker._operatorPoint.y,obstacles) then return worker._operatorPoint end
            local signs={northwest={1,1},north={0,1},northeast={-1,1},east={-1,0},
                southeast={-1,-1},south={0,-1},southwest={1,-1},west={1,0}}
            local sign=signs[pose.direction] or signs.northwest
            local candidates={}
            for _,distance in ipairs({64,80,92}) do
                local sx,sy=sign[1],sign[2]
                local length=math.sqrt(sx*sx+sy*sy)
                local vx,vy=sx/length,sy/length
                for _,side in ipairs({0,-32,32,-48,48}) do
                    local x,y=pose.x+vx*distance-vy*side,pose.y+vy*distance+vx*side
                    if Runtime.Navigation.isWalkable(assets,x,y,obstacles)
                        and (not avoidPoint or (x-avoidPoint.x)^2+(y-avoidPoint.y)^2>4) then
                        candidates[#candidates+1]={x=x,y=y}
                    end
                end
            end
            local point=Runtime.EmployeeAI.findReachablePoint(worker,candidates,{
                assets=assets,obstacles=function() return obstacles end})
            if point then
                worker._operatorKey=key;worker._operatorPoint={x=point.x,y=point.y}
                return worker._operatorPoint
            end
        end
        function context.palletApproachPoint(pallet,worker)
            local origin=pallet and pallet.world
            if not origin then return nil end
            local key=table.concat({pallet.id,math.floor(origin.x),math.floor(origin.y)},":")
            local obstacles=context.obstacles(worker)
            if worker._palletApproachKey==key and worker._palletApproachPoint
                and Runtime.Navigation.isWalkable(assets,worker._palletApproachPoint.x,worker._palletApproachPoint.y,obstacles) then
                return worker._palletApproachPoint
            end
            local candidates={}
            for _,distance in ipairs({58,70,82}) do
                for _,direction in ipairs({{1,0},{1,1},{0,1},{-1,1},{-1,0},{-1,-1},{0,-1},{1,-1}}) do
                    local length=math.sqrt(direction[1]^2+direction[2]^2)
                    local x,y=origin.x+direction[1]/length*distance,origin.y+direction[2]/length*distance
                    if Runtime.Navigation.isWalkable(assets,x,y,obstacles) then candidates[#candidates+1]={x=x,y=y} end
                end
            end
            local point=Runtime.EmployeeAI.findReachablePoint(worker,candidates,{
                assets=assets,obstacles=function() return obstacles end})
            if point then worker._palletApproachKey=key;worker._palletApproachPoint=point end
            return point
        end
        function context.palletDropPoint(machineId,worker,pallet,forJack)
            local item=Runtime.MachineFleet.byId(state,machineId)
            local wrapper=item and item.world
            if item and not wrapper then wrapper=Runtime.WrapperPlacement.ensure(state,Runtime.Config.wrapperPlacement) end
            if not wrapper or wrapper.moving then return nil end
            local key=table.concat({machineId,math.floor(wrapper.x),math.floor(wrapper.y),wrapper.direction or ""},":")
            local obstacles=context.obstacles(worker)
            local function skidFootprintClear(x,y)
                local width,height=Runtime.Config.palletLogistics.collisionHalfWidth,Runtime.Config.palletLogistics.collisionHalfHeight
                if not Runtime.Navigation.isAreaWalkable(assets,x,y,width,height) then return false end
                local skid={x=width,y=height,shape="diamond"}
                for _,obstacle in ipairs(obstacles) do
                    if Runtime.Footprint.penetration(Runtime.Footprint.expand(obstacle,skid),x,y)>0 then return false end
                end
                return true
            end
            local cached=worker._palletDropKey==key and worker._palletDropPoint
            if not forJack and cached and skidFootprintClear(cached.x,cached.y)
                and Runtime.Footprint.distanceSquared(Runtime.Footprint.at(wrapper.x,wrapper.y,Runtime.Config.wrapperPlacement),
                    Runtime.Footprint.at(cached.x,cached.y,Runtime.Config.palletLogistics))<=Runtime.Config.wrapperPlacement.palletReach^2 then
                return cached
            end
            local candidates={}
            for _,distance in ipairs({56,70,84,98,112,126,140}) do
                for _,direction in ipairs({{1,0},{1,1},{0,1},{-1,1},{-1,0},{-1,-1},{0,-1},{1,-1}}) do
                    local length=math.sqrt(direction[1]^2+direction[2]^2)
                    local x,y=wrapper.x+direction[1]/length*distance,wrapper.y+direction[2]/length*distance
                    if skidFootprintClear(x,y)
                        and Runtime.Footprint.distanceSquared(Runtime.Footprint.at(wrapper.x,wrapper.y,Runtime.Config.wrapperPlacement),
                            Runtime.Footprint.at(x,y,Runtime.Config.palletLogistics))<=Runtime.Config.wrapperPlacement.palletReach^2 then
                        if forJack then
                            -- A route goal is the jack's wheelbase, while the
                            -- pallet lands at its direction-dependent fork tip.
                            -- Plan from the real pallet position back to a jack
                            -- pose, and carry the intended final facing with it.
                            for _,facing in ipairs({"northwest","north","northeast","east",
                                "southeast","south","southwest","west"}) do
                                local offsetX,offsetY=Runtime.PalletJack.dropOffset(facing)
                                candidates[#candidates+1]={x=x-offsetX,y=y-offsetY,
                                    dropDirection=facing,dropX=x,dropY=y}
                            end
                        else
                            candidates[#candidates+1]={x=x,y=y}
                        end
                    end
                end
            end
            local routeContext=forJack and context.jackNavigation(worker,pallet.id,true)
                or {assets=assets,obstacles=function() return obstacles end}
            local point=Runtime.EmployeeAI.findReachablePoint(forJack and context.jackActor(worker) or worker,candidates,routeContext)
            if point and forJack then
                for _,candidate in ipairs(candidates) do
                    if math.abs(point.x-candidate.x)<.01 and math.abs(point.y-candidate.y)<.01 then
                        point.dropDirection=candidate.dropDirection
                        point.dropX,point.dropY=candidate.dropX,candidate.dropY
                        break
                    end
                end
            end
            if point then worker._palletDropKey=key;worker._palletDropPoint=point end
            return point
        end
        function context.machinePalletDropPoint(machineId,worker,pallet,stage,forJack)
            local item=Runtime.MachineFleet.byId(state,machineId)
            if not item then return nil end
            local pose=item.world
            if not pose then
                Runtime.MachineFleet.withUnit(state,machineId,function()
                    if item.modelId=="polar_115" then pose=Runtime.CutterPlacement.ensure(state,Runtime.Config.cutterPlacement)
                    elseif item.modelId=="heidelberg_10x15" then pose=Runtime.WindmillPlacement.ensure(state,Runtime.Config.windmillPlacement) end
                end)
            end
            if not pose or pose.moving then return nil end
            local cutter=stage=="cutter" and item.modelId=="polar_115"
            local press=stage=="press" and item.modelId=="heidelberg_10x15"
            if not cutter and not press then return nil end
            local baseX,baseY=pose.x,pose.y
            if cutter then
                Runtime.MachineFleet.withUnit(state,machineId,function()
                    baseX,baseY=Runtime.CutterZones.inputAnchor(state,Runtime.Config.cutterPlacement)
                end)
            end
            local key=table.concat({machineId,stage,math.floor(pose.x),math.floor(pose.y),pose.direction or ""},":")
            local obstacles=context.obstacles(worker,pallet and pallet.id)
            local function inLoadZone(x,y)
                if cutter then
                    local accepted=false
                    Runtime.MachineFleet.withUnit(state,machineId,function()
                        accepted=Runtime.CutterZones.inInputZone(state,{world={x=x,y=y}},Runtime.Config.cutterPlacement,
                            Runtime.Config.cutterPlacement.palletInputZoneRadius)
                    end)
                    return accepted
                end
                return Runtime.Footprint.distanceSquared(Runtime.Footprint.at(pose.x,pose.y,Runtime.Config.windmillPlacement),
                    Runtime.Footprint.at(x,y,Runtime.Config.palletLogistics))<=Runtime.Config.windmillPlacement.palletReach^2
            end
            local function skidFootprintClear(x,y)
                local width,height=Runtime.Config.palletLogistics.collisionHalfWidth,Runtime.Config.palletLogistics.collisionHalfHeight
                if not Runtime.Navigation.isAreaWalkable(assets,x,y,width,height) then return false end
                local skid={x=width,y=height,shape="diamond"}
                for _,obstacle in ipairs(obstacles) do
                    if Runtime.Footprint.penetration(Runtime.Footprint.expand(obstacle,skid),x,y)>0 then return false end
                end
                return true
            end
            local cached=worker._machinePalletDropKey==key and worker._machinePalletDropPoint
            if not forJack and cached and inLoadZone(cached.x,cached.y) and skidFootprintClear(cached.x,cached.y) then return cached end
            local candidates,seen={},{}
            local function add(x,y)
                local token=string.format("%.2f,%.2f",x,y)
                if not seen[token] and inLoadZone(x,y) and skidFootprintClear(x,y) then
                    seen[token]=true;candidates[#candidates+1]={x=x,y=y}
                end
            end
            local directions={{1,0},{1,1},{0,1},{-1,1},{-1,0},{-1,-1},{0,-1},{1,-1}}
            if cutter then
                for _,distance in ipairs({0,20,40,60,80,100,120,140,160,180}) do
                    for _,direction in ipairs(directions) do
                        local length=math.sqrt(direction[1]^2+direction[2]^2)
                        add(baseX+direction[1]/length*distance,baseY+direction[2]/length*distance)
                    end
                end
            else
                for _,distance in ipairs({80,88,96,104,112,120,128,136,144,152}) do
                    for _,direction in ipairs(directions) do
                        local length=math.sqrt(direction[1]^2+direction[2]^2)
                        add(baseX+direction[1]/length*distance,baseY+direction[2]/length*distance)
                    end
                end
            end
            local routeContext=forJack and context.jackNavigation(worker,pallet.id,true)
                or {assets=assets,obstacles=function() return obstacles end}
            local point=Runtime.EmployeeAI.findReachablePoint(forJack and context.jackActor(worker) or worker,candidates,routeContext)
            if point then worker._machinePalletDropKey=key;worker._machinePalletDropPoint=point end
            return point
        end
        function context.palletEmergencyDropPoint(worker,pallet)
            local origin=pallet and pallet.world
            if origin then return {x=origin.x,y=origin.y,direction=origin.direction,rotation=origin.rotation} end
            return {x=worker.x,y=worker.y}
        end
        function context.jackDropPoint(machineId,worker,pallet,stage)
            if stage=="wrapping" then return context.palletDropPoint(machineId,worker,pallet,true) end
            return context.machinePalletDropPoint(machineId,worker,pallet,stage,true)
        end
        function context.idlePoint(worker)
            local n=tonumber(worker.id:match("(%d+)$")) or 1
            return {x=520+((n-1)%3)*28,y=505}
        end
        function context.seat(bayId)
            local room=Runtime.WarehouseLayout.bayState(state,bayId)
            if room and room.status=="complete" and room.optionId=="breakroom" then
                local entrance=require("src.shop_rooms").entrance
                return {x=entrance.x,y=entrance.y+20,bayId=bayId}
            end
        end
        function context.freeSeat(worker)
            for _,bayId in ipairs(Runtime.WarehouseLayout.BAY_IDS) do
                local seat=context.seat(bayId)
                if seat then
                    local occupied=false
                    for _,w in ipairs(Runtime.Employees.ensure(state).staff) do if w~=worker and w.visible and w.seatBay==bayId then occupied=true end end
                    local Rooms=require("src.shop_rooms")
                    for _,p in ipairs(players()) do
                        local contact=Rooms.seats[3]
                        if Rooms.scene(p)==bayId and p.resting and (p.x-contact.x)^2+(p.y-contact.y)^2<30^2 then occupied=true end
                    end
                    if not occupied and Runtime.Navigation.isWalkable(assets,seat.x,seat.y,context.obstacles(worker)) then return seat end
                end
            end
        end
        return context
    end
end

return Component
