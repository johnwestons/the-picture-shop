-- Pallet, machine, visitor, and environment snapshots.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.World.palletJackSnapshot(state)
        return Runtime.PalletJack.snapshot(state, Runtime.Config.palletJack)
    end

    function Runtime.World.palletPickupSnapshot(state, cursorX, cursorY, player)
        return require("src.pallet_pickup").snapshot(state, Runtime.Config.palletJack,
            player or Runtime.World.player, cursorX, cursorY)
    end

    function Runtime.World.networkPalletJackSnapshot(state)
        local snapshot = Runtime.PalletJack.snapshot(state, Runtime.Config.palletJack)
        local machineAttached = Runtime.palletJackHasAttachedMachine(state)
        local candidatePalletId = snapshot.candidatePalletId
        if machineAttached then candidatePalletId = nil end
        return {
            x = snapshot.x,
            y = snapshot.y,
            direction = snapshot.direction,
            sceneId = snapshot.sceneId,
            operating = snapshot.operating,
            moving = snapshot.moving,
            operatorPlayerId = snapshot.operatorPlayerId,
            operatorEmployeeId = snapshot.operatorEmployeeId,
            carriedPalletId = snapshot.carriedPalletId,
            candidatePalletId = candidatePalletId,
        }
    end

    function Runtime.World.networkMachinePoseSnapshot(state)
        return Runtime.MachinePose.snapshot(state)
    end

    function Runtime.World.applyNetworkPalletJackSnapshot(state, snapshot, machinePoses)
        local normalizedMachinePoses, machinePoseError = Runtime.MachinePose.normalize(
            machinePoses, snapshot, 100000, "network machine poses")
        if not normalizedMachinePoses then return false, machinePoseError end
        local targetsValid, targetError = Runtime.MachinePose.canApply(state, normalizedMachinePoses)
        if not targetsValid then return false, targetError end
        local applied, applyError = Runtime.PalletJack.applySnapshot(
            state, snapshot, Runtime.Config.palletJack)
        if not applied then return false, applyError end
        local posesApplied, posesError = Runtime.MachinePose.apply(state, normalizedMachinePoses)
        if not posesApplied then return false, posesError end
        state._networkMachinePoses = Runtime.MachinePose.activeKind(normalizedMachinePoses)
            and assert(Runtime.MachinePose.copy(normalizedMachinePoses)) or nil
        local jack = Runtime.PalletJack.ensure(state, Runtime.Config.palletJack)
        local localPlayerId = tonumber(Runtime.World.player.id) or 1
        if jack.operating and jack.operatorPlayerId == localPlayerId then
            Runtime.World.player.x, Runtime.World.player.y = Runtime.PalletJack.operatorPosition(state, Runtime.Config.palletJack)
            Runtime.World.player.moving = jack.moving
            Runtime.World.player.facing = (jack.direction == "northeast" or jack.direction == "east"
                or jack.direction == "southeast") and 1 or -1
        end
        return true
    end

    function Runtime.World.palletsSnapshot(state)
        return Runtime.PalletLogistics.physicalPallets(state)
    end

    function Runtime.World.palletAt(state, x, y)
        return Runtime.PalletLogistics.hovered(state, x, y,
            require("src.shop_rooms").scene(Runtime.World.player))
    end

    function Runtime.World.palletTooltipAt(state, x, y)
        if type(x) ~= "number" or type(y) ~= "number" then return nil end
        local pickup = Runtime.World.palletPickupSnapshot(state, x, y)
        local sceneId=require("src.shop_rooms").scene(Runtime.World.player)
        local hovered = pickup.hovered and pickup.selected
            or Runtime.PalletLogistics.hovered(state, x, y,sceneId)
        if not hovered then
            local carried = Runtime.PalletJack.carriedItem(state, Runtime.Config.palletJack)
            if Runtime.PalletJack.ensure(state,Runtime.Config.palletJack).sceneId==sceneId
                and carried and x >= carried.x - 58 and x <= carried.x + 58
                and y >= carried.y - 92 and y <= carried.y + 12
            then hovered = carried end
        end
        return Runtime.PalletLogistics.tooltip(hovered)
    end

    function Runtime.World.bayDoorSnapshot()
        return Runtime.World.bayDoor:snapshot()
    end

    function Runtime.World.customerSnapshot()
        return Runtime.World.customer:snapshot()
    end

    function Runtime.World.vendorSnapshot()
        return Runtime.World.vendor:snapshot()
    end

    function Runtime.World.applyVisitorSnapshot(customer, vendor)
        if type(customer) ~= "table" or type(vendor) ~= "table" then return false end
        -- Network protocol validation is atomic before this seam is reached.
        return Runtime.World.customer:applySnapshot(customer) and Runtime.World.vendor:applySnapshot(vendor)
    end

    function Runtime.World.environmentSnapshot()
        local door = Runtime.World.bayDoor:snapshot()
        local truck = Runtime.World.truck:snapshot()
        return {
            bayDoor = { state = door.state, progress = door.progress },
            employees = Runtime.World._state and require("src.employee_pose").capture(Runtime.Employees.actors(Runtime.World._state)),
            truck = {
                state = truck.state,
                jobId = truck.jobId,
                mode = truck.mode,
                backingProgress = truck.backingProgress,
                cargoProgress = truck.cargoProgress,
            },
        }
    end

    function Runtime.World.applyEmployeeSnapshot(employees,state)
        local poses=require("src.employee_pose").actors(employees)
        state=state or Runtime.World._state
        if not poses or not state then return false end
        state._employeePoses=poses
        return true
    end
    function Runtime.World.applyEnvironmentSnapshot(bayDoor, truck, employees, state)
        if type(bayDoor) ~= "table" or type(truck) ~= "table" then return false end
        local poses
        if employees~=nil then
            poses=require("src.employee_pose").actors(employees)
            if not poses then return false end
        end
        local previousDoor = Runtime.World.environmentSnapshot().bayDoor
        if not Runtime.World.bayDoor:applySnapshot(bayDoor) then return false end
        if Runtime.World.truck:applySnapshot(truck) then
            state=state or Runtime.World._state
            if poses and state then state._employeePoses=poses end
            return true
        end
        Runtime.World.bayDoor:applySnapshot(previousDoor)
        return false
    end

    function Runtime.World.truckSnapshot()
        return Runtime.World.truck:snapshot()
    end

    function Runtime.World.snapshot()
        if require("src.shop_rooms").scene(Runtime.World.player)~="warehouse" then
            return {x=Runtime.Config.player.spawnX,y=Runtime.Config.player.spawnY,character=Runtime.World.player.character}
        end
        return { x = Runtime.World.player.x, y = Runtime.World.player.y, character = Runtime.World.player.character }
    end
end

return Component
