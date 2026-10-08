-- Save reconciliation, snapshots, payload validation, and migration.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.Schema.reconcile(state)
        if type(state) ~= "table" then return false end
        state.inventory = type(state.inventory) == "table" and state.inventory or {}
        local raw, inProcess, finished = 0, 0, 0
        local active = state.jobs and type(state.jobs.active) == "table" and state.jobs.active or {}
        for _, savedJob in ipairs(active) do
            local pallets = type(savedJob) == "table" and type(savedJob.pallets) == "table"
                and savedJob.pallets or {}
            for _, pallet in ipairs(pallets) do
                if pallet.activeLift == nil then
                    pallet.activeLift = math.min(pallet.requiredLifts or 1, (pallet.completedLifts or 0) + 1)
                end
                if pallet.lastLiftSheets == nil then pallet.lastLiftSheets = 0 end
                if pallet.programVerified == nil then
                    pallet.programVerified = (pallet.completedLifts or 0) > 0
                        or (pallet.paper and pallet.paper.status == "complete")
                end
                if pallet.location == "at_cutter"
                    and pallet.paper and pallet.paper.status == "complete"
                    and (pallet.completedLifts or 0) == 0 and (pallet.remainingSheets or 0) > 0
                then
                    local migratedSheets = math.min(500, pallet.remainingSheets)
                    pallet.completedLifts = 1
                    pallet.lastLiftSheets = migratedSheets
                    pallet.remainingSheets = pallet.remainingSheets - migratedSheets
                    pallet.finishedSheets = (pallet.finishedSheets or 0) + migratedSheets
                    pallet.activeLift = math.min(pallet.requiredLifts or 1, pallet.completedLifts + 1)
                    pallet.programVerified = true
                end
                if pallet.location == "warehouse" or pallet.location == "cutter_output"
                    or pallet.location == "on_pallet_jack" or pallet.location == "at_cutter"
                    or pallet.location == "at_press" or pallet.location == "press_output"
                    or pallet.location == "rack" or pallet.location == "stacked" or pallet.location == "on_forklift"
                    or pallet.location == "on_employee"
                then
                    local needsPrinting = type(savedJob.press) == "table"
                    local printingComplete = not needsPrinting
                        or (type(pallet.press) == "table" and pallet.press.status == "complete")
                    local cuttingComplete = pallet.status == "cut" or pallet.status == "printed"
                        or pallet.status == "finished" or pallet.status == "wrapped"
                        or (pallet.paper and pallet.paper.status == "complete"
                            and (pallet.remainingSheets or 0) == 0)
                    if pallet.location == "at_press"
                        or (needsPrinting and not printingComplete and cuttingComplete)
                        or pallet.status == "in_process" or pallet.status == "press_setup"
                    then
                        inProcess = inProcess + 1
                    elseif pallet.status == "cut" or pallet.status == "printed"
                        or pallet.status == "finished" or pallet.status == "wrapped"
                        or (cuttingComplete and printingComplete)
                    then
                        finished = finished + 1
                    elseif pallet.location == "at_cutter" then
                        inProcess = inProcess + 1
                    else
                        raw = raw + 1
                    end
                end
            end
        end
        state.inventory.rawPallets = raw
        state.inventory.inProcessPallets = inProcess
        state.inventory.finishedPallets = finished
        state.inventory.stock = type(state.inventory.stock) == "table" and state.inventory.stock or {}
        state.cutterMemory = type(state.cutterMemory) == "table" and state.cutterMemory or {}
        Runtime.MachineFleet.ensure(state)
        Runtime.BusinessCalendar.ensure(state)
        return true
    end

    function Runtime.Schema.snapshot(state)
        local committedPlacements = {}
        for _, kind in ipairs({ "cutter", "wrapper", "windmill" }) do
            local item = type(state) == "table" and state[kind] or nil
            local origin = type(item) == "table" and item.moving == true
                and item._relocationOrigin or nil
            if type(origin) == "table" and Runtime.number(origin.x) and Runtime.number(origin.y)
                and Runtime.directions[origin.direction]
            then
                committedPlacements[kind] = {
                    x = origin.x,
                    y = origin.y,
                    direction = origin.direction,
                }
            end
        end
        local result, reason = Runtime.normalizeState(state)
        if not result then return nil, reason end
        for kind, origin in pairs(committedPlacements) do
            result[kind].x, result[kind].y = origin.x, origin.y
            result[kind].direction = origin.direction
        end
        result.cutter.moving, result.cutter.inMotion = false, false
        result.wrapper.moving, result.wrapper.inMotion = false, false
        result.windmill.moving, result.windmill.inMotion = false, false
        result.palletJack.operating = false
        result.palletJack.moving, result.palletJack.inMotion = false, false
        result.palletJack.operatorPlayerId = nil
        result.palletJack.operatorEmployeeId = nil
        Runtime.Forklift.forceRelease(result, Runtime.Config.forklift)
        Runtime.Schema.reconcile(result)
        return result
    end

    function Runtime.Schema.validState(state)
        return Runtime.persistentState(state)
    end

    function Runtime.Schema.newPayload(slot, timestamp)
        assert(Runtime.validSlot(slot), "save slot must be 1, 2, or 3")
        local now = timestamp or os.time()
        return {
            version = Runtime.Schema.VERSION,
            slot = slot,
            createdAt = now,
            updatedAt = now,
            state = Runtime.Schema.defaultState(),
            player = { x = Runtime.Config.player.spawnX, y = Runtime.Config.player.spawnY },
        }
    end

    function Runtime.Schema.validPayload(payload)
        return type(payload) == "table"
            and payload.version == Runtime.Schema.VERSION
            and Runtime.validSlot(payload.slot)
            and Runtime.number(payload.createdAt)
            and Runtime.number(payload.updatedAt)
            and Runtime.persistentState(payload.state)
            and type(payload.player) == "table"
            and Runtime.number(payload.player.x)
            and Runtime.number(payload.player.y)
    end

    function Runtime.legacyCore(payload)
        return type(payload) == "table"
            and Runtime.validSlot(payload.slot)
            and type(payload.state) == "table"
            and Runtime.nonnegative(payload.state.money)
            and type(payload.state.inventory) == "table"
            and type(payload.player) == "table"
            and Runtime.number(payload.player.x)
            and Runtime.number(payload.player.y)
    end

    function Runtime.validV2Core(payload)
        local state = payload and payload.state
        return Runtime.legacyCore(payload)
            and type(state.jobs) == "table"
            and type(state.jobs.active) == "table"
            and type(state.jobs.completed) == "table"
            and type(state.jobs.declined) == "table"
            and Runtime.positiveInteger(state.nextJobId)
            and Runtime.nonnegative(state.accountsReceivable)
    end

    function Runtime.Schema.migrate(payload)
        if type(payload) ~= "table" then return nil end
        if payload.version == Runtime.Schema.VERSION then
            local current = Runtime.copy(payload)
            return Runtime.Schema.validPayload(current) and current or nil
        end
        if payload.version == 1 then
            if not Runtime.legacyCore(payload) then return nil end
        elseif payload.version == 2 or payload.version == 3 or payload.version == 4
            or payload.version == 5 or payload.version == 6 or payload.version == 7
            or payload.version == 8 or payload.version == 9 or payload.version == 10
            or payload.version == 11 or payload.version == 12 or payload.version == 13
            or payload.version == 14 or payload.version == 15 or payload.version == 16 or payload.version == 17 or payload.version == 18 or payload.version == 19 or payload.version == 20
        then
            if not Runtime.validV2Core(payload) then return nil end
        else
            return nil
        end

        local createdAt = Runtime.number(payload.createdAt) and payload.createdAt or os.time()
        local migrated = {
            version = Runtime.Schema.VERSION,
            slot = payload.slot,
            createdAt = createdAt,
            updatedAt = Runtime.number(payload.updatedAt) and payload.updatedAt or createdAt,
            state = Runtime.normalizeState(payload.state, true),
            player = { x = payload.player.x, y = payload.player.y },
        }
        Runtime.Schema.reconcile(migrated.state)
        return Runtime.Schema.validPayload(migrated) and migrated or nil
    end

    Runtime.Schema.copy = Runtime.copy
    Runtime.Schema.validSlot = Runtime.validSlot
end

return Component
