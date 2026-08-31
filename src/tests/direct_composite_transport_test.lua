local DirectComposite = require("src.net.transport_direct_composite")

local Test = {}

local function fakeLink(label)
    local link = {
        mode = "host",
        channels = 3,
        maxGuests = 1,
        peerCapacity = 1,
        label = label,
        events = {},
        sends = {},
        disconnects = {},
        flushCalls = 0,
        closeCalls = 0,
        failPoll = nil,
        throwPoll = nil,
        failSend = nil,
        failFlush = nil,
        failClose = nil,
    }
    function link:poll()
        if self.throwPoll then error(self.throwPoll) end
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
        if self.failSend then return false, self.failSend end
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
        if self.failFlush then return false, self.failFlush end
        return true
    end
    function link:close()
        self.closeCalls = self.closeCalls + 1
        if self.closeResult ~= nil then return self.closeResult end
        if type(self.failClose) == "number" then
            self.closeResult = self.closeCalls > self.failClose
            return self.closeResult
        end
        self.closeResult = not self.failClose
        return self.closeResult
    end
    return link
end

local function factoryFor(link, log)
    local factory = {}
    log.closeCalls = log.closeCalls or 0
    function factory.createHost(options)
        log.calls = log.calls + 1
        log.options = options
        if log.throw then error(log.throw) end
        if log.fail then return nil, log.fail end
        return link
    end
    function factory.close()
        log.closeCalls = log.closeCalls + 1
        return log.closeResult ~= false
    end
    return factory
end

local function eventOf(events, eventType, peer)
    for _, event in ipairs(events or {}) do
        if event.type == eventType and (peer == nil or event.peer == peer) then
            return event
        end
    end
end

local function containsText(value, needle, seen)
    if type(value) == "string" then return value:find(needle, 1, true) ~= nil end
    if type(value) ~= "table" then return false end
    seen = seen or {}
    if seen[value] then return false end
    seen[value] = true
    for key, item in pairs(value) do
        if containsText(key, needle, seen) or containsText(item, needle, seen) then
            return true
        end
    end
    return false
end

function Test.run(_, check)
    local leakedInvitation = "TPS2H-DO-NOT-EXPOSE-THIS-INVITATION"
    local compositeFactory, controller = DirectComposite.newFactory({ channels = 3 })
    local first, second, third = fakeLink("first"), fakeLink("second"), fakeLink("third")
    local firstLog, secondLog, thirdLog = { calls = 0 }, { calls = 0 }, { calls = 0 }
    local firstHandle, firstError = controller:attachFactory(
        factoryFor(first, firstLog), { port = 23122, private = leakedInvitation })
    local secondHandle = controller:attachFactory(
        factoryFor(second, secondLog), { port = 23123 })
    local thirdHandle = controller:attachInstance(third)
    check("direct_composite_materializes_owned_links_before_session_handoff",
        compositeFactory and firstHandle and not firstError and secondHandle and thirdHandle
        and controller:linkCount() == 3 and controller:capacity() == 3
        and controller:remainingCapacity() == 0
        and firstLog.calls == 1 and secondLog.calls == 1
        and firstLog.options.channels == 3
        and firstLog.options.maxGuests == 1
        and firstLog.options.peerCapacity == 1
        and firstLog.options.port == 23122)

    local fourthLog = { calls = 0, fail = leakedInvitation }
    local fourthHandle, fourthError = controller:attachFactory(
        factoryFor(fakeLink("fourth"), fourthLog), { port = 23124 })
    check("direct_composite_rejects_a_fourth_link_before_factory_or_secret_activity",
        fourthHandle == nil and fourthError == DirectComposite.ERROR_FULL
        and fourthLog.calls == 0 and fourthLog.closeCalls == 1
        and not fourthError:find(leakedInvitation, 1, true))

    local host = assert(compositeFactory.createHost({ channels = 3, maxGuests = 3 }))
    local secondHost, secondHostError = compositeFactory.createHost({ channels = 3 })
    check("direct_composite_factory_hands_one_host_transport_to_session_once",
        host.mode == "host" and host.maxGuests == 3 and host.peerCapacity == 3
        and secondHost == nil and type(secondHostError) == "string"
        and not secondHostError:find(leakedInvitation, 1, true))

    local rawFirst = { invitation = leakedInvitation, id = "raw-first" }
    local rawSecond = { invitation = leakedInvitation, id = "raw-second" }
    local rawThird = { invitation = leakedInvitation, id = "raw-third" }
    first.events[#first.events + 1] = {
        type = "connect", peer = rawFirst, invitation = leakedInvitation,
    }
    second.events[#second.events + 1] = {
        type = "connect", peer = rawSecond, invitation = leakedInvitation,
    }
    third.events[#third.events + 1] = {
        type = "connect", peer = rawThird, invitation = leakedInvitation,
    }
    local connected, connectError = host:service(8)
    local firstConnect = connected[1]
    local secondConnect = connected[2]
    local thirdConnect = connected[3]
    local firstPeer = firstConnect and firstConnect.peer
    local secondPeer = secondConnect and secondConnect.peer
    local thirdPeer = thirdConnect and thirdConnect.peer
    check("direct_composite_maps_three_links_to_stable_opaque_peers",
        connectError == nil and #connected == 3
        and firstConnect.type == "connect" and secondConnect.type == "connect"
        and thirdConnect.type == "connect"
        and firstPeer ~= rawFirst and secondPeer ~= rawSecond and thirdPeer ~= rawThird
        and firstPeer ~= secondPeer and secondPeer ~= thirdPeer and firstPeer ~= thirdPeer
        and next(firstPeer) == nil and next(secondPeer) == nil and next(thirdPeer) == nil
        and controller:peerCount() == 3
        and not containsText(connected, leakedInvitation))

    first.events[#first.events + 1] = {
        type = "receive",
        peer = rawFirst,
        data = "first-game-packet",
        channel = 1,
        reliable = false,
        invitation = leakedInvitation,
    }
    second.events[#second.events + 1] = {
        type = "receive",
        peer = rawSecond,
        payload = "second-game-packet",
        channel = 2,
        reliable = true,
        invitation = leakedInvitation,
    }
    local received = host:service(4)
    local firstReceive, secondReceive
    for _, event in ipairs(received) do
        if event.data == "first-game-packet" then firstReceive = event end
        if event.data == "second-game-packet" then secondReceive = event end
    end
    check("direct_composite_preserves_peer_identity_channels_and_payload_only",
        firstReceive and firstReceive.peer == firstPeer
        and firstReceive.channel == 1 and firstReceive.reliable == false
        and secondReceive and secondReceive.peer == secondPeer
        and secondReceive.channel == 2 and secondReceive.reliable == true
        and secondReceive.data == secondReceive.payload
        and not containsText(received, leakedInvitation))

    local targeted = host:send(firstPeer, "targeted", 1, false)
    local broadcast = host:broadcast("broadcast", 2, true)
    local flushed = host:flush()
    check("direct_composite_routes_targeted_send_broadcast_and_flush",
        targeted and broadcast and flushed
        and #first.sends == 2 and first.sends[1].peer == rawFirst
        and first.sends[1].payload == "targeted"
        and first.sends[2].payload == "broadcast"
        and #second.sends == 1 and second.sends[1].peer == rawSecond
        and #third.sends == 1 and third.sends[1].peer == rawThird
        and first.flushCalls == 1 and second.flushCalls == 1 and third.flushCalls == 1)

    second.failPoll = leakedInvitation
    local afterFailure, serviceError = host:service(8)
    local isolatedDisconnect = eventOf(afterFailure, "disconnect", secondPeer)
    local firstStillWorks = host:send(firstPeer, "survives-link-two", 1, true)
    local secondGone, secondGoneError = host:send(secondPeer, "must-not-send", 1, true)
    check("direct_composite_converts_one_link_service_error_to_only_its_disconnect",
        serviceError == nil and isolatedDisconnect
        and not containsText(afterFailure, leakedInvitation)
        and firstStillWorks and secondGone == false
        and type(secondGoneError) == "string"
        and not secondGoneError:find(leakedInvitation, 1, true)
        and second.closeCalls == 1
        and first.closeCalls == 0 and third.closeCalls == 0
        and controller:linkCount() == 2 and controller:peerCount() == 2)

    local replacement = fakeLink("replacement")
    local replacementLog = { calls = 0 }
    local replacementHandle = controller:attachFactory(
        factoryFor(replacement, replacementLog), { port = 23125 })
    local rawReplacement = { invitation = leakedInvitation, id = "raw-replacement" }
    replacement.events[#replacement.events + 1] = {
        type = "connect", peer = rawReplacement, invitation = leakedInvitation,
    }
    local replacementEvents = host:service(8)
    local replacementConnect = eventOf(replacementEvents, "connect")
    local replacementPeer = replacementConnect and replacementConnect.peer
    check("direct_composite_accepts_a_fresh_replacement_after_isolated_cleanup",
        replacementHandle and replacementLog.calls == 1
        and replacementPeer and replacementPeer ~= rawReplacement
        and controller:linkCount() == 3 and controller:peerCount() == 3
        and not containsText(replacementEvents, leakedInvitation))

    replacement.failSend = leakedInvitation
    local isolatedBroadcast = host:broadcast("surviving-broadcast", 1, false)
    local sendFailureEvents, sendFailureError = host:service(8)
    check("direct_composite_broadcast_continues_when_one_guest_send_fails",
        isolatedBroadcast and sendFailureError == nil
        and eventOf(sendFailureEvents, "disconnect", replacementPeer)
        and replacement.closeCalls == 1
        and first.sends[#first.sends].payload == "surviving-broadcast"
        and third.sends[#third.sends].payload == "surviving-broadcast"
        and controller:linkCount() == 2 and controller:peerCount() == 2
        and not containsText(sendFailureEvents, leakedInvitation))

    local disconnected = host:disconnect(firstPeer, 9, false)
    check("direct_composite_targeted_disconnect_retires_only_that_one_use_link",
        disconnected and first.closeCalls == 1
        and first.disconnects[#first.disconnects].peer == rawFirst
        and first.disconnects[#first.disconnects].code == 9
        and third.closeCalls == 0
        and controller:linkCount() == 1 and controller:peerCount() == 1)

    local closed, closeError = host:close(0, false)
    local closedAgain, closeAgainError = host:close(0, false)
    check("direct_composite_close_is_idempotent_and_cleans_every_remaining_link_once",
        closed and not closeError and closedAgain and not closeAgainError
        and third.closeCalls == 1
        and controller:linkCount() == 0 and controller:peerCount() == 0)

    local redactedFactory, redactedController = DirectComposite.newFactory({ channels = 3 })
    local badLog = { calls = 0, throw = leakedInvitation }
    local badHandle, badError = redactedController:attachFactory(
        factoryFor(fakeLink("bad"), badLog), { invitation = leakedInvitation })
    local redactedClosed = redactedController:close()
    check("direct_composite_factory_failures_are_generic_and_secret_free",
        redactedFactory and badHandle == nil and badLog.calls == 1
        and badLog.closeCalls == 1
        and badError == DirectComposite.ERROR_ATTACH
        and not badError:find(leakedInvitation, 1, true)
        and redactedClosed)

    local duplicateFactory, duplicateController = DirectComposite.newFactory({ channels = 3 })
    local duplicateLink = fakeLink("duplicate-connect")
    local duplicateHandle = duplicateController:attachInstance(duplicateLink)
    local duplicateHost = duplicateFactory.createHost({ channels = 3 })
    local duplicateRaw = { invitation = leakedInvitation, id = "duplicate-raw" }
    duplicateLink.events[#duplicateLink.events + 1] = {
        type = "connect", peer = duplicateRaw, invitation = leakedInvitation,
    }
    local initialConnect = duplicateHost:service(2)
    local duplicatePeer = initialConnect[1] and initialConnect[1].peer
    duplicateLink.events[#duplicateLink.events + 1] = {
        type = "connect", peer = duplicateRaw, invitation = leakedInvitation,
    }
    local duplicateEvents, duplicateError = duplicateHost:service(4)
    check("direct_composite_second_connect_signal_burns_the_one_guest_link",
        duplicateHandle and duplicatePeer and duplicateError == nil
        and eventOf(duplicateEvents, "disconnect", duplicatePeer)
        and duplicateLink.closeCalls == 1
        and duplicateController:linkCount() == 0
        and duplicateController:peerCount() == 0
        and not containsText(duplicateEvents, leakedInvitation))
    duplicateHost:close()

    local fatalFactory, fatalController = DirectComposite.newFactory({ channels = 3 })
    local fatalLink = fakeLink("fatal-cleanup")
    local fatalHandle = fatalController:attachInstance(fatalLink)
    local fatalHost = fatalFactory.createHost({ channels = 3 })
    local fatalRaw = { invitation = leakedInvitation, id = "fatal-raw" }
    fatalLink.events[#fatalLink.events + 1] = {
        type = "connect", peer = fatalRaw, invitation = leakedInvitation,
    }
    local fatalConnect = fatalHost:service(2)
    fatalLink.failPoll = leakedInvitation
    fatalLink.failClose = 1
    local fatalEvents, fatalError = fatalHost:service(4)
    local blockedSend, blockedError = fatalHost:send(
        fatalConnect[1] and fatalConnect[1].peer, "blocked", 1, true)
    local fatalClosed, fatalCloseError = fatalHost:close()
    check("direct_composite_unverified_link_cleanup_escalates_host_fail_closed",
        fatalHandle and #fatalEvents == 0
        and fatalError == "Direct guest link cleanup failed."
        and blockedSend == false and blockedError == fatalError
        and not fatalError:find(leakedInvitation, 1, true)
        and fatalLink.closeCalls == 2
        and fatalClosed == false and fatalCloseError == fatalError)

    local cleanupFactory, cleanupController = DirectComposite.newFactory({ channels = 3 })
    local cleanupLink = fakeLink("cleanup-failure")
    cleanupLink.failClose = true
    local cleanupHandle = cleanupController:attachInstance(cleanupLink)
    local cleanupHost = cleanupFactory.createHost({ channels = 3 })
    local cleanupOk, cleanupError = cleanupHost:close()
    local cleanupAgain, cleanupAgainError = cleanupHost:close()
    check("direct_composite_remembers_cleanup_failure_across_idempotent_close",
        cleanupHandle and cleanupOk == false and cleanupAgain == false
        and cleanupError == "Direct guest link cleanup failed."
        and cleanupAgainError == cleanupError and cleanupLink.closeCalls == 3)

    local now = 100
    local timeoutFactory, timeoutController = DirectComposite.newFactory({
        channels = 3,
        firstConnectTimeoutSeconds = 2,
        clock = function() return now end,
    })
    local abandoned = fakeLink("abandoned-before-connect")
    local abandonedHandle = timeoutController:attachInstance(abandoned)
    local timeoutHost = timeoutFactory.createHost({ channels = 3 })
    now = 102.01
    local timeoutEvents, timeoutError = timeoutHost:service(4)
    local replacementAfterTimeout = fakeLink("replacement-after-timeout")
    local replacementHandleAfterTimeout = timeoutController:attachInstance(
        replacementAfterTimeout)
    check("direct_composite_expires_an_attached_link_that_never_connects",
        abandonedHandle and #timeoutEvents == 0 and timeoutError == nil
        and abandoned.closeCalls == 1 and timeoutController:linkCount() == 1
        and replacementHandleAfterTimeout ~= nil)
    timeoutHost:close()
end

return Test
