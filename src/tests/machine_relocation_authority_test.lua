local MachineRelocationAuthority = require("src.machine_relocation_authority")
local Protocol = require("src.net.protocol")
local WorkshopAuthority = require("src.workshop_authority")

local Test = {}

local MACHINE_CONFIGS = {
    [1] = "cutterPlacement",
    [2] = "wrapperPlacement",
    [3] = "windmillPlacement",
}

local function fixture(context, machineIndex, prefix)
    local state = context.State.new()
    context.machine.reset(state)
    context.wrapper.reset(state)
    context.windmill.ensure(state).status = "idle"
    if machineIndex == 3 then
        state.money = 100000
        assert(context.machineFleet.buy(state, "dealer", 3))
    end
    local config = context.config[MACHINE_CONFIGS[machineIndex]]
    local jack = context.PalletJack.ensure(state, context.config.palletJack)
    jack.x, jack.y = config.spawnX, config.spawnY
    local worker = { id = 2, x = jack.x, y = jack.y, facing = 1 }
    local other = { id = 3, x = jack.x, y = jack.y, facing = -1 }
    local saves, occupied = 0, false
    local resource = MachineRelocationAuthority.resource({
        state = state,
        assets = context.assets,
        world = context.world,
        palletJack = context.PalletJack,
        config = context.config,
        save = function() saves = saves + 1 end,
        controlOccupied = function(index)
            return occupied and index == machineIndex
        end,
    })
    local authority = WorkshopAuthority.new({
        tokenGenerator = function(serial)
            return tostring(prefix) .. "-relocation-" .. tostring(serial)
        end,
        resources = { pallet_jack = resource },
    })
    return {
        state = state,
        worker = worker,
        other = other,
        authority = authority,
        saves = function() return saves end,
        setOccupied = function(value) occupied = value == true end,
    }
end

local function command(f, grant, requestId, action, arguments)
    return f.authority:command(f.worker, {
        requestId = requestId,
        resourceId = "pallet_jack",
        leaseId = grant.leaseId,
        action = action,
        args = arguments or {},
        expectedRevision = grant.revision,
    }, {})
end

local function acquire(f, requestId, worker)
    return f.authority:acquire(worker or f.worker, {
        requestId = requestId or 1,
        resourceId = "pallet_jack",
    }, {})
end

function Test.run(context, check)
    context.world.load()
    for machineIndex = 1, 3 do
        local f = fixture(context, machineIndex, "machine-" .. machineIndex)
        local grant = acquire(f)
        local contention = acquire(f, 1, f.other)
        local moveRequest = {
            requestId = 2,
            resourceId = "pallet_jack",
            leaseId = grant.leaseId,
            action = "move_machine",
            args = { machineIndex = machineIndex },
            expectedRevision = grant.revision,
        }
        local moved = f.authority:command(f.worker, moveRequest, {})
        local replayed = f.authority:command(f.worker, moveRequest, {})
        local poseAfterMove = context.world.networkMachinePoseSnapshot(f.state)
        local kinds = { "cutter", "wrapper", "windmill" }
        local models = { "polar_115", "skid_wrapper", "heidelberg_10x15" }
        local kind = kinds[machineIndex]
        local installed = context.machineFleet.installed(f.state, models[machineIndex])
        local sold, saleError = context.machineFleet.sell(
            f.state, installed and installed.id, "online")
        check("machine_relocation_" .. kind .. "_lease_and_exact_once_attach",
            grant.accepted and not contention.accepted
            and contention.code == "resource_busy"
            and moved.accepted and replayed.accepted
            and poseAfterMove[kind].moving
            and not sold and tostring(saleError):find("moving machine", 1, true) ~= nil
            and f.state.palletJack.operatorPlayerId == 2
            and f.saves() == 1)

        local beforeX = poseAfterMove[kind].x
        context.world.updateNetworkPalletJack(
            f.worker, 0.12, 1, 0, context.assets, f.state)
        local afterMotion = context.world.networkMachinePoseSnapshot(f.state)
        local jackXAfterMotion = f.state.palletJack.x
        local rotated = command(f, moved, 3, "rotate_machine")
        local grid = context.world.placementGridSnapshot(f.state, context.assets)
        local selected = grid and grid.selected
        if not selected then
            for _, candidate in ipairs(grid and grid.cells or {}) do
                if candidate.valid then selected = candidate; break end
            end
        end
        if selected then
            context.world.selectPlacement(
                f.state, context.assets, selected.x, selected.y, false)
        end
        local cell = context.world.networkPlacementCellId(f.state, context.assets)
        local blocked = command(f, rotated, 4, "place_machine", {
            placementCell = "c64r64",
        })
        local placed = command(f, rotated, 5, "place_machine", {
            placementCell = cell,
        })
        local finalPose = context.world.networkMachinePoseSnapshot(f.state)
        check("machine_relocation_" .. kind .. "_host_motion_rotation_and_cell_placement",
            afterMotion[kind].x ~= beforeX
            and afterMotion[kind].x == jackXAfterMotion
            and rotated.accepted and not blocked.accepted
            and blocked.code == "placement_blocked"
            and type(cell) == "string" and #cell <= 8
            and placed.accepted and not finalPose[kind].moving
            and finalPose[kind].x == selected.x and finalPose[kind].y == selected.y
            and f.saves() == 3,
            string.format("before=%s after=%s rotated=%s blocked=%s/%s cell=%s placed=%s final=%s,%s selected=%s,%s saves=%d",
                tostring(beforeX), tostring(afterMotion[kind].x), tostring(rotated.accepted),
                tostring(blocked.accepted), tostring(blocked.code), tostring(cell),
                tostring(placed.accepted), tostring(finalPose[kind].x),
                tostring(finalPose[kind].y), tostring(selected and selected.x),
                tostring(selected and selected.y), f.saves()))
    end

    local busy = fixture(context, 1, "machine-busy")
    local busyGrant = acquire(busy)
    busy.setOccupied(true)
    local occupied = command(busy, busyGrant, 2, "move_machine", { machineIndex = 1 })
    local invalid = command(busy, busyGrant, 3, "move_machine", { machineIndex = 4 })
    busy.worker.x = busy.worker.x + 1000
    busy.setOccupied(false)
    local outOfRange = command(busy, busyGrant, 4, "move_machine", { machineIndex = 1 })
    check("machine_relocation_rejects_console_invalid_target_and_stale_access",
        not occupied.accepted and occupied.code == "console_busy"
        and not invalid.accepted and invalid.code == "invalid_machine"
        and not outOfRange.accepted and outOfRange.code == "out_of_range"
        and busy.saves() == 0,
        string.format("occupied=%s invalid=%s range=%s saves=%d",
            tostring(occupied.code), tostring(invalid.code),
            tostring(outOfRange.code), busy.saves()))

    local recovery = fixture(context, 2, "machine-recovery")
    local recoveryGrant = acquire(recovery)
    local recoveryMove = command(
        recovery, recoveryGrant, 2, "move_machine", { machineIndex = 2 })
    context.world.updateNetworkPalletJack(
        recovery.worker, 0.1, -1, 0, context.assets, recovery.state)
    local cleanup = recovery.authority:cleanupPlayer(
        recovery.worker, "disconnected", {})
    check("machine_relocation_disconnect_recovers_machine_and_parks_jack",
        recoveryMove.accepted and #cleanup == 1
        and not recovery.state.wrapper.moving
        and not recovery.state.palletJack.operating
        and recovery.state.palletJack.operatorPlayerId == nil
        and recovery.saves() == 2)

    local movePacket = Protocol.encode("workshop_command", {
        sessionId = "machine-relocation", commandId = 1,
        leaseId = "machine-relocation-lease", resourceId = "pallet_jack",
        action = "move_machine", expectedRevision = 1, machineIndex = 3,
    })
    local rotatePacket = Protocol.encode("workshop_command", {
        sessionId = "machine-relocation", commandId = 2,
        leaseId = "machine-relocation-lease", resourceId = "pallet_jack",
        action = "rotate_machine", expectedRevision = 2,
    })
    local placePacket = Protocol.encode("workshop_command", {
        sessionId = "machine-relocation", commandId = 3,
        leaseId = "machine-relocation-lease", resourceId = "pallet_jack",
        action = "place_machine", expectedRevision = 3, placementCell = "c20r17",
    })
    local spoofedCoordinates = Protocol.encode("workshop_command", {
        sessionId = "machine-relocation", commandId = 4,
        leaseId = "machine-relocation-lease", resourceId = "pallet_jack",
        action = "place_machine", expectedRevision = 3, placementCell = "c20r17",
        x = 640, y = 408,
    })
    local invalidCell = Protocol.encode("workshop_command", {
        sessionId = "machine-relocation", commandId = 5,
        leaseId = "machine-relocation-lease", resourceId = "pallet_jack",
        action = "place_machine", expectedRevision = 3, placementCell = "c65r17",
    })
    check("machine_relocation_protocol_is_bounded_and_rejects_coordinates",
        movePacket and rotatePacket and placePacket
        and #movePacket <= Protocol.MAX_PACKET_BYTES
        and #placePacket <= Protocol.MAX_PACKET_BYTES
        and spoofedCoordinates == nil and invalidCell == nil,
        string.format("move=%s rotate=%s place=%s spoof=%s invalid=%s",
            tostring(movePacket ~= nil), tostring(rotatePacket ~= nil),
            tostring(placePacket ~= nil), tostring(spoofedCoordinates ~= nil),
            tostring(invalidCell ~= nil)))
end

return Test
