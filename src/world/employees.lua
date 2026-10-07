-- Employee reservations, applications, and work context.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
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

    function Runtime.World.employeeContext(state,assets)
        local options=Runtime.World._employeeOptions or {}
        local context={assets=assets}
        local function players()
            local result={Runtime.World.player}
            for _,p in ipairs(options.players and options.players() or {}) do result[#result+1]=p end
            return result
        end
        function context.obstacles(actor,excludedPalletId)
            local result={}
            for _,o in ipairs(Runtime.movementObstacles(state,false,{x=5,y=4},false,false,excludedPalletId)) do
                if o.actor~=actor then result[#result+1]=o end
            end
            for _,p in ipairs(players()) do result[#result+1]={x=p.x,y=p.y,radius=18} end
            return result
        end
        function context.receptionBusy()
            local technician=state.technicianVisit
            return Runtime.World.customer:isPresent() or Runtime.World.vendor:isPresent()
                or (technician and technician.visible) or Runtime.WarehouseConstruction.worker(state)~=nil
        end
        function context.canClaim(machineId)
            local pose=Runtime.MachineFleet.byId(state,machineId)
            pose=pose and (pose.world or state.cutter)
            return pose and not pose.moving and (not options.canClaim or options.canClaim(machineId))
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
            local point
            if avoidPoint then
                point=Runtime.EmployeeAI.findReachablePoint(worker,candidates,{
                    assets=assets,obstacles=function() return obstacles end})
            else
                point=candidates[1]
            end
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
        function context.palletDropPoint(machineId,worker,pallet)
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
            if cached and skidFootprintClear(cached.x,cached.y)
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
                        candidates[#candidates+1]={x=x,y=y}
                    end
                end
            end
            local point=Runtime.EmployeeAI.findReachablePoint(worker,candidates,{
                assets=assets,obstacles=function() return obstacles end})
            if point then worker._palletDropKey=key;worker._palletDropPoint=point end
            return point
        end
        function context.machinePalletDropPoint(machineId,worker,pallet,stage)
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
            if cached and inLoadZone(cached.x,cached.y) and skidFootprintClear(cached.x,cached.y) then return cached end
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
            local point=Runtime.EmployeeAI.findReachablePoint(worker,candidates,{
                assets=assets,obstacles=function() return obstacles end})
            if point then worker._machinePalletDropKey=key;worker._machinePalletDropPoint=point end
            return point
        end
        function context.palletEmergencyDropPoint(worker,pallet)
            local origin=pallet and pallet.world
            if origin then return {x=origin.x,y=origin.y,direction=origin.direction,rotation=origin.rotation} end
            return {x=worker.x,y=worker.y}
        end
        function context.idlePoint(worker)
            local n=tonumber(worker.id:match("(%d+)$")) or 1
            return {x=520+((n-1)%3)*28,y=505}
        end
        function context.seat(bayId)
            local room=Runtime.WarehouseLayout.bayState(state,bayId)
            if room and room.status=="complete" and room.optionId=="breakroom" then
                local seat=Runtime.WarehouseLayout.bay(bayId).restPoint;seat.bayId=bayId;return seat
            end
        end
        function context.freeSeat(worker)
            for _,bayId in ipairs(Runtime.WarehouseLayout.BAY_IDS) do
                local seat=context.seat(bayId)
                if seat then
                    local occupied=false
                    for _,w in ipairs(Runtime.Employees.ensure(state).staff) do if w~=worker and w.visible and w.seatBay==bayId then occupied=true end end
                    for _,p in ipairs(players()) do if (p.x-seat.x)^2+(p.y-seat.y)^2<30^2 then occupied=true end end
                    if not occupied and Runtime.Navigation.isWalkable(assets,seat.x,seat.y,context.obstacles(worker)) then return seat end
                end
            end
        end
        return context
    end
end

return Component
