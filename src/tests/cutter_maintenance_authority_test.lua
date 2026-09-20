local Codec = require("src.net.codec")
local CutterMaintenanceAuthority = require("src.cutter_maintenance_authority")
local MachineFleet = require("src.machine_fleet")
local Protocol = require("src.net.protocol")
local WorkshopAuthority = require("src.workshop_authority")

local Test = {}

local function baseView()
    return {
        runtimeRevision = 1,
        step = "idle",
        phasePermille = 0,
        loaded = false,
        clamp = false,
        clampPermille = 0,
        bladePermille = 0,
        barrierClear = true,
        emergencyStopped = false,
        gaugeCentiInch = 0,
        programIndex = 1,
        memoryCentiInch = {},
        candidates = {},
        genericSheets = 2500,
    }
end

local function fixture(context, prefix)
    local state = context.State.new()
    state.inventory.stock.maintenance_kit = 2
    local saves = { count = 0 }
    local inRange, machineIdle = true, true
    local service = CutterMaintenanceAuthority.create({
        state = state,
        baseView = baseView,
        validateAccess = function()
            return inRange, inRange and nil or "out_of_range",
                inRange and nil or "Move closer to the cutter controls."
        end,
        save = function() saves.count = saves.count + 1 end,
        machineReady = function()
            return machineIdle, machineIdle and nil
                or "Unload the cutter and return it to idle before beginning maintenance."
        end,
    })
    local productionCalls = 0
    local commands = service.withProductionCommands({
        load_stock = {
            normalize = function(arguments)
                return type(arguments) == "table" and next(arguments) == nil and {} or nil
            end,
            perform = function()
                productionCalls = productionCalls + 1
                return true, "loaded", "Production action accepted."
            end,
        },
    })
    local authority = WorkshopAuthority.new({
        tokenGenerator = function(serial)
            return tostring(prefix) .. "-cutter-lease-" .. tostring(serial)
        end,
        resources = {
            cutter = {
                canAcquire = function()
                    return inRange, inRange and nil or "out_of_range",
                        inRange and nil or "Move closer to the cutter controls."
                end,
                onAcquire = function()
                    local session = CutterMaintenanceAuthority.newSession()
                    return true, "acquired", "Cutter connected.", service.view(session, true), session
                end,
                commands = commands,
            },
        },
    })
    return {
        state = state,
        saves = saves,
        service = service,
        authority = authority,
        setRange = function(value) inRange = value == true end,
        setMachineIdle = function(value) machineIdle = value == true end,
        productionCalls = function() return productionCalls end,
    }
end

local function command(fixtureValue, worker, grant, requestId, action, arguments)
    return fixtureValue.authority:command(worker, {
        requestId = requestId,
        resourceId = "cutter",
        leaseId = grant.leaseId,
        action = action,
        args = arguments or {},
        expectedRevision = fixtureValue.authority:resourceRevision("cutter"),
    }, {})
end

local function completePoint(fixtureValue, worker, grant, requestId, viewIndex, pointIndexes)
    local result = command(fixtureValue, worker, grant, requestId, "service_view",
        { itemIndex = viewIndex })
    requestId = requestId + 1
    for _, pointIndex in ipairs(pointIndexes) do
        result = command(fixtureValue, worker, grant, requestId, "service_tool", { itemIndex = 1 })
        requestId = requestId + 1
        result = command(fixtureValue, worker, grant, requestId, "service_point",
            { itemIndex = pointIndex })
        requestId = requestId + 1
        result = command(fixtureValue, worker, grant, requestId, "service_tool", { itemIndex = 2 })
        requestId = requestId + 1
        result = command(fixtureValue, worker, grant, requestId, "service_point",
            { itemIndex = pointIndex })
        requestId = requestId + 1
        result = command(fixtureValue, worker, grant, requestId, "service_pump", {})
        requestId = requestId + 1
        result = command(fixtureValue, worker, grant, requestId, "service_pump", {})
        requestId = requestId + 1
    end
    return result, requestId
end

function Test.run(context, check)
    local lubrication = fixture(context, "lubrication")
    local worker = { id = 2 }
    local other = { id = 3 }
    local grant = lubrication.authority:acquire(worker, {
        requestId = 1, resourceId = "cutter",
    }, {})
    local busy = lubrication.authority:acquire(other, {
        requestId = 1, resourceId = "cutter",
    }, {})
    check("cutter_maintenance_guest_gets_exclusive_host_owned_service_lease",
        grant.accepted and grant.data and grant.data.serviceStep == nil
        and not busy.accepted and busy.code == "resource_busy")

    lubrication.setRange(false)
    local outOfRange = command(lubrication, worker, grant, 2, "begin_lubrication", {})
    lubrication.setRange(true)
    lubrication.setMachineIdle(false)
    local machineBusy = command(lubrication, worker, grant, 3, "begin_lubrication", {})
    lubrication.setMachineIdle(true)
    local begun = command(lubrication, worker, grant, 4, "begin_lubrication", {})
    local productionBlocked = command(lubrication, worker, grant, 5, "load_stock", {})
    check("cutter_maintenance_revalidates_range_machine_state_and_production_interlock",
        not outOfRange.accepted and outOfRange.code == "out_of_range"
        and not machineBusy.accepted and machineBusy.code == "machine_busy"
        and begun.accepted and begun.data.serviceStep == "lockout_disconnect"
        and not productionBlocked.accepted and productionBlocked.code == "service_active"
        and lubrication.productionCalls() == 0 and lubrication.saves.count == 0)

    local requestId = 6
    local advanced
    for _, expectedStep in ipairs({
        "lockout_key", "lockout_tag", "prep_cartridge", "prep_prime", "lubricate",
    }) do
        advanced = command(lubrication, worker, grant, requestId, "service_advance", {})
        requestId = requestId + 1
        check("cutter_maintenance_host_advances_to_" .. expectedStep,
            advanced.accepted and advanced.data.serviceStep == expectedStep)
    end

    advanced, requestId = completePoint(
        lubrication, worker, grant, requestId, 1, { 1, 2 })
    advanced, requestId = completePoint(
        lubrication, worker, grant, requestId, 2, { 3, 4 })
    advanced, requestId = completePoint(
        lubrication, worker, grant, requestId, 3, { 5, 6 })
    local gearView = command(lubrication, worker, grant, requestId,
        "service_view", { itemIndex = 4 })
    requestId = requestId + 1
    local inspectTool = command(lubrication, worker, grant, requestId,
        "service_tool", { itemIndex = 3 })
    requestId = requestId + 1
    local inspected = command(lubrication, worker, grant, requestId, "service_gear", {})
    requestId = requestId + 1
    local finishRequest = {
        requestId = requestId, resourceId = "cutter", leaseId = grant.leaseId,
        action = "finish_lubrication", args = {},
        expectedRevision = lubrication.authority:resourceRevision("cutter"),
    }
    local finished = lubrication.authority:command(worker, finishRequest, {})
    local replay = lubrication.authority:command(worker, finishRequest, {})
    local cutter = MachineFleet.installed(lubrication.state, "polar_115")
    check("cutter_guest_lubrication_consumes_and_saves_exactly_once",
        advanced.accepted and gearView.accepted and inspectTool.accepted and inspected.accepted
        and finished.accepted and finished.code == "maintenance_completed"
        and replay.accepted and lubrication.state.inventory.stock.maintenance_kit == 1
        and cutter.maintenance.cutter.lubricationServices == 1
        and lubrication.saves.count == 1)

    local blade = fixture(context, "blade")
    local bladeGrant = blade.authority:acquire(worker, {
        requestId = 1, resourceId = "cutter",
    }, {})
    local bladeBegun = command(blade, worker, bladeGrant, 2, "begin_blade", {})
    local boltResult
    for index = 1, 4 do
        boltResult = command(blade, worker, bladeGrant, 2 + index,
            "remove_blade_bolt", { itemIndex = index })
    end
    local lifted = command(blade, worker, bladeGrant, 7, "lift_blade", {})
    local sleevedRequest = {
        requestId = 8, resourceId = "cutter", leaseId = bladeGrant.leaseId,
        action = "sleeve_blade", args = {},
        expectedRevision = blade.authority:resourceRevision("cutter"),
    }
    local sleeved = blade.authority:command(worker, sleevedRequest, {})
    local sleeveReplay = blade.authority:command(worker, sleevedRequest, {})
    local booked = command(blade, worker, bladeGrant, 9, "book_blade_technician", {})
    local bookedAgain = command(blade, worker, bladeGrant, 10, "book_blade_technician", {})
    local weeklyRequest = {
        requestId = 11, resourceId = "cutter", leaseId = bladeGrant.leaseId,
        action = "set_weekly_technician", args = { enabled = true },
        expectedRevision = blade.authority:resourceRevision("cutter"),
    }
    local weekly = blade.authority:command(worker, weeklyRequest, {})
    local weeklyReplay = blade.authority:command(worker, weeklyRequest, {})
    local weeklyAgain = command(blade, worker, bladeGrant, 12,
        "set_weekly_technician", { enabled = true })
    local _, cutterMaintenance = context.machineMaintenance.cutterStatus(blade.state)
    check("cutter_guest_blade_and_technician_workflow_is_host_owned_exactly_once",
        bladeBegun.accepted and boltResult.accepted and lifted.accepted
        and sleeved.accepted and sleeveReplay.accepted and cutterMaintenance.bladeInSleeve
        and booked.accepted and not bookedAgain.accepted
        and weekly.accepted and weeklyReplay.accepted and not weeklyAgain.accepted
        and cutterMaintenance.weeklyTechnician and cutterMaintenance.nextTechnicianDay ~= nil
        and blade.saves.count == 3)

    local disconnect = fixture(context, "disconnect")
    local disconnectGrant = disconnect.authority:acquire(worker, {
        requestId = 1, resourceId = "cutter",
    }, {})
    local disconnectBegin = command(disconnect, worker, disconnectGrant, 2,
        "begin_lubrication", {})
    local disconnectAdvance = command(disconnect, worker, disconnectGrant, 3,
        "service_advance", {})
    local cleanup = disconnect.authority:cleanupPlayer(worker, "disconnected", {})
    local reacquired = disconnect.authority:acquire(other, {
        requestId = 2, resourceId = "cutter",
    }, {})
    check("cutter_maintenance_disconnect_discards_transient_progress_and_releases_lease",
        disconnectBegin.accepted and disconnectAdvance.accepted and #cleanup == 1
        and reacquired.accepted and reacquired.data.serviceStep == nil
        and disconnect.state.inventory.stock.maintenance_kit == 2
        and disconnect.saves.count == 0)

    local activeView = inspected.data
    activeView.memoryCentiInch = Codec.array(activeView.memoryCentiInch)
    activeView.serviceItems = Codec.array(activeView.serviceItems)
    local viewPacket = Protocol.encode("workshop_result", {
        sessionId = "cutter-service-session", commandId = 50, resourceId = "cutter",
        action = "service_gear", accepted = true, code = "gear_serviced",
        message = "Gearbox sight-glass action accepted.", revision = 50, view = activeView,
    })
    local viewCommand = Protocol.encode("workshop_command", {
        sessionId = "cutter-service-session", commandId = 51,
        leaseId = "cutter-service-lease", resourceId = "cutter",
        action = "service_view", expectedRevision = 50, itemIndex = 4,
    })
    local weeklyCommand = Protocol.encode("workshop_command", {
        sessionId = "cutter-service-session", commandId = 52,
        leaseId = "cutter-service-lease", resourceId = "cutter",
        action = "set_weekly_technician", expectedRevision = 51, enabled = true,
    })
    local spoofedPoint = Protocol.encode("workshop_command", {
        sessionId = "cutter-service-session", commandId = 53,
        leaseId = "cutter-service-lease", resourceId = "cutter",
        action = "service_point", expectedRevision = 52, itemIndex = 1,
        palletId = "forged-point-id",
    })
    check("cutter_maintenance_protocol_is_strict_bounded_and_boolean_explicit",
        viewPacket ~= nil and #viewPacket <= Protocol.MAX_PACKET_BYTES
        and Protocol.decode(viewPacket) ~= nil and viewCommand ~= nil and weeklyCommand ~= nil
        and spoofedPoint == nil)

    local screen = context.inputContext.workshopRemoteScreen
    screen.enter({
        resourceId = "cutter", leaseId = "screen-cutter-service", revision = 1,
        message = "Cutter connected.", view = baseView(),
    }, blade.state)
    local sent = {}
    local function send(action, arguments)
        sent[#sent + 1] = { action = action, arguments = arguments }
        return true
    end
    local tabX, tabY = screen.cutterServiceCenter("tab")
    screen.mousepressed(blade.state, tabX, tabY, 1, send)
    local weeklyX, weeklyY = screen.cutterServiceCenter("set_weekly_technician")
    screen.mousepressed(blade.state, weeklyX, weeklyY, 1, send)
    check("cutter_maintenance_remote_ui_sends_only_explicit_bounded_intent",
        #sent == 1 and sent[1].action == "set_weekly_technician"
        and sent[1].arguments.enabled == false
        and sent[1].arguments.itemIndex == nil)
    screen.clear()
end

return Test
