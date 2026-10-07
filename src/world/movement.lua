-- Local and network player movement and spawning.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.World.update(dt, directionX, directionY, assets, state, cursorX, cursorY, simulationDt)
        assets = Runtime.WarehouseGameplay.assets(assets, state)
        Runtime.World._assets = assets
        if directionX ~= 0 or directionY ~= 0 then Runtime.World.placementSelection = nil end
        Runtime.World._state = state
        local player = Runtime.World.player
        local playerStartX, playerStartY = player.x, player.y
        local jack = Runtime.PalletJack.ensure(state, Runtime.Config.palletJack)
        local cutter = Runtime.CutterPlacement.ensure(state, Runtime.Config.cutterPlacement)
        local wrapper = Runtime.WrapperPlacement.ensure(state, Runtime.Config.wrapperPlacement)
        local windmill = Runtime.WindmillPlacement.ensure(state, Runtime.Config.windmillPlacement)
        local localOperatesJack = jack.operating and jack.operatorPlayerId == 1
        local localOperatesForklift = Runtime.Forklift.isOperator(state, Runtime.Config.forklift, tonumber(player.id) or 1)
        local externalMovement = localOperatesJack or localOperatesForklift
        if localOperatesForklift then
            Runtime.World.updateNetworkForklift(player, dt, directionX, directionY, assets, state)
        elseif localOperatesJack and cutter.moving then
            Runtime.CutterPlacement.move(state, directionX, directionY, dt, Runtime.Config.cutterPlacement,
                function(nextX, nextY)
                    local halfWidth = Runtime.Config.cutterPlacement.collisionHalfWidth
                    local halfHeight = Runtime.Config.cutterPlacement.collisionHalfHeight
                    local obstacles = Runtime.movementObstacles(state, false,
                        { x = halfWidth, y = halfHeight, shape = "diamond" }, true)
                    return Runtime.Navigation.canMoveAreaFrom(assets, cutter.x, cutter.y, nextX, nextY,
                        halfWidth, halfHeight, obstacles)
                end)
            Runtime.PalletJack.followPlacement(state, cutter, dt, Runtime.Config.palletJack)
            player.x, player.y = Runtime.PalletJack.operatorPosition(state, Runtime.Config.palletJack)
            player.moving = cutter.inMotion
            player.facing = player.x < cutter.x and 1 or -1
        elseif localOperatesJack and wrapper.moving then
            Runtime.WrapperPlacement.move(state, directionX, directionY, dt, Runtime.Config.wrapperPlacement,
                function(nextX, nextY)
                    local halfWidth = Runtime.Config.wrapperPlacement.collisionHalfWidth
                    local halfHeight = Runtime.Config.wrapperPlacement.collisionHalfHeight
                    return Runtime.Navigation.canMoveAreaFrom(assets, wrapper.x, wrapper.y, nextX, nextY,
                        halfWidth, halfHeight, Runtime.movementObstacles(state, false, {
                            x = Runtime.Config.wrapperPlacement.collisionHalfWidth,
                            y = Runtime.Config.wrapperPlacement.collisionHalfHeight,
                            shape = "diamond",
                        }, false, true))
                end)
            Runtime.PalletJack.followPlacement(state, wrapper, dt, Runtime.Config.palletJack)
            player.x, player.y = Runtime.PalletJack.operatorPosition(state, Runtime.Config.palletJack)
            player.moving = wrapper.inMotion
            player.facing = player.x < wrapper.x and 1 or -1
        elseif localOperatesJack and windmill.moving then
            Runtime.WindmillPlacement.move(state, directionX, directionY, dt, Runtime.Config.windmillPlacement,
                function(nextX, nextY)
                    local halfWidth = Runtime.Config.windmillPlacement.collisionHalfWidth
                    local halfHeight = Runtime.Config.windmillPlacement.collisionHalfHeight
                    local obstacles = Runtime.movementObstacles(state, false, {
                        x = halfWidth, y = halfHeight, shape = "diamond",
                    }, false, false, nil, true)
                    if not Runtime.Navigation.isAreaWalkable(assets, windmill.x, windmill.y, 0, 0) then
                        -- The original spawn used an old floor mask and can sit on
                        -- a newly blocked pixel. Permit controlled recovery motion
                        -- until the machine center reaches the current walkable
                        -- factory floor again.
                        return nextX > halfWidth and nextX < Runtime.Config.baseWidth - halfWidth
                            and nextY > halfHeight and nextY < Runtime.Config.baseHeight - halfHeight
                    end
                    if Runtime.Navigation.canMoveAreaFrom(assets, windmill.x, windmill.y, nextX, nextY,
                        halfWidth, halfHeight, obstacles)
                    then return true end
                    -- Older/default placements can begin partly inside the edge of
                    -- the walk mask. Let the operator move the machine's center
                    -- toward open floor until its full footprint clears the edge.
                    if not Runtime.Navigation.isAreaWalkable(assets, windmill.x, windmill.y,
                        halfWidth, halfHeight)
                    then
                        return Runtime.Navigation.canMoveFrom(assets, windmill.x, windmill.y,
                            nextX, nextY, obstacles)
                            and Runtime.Navigation.isAreaWalkable(assets, nextX, nextY, 0, 0)
                    end
                    return false
                end)
            Runtime.PalletJack.followPlacement(state, windmill, dt, Runtime.Config.palletJack)
            player.x, player.y = Runtime.PalletJack.operatorPosition(state, Runtime.Config.palletJack)
            player.moving = windmill.inMotion
            player.facing = player.x < windmill.x and 1 or -1
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
            Runtime.PlayerController.update(player, directionX, directionY, dt,
                function(currentX, currentY, nextX, nextY)
                    return Runtime.Navigation.canMoveFrom(assets, currentX, currentY, nextX, nextY,
                        Runtime.movementObstacles(state, false))
                end, Runtime.Config.player)
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
            or math.abs(tonumber(directionY) or 0)>0.001) then player.resting=false end
        assets = Runtime.WarehouseGameplay.assets(assets, state)
        Runtime.PlayerController.update(player, directionX or 0, directionY or 0, dt,
            function(currentX, currentY, nextX, nextY)
                return Runtime.Navigation.canMoveFrom(assets, currentX, currentY, nextX, nextY,
                    Runtime.movementObstacles(state, false))
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
        if Runtime.Forklift.isOperator(state, Runtime.Config.forklift, Runtime.World.player.id) then
            updated = Runtime.World.updateNetworkForklift(Runtime.World.player, dt, directionX, directionY, assets, state, true)
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
        if not Runtime.PalletJack.isOperator(state, Runtime.Config.palletJack, player.id) then return false end
        assets = Runtime.WarehouseGameplay.assets(assets, state)
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
                    return Runtime.Navigation.canMoveAreaFrom(assets, jack.x, jack.y, nextX, nextY,
                        footprint.x, footprint.y, Runtime.movementObstacles(state, true, footprint))
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
