local Harness = require("src.tests.support.network_impairment_harness")
local MachineRelocationAuthority = require("src.machine_relocation_authority")
local Protocol = require("src.net.protocol")
local SaveSchema = require("src.save_schema")
local Session = require("src.net.session")
local State = require("src.state")
local WorkshopAuthority = require("src.workshop_authority")

local Test = {}

local function player(x, y)
    return {
        x = x, y = y, velocityX = 0, velocityY = 0,
        intentX = 0, intentY = 0, moving = false, facing = 1,
        animationDistance = 0, character = "rabbit-worker",
    }
end

local function eventNamed(events, name)
    for _, event in ipairs(events or {}) do
        if event.type == name then return event end
    end
end

function Test.run(context, check)
    local state = context.State.new()
    context.machine.reset(state)
    context.wrapper.reset(state)
    local jack = context.PalletJack.ensure(state, context.config.palletJack)
    jack.x, jack.y = context.config.cutterPlacement.spawnX,
        context.config.cutterPlacement.spawnY
    local saves, observed = 0, {}
    local host
    local authority = WorkshopAuthority.new({
        tokenGenerator = function(serial)
            return "relocation-session-lease-" .. tostring(serial)
        end,
        resources = {
            pallet_jack = MachineRelocationAuthority.resource({
                state = state,
                assets = context.assets,
                world = context.world,
                palletJack = context.PalletJack,
                config = context.config,
                save = function()
                    saves = saves + 1
                    if host then host:markShopDirty(true) end
                end,
            }),
        },
    })
    local network = Harness.new({
        maxClients = 1,
        classify = function(bytes)
            local envelope = Protocol.decode(bytes)
            return envelope and envelope.type or "invalid"
        end,
    })
    host = Session.new({ transportFactory = network.factory })
    local client = Session.new({ transportFactory = network.factory })
    local hostPlayer = player(jack.x, jack.y)
    local clientPlayer = player(jack.x, jack.y)
    local hostContext = {
        localPlayer = hostPlayer,
        resolveGuestSpawn = function() return jack.x, jack.y end,
        getShopSnapshot = function()
            return {
                state = SaveSchema.snapshot(state),
                player = { x = hostPlayer.x, y = hostPlayer.y,
                    character = hostPlayer.character },
            }
        end,
        getWorkshopSnapshot = function()
            return { resources = authority:snapshot() }
        end,
        getPalletJackSnapshot = function()
            return context.world.networkPalletJackSnapshot(state)
        end,
        getMachinePoseSnapshot = function()
            return context.world.networkMachinePoseSnapshot(state)
        end,
        moveRemote = function(worker, dt, x, y)
            context.world.updateRemotePlayer(worker, dt, x, y, context.assets, state)
        end,
        touchWorkshop = function(worker) authority:touchPlayer(worker) end,
        updateWorkshop = function() authority:update({}) end,
    }
    hostContext.performWorkshop = function(worker, operation, payload)
        if operation == "workshop_acquire" then
            return authority:acquire(worker, {
                requestId = payload.requestId, resourceId = payload.resourceId,
            }, {})
        elseif operation == "workshop_command" then
            observed[#observed + 1] = payload
            local arguments = {}
            if payload.machineIndex ~= nil then arguments.machineIndex = payload.machineIndex end
            if payload.placementCell ~= nil then arguments.placementCell = payload.placementCell end
            return authority:command(worker, {
                requestId = payload.commandId, resourceId = payload.resourceId,
                leaseId = payload.leaseId, action = payload.action,
                args = arguments, expectedRevision = payload.expectedRevision,
            }, {})
        elseif operation == "workshop_release" then
            return authority:release(worker, {
                requestId = payload.requestId, resourceId = payload.resourceId,
                leaseId = payload.leaseId, reason = payload.reason,
            }, {})
        end
    end
    local clientContext = { localPlayer = clientPlayer, inputX = 0, inputY = 0 }
    local hostStarted = host:startHost({
        name = "Relocation Host", character = "rabbit-worker",
        addressOptions = { socket = { dns = {
            gethostname = function() return "relocation-host" end,
            getaddrinfo = function() return { { addr = "192.168.1.94" } } end,
        } } },
    })
    host.sessionId = "machine-relocation-session-test"
    local clientStarted = client:startClient("192.168.1.94:22122", {
        name = "Relocation Guest", character = "rabbit-worker",
    })
    client.clientNonce = "machine-relocation-client"
    if hostStarted and clientStarted then
        client:update(0, clientContext)
        host:update(0, hostContext)
        client:update(0, clientContext)
        host:update(0.1, hostContext)
        client:update(0, clientContext)
        client:drainEvents()
        host:drainEvents()
    end

    local function command(action, arguments)
        local sent = client:requestWorkshopCommand(action, arguments or {})
        host:update(0, hostContext)
        client:update(0, clientContext)
        local events = client:drainEvents()
        return sent, eventNamed(events, "workshop_result"), events
    end

    local acquireSent = client:requestWorkshopAcquire("pallet_jack")
    host:update(0, hostContext)
    client:update(0, clientContext)
    local grant = eventNamed(client:drainEvents(), "workshop_grant")
    local clientReplica = State.new()
    State.applySharedSnapshot(clientReplica, SaveSchema.snapshot(state))
    local duplicatedMove = network:duplicateNext("client_to_host", 1, 1, true)
    local moveSent, moved, moveEvents = command("move_machine", { machineIndex = 1 })
    local activePoseApplied, activeShopApplied = false, false
    local function applyReplicaEvents(events)
        for _, event in ipairs(events) do
            if event.type == "pallet_jack_state" then
                activePoseApplied = context.world.applyNetworkPalletJackSnapshot(
                    clientReplica, event.jack, event.machines) or activePoseApplied
            elseif event.type == "shop_state" then
                activeShopApplied = State.applySharedUpdate(
                    clientReplica, event.state) or activeShopApplied
            end
        end
    end
    applyReplicaEvents(moveEvents)
    host:update(0.3, hostContext)
    client:update(0, clientContext)
    local activeEvents = client:drainEvents()
    applyReplicaEvents(activeEvents)
    check("machine_relocation_session_active_pose_survives_same_cycle_durable_save",
        activePoseApplied and activeShopApplied and clientReplica.wrapper.moving == false
        and clientReplica.cutter.moving == true
        and clientReplica.palletJack.operating
        and clientReplica.palletJack.operatorPlayerId == client.localId)
    clientContext.inputX = 1
    client:update(0.15, clientContext)
    host:update(0.15, hostContext)
    client:update(0, clientContext)
    clientContext.inputX = 0
    local rotateSent, rotated = command("rotate_machine", {})
    local grid = context.world.placementGridSnapshot(state, context.assets)
    local selected = grid and grid.selected
    if not selected then
        for _, cell in ipairs(grid and grid.cells or {}) do
            if cell.valid then selected = cell; break end
        end
    end
    if selected then
        context.world.selectPlacement(state, context.assets, selected.x, selected.y, false)
    end
    local placementCell = context.world.networkPlacementCellId(state, context.assets)
    local duplicatedPlace = network:duplicateNext("client_to_host", 1, 1, true)
    local placeSent, placed = command("place_machine", {
        placementCell = placementCell,
    })
    local movePayload, placePayload
    for _, payload in ipairs(observed) do
        if payload.action == "move_machine" then movePayload = payload end
        if payload.action == "place_machine" then placePayload = payload end
    end
    check("machine_relocation_session_round_trip_is_host_owned_bounded_and_exact_once",
        hostStarted and clientStarted and client.ready and acquireSent
        and grant and grant.granted and duplicatedMove and moveSent
        and moved and moved.accepted and rotateSent and rotated and rotated.accepted
        and duplicatedPlace and placeSent and placed and placed.accepted
        and not state.cutter.moving and saves == 3
        and movePayload and movePayload.machineIndex == 1
        and movePayload.x == nil and movePayload.y == nil
        and placePayload and placePayload.placementCell == placementCell
        and placePayload.x == nil and placePayload.y == nil)

    client:stop("test_complete")
    host:update(0, hostContext)
    host:stop("test_complete")
end

return Test
