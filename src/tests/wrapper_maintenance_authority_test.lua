local Codec = require("src.net.codec")
local MachineFleet = require("src.machine_fleet")
local Protocol = require("src.net.protocol")
local WorkshopAuthority = require("src.workshop_authority")
local WrapperMaintenanceAuthority = require("src.wrapper_maintenance_authority")

local Test = {}

local function baseView(detailed)
    local view = {
        step = "idle", progress = 0, cycleTime = 3,
        pallets = {}, selectedPalletId = nil, palletId = nil,
    }
    if detailed ~= false then
        view.plasticWrapRolls, view.plasticWrapUses = 1, 11
    end
    return view
end

local function fixture(context, prefix)
    local state = context.State.new()
    state.inventory.stock.maintenance_kit = 2
    MachineFleet.recordUse(state, "skid_wrapper", 18)
    local saves, productionCalls, resets = 0, 0, 0
    local inRange, machineReady = true, true
    local service = WrapperMaintenanceAuthority.create({
        state = state,
        baseView = baseView,
        validateAccess = function()
            return inRange, inRange and nil or "out_of_range",
                inRange and nil or "Move closer to the skid-wrapper controls."
        end,
        machineReady = function()
            return machineReady, machineReady and nil or "machine_busy",
                machineReady and nil or "Clear the wrapper turntable first."
        end,
        resetRuntime = function() resets = resets + 1; return true end,
        save = function() saves = saves + 1 end,
    })
    local commands = service.withProductionCommands({
        start_cycle = {
            normalize = function(arguments)
                return type(arguments) == "table" and next(arguments) == nil and {} or nil
            end,
            perform = function()
                productionCalls = productionCalls + 1
                return true, "cycle_started", "Wrapper cycle started."
            end,
        },
    })
    local authority = WorkshopAuthority.new({
        tokenGenerator = function(serial)
            return tostring(prefix) .. "-wrapper-lease-" .. tostring(serial)
        end,
        resources = {
            skid_wrapper = {
                canAcquire = function()
                    return inRange, inRange and nil or "out_of_range",
                        inRange and nil or "Move closer to the skid-wrapper controls."
                end,
                onAcquire = function()
                    local private = WrapperMaintenanceAuthority.newSession()
                    return true, "acquired", "Wrapper connected.",
                        service.view(private, true), private
                end,
                commands = commands,
            },
        },
    })
    return {
        state = state, service = service, authority = authority,
        saves = function() return saves end,
        resets = function() return resets end,
        productionCalls = function() return productionCalls end,
        setRange = function(value) inRange = value == true end,
        setMachineReady = function(value) machineReady = value == true end,
    }
end

local function command(f, worker, grant, requestId, action, arguments)
    return f.authority:command(worker, {
        requestId = requestId, resourceId = "skid_wrapper",
        leaseId = grant.leaseId, action = action, args = arguments or {},
        expectedRevision = f.authority:resourceRevision("skid_wrapper"),
    }, {})
end

function Test.run(context, check)
    local f = fixture(context, "service")
    local worker, other = { id = 2 }, { id = 3 }
    local grant = f.authority:acquire(worker, {
        requestId = 1, resourceId = "skid_wrapper",
    }, {})
    local busy = f.authority:acquire(other, {
        requestId = 1, resourceId = "skid_wrapper",
    }, {})
    check("wrapper_maintenance_guest_gets_exclusive_host_owned_lease",
        grant.accepted and grant.data and grant.data.serviceStep == nil
        and not busy.accepted and busy.code == "resource_busy")

    f.setRange(false)
    local outOfRange = command(f, worker, grant, 2, "begin_service", {})
    f.setRange(true)
    f.setMachineReady(false)
    local blocked = command(f, worker, grant, 3, "begin_service", {})
    f.setMachineReady(true)
    local begun = command(f, worker, grant, 4, "begin_service", {})
    local productionBlocked = command(f, worker, grant, 5, "start_cycle", {})
    check("wrapper_maintenance_revalidates_range_turntable_and_production_interlock",
        not outOfRange.accepted and outOfRange.code == "out_of_range"
        and not blocked.accepted and blocked.code == "machine_busy"
        and begun.accepted and begun.data.serviceStep == "task"
        and not productionBlocked.accepted and productionBlocked.code == "service_active"
        and f.productionCalls() == 0 and f.resets() == 1 and f.saves() == 0)

    local missRequest = {
        requestId = 6, resourceId = "skid_wrapper", leaseId = grant.leaseId,
        action = "service_miss", args = {},
        expectedRevision = f.authority:resourceRevision("skid_wrapper"),
    }
    local missed = f.authority:command(worker, missRequest, {})
    local missReplay = f.authority:command(worker, missRequest, {})
    local stale = command(f, worker, grant, 7, "service_target", { itemIndex = 3 })
    check("wrapper_maintenance_host_scores_misses_once_and_rejects_stale_targets",
        missed.accepted and missReplay.accepted and missed.data.serviceAttempts == 1
        and missed.data.serviceMisses == 1 and not stale.accepted
        and stale.code == "stale_target")

    local requestId, current, finalRequest = 8, missed
    local guard = 0
    while current.data and current.data.serviceStep == "task" and guard < 16 do
        finalRequest = {
            requestId = requestId, resourceId = "skid_wrapper", leaseId = grant.leaseId,
            action = "service_target", args = { itemIndex = current.data.servicePhase },
            expectedRevision = f.authority:resourceRevision("skid_wrapper"),
        }
        current = f.authority:command(worker, finalRequest, {})
        requestId, guard = requestId + 1, guard + 1
    end
    local replay = f.authority:command(worker, finalRequest, {})
    local wrapper = MachineFleet.installed(f.state, "skid_wrapper")
    check("wrapper_guest_four_component_service_consumes_and_saves_exactly_once",
        current.accepted and current.code == "maintenance_completed" and replay.accepted
        and guard == 10 and f.state.inventory.stock.maintenance_kit == 1
        and wrapper.maintenance.serviceCount == 1
        and wrapper.maintenance.lastServiceQuality < 1
        and f.saves() == 1,
        string.format("accepted=%s code=%s replay=%s guard=%s kits=%s services=%s quality=%s saves=%s",
            tostring(current.accepted), tostring(current.code), tostring(replay.accepted),
            tostring(guard), tostring(f.state.inventory.stock.maintenance_kit),
            tostring(wrapper.maintenance.serviceCount),
            tostring(wrapper.maintenance.lastServiceQuality), tostring(f.saves())))

    local disconnect = fixture(context, "disconnect")
    local disconnectGrant = disconnect.authority:acquire(worker, {
        requestId = 1, resourceId = "skid_wrapper",
    }, {})
    local disconnectBegin = command(disconnect, worker, disconnectGrant, 2,
        "begin_service", {})
    local disconnectTarget = command(disconnect, worker, disconnectGrant, 3,
        "service_target", { itemIndex = 1 })
    local cleanup = disconnect.authority:cleanupPlayer(worker, "disconnected", {})
    local reacquired = disconnect.authority:acquire(other, {
        requestId = 2, resourceId = "skid_wrapper",
    }, {})
    check("wrapper_maintenance_disconnect_discards_progress_and_reacquires_cleanly",
        disconnectBegin.accepted and disconnectTarget.accepted and #cleanup == 1
        and reacquired.accepted and reacquired.data.serviceStep == nil
        and disconnect.state.inventory.stock.maintenance_kit == 2
        and disconnect.saves() == 0)

    local relocationState = context.State.new()
    local moveBlocked = not context.world.beginWrapperMove(relocationState, true)
    local rotateBlocked = not context.world.rotateWrapper(relocationState, true)
    check("wrapper_active_console_blocks_host_relocation_and_rotation",
        moveBlocked and rotateBlocked
        and relocationState.message:find("active skid%-wrapper console") ~= nil)

    local activeView = begun.data
    activeView.pallets = Codec.array(activeView.pallets)
    local viewPacket = Protocol.encode("workshop_result", {
        sessionId = "wrapper-service-session", commandId = 41,
        resourceId = "skid_wrapper", action = "begin_service", accepted = true,
        code = "service_started", message = "Wrapper service opened.",
        revision = 2, view = activeView,
    })
    local targetPacket = Protocol.encode("workshop_command", {
        sessionId = "wrapper-service-session", commandId = 42,
        leaseId = "wrapper-service-lease", resourceId = "skid_wrapper",
        action = "service_target", expectedRevision = 2, itemIndex = 1,
    })
    local spoofedTarget = Protocol.encode("workshop_command", {
        sessionId = "wrapper-service-session", commandId = 43,
        leaseId = "wrapper-service-lease", resourceId = "skid_wrapper",
        action = "service_target", expectedRevision = 2, itemIndex = 1,
        palletId = "forged-target",
    })
    check("wrapper_maintenance_protocol_is_strict_and_bounded",
        viewPacket ~= nil and #viewPacket <= Protocol.MAX_PACKET_BYTES
        and Protocol.decode(viewPacket) ~= nil and targetPacket ~= nil
        and spoofedTarget == nil)

    local screen = context.inputContext.workshopRemoteScreen
    screen.enter({
        resourceId = "skid_wrapper", leaseId = "wrapper-screen-lease",
        revision = 1, message = "Wrapper connected.", view = begun.data,
    }, f.state)
    local sent = {}
    local function send(action, arguments)
        sent[#sent + 1] = { action = action, arguments = arguments }
        return true
    end
    local tabX, tabY = screen.wrapperTabCenter("service")
    screen.mousepressed(f.state, tabX, tabY, 1, send)
    local targetX, targetY = screen.wrapperServiceCenter("service_target")
    screen.mousepressed(f.state, targetX, targetY, 1, send)
    check("wrapper_maintenance_remote_ui_sends_only_current_bounded_target",
        #sent == 1 and sent[1].action == "service_target"
        and sent[1].arguments.itemIndex == begun.data.servicePhase
        and sent[1].arguments.palletId == nil)
    screen.clear()
end

return Test
