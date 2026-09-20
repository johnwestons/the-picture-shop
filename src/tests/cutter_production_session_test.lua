local Machine = require("src.machine")
local Protocol = require("src.net.protocol")
local Remote = require("src.screens.workshop_remote_screen")
local Session = require("src.net.session")
local WorkshopAuthority = require("src.workshop_authority")
local Harness = require("src.tests.support.network_impairment_harness")

local Test = {}

local function player()
    return { x = 100, y = 100, velocityX = 0, velocityY = 0, intentX = 0, intentY = 0,
        moving = false, facing = 1, animationDistance = 0, character = "rabbit-worker" }
end

function Test.run(context, check)
    local state = context.State.new()
    state.cutterMemory = { ["1"] = { 12.5 }, ["2"] = { 9.5 } }
    local guestState = context.State.new()
    Machine.reset()
    local operations = {
        load_stock = function() return Machine.load(state, "__generic_stock__") end,
        rotate_paper = function() return Machine.rotate(state) end,
        auto_gauge = function() return Machine.autoGauge(state) end,
        position_paper = function() return Machine.position(state) end,
        set_clamp = function(args) return Machine.setClamp(args.clamp, state) end,
        guarded_cut = function() return Machine.guardedCut(state) end,
        emergency_stop = function() return Machine.emergencyStop(state) end,
        reset_safety = function() return Machine.resetSafety(state) end,
        set_gauge = function(args) return Machine.setGauge(args.gaugeCentiInch / 100, state) end,
    }
    local calls, completedCuts = {}, 0
    local commands = {}
    for action, operation in pairs(operations) do
        commands[action] = {
            normalize = function(args)
                for key in pairs(args) do
                    if not (action == "set_clamp" and key == "clamp")
                        and not (action == "set_gauge" and key == "gaugeCentiInch") then return nil end
                end
                if action == "set_clamp" and type(args.clamp) ~= "boolean" then return nil end
                if action == "set_gauge" and type(args.gaugeCentiInch) ~= "number" then return nil end
                return args
            end,
            perform = function(_, _, args)
                calls[action] = (calls[action] or 0) + 1
                local ok = operation(args)
                return ok, ok and "completed" or "machine_blocked", state.message,
                    Machine.networkView(state, true)
            end,
        }
    end
    local authority = WorkshopAuthority.new({
        tokenGenerator = function(serial) return "production-lease-" .. serial end,
        resources = { cutter = {
            canAcquire = function() return true end,
            onAcquire = function()
                Machine.open(state)
                return true, "acquired", "Cutter connected.", Machine.networkView(state, true)
            end,
            onRelease = function() Machine.releaseOperator(state); return true end,
            commands = commands,
        } },
    })
    local network = Harness.new({ maxClients = 1, classify = function(bytes)
        local packet = Protocol.decode(bytes)
        return packet and packet.type or "invalid"
    end })
    local host = Session.new({ transportFactory = network.factory })
    local client = Session.new({ transportFactory = network.factory })
    local hostContext = {
        localPlayer = player(), resolveGuestSpawn = function() return 100, 100 end,
        moveRemote = function() end,
        getShopSnapshot = function()
            return { state = { money = state.money, screen = "world",
                inventory = { paper = 2500, prints = 0 }, jobs = { active = {}, completed = {} } },
                player = { x = 100, y = 100, character = "rabbit-worker" } }
        end,
        getCutterSnapshot = function()
            return { resourceRevision = authority:resourceRevision("cutter"),
                view = Machine.networkView(state, true) }
        end,
        touchWorkshop = function(worker) authority:touchPlayer(worker) end,
        updateWorkshop = function() authority:update({}) end,
        performWorkshop = function(worker, operation, payload)
            if operation == "workshop_acquire" then
                return authority:acquire(worker, { requestId = payload.requestId,
                    resourceId = payload.resourceId }, {})
            elseif operation == "workshop_command" then
                local args = {}
                if payload.clamp ~= nil then args.clamp = payload.clamp end
                if payload.gaugeCentiInch ~= nil then args.gaugeCentiInch = payload.gaugeCentiInch end
                return authority:command(worker, { requestId = payload.commandId,
                    resourceId = payload.resourceId, leaseId = payload.leaseId,
                    action = payload.action, args = args, expectedRevision = payload.expectedRevision }, {})
            end
        end,
    }
    local clientContext = { localPlayer = player(), inputX = 0, inputY = 0 }
    local function receive()
        client:update(0, clientContext)
        for _, event in ipairs(client:drainEvents()) do
            if event.type == "workshop_grant" and event.granted then Remote.enter(event, guestState)
            elseif event.type == "workshop_result" then Remote.applyResult(event)
            elseif event.type == "cutter_state" then Remote.applyCutterSnapshot(event) end
        end
    end
    local started = host:startHost({ name = "Production Host", character = "rabbit-worker",
        addressOptions = { socket = { dns = { gethostname = function() return "test-host" end,
            getaddrinfo = function() return { { addr = "192.168.1.92" } } end } } } })
    host.sessionId = "cutter-production-session"
    started = started and client:startClient("192.168.1.92:22122",
        { name = "Production Guest", character = "rabbit-worker" })
    client.clientNonce = "production-guest"
    client:update(0, clientContext)
    host:update(0, hostContext)
    receive()
    host:update(0.1, hostContext)
    receive()
    local acquired = client:requestWorkshopAcquire("cutter")
    host:update(0, hostContext)
    receive()
    check("cutter_production_real_session_opens_guest_console", started and acquired
        and client.ready and Remote.isOpen() and Remote.view.step == "idle")

    local function send(action, args) return client:requestWorkshopCommand(action, args) end
    local function key(keyName)
        Remote.keypressed(keyName, guestState, send)
        host:update(0, hostContext)
        receive()
    end
    local function advance(dt)
        if Machine.update(dt, state) then completedCuts = completedCuts + 1 end
        host:update(dt, hostContext)
        receive()
        Remote.update(0.1)
    end
    key("l")
    advance(0.5)
    key("q")
    key("g")
    key("p")
    advance(0.5)
    key("space")
    check("cutter_production_guest_load_rotate_gauge_position_clamp_round_trip",
        Machine.step == "clamped" and Remote.view.step == "clamped"
        and Remote.view.paper.orientation == Machine.paper.orientation
        and Remote.view.gaugeCentiInch == 1250 and Machine.gauge == 12.5)
    network:duplicateNext("client_to_host", 1, 1, true)
    key("j")
    advance(0.25)
    local first = Remote.cutterPresentation:model(guestState, Remote.view)
    advance(0.25)
    local second = Remote.cutterPresentation:model(guestState, Remote.view)
    check("cutter_production_real_snapshots_animate_without_duplicate_blade_start",
        calls.guarded_cut == 1 and first.step == "cutting" and first.paper ~= nil
        and second.progress > first.progress and second.progress < 1 and completedCuts == 0)
    -- A paused guest stream must not finish a cut or mutate host/guest stock.
    local hostProgress = Machine.progress
    Remote.update(20)
    check("cutter_production_guest_animation_cannot_finish_host_cycle",
        Machine.progress == hostProgress and completedCuts == 0
        and Remote.view.paper.activeCut == 1)
    advance(0.8)
    check("cutter_production_host_confirms_one_cut_and_guest_shows_next_program",
        completedCuts == 1 and #Machine.paper.history == 1
        and Remote.view.paper.activeCut == 2 and Remote.view.programIndex == 2
        and Remote.cutterPresentation:model(guestState, Remote.view).paper.currentSize.width
            == Machine.paper.currentSize.width,
        string.format("cuts=%d history=%d step=%s active=%s program=%s hostWidth=%s guestWidth=%s message=%s",
            completedCuts, #Machine.paper.history, Machine.step, tostring(Remote.view.paper.activeCut),
            tostring(Remote.view.programIndex), tostring(Machine.paper.currentSize.width),
            tostring(Remote.cutterPresentation:model(guestState, Remote.view).paper.currentSize.width),
            tostring(state.message)))
    key("q")
    key("g")
    key("p")
    advance(0.5)
    key("space")
    key("k")
    advance(0.2)
    key("x")
    advance(0.2)
    check("cutter_production_guest_estop_stops_shared_blade_without_extra_cut",
        Machine.step == "blocked" and Machine.emergencyStopped and Remote.view.emergencyStopped
        and Remote.cutterPresentation:model(guestState, Remote.view).step == "blocked"
        and completedCuts == 1 and #Machine.paper.history == 1)
    key("r")
    advance(0.4)
    local gx, gy = Remote.cutterGaugeInputCenter()
    Remote.mousepressed(guestState, gx, gy, 1, send)
    Remote.textinput("1")
    key("return")
    key("p")
    advance(0.5)
    key("space")
    key("k")
    advance(1.3)
    local ruined = Remote.cutterPresentation:model(guestState, Remote.view)
    check("cutter_production_wrong_guest_cut_shows_actual_spoiled_stock_not_finished_size",
        Machine.paper.offSpec and Remote.view.paper.offSpec and ruined.paper.offSpec
        and ruined.paper.currentSize.width == Machine.paper.currentSize.width
        and ruined.paper.currentSize.height == Machine.paper.currentSize.height
        and ruined.paper.currentSize.height == 1 and completedCuts == 2)
    local packetBounded = true
    for _, item in ipairs(network.log) do
        if item.kind == "cutter_snapshot" then
            packetBounded = packetBounded and item.bytes <= Protocol.MAX_PACKET_BYTES
        end
    end
    check("cutter_production_animation_preserves_existing_packet_budget", packetBounded)
    client:stop("test_complete")
    host:update(0, hostContext)
    host:stop("test_complete")
    Remote.clear()
    Machine.reset()
end

return Test
