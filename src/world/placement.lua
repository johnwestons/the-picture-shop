-- Movement obstacles and placement validation.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.movementObstacles(state, excludeJack, inflate, excludeCutter, excludeWrapper,
        excludedPalletId, excludeWindmill, excludeForklift)
        inflate = inflate or { x = 0, y = 0 }
        if type(inflate) == "number" then inflate = { x = inflate, y = inflate } end
        local obstacles = {}
        local activeKind, activePose = Runtime.MachineTransport.active(state)
        -- Moving an extra unit must still collide with the original machine.
        if activePose and activePose ~= state[activeKind] then
            excludeCutter, excludeWrapper, excludeWindmill = false, false, false
        end
        local firstCutter = Runtime.MachineFleet.installedUnits(state, "polar_115")[1]
        local firstWrapper = Runtime.MachineFleet.installedUnits(state, "skid_wrapper")[1]
        local firstWindmill = Runtime.MachineFleet.installedUnits(state, "heidelberg_10x15")[1]
        if not excludeCutter and firstCutter and not firstCutter.world then
            local cutterObstacle = Runtime.CutterPlacement.obstacle(state, Runtime.Config.cutterPlacement)
            if cutterObstacle then obstacles[#obstacles + 1] = cutterObstacle end
        end
        if not excludeWrapper and firstWrapper and not firstWrapper.world then
            local wrapperObstacle = Runtime.WrapperPlacement.obstacle(state, Runtime.Config.wrapperPlacement)
            if wrapperObstacle then obstacles[#obstacles + 1] = wrapperObstacle end
        end
        if not excludeWindmill and firstWindmill and not firstWindmill.world then
            local pressObstacle = Runtime.WindmillPlacement.obstacle(state, Runtime.Config.windmillPlacement)
            if pressObstacle then obstacles[#obstacles + 1] = pressObstacle end
        end
        for _, item in ipairs(Runtime.MachineFleet.installedUnits(state)) do
            if item.world and not item.world.moving then
                local config = Runtime.Config[Runtime.MachineFleet.definition(item.modelId).placementKey .. "Placement"]
                obstacles[#obstacles + 1] = Runtime.Footprint.at(item.world.x, item.world.y, config)
            end
        end
        local customerObstacle = Runtime.World.customer:getObstacle()
        if customerObstacle then obstacles[#obstacles + 1] = customerObstacle end
        local vendorObstacle = Runtime.World.vendor:getObstacle()
        if vendorObstacle then obstacles[#obstacles + 1] = vendorObstacle end
        local technicianObstacle = Runtime.Technician.obstacle(state)
        if technicianObstacle then obstacles[#obstacles + 1] = technicianObstacle end
        local truckObstacle = Runtime.World.truck:getObstacle()
        if truckObstacle then obstacles[#obstacles + 1] = truckObstacle end
        for _, obstacle in ipairs(Runtime.PalletLogistics.obstacles(state,
            Runtime.Config.palletLogistics.collisionHalfWidth,
            Runtime.Config.palletLogistics.collisionHalfHeight,
            excludedPalletId)) do
            if not obstacle.palletSceneId or obstacle.palletSceneId=="warehouse" then
                obstacles[#obstacles + 1] = obstacle
            end
        end
        if not excludeJack and (not state.palletJack or (state.palletJack.sceneId or "warehouse")=="warehouse") then
            local jackObstacle = Runtime.PalletJack.obstacle(state, Runtime.Config.palletJack)
            if jackObstacle then obstacles[#obstacles + 1] = jackObstacle end
        end
        if not excludeForklift then
            local liftObstacle = Runtime.Forklift.obstacle(state, Runtime.Config.forklift)
            if liftObstacle then obstacles[#obstacles + 1] = liftObstacle end
        end
        for _, obstacle in ipairs(Runtime.WarehouseLayout.obstacles(state)) do obstacles[#obstacles + 1] = obstacle end
        local builder = Runtime.WarehouseConstruction.worker(state)
        if builder then obstacles[#obstacles + 1] = {x=builder.x,y=builder.y,radius=14,kind="construction_worker"} end
        for _,entry in ipairs(Runtime.Employees.actors(state)) do
            if require("src.shop_rooms").employeeScene(entry)=="warehouse" then
                obstacles[#obstacles+1]={x=entry.actor.x,y=entry.actor.y,radius=14,kind="employee",actor=entry.actor}
            end
        end
        if inflate.x > 0 or inflate.y > 0 then
            for index, obstacle in ipairs(obstacles) do
                obstacles[index] = Runtime.Footprint.expand(obstacle, inflate)
            end
        end
        return obstacles
    end

    function Runtime.placementConfig(kind)
        return kind == "pallet" and Runtime.Config.palletLogistics
            or kind == "cutter" and Runtime.Config.cutterPlacement
            or kind == "wrapper" and Runtime.Config.wrapperPlacement or Runtime.Config.windmillPlacement
    end

    function Runtime.placementValidator(state, assets, kind, excludedPalletId, sceneOverride)
        assets = Runtime.WarehouseGameplay.assets(assets or Runtime.World._assets, state)
        local config = Runtime.placementConfig(kind)
        local Rooms=require("src.shop_rooms")
        local sceneId=sceneOverride or Rooms.scene(Runtime.World.player)
        local obstacles
        if sceneId~="warehouse" and kind=="pallet" then
            assets=Rooms.assets(assets,sceneId,state)
            obstacles=Rooms.obstacles(state,sceneId)
            for _,item in ipairs(Runtime.PalletLogistics.physicalPallets(state)) do
                local world=item.pallet.world
                if item.pallet.id~=excludedPalletId and world
                    and (world.sceneId or "warehouse")==sceneId then
                    obstacles[#obstacles+1]={x=item.x,y=item.y-8,
                        halfWidth=Runtime.Config.palletLogistics.collisionHalfWidth,
                        halfHeight=Runtime.Config.palletLogistics.collisionHalfHeight,shape="diamond"}
                end
            end
            local jack=state and state.palletJack
            if jack and jack.sceneId==sceneId then
                local obstacle=Runtime.PalletJack.obstacle(state,Runtime.Config.palletJack)
                if obstacle then obstacles[#obstacles+1]=obstacle end
            end
        else
            obstacles = Runtime.movementObstacles(state, kind ~= "pallet", {
                x=config.collisionHalfWidth,y=config.collisionHalfHeight,shape="diamond",
            }, kind == "cutter", kind == "wrapper", excludedPalletId, kind == "windmill")
        end
        return function(x,y)
            local floor = Runtime.Footprint.at(x,y,config)
            return assets and Runtime.Navigation.isAreaWalkable(assets, floor.x, floor.y,
                floor.halfWidth, floor.halfHeight)
                and Runtime.Navigation.isWalkable(assets, floor.x, floor.y, obstacles) == true
        end
    end

    function Runtime.World.isPalletPlacementClear(state, assets, x, y, excludedPalletId, sceneId)
        return Runtime.placementValidator(state,assets,"pallet",excludedPalletId,sceneId)(x,y)
    end

    function Runtime.isMachinePlacementClear(state, assets, kind, x, y)
        return Runtime.placementValidator(state,assets,kind)(x,y)
    end

    function Runtime.activeMachineKind(state)
        return Runtime.MachineTransport.active(state)
    end

    function Runtime.World.movingMachine(state)
        return Runtime.MachineTransport.active(state)
    end

    function Runtime.moveNetworkAttachedMachine(player, dt, directionX, directionY, assets, state)
        local kind = Runtime.activeMachineKind(state)
        if not kind then return false end
        local placement = kind == "cutter" and Runtime.CutterPlacement
            or kind == "wrapper" and Runtime.WrapperPlacement or Runtime.WindmillPlacement
        local config = kind == "cutter" and Runtime.Config.cutterPlacement
            or kind == "wrapper" and Runtime.Config.wrapperPlacement or Runtime.Config.windmillPlacement
        local _, _, unit = Runtime.MachineTransport.active(state)
        local moveState = Runtime.MachineTransport.view(state, kind, unit)
        local item = placement.ensure(moveState, config)
        if directionX ~= 0 or directionY ~= 0 then Runtime.World.placementSelection = nil end
        placement.move(moveState, directionX, directionY, dt, config, function(nextX, nextY)
            local halfWidth, halfHeight = config.collisionHalfWidth, config.collisionHalfHeight
            local obstacles = Runtime.movementObstacles(state, false, {
                x = halfWidth, y = halfHeight, shape = "diamond",
            }, kind == "cutter", kind == "wrapper", nil, kind == "windmill")
            if kind == "windmill"
                and not Runtime.Navigation.isAreaWalkable(assets, item.x, item.y, 0, 0)
            then
                return nextX > halfWidth and nextX < Runtime.Config.baseWidth - halfWidth
                    and nextY > halfHeight and nextY < Runtime.Config.baseHeight - halfHeight
            end
            if Runtime.Navigation.canMoveAreaFrom(assets, item.x, item.y, nextX, nextY,
                halfWidth, halfHeight, obstacles)
            then return true end
            if kind == "windmill"
                and not Runtime.Navigation.isAreaWalkable(assets, item.x, item.y, halfWidth, halfHeight)
            then
                return Runtime.Navigation.canMoveFrom(assets, item.x, item.y, nextX, nextY, obstacles)
                    and Runtime.Navigation.isAreaWalkable(assets, nextX, nextY, 0, 0)
            end
            return false
        end)
        Runtime.PalletJack.followPlacement(state, item, dt, Runtime.Config.palletJack)
        player.x, player.y = Runtime.PalletJack.operatorPosition(state, Runtime.Config.palletJack)
        player.moving = item.inMotion
        player.facing = player.x < item.x and 1 or -1
        return true
    end

    function Runtime.activePlacement(state)
        local networkMachineView = state and state._networkMachinePoses ~= nil
        local jack = state and Runtime.PalletJack.ensure(state, Runtime.Config.palletJack)
        local localPlayerId = tonumber(Runtime.World.player.id) or 1
        local localGuestControlsMachine = networkMachineView and jack and jack.operating
            and localPlayerId >= 2 and jack.operatorPlayerId == localPlayerId
            and Runtime.activeMachineKind(state) ~= nil
        local kind, item = Runtime.MachineTransport.active(state)
        if kind and (not networkMachineView or localGuestControlsMachine) then
            return kind, item.x, item.y
        end
        if jack and jack.operating and jack.carriedPalletId then
            local x, y = Runtime.PalletJack.dropPosition(state, Runtime.Config.palletJack)
            return "pallet", x, y
        end
    end

    function Runtime.World.placementGridSnapshot(state, assets, sceneOverride)
        local kind, centerX, centerY = Runtime.activePlacement(state)
        if not kind then Runtime.World.placementSelection = nil; return nil end
        assets = assets or Runtime.World._assets
        local carriedId = kind == "pallet" and state.palletJack.carriedPalletId or nil
        local cells, snappedX, snappedY = Runtime.PlacementGrid.cells(
            centerX, centerY, Runtime.Config.placementGrid,
            Runtime.placementValidator(state,assets,kind,carriedId,sceneOverride))
        local selected = Runtime.World.placementSelection
        if not selected or selected.kind ~= kind then
            selected = nil
            local cell = Runtime.PlacementGrid.nearestValid(cells, snappedX, snappedY,
                Runtime.Config.placementGrid.autoSelectRadius)
            if cell then selected = {kind=kind,x=cell.x,y=cell.y} end
        else
            local cell = Runtime.PlacementGrid.find(cells,selected.x,selected.y)
            if not cell or not cell.valid then selected = nil end
        end
        return { kind=kind,cells=cells,selected=selected,config=Runtime.Config.placementGrid,
            footprint=selected and Runtime.Footprint.at(selected.x,selected.y,Runtime.placementConfig(kind)) }
    end

    function Runtime.World.selectPlacement(state, assets, x, y, readOnly)
        local snapshot = Runtime.World.placementGridSnapshot(state, assets)
        if not snapshot then return false end
        local cell = Runtime.PlacementGrid.hit(snapshot.cells, x, y, snapshot.config)
        if not cell then return false end
        if not cell.valid then
            state.message = "That red grid space is blocked. Choose a green space."
            return true
        end
        Runtime.World.placementSelection = { kind = snapshot.kind, x = cell.x, y = cell.y }
        state.message = snapshot.kind == "pallet"
            and "Placement selected. Press L to lower the skid, or choose another green space."
            or "Placement selected. Press E to set it down, or choose another green space."
        return true
    end

    function Runtime.World.findCutterOutput(state, assets, excludedPalletId)
        return Runtime.CutterStaging.find(function(x, y)
            if not Runtime.World.isPalletPlacementClear(state, assets, x, y, excludedPalletId) then return false end
            for _,unit in ipairs(Runtime.MachineFleet.installedUnits(state,"polar_115")) do
                local machine=Runtime.Machine.forId(unit.id)
                if machine.pendingOutput and machine.pallet and machine.pallet.id~=excludedPalletId
                    and Runtime.Footprint.distanceSquared(Runtime.Footprint.at(x,y,Runtime.Config.palletLogistics),
                        Runtime.Footprint.at(machine.pendingOutput.x,machine.pendingOutput.y,Runtime.Config.palletLogistics))<.01 then return false end
            end
            return true
        end)
    end
end

return Component
