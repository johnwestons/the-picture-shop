local Protocol = require("src.net.protocol")
local Session = require("src.net.session")
local DirectComposite = require("src.net.transport_direct_composite")

local Test = {}

local function fakeLink(label, options)
    options = options or {}
    local link = {
        mode = "host",
        channels = Protocol.CHANNEL_COUNT,
        maxGuests = 1,
        peerCapacity = 1,
        label = label,
        events = {},
        sends = {},
        disconnects = {},
        closeCalls = 0,
        flushCalls = 0,
        failPoll = nil,
        failClose = options.failClose == true,
    }

    function link:poll()
        if self.failPoll then return nil, self.failPoll end
        return table.remove(self.events, 1)
    end

    function link:send(peer, payload, channel, reliable)
        self.sends[#self.sends + 1] = {
            peer = peer,
            payload = payload,
            channel = channel,
            reliable = reliable,
        }
        return true
    end

    function link:disconnect(peer, code, immediate)
        self.disconnects[#self.disconnects + 1] = {
            peer = peer,
            code = code,
            immediate = immediate,
        }
        return true
    end

    function link:flush()
        self.flushCalls = self.flushCalls + 1
        return true
    end

    function link:close()
        self.closeCalls = self.closeCalls + 1
        return not self.failClose
    end

    return link
end

local function factoryFor(link)
    local factory = {}
    local created = false
    local closed = false
    function factory.createHost(options)
        if created or closed then
            return nil, "The fake one-use factory is unavailable."
        end
        created = true
        link.createOptions = options
        return link
    end
    function factory.close()
        -- Before createHost, close disposes the unused factory. Once createHost
        -- succeeds, ownership belongs to the returned link and the factory must
        -- not close that handed-off transport.
        if created then return true end
        closed = true
        return true
    end
    return factory
end

local function eventNamed(events, eventType, predicate)
    for _, event in ipairs(events or {}) do
        if event.type == eventType and (not predicate or predicate(event)) then
            return event
        end
    end
end

local function playerCount(session)
    local count = 0
    for _ in pairs(session.players or {}) do count = count + 1 end
    return count
end

local function queueConnect(link, rawPeer)
    link.events[#link.events + 1] = { type = "connect", peer = rawPeer }
end

local function queueHello(link, rawPeer, name, nonce)
    local packet = assert(Protocol.encode("hello", {
        clientNonce = nonce,
        name = name,
        character = "rabbit-worker",
    }))
    link.events[#link.events + 1] = {
        type = "receive",
        peer = rawPeer,
        data = packet,
        channel = Protocol.route("hello"),
        reliable = true,
    }
end

local function hostContext()
    return {
        localPlayer = {
            x = 400,
            y = 500,
            velocityX = 0,
            velocityY = 0,
            intentX = 1,
            intentY = 0,
            animationDistance = 0,
            moving = false,
            facing = 1,
            character = "rabbit-worker",
        },
        resolveGuestSpawn = function(hostX, hostY, guestIndex)
            return hostX + guestIndex * 10, hostY
        end,
        getShopSnapshot = function()
            return {
                state = { money = 5000, inventory = {}, jobs = {} },
                player = { x = 400, y = 500, character = "rabbit-worker" },
            }
        end,
        moveRemote = function() end,
    }
end

local function attachAndRequest(controller, session, context, link, rawPeer, name, nonce)
    local handle, attachError = controller:attachFactory(
        factoryFor(link), { channels = Protocol.CHANNEL_COUNT })
    if not handle then return nil, attachError end
    queueConnect(link, rawPeer)
    session:update(0, context)
    queueHello(link, rawPeer, name, nonce)
    session:update(0, context)
    local request = eventNamed(session:drainEvents(), "join_requested", function(event)
        return event.name == name
    end)
    return request, nil, handle
end

function Test.run(_, check)
    local now = 100
    local clock = function() return now end
    local context = hostContext()
    local compositeFactory, controller = DirectComposite.newFactory({
        channels = Protocol.CHANNEL_COUNT,
        maxGuests = Protocol.MAX_PLAYERS - 1,
    })
    local firstLink = fakeLink("first")
    local firstHandle = controller:attachFactory(
        factoryFor(firstLink), { channels = Protocol.CHANNEL_COUNT })
    local host = Session.new({ clock = clock })
    local hosted, hostError = host:startHost({
        name = "Composite Host",
        character = "rabbit-worker",
        networkKind = "direct",
        transportFactory = compositeFactory,
    })
    host:drainEvents()
    check("direct_composite_session_starts_with_one_attached_single_guest_link",
        firstHandle and hosted and hostError == nil
        and host:isHost() and host.networkKind == "direct" and host.ready
        and firstLink.createOptions.maxGuests == 1
        and firstLink.createOptions.peerCapacity == 1
        and controller:linkCount() == 1 and controller:peerCount() == 0)

    local firstRaw = { id = "first-raw" }
    queueConnect(firstLink, firstRaw)
    host:update(0, context)
    queueHello(firstLink, firstRaw, "Direct Worker Two", "composite-nonce-two")
    host:update(0, context)
    local firstRequest = eventNamed(host:drainEvents(), "join_requested")
    local firstQuarantined = firstRequest and playerCount(host) == 1
        and #firstLink.sends == 0
    local firstApproved = firstRequest and host:approveJoin(firstRequest.requestId)
    host:update(0, context)
    local firstJoined = eventNamed(host:drainEvents(), "player_joined")
    local firstPlayerId = firstJoined and firstJoined.playerId
    check("direct_composite_session_first_link_requires_approval_before_joining",
        firstRequest and firstQuarantined and firstApproved and firstJoined
        and firstPlayerId and host.players[firstPlayerId]
        and playerCount(host) == 2 and controller:peerCount() == 1
        and not host.terminal and host.transport ~= nil)

    local secondLink = fakeLink("second")
    local secondRaw = { id = "second-raw" }
    local secondRequest, secondError, secondHandle = attachAndRequest(
        controller, host, context, secondLink, secondRaw,
        "Direct Worker Three", "composite-nonce-three")
    local secondQuarantined = secondRequest and playerCount(host) == 2
        and #secondLink.sends == 0
    local secondApproved = secondRequest and host:approveJoin(secondRequest.requestId)
    host:update(0, context)
    local secondJoined = eventNamed(host:drainEvents(), "player_joined")
    local secondPlayerId = secondJoined and secondJoined.playerId
    check("direct_composite_session_attaches_and_approves_a_second_link_sequentially",
        secondHandle and secondError == nil and secondRequest and secondQuarantined
        and secondApproved
        and secondJoined and secondPlayerId and secondPlayerId ~= firstPlayerId
        and host.players[firstPlayerId] and host.players[secondPlayerId]
        and playerCount(host) == 3 and controller:linkCount() == 2
        and controller:peerCount() == 2 and not host.terminal)

    firstLink.failPoll = "first link failed"
    host:update(0, context)
    local failureEvents = host:drainEvents()
    local firstLeft = eventNamed(failureEvents, "player_left", function(event)
        return event.playerId == firstPlayerId
    end)
    check("direct_composite_session_one_link_failure_preserves_host_and_surviving_guest",
        firstLeft and firstLink.closeCalls == 1
        and eventNamed(failureEvents, "disconnected") == nil
        and eventNamed(failureEvents, "error") == nil
        and host.players[firstPlayerId] == nil and host.players[secondPlayerId] ~= nil
        and playerCount(host) == 2 and controller:linkCount() == 1
        and controller:peerCount() == 1 and host:isHost() and host.ready
        and not host.terminal and host.transport ~= nil)

    local replacementLink = fakeLink("replacement")
    local replacementRaw = { id = "replacement-raw" }
    local replacementRequest, replacementError, replacementHandle = attachAndRequest(
        controller, host, context, replacementLink, replacementRaw,
        "Replacement Worker", "composite-nonce-replacement")
    local replacementApproved = replacementRequest
        and host:approveJoin(replacementRequest.requestId)
    host:update(0, context)
    local replacementJoined = eventNamed(host:drainEvents(), "player_joined")
    local replacementPlayerId = replacementJoined and replacementJoined.playerId
    check("direct_composite_session_replaces_a_failed_link_with_fresh_approval",
        replacementHandle and replacementError == nil and replacementRequest
        and secondRequest
        and replacementRequest.requestId > secondRequest.requestId
        and replacementApproved and replacementJoined and replacementPlayerId
        and host.players[secondPlayerId] and host.players[replacementPlayerId]
        and playerCount(host) == 3 and controller:linkCount() == 2
        and controller:peerCount() == 2 and not host.terminal)

    local kicked, kickMessage
    if replacementPlayerId then
        kicked, kickMessage = host:kickPlayer(replacementPlayerId)
    end
    local kickEvents = host:drainEvents()
    local kickedEvent = eventNamed(kickEvents, "player_kicked", function(event)
        return event.playerId == replacementPlayerId
    end)
    check("direct_composite_session_kick_retires_only_the_target_link",
        kicked and type(kickMessage) == "string" and kickedEvent
        and eventNamed(kickEvents, "disconnected") == nil
        and replacementLink.closeCalls == 1
        and host.players[replacementPlayerId] == nil
        and host.players[secondPlayerId] ~= nil and playerCount(host) == 2
        and controller:linkCount() == 1 and controller:peerCount() == 1
        and host:isHost() and host.ready and not host.terminal)

    local stopped = host:stop("Composite integration complete")
    local closedAgain, closeAgainError = controller:close()
    check("direct_composite_session_stop_closes_every_owned_link_idempotently",
        stopped and not host:isActive() and secondLink.closeCalls == 1
        and controller:linkCount() == 0 and controller:peerCount() == 0
        and closedAgain and closeAgainError == nil)

    local failingFactory, failingController = DirectComposite.newFactory({
        channels = Protocol.CHANNEL_COUNT,
        maxGuests = Protocol.MAX_PLAYERS - 1,
    })
    local failingLink = fakeLink("persistent-cleanup-failure", { failClose = true })
    local failingHandle = failingController:attachFactory(
        factoryFor(failingLink), { channels = Protocol.CHANNEL_COUNT })
    local failingHost = Session.new({ clock = clock })
    local failingStarted = failingHost:startHost({
        name = "Cleanup Truth Host",
        character = "rabbit-worker",
        networkKind = "direct",
        transportFactory = failingFactory,
    })
    local failingStopped, failingStopError = failingHost:stop(
        "Exercise persistent cleanup failure")
    local cleanupVerified, cleanupError = failingController:close()
    check("direct_composite_session_persistent_cleanup_failure_remains_unverified",
        failingHandle and failingStarted and failingStopped == false
        and type(failingStopError) == "string"
        and cleanupVerified == false
        and cleanupError == "Direct guest link cleanup failed."
        and failingLink.closeCalls >= 3)
end

return Test
