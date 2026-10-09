-- Local and network player movement and spawning.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    local function roomMovementObstacles(state,sceneId,excludeJack)
        local Rooms=require("src.shop_rooms")
        local obstacles=Rooms.obstacles(state,sceneId)
        local jack=state and state.palletJack
        if not excludeJack and jack and jack.sceneId==sceneId then
            local obstacle=Runtime.PalletJack.obstacle(state,Runtime.Config.palletJack)
            if obstacle then obstacles[#obstacles+1]=obstacle end
        end
        for _,item in ipairs(Runtime.PalletLogistics.physicalPallets(state)) do
            local world=item.pallet.world
            if world and (world.sceneId or "warehouse")==sceneId
                and (not jack or item.pallet.id~=jack.carriedPalletId) then
                obstacles[#obstacles+1]={x=item.x,y=item.y-8,
                    halfWidth=Runtime.Config.palletLogistics.collisionHalfWidth,
                    halfHeight=Runtime.Config.palletLogistics.collisionHalfHeight,shape="diamond"}
            end
        end
        return obstacles
    end

    function Runtime.World.update(dt, directionX, directionY, assets, state, cursorX, cursorY, simulationDt)
        if require("src.shop_rooms").scene(Runtime.World.player)~="warehouse" then
            Runtime.World._assets,Runtime.World._state=assets,state
            local player=Runtime.World.player
            local jack=Runtime.PalletJack.ensure(state,Runtime.Config.palletJack)
            if jack.operating and jack.operatorPlayerId==(tonumber(player.id) or 1) then
                Runtime.World.updateNetworkPalletJack(player,dt,directionX,directionY,assets,state,cursorX,cursorY)
            else
                Runtime.updateWalkingPlayer(player,dt,directionX,directionY,assets,state)
            end
            local changed=Runtime.World.updateSimulation(simulationDt or dt,
                Runtime.WarehouseGameplay.assets(assets,state),state,dt)
            Runtime.World.selectedInteraction=Runtime.selectInteractionFor(Runtime.World.player,
                Runtime.World.selectedInteraction,cursorX,cursorY)
            return changed
        end
        assets = Runtime.WarehouseGameplay.assets(assets, state)
        Runtime.World._assets = assets
        if directionX ~= 0 or directionY ~= 0 then Runtime.World.placementSelection = nil end
        Runtime.World._state = state
        local player = Runtime.World.player
        local playerStartX, playerStartY = player.x, player.y
        local jack = Runtime.PalletJack.ensure(state, Runtime.Config.palletJack)
        local localOperatesJack = jack.operating and jack.operatorPlayerId == 1
        local localOperatesForklift = Runtime.Forklift.isOperator(state, Runtime.Config.forklift, tonumber(player.id) or 1)
        local externalMovement = localOperatesJack or localOperatesForklift
        if localOperatesForklift then
            Runtime.World.updateNetworkForklift(player, dt, directionX, directionY, assets, state)
        elseif localOperatesJack and Runtime.activeMachineKind(state) then
            Runtime.moveNetworkAttachedMachine(player, dt, directionX, directionY, assets, state)
        elseif localOperatesJack then
            Runtime.PalletJack.move(state, directionX, directionY, dt, Runtime.Config.palletJack, function(nextX, nextY, loaded)
                local inflate = loaded and {
                    x = Runtime.Config.palletJack.loadedCollisionHalfWidth,
                    y = Runtime.Config.palletJack.loadedCollisionHalfHeight, shape = "diamond",
                } or {
                    x = Runtime.Config.palletJack.collisionHalfWidth,
                    y = Runtime.Config.palletJack.collisionHalfHeight, shape = "diamond",
                }
                return Runtime.Navigation.canMoveAreaFrom(assets, jack.x, jack.y, nextX, nextY,
                    inflate.x, inflate.y, Runtime.movementObstacles(state, true, inflate))
            end)
            player.x, player.y = Runtime.PalletJack.operatorPosition(state, Runtime.Config.palletJack)
            player.moving = jack.moving
            player.facing = (jack.direction == "northeast" or jack.direction == "east"
                or jack.direction == "southeast") and 1 or -1
        else
            Runtime.updateWalkingPlayer(player, dt, directionX, directionY, assets, state)
        end
        if externalMovement and not localOperatesForklift then
            Runtime.PlayerController.observeExternalMove(player, playerStartX, playerStartY, player.moving, dt)
        end
        local saveNeeded = Runtime.World.updateSimulation(simulationDt or dt, assets, state, dt)
        Runtime.World.selectedInteraction = Runtime.selectInteractionFor(
            player, Runtime.World.selectedInteraction, cursorX, cursorY)
        return saveNeeded
    end

    function Runtime.World.updatePalletJackPresentation(state, dt, players, localPlayer)
        Runtime.PalletJack.updatePresentation(state, dt, Runtime.Config.palletJack)
        local jack = Runtime.PalletJack.ensure(state, Runtime.Config.palletJack)
        if not jack.operating then return end
        local x, y = Runtime.PalletJack.operatorPosition(state, Runtime.Config.palletJack)
        local function align(player)
            if player and player.id == jack.operatorPlayerId then
                player.x, player.y, player.moving = x, y, jack.moving
                player.facing = (jack.direction == "northeast" or jack.direction == "east"
                    or jack.direction == "southeast") and 1 or -1
            end
        end
        align(localPlayer)
        for _, player in ipairs(players or {}) do align(player) end
    end

    function Runtime.updateWalkingPlayer(player, dt, directionX, directionY, assets, state)
        if type(player) ~= "table" then return false end
        if player.resting and (math.abs(tonumber(directionX) or 0)>0.001
            or math.abs(tonumber(directionY) or 0)>0.001) then require("src.shop_rooms").stand(player) end
        assets = Runtime.WarehouseGameplay.assets(assets, state)
        local Rooms=require("src.shop_rooms")
        local sceneId=Rooms.scene(player)
        if sceneId~="warehouse" then assets=Rooms.assets(assets,sceneId,state) end
        -- Obstacles cannot change during one controller update. Share the same
        -- snapshot across its axis checks and collision substeps.
        local obstacles
        Runtime.PlayerController.update(player, directionX or 0, directionY or 0, dt,
            function(currentX, currentY, nextX, nextY)
                obstacles=obstacles or (sceneId~="warehouse" and roomMovementObstacles(state,sceneId)
                    or Runtime.movementObstacles(state, false))
                return Runtime.Navigation.canMoveFrom(assets, currentX, currentY, nextX, nextY,obstacles)
            end, Runtime.Config.player)
        return true
    end

    -- LAN guests predict only their own walking. Durable shop systems continue to
    -- run exclusively on the authoritative host.
    function Runtime.World.updateNetworkPlayer(dt, directionX, directionY, assets, state, cursorX, cursorY)
        assets = Runtime.WarehouseGameplay.assets(assets, state)
        Runtime.World._assets, Runtime.World._state = assets, state
        Runtime.World.placementSelection = nil
        local updated
        local jack=Runtime.PalletJack.ensure(state,Runtime.Config.palletJack)
        if Runtime.Forklift.isOperator(state, Runtime.Config.forklift, Runtime.World.player.id) then
            updated = Runtime.World.updateNetworkForklift(Runtime.World.player, dt, directionX, directionY, assets, state, true)
        elseif jack.operating and jack.operatorPlayerId==(tonumber(Runtime.World.player.id) or 1) then
            updated = Runtime.World.updateNetworkPalletJack(Runtime.World.player,dt,directionX,directionY,
                assets,state,cursorX,cursorY)
        else updated = Runtime.updateWalkingPlayer(Runtime.World.player, dt, directionX, directionY, assets, state) end
        Runtime.World.selectedInteraction = Runtime.selectNetworkInteractionFor(
            Runtime.World.player, Runtime.World.selectedInteraction, cursorX, cursorY)
        return updated
    end

    -- The host uses the same collision and gait controller for every connected
    -- worker, while leaving the original single-player World.player seam intact.
    function Runtime.World.updateNetworkPalletJack(
        player, dt, directionX, directionY, assets, state, cursorX, cursorY)
        if type(player) ~= "table" or type(state) ~= "table" then return false end
        local jack = Runtime.PalletJack.ensure(state, Runtime.Config.palletJack)
        local playerId=tonumber(player.id) or (player==Runtime.World.player and 1 or nil)
        if not Runtime.PalletJack.isOperator(state, Runtime.Config.palletJack, playerId) then return false end
        assets = Runtime.WarehouseGameplay.assets(assets, state)
        local Rooms=require("src.shop_rooms")
        local sceneId=Rooms.scene(player)
        if jack.sceneId~=sceneId then return false end
        if sceneId~="warehouse" then assets=Rooms.assets(assets,sceneId,state) end
        Runtime.World._assets, Runtime.World._state = assets, state
        local playerStartX, playerStartY = player.x, player.y
        if not Runtime.moveNetworkAttachedMachine(
            player, dt, directionX or 0, directionY or 0, assets, state)
        then
            Runtime.PalletJack.move(state, directionX or 0, directionY or 0, dt, Runtime.Config.palletJack,
                function(nextX, nextY, loaded)
                    local footprint = loaded and {
                        x = Runtime.Config.palletJack.loadedCollisionHalfWidth,
                        y = Runtime.Config.palletJack.loadedCollisionHalfHeight, shape = "diamond",
                    } or {
                        x = Runtime.Config.palletJack.collisionHalfWidth,
                        y = Runtime.Config.palletJack.collisionHalfHeight, shape = "diamond",
                    }
                    local obstacles=sceneId=="warehouse"
                        and Runtime.movementObstacles(state,true,footprint)
                        or roomMovementObstacles(state,sceneId,true)
                    return Runtime.Navigation.canMoveAreaFrom(assets, jack.x, jack.y, nextX, nextY,
                        footprint.x, footprint.y, obstacles)
                end)
            player.x, player.y = Runtime.PalletJack.operatorPosition(state, Runtime.Config.palletJack)
        end
        Runtime.PlayerController.observeExternalMove(
            player, playerStartX, playerStartY, jack.moving, dt)
        player.facing = (jack.direction == "northeast" or jack.direction == "east"
            or jack.direction == "southeast") and 1 or -1
        if player == Runtime.World.player then
            Runtime.World.selectedInteraction = Runtime.selectNetworkInteractionFor(
                player, Runtime.World.selectedInteraction, cursorX, cursorY)
        end
        return true
    end

    function Runtime.World.updateRemotePlayer(player, dt, directionX, directionY, assets, state)
        assets = Runtime.WarehouseGameplay.assets(assets, state)
        Runtime.World._assets, Runtime.World._state = assets, state
        if Runtime.Forklift.isOperator(state, Runtime.Config.forklift, player.id) then
            return Runtime.World.updateNetworkForklift(player, dt, directionX, directionY, assets, state)
        end
        local jack = type(state) == "table" and Runtime.PalletJack.ensure(state, Runtime.Config.palletJack) or nil
        if jack and jack.operating and jack.operatorPlayerId == player.id then
            return Runtime.World.updateNetworkPalletJack(
                player, dt, directionX, directionY, assets, state)
        end
        return Runtime.updateWalkingPlayer(player, dt, directionX, directionY, assets, state)
    end

    -- Find a nearby walkable guest start without trusting a fixed offset that may
    -- land across a mask edge or inside a moved machine/pallet.
    function Runtime.World.resolveNetworkSpawn(originX, originY, guestIndex, assets, state, players)
        assets, state = assets or Runtime.World._assets, state or Runtime.World._state
        assets = Runtime.WarehouseGameplay.assets(assets, state)
        originX, originY = tonumber(originX) or Runtime.Config.player.spawnX,
            tonumber(originY) or Runtime.Config.player.spawnY
        if not assets or not state then return originX, originY end

        local obstacles = Runtime.movementObstacles(state, false)
        for _, player in pairs(players or {}) do
            if type(player) == "table" and type(player.x) == "number" and type(player.y) == "number" then
                obstacles[#obstacles + 1] = { x = player.x, y = player.y, radius = 16 }
            end
        end
        local startingAngles = { [2] = 0, [3] = math.pi, [4] = math.pi / 2 }
        local start = startingAngles[tonumber(guestIndex)] or 0
        for _, radius in ipairs({ 32, 48, 64, 80 }) do
            for step = 0, 7 do
                local angle = start + step * math.pi / 4
                local candidateX = originX + math.cos(angle) * radius
                local candidateY = originY + math.sin(angle) * radius
                if Runtime.Navigation.isWalkable(assets, candidateX, candidateY, obstacles) then
                    return candidateX, candidateY
                end
            end
        end

        -- An exact overlap is preferable to trapping the guest off-mask. Normal
        -- movement separates overlapping workers immediately.
        if Runtime.Navigation.isWalkable(assets, originX, originY, {}) then return originX, originY end
        if Runtime.Navigation.isWalkable(assets, Runtime.Config.player.spawnX, Runtime.Config.player.spawnY, obstacles) then
            return Runtime.Config.player.spawnX, Runtime.Config.player.spawnY
        end
        return Runtime.Config.player.spawnX, Runtime.Config.player.spawnY
    end
end

return Component
