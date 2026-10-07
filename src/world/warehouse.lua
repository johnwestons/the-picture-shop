-- Warehouse commands, racks, and forklift movement.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.warehousePlayer(player)
        if player == Runtime.World.player and player.id == nil then player.id = 1 end
        return player
    end

    function Runtime.warehouseContext(assets)
        return { assets=assets or Runtime.World._assets, obstacles=Runtime.movementObstacles }
    end

    function Runtime.World.warehouseAccess(player, state, intent)
        return Runtime.WarehouseGameplay.access(Runtime.warehousePlayer(player), state, intent, Runtime.warehouseContext())
    end

    function Runtime.World.warehouseCommand(player, state, intent)
        local okay, code, message = Runtime.WarehouseGameplay.command(Runtime.warehousePlayer(player), state, intent, Runtime.warehouseContext())
        -- Local workshop authority authenticates a detached player view. Copy the
        -- successful seat/exit placement back to the actual local controller;
        -- remote Session players already arrive here by mutable reference.
        if okay and player ~= Runtime.World.player and type(player) == "table"
            and player.id == (tonumber(Runtime.World.player.id) or 1)
            and (intent.kind == "operate" or intent.kind == "release") then
            Runtime.World.player.x, Runtime.World.player.y = player.x, player.y
            Runtime.World.player.moving = player.moving == true
            Runtime.World.player.velocityX, Runtime.World.player.velocityY = 0, 0
        end
        return okay, code, message
    end

    function Runtime.World.forceReleaseForklift(player,state)
        local okay,code,exit=Runtime.WarehouseGameplay.forceRelease(Runtime.warehousePlayer(player),state,Runtime.warehouseContext())
        if okay and exit and player ~= Runtime.World.player and player.id == (tonumber(Runtime.World.player.id) or 1) then
            Runtime.World.player.x,Runtime.World.player.y=player.x,player.y
            Runtime.World.player.moving=false
            Runtime.World.player.velocityX,Runtime.World.player.velocityY=0,0
        end
        return okay,code,exit
    end

    function Runtime.World.warehouseRackContext(player, state, rackId, row, column)
        return Runtime.WarehouseGameplay.rackContext(Runtime.warehousePlayer(player), state, rackId, Runtime.warehouseContext(), row, column)
    end

    function Runtime.World.warehouseCandidate(state)
        return Runtime.WarehouseGameplay.candidate(state)
    end

    function Runtime.World.warehouseStackCandidate(state)
        return Runtime.WarehouseGameplay.stackCandidate(state)
    end

    function Runtime.World.warehouseNearRack(player, state)
        return Runtime.WarehouseGameplay.nearRack(Runtime.warehousePlayer(player), state)
    end

    function Runtime.World.updateNetworkForklift(player, dt, directionX, directionY, assets, state, readOnly)
        if type(player) ~= "table" or type(state) ~= "table" then return false end
        Runtime.warehousePlayer(player)
        Runtime.World._assets, Runtime.World._state = assets or Runtime.World._assets, state
        local startX, startY = player.x, player.y
        local updated = Runtime.WarehouseGameplay.move(player, dt, directionX, directionY, state,
            Runtime.warehouseContext(assets), readOnly == true)
        if updated then
            Runtime.PlayerController.observeExternalMove(player, startX, startY, player.moving, dt)
        end
        return updated
    end

    -- The authoritative App calls this before WorkPhone.update, including while
    -- a GUI is open. Guests render replicated state without advancing construction.
    function Runtime.World.updateWarehouse(dt, state, assets)
        Runtime.World._assets, Runtime.World._state = assets or Runtime.World._assets, state
        return Runtime.WarehouseGameplay.update(dt, state, Runtime.warehouseContext(assets))
    end
end

return Component
