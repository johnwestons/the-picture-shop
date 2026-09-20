local Protocol = require("src.net.protocol")
local Reconnect = require("src.net.lan_reconnect")
local Session = require("src.net.session")
local Harness = require("src.tests.support.network_impairment_harness")

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

function Test.run(_, check)
    local now = 900
    local authoritativeMoney = 1200
    local clock = function() return now end
    local network = Harness.new({
        maxClients = 1,
        classify = function(payload)
            local envelope = Protocol.decode(payload)
            return envelope and envelope.type or "invalid"
        end,
    })
    local host = Session.new({ transportFactory = network.factory, clock = clock })
    local hostPlayer = player(400, 500)
    local hostContext = {
        localPlayer = hostPlayer,
        resolveGuestSpawn = function() return 430, 500 end,
        getShopSnapshot = function()
            return {
                state = {
                    money = authoritativeMoney,
                    inventory = { paper = 2500 },
                    jobs = { active = {}, completed = {} },
                },
                player = { x = hostPlayer.x, y = hostPlayer.y,
                    character = hostPlayer.character },
            }
        end,
    }
    local addressOptions = { socket = { dns = {
        gethostname = function() return "reconnect-host" end,
        getaddrinfo = function() return { { addr = "192.168.1.88" } } end,
    } } }
    local hosted = host:startHost({
        name = "Reconnect Host", character = "rabbit-worker",
        addressOptions = addressOptions,
    })
    host.sessionId = "lan-reconnect-session"

    local oldClient = Session.new({ transportFactory = network.factory, clock = clock })
    local clientContext = { localPlayer = player(430, 500), inputX = 0, inputY = 0 }
    local joined = oldClient:startClient("192.168.1.88:22122", {
        name = "Returning Worker", character = "rabbit-worker",
    })
    oldClient.clientNonce = "lan-reconnect-initial"
    oldClient:update(0, clientContext)
    host:update(0, hostContext)
    oldClient:update(0, clientContext)
    host:update(0.1, hostContext)
    oldClient:update(0, clientContext)
    local initialId = oldClient.localId
    check("lan_reconnect_session_initial_guest_receives_host_snapshot",
        hosted and joined and oldClient.ready and initialId == 2
        and host:hudInfo().playerCount == 2)

    -- These are deliberately transient client-only values. A reconnect must
    -- never carry them into the replacement Session.
    oldClient.pendingInteraction = {
        requestId = 77, targetKind = "loadingBayDoor", desiredState = "open", sentAt = now,
    }
    oldClient.activeWorkshop = {
        resourceId = "cutter", leaseId = "stale-client-lease", revision = 9,
    }
    local disconnected = network:disconnectPeer(1, 55)
    host:update(0, hostContext)
    oldClient:update(0, clientContext)
    local disconnectEvent = eventNamed(oldClient:drainEvents(), "disconnected")
    local oldStopped = oldClient:stop("Replacing disconnected LAN session")
    check("lan_reconnect_session_host_removes_old_generation_before_retry",
        disconnected and disconnectEvent and oldStopped
        and host:hudInfo().playerCount == 1 and host.players[initialId] == nil)

    local scheduler = Reconnect.new({ delays = { 0, 1 } })
    scheduler:remember("192.168.1.88:22122", "Returning Worker")
    scheduler:begin(disconnectEvent and disconnectEvent.message)
    local attempt = scheduler:update(0)
    authoritativeMoney = 2222
    now = now + 0.5
    local replacement = Session.new({ transportFactory = network.factory, clock = clock })
    local replacementStarted = replacement:startClient(attempt.address, {
        name = attempt.playerName, character = "rabbit-worker",
    })
    replacement.clientNonce = "lan-reconnect-replacement"
    replacement:update(0, clientContext)
    host:update(0, hostContext)
    replacement:update(0, clientContext)
    local ready = eventNamed(replacement:drainEvents(), "ready")
    local recovered = scheduler:succeeded()
    check("lan_reconnect_session_fresh_generation_uses_new_authoritative_snapshot_only",
        replacementStarted and ready and recovered
        and replacement.ready and replacement.localId == initialId
        and ready.state.money == 2222
        and replacement.pendingInteraction == nil
        and replacement.activeWorkshop == nil
        and replacement.sessionId == host.sessionId
        and network:peer(1) ~= nil
        and host:hudInfo().playerCount == 2
        and not scheduler:isActive())

    replacement:stop("Reconnect session test complete")
    host:update(0, hostContext)
    host:stop("Reconnect session test complete")
end

return Test
