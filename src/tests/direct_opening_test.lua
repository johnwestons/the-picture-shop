local DirectOpening = require("src.net.direct_opening")
local DirectOpeningCode = require("src.net.direct_opening_code")

local Test = {}

local HOST_ADDRESS = "2606:4700:4700::1111"
local GUEST_ADDRESS = "2001:4860:4860::8888"
local OTHER_ADDRESS = "2607:f8b0:4005:805::200e"
local HOST_PORT = 22122
local GUEST_PORT = 28686
local KEY = string.rep("K", 32)
local INVITATION_ID = string.rep("I", 16)
local GUEST_NONCE = string.rep("N", 16)
local RESPONSE_TAG = string.rep("T", 32)
local SECRET_ERROR = "must-not-leak-" .. KEY .. INVITATION_ID .. GUEST_NONCE

local function openingRecords()
    return {
        host = {
            kind = "host",
            version = 2,
            issuedAt = 1700000000,
            lifetime = 600,
            address = HOST_ADDRESS,
            hostAddress = HOST_ADDRESS,
            port = HOST_PORT,
            hostPort = HOST_PORT,
            invitationId = INVITATION_ID,
            masterKey = KEY,
        },
        response = {
            kind = "response",
            version = 2,
            issuedAt = 1700000000,
            lifetime = 600,
            address = GUEST_ADDRESS,
            guestAddress = GUEST_ADDRESS,
            port = GUEST_PORT,
            guestPort = GUEST_PORT,
            invitationId = INVITATION_ID,
            guestNonce = GUEST_NONCE,
            responseTag = RESPONSE_TAG,
        },
    }
end

local function packet(role, acknowledged)
    local header = role .. (acknowledged and "1" or "0")
    return header .. string.rep(role, DirectOpening.PACKET_BYTES - #header)
end

local function fakeSocket()
    local socket = {
        inbound = {},
        sends = {},
        receiveCalls = 0,
        closeCalls = 0,
        timeoutCalls = {},
    }
    function socket:settimeout(value)
        self.timeoutCalls[#self.timeoutCalls + 1] = value
        if self.failSetTimeout then return nil, SECRET_ERROR end
        return 1
    end
    function socket:sendto(payload, address, port)
        if self.raiseSend then error(SECRET_ERROR) end
        if self.failSend then return nil, SECRET_ERROR end
        self.sends[#self.sends + 1] = {
            payload = payload,
            address = address,
            port = port,
            socket = self,
        }
        return self.returnOne and 1 or #payload
    end
    function socket:receivefrom()
        self.receiveCalls = self.receiveCalls + 1
        if self.raiseReceive then error(SECRET_ERROR) end
        if self.failReceive then return nil, SECRET_ERROR end
        if #self.inbound == 0 then return nil, "timeout" end
        local item = table.remove(self.inbound, 1)
        return item.payload, item.address, item.port
    end
    function socket:close()
        self.closeCalls = self.closeCalls + 1
        if self.raiseClose then error(SECRET_ERROR) end
        if self.failClose then return nil, SECRET_ERROR end
        return true
    end
    return socket
end

local function fakeProvider(overrides)
    local provider = {
        states = {},
        constructorCalls = {},
        verifierCalls = {},
        overrides = overrides or {},
    }
    local expected = openingRecords()
    local expectedTranscript = DirectOpeningCode.responseTranscript(
        expected.host, expected.response)

    function provider.verifyResponseTag(key, transcript, tag)
        provider.verifierCalls[#provider.verifierCalls + 1] = {
            key = key,
            transcript = transcript,
            tag = tag,
        }
        if provider.overrides.raiseVerify then error(SECRET_ERROR) end
        if provider.overrides.failVerify then return nil, SECRET_ERROR end
        if provider.overrides.rejectVerify then return false, SECRET_ERROR end
        return key == KEY and transcript == expectedTranscript
            and tag == RESPONSE_TAG
    end

    local function newState(role, key, invitationId, guestNonce)
        provider.constructorCalls[#provider.constructorCalls + 1] = {
            role = role,
            key = key,
            invitationId = invitationId,
            guestNonce = guestNonce,
        }
        if provider.overrides.raiseConstructor then error(SECRET_ERROR) end
        if provider.overrides.rejectConstructor then return nil, SECRET_ERROR end

        local state = {
            role = role,
            peerRole = role == "H" and "G" or "H",
            acknowledged = false,
            ready = provider.overrides.initialReady == true,
            receiveCalls = 0,
            acceptedCalls = 0,
            rejectedCalls = 0,
            nextCalls = 0,
            readyCalls = 0,
            closeCalls = 0,
        }
        function state:next()
            self.nextCalls = self.nextCalls + 1
            if provider.overrides.raiseNext then error(SECRET_ERROR) end
            if provider.overrides.failNext then return nil, SECRET_ERROR end
            return packet(self.role, self.acknowledged)
        end
        function state:receive(value)
            self.receiveCalls = self.receiveCalls + 1
            if provider.overrides.raiseReceive then error(SECRET_ERROR) end
            if provider.overrides.failReceive then return nil, SECRET_ERROR end
            if provider.overrides.rejectReceive then
                self.rejectedCalls = self.rejectedCalls + 1
                return false, SECRET_ERROR
            end
            local plain = packet(self.peerRole, false)
            local acknowledged = packet(self.peerRole, true)
            if value == acknowledged then
                local changed = not self.acknowledged or not self.ready
                self.acknowledged = true
                self.ready = true
                if changed then
                    self.acceptedCalls = self.acceptedCalls + 1
                else
                    self.rejectedCalls = self.rejectedCalls + 1
                end
                return changed
            end
            if value == plain and not self.acknowledged then
                self.acknowledged = true
                self.acceptedCalls = self.acceptedCalls + 1
                return true
            end
            self.rejectedCalls = self.rejectedCalls + 1
            return false, SECRET_ERROR
        end
        function state:isReady()
            self.readyCalls = self.readyCalls + 1
            if provider.overrides.raiseReady then error(SECRET_ERROR) end
            if provider.overrides.failReady then return nil, SECRET_ERROR end
            return self.ready
        end
        function state:close()
            self.closeCalls = self.closeCalls + 1
            if provider.overrides.raiseClose then error(SECRET_ERROR) end
            if provider.overrides.failClose then return nil, SECRET_ERROR end
            return true
        end
        provider.states[#provider.states + 1] = state
        return state
    end

    function provider.newOpeningHost(key, invitationId, guestNonce)
        return newState("H", key, invitationId, guestNonce)
    end
    function provider.newOpeningGuest(key, invitationId, guestNonce)
        return newState("G", key, invitationId, guestNonce)
    end
    return provider
end

local function enqueue(socket, payload, address, port)
    socket.inbound[#socket.inbound + 1] = {
        payload = payload,
        address = address,
        port = port,
    }
end

local function deliverNew(source, target, sourceAddress, sourcePort, cursor, reverse)
    local pending = {}
    for index = cursor + 1, #source.sends do pending[#pending + 1] = source.sends[index] end
    if reverse then
        for index = #pending, 1, -1 do
            enqueue(target, pending[index].payload, sourceAddress, sourcePort)
        end
    else
        for _, send in ipairs(pending) do
            enqueue(target, send.payload, sourceAddress, sourcePort)
        end
    end
    return #source.sends
end

local function controllerOptions(role, socket, provider, clock, ownsSocket)
    local records = openingRecords()
    return {
        role = role,
        host = records.host,
        response = records.response,
        socket = socket,
        provider = provider,
        clock = clock,
        ownsSocket = ownsSocket,
        timeoutSeconds = 10,
    }
end

local function containsSecret(value)
    if type(value) ~= "string" then return false end
    return value:find(KEY, 1, true) ~= nil
        or value:find(INVITATION_ID, 1, true) ~= nil
        or value:find(GUEST_NONCE, 1, true) ~= nil
        or value:find(SECRET_ERROR, 1, true) ~= nil
end

function Test.run(_, check)
    local now = 100
    local clock = function() return now end
    local hostSocket, guestSocket = fakeSocket(), fakeSocket()
    local provider = fakeProvider()
    local host = DirectOpening.create(controllerOptions(
        "host", hostSocket, provider, clock, false))
    local guest = DirectOpening.create(controllerOptions(
        "guest", guestSocket, provider, clock, false))
    check("direct_opening_starts_both_roles_immediately_on_the_injected_sockets",
        host and guest and host.status == "opening" and guest.status == "opening"
        and #hostSocket.sends == 1 and #guestSocket.sends == 1
        and hostSocket.sends[1].socket == hostSocket
        and guestSocket.sends[1].socket == guestSocket
        and hostSocket.sends[1].address == GUEST_ADDRESS
        and hostSocket.sends[1].port == GUEST_PORT
        and guestSocket.sends[1].address == HOST_ADDRESS
        and guestSocket.sends[1].port == HOST_PORT
        and hostSocket.timeoutCalls[1] == 0 and guestSocket.timeoutCalls[1] == 0)
    check("direct_opening_passes_fixed_secret_inputs_only_to_the_selected_native_roles",
        #provider.constructorCalls == 2
        and #provider.verifierCalls == 2
        and provider.constructorCalls[1].role == "H"
        and provider.constructorCalls[2].role == "G"
        and provider.constructorCalls[1].key == KEY
        and provider.constructorCalls[2].invitationId == INVITATION_ID
        and provider.constructorCalls[2].guestNonce == GUEST_NONCE)

    local hostCursor, guestCursor = 0, 0
    hostCursor = deliverNew(hostSocket, guestSocket, HOST_ADDRESS, HOST_PORT, hostCursor)
    guestCursor = deliverNew(guestSocket, hostSocket, GUEST_ADDRESS, GUEST_PORT, guestCursor)
    host:update()
    guest:poll()
    hostCursor = deliverNew(hostSocket, guestSocket, HOST_ADDRESS, HOST_PORT, hostCursor)
    guestCursor = deliverNew(guestSocket, hostSocket, GUEST_ADDRESS, GUEST_PORT, guestCursor)
    host:update()
    guest:update()
    local sendsAtNativeReady = #hostSocket.sends + #guestSocket.sends
    check("direct_opening_native_readiness_enters_bounded_confirmation_before_handoff",
        provider.states[1].ready and provider.states[2].ready
        and host.status == "confirming" and guest.status == "confirming"
        and not host:isReady() and not guest:isReady())
    now = 102.999
    host:update()
    guest:update()
    local hiddenBeforeGrace = not host:isReady() and not guest:isReady()
    now = 103
    host:update()
    guest:update()
    check("direct_opening_two_controllers_converge_only_after_native_readiness",
        hiddenBeforeGrace and host:isReady() and guest:isReady()
        and host.status == "ready" and guest.status == "ready"
        and provider.states[1].ready and provider.states[2].ready
        and #hostSocket.sends + #guestSocket.sends == sendsAtNativeReady + 2)
    local handedOffSocket = host:takeSocket()
    local secondHandoff, secondHandoffError = host:takeSocket()
    check("direct_opening_hands_the_authenticated_socket_to_the_bridge_exactly_once",
        handedOffSocket == hostSocket and host.status == "handed_off"
        and not host:isReady() and provider.states[1].closeCalls == 1
        and hostSocket.closeCalls == 0
        and secondHandoff == nil
        and secondHandoffError == "Direct opening initialization failed.")
    check("direct_opening_keeps_socket_ownership_explicit_at_close",
        host:close() and host:close() and guest:close()
        and provider.states[1].closeCalls == 1
        and provider.states[2].closeCalls == 1
        and hostSocket.closeCalls == 0 and guestSocket.closeCalls == 0)

    now = 200
    local retrySocket, retryProvider = fakeSocket(), fakeProvider()
    retrySocket.returnOne = true
    local retry = DirectOpening.create(controllerOptions(
        "host", retrySocket, retryProvider, clock, false))
    local initialPacket = retrySocket.sends[1].payload
    now = 200.249
    retry:update()
    local beforeBoundary = #retrySocket.sends
    now = 200.250
    retry:update()
    check("direct_opening_retries_the_same_native_flight_every_250_milliseconds",
        retry and beforeBoundary == 1 and #retrySocket.sends == 2
        and retrySocket.sends[2].payload == initialPacket
        and retrySocket.sends[2].address == GUEST_ADDRESS
        and retrySocket.sends[2].port == GUEST_PORT)
    retry:close()

    now = 300
    local lossHostSocket, lossGuestSocket = fakeSocket(), fakeSocket()
    local lossProvider = fakeProvider()
    local lossHost = DirectOpening.create(controllerOptions(
        "host", lossHostSocket, lossProvider, clock, false))
    local lossGuest = DirectOpening.create(controllerOptions(
        "guest", lossGuestSocket, lossProvider, clock, false))
    -- Discard both first flights, then deliver retries in reverse order with
    -- duplicates.  Native state, rather than the controller, judges replay.
    now = 300.25
    lossHost:update()
    lossGuest:update()
    enqueue(lossHostSocket, lossGuestSocket.sends[2].payload,
        GUEST_ADDRESS, GUEST_PORT)
    enqueue(lossHostSocket, lossGuestSocket.sends[1].payload,
        GUEST_ADDRESS, GUEST_PORT)
    enqueue(lossGuestSocket, lossHostSocket.sends[2].payload,
        HOST_ADDRESS, HOST_PORT)
    enqueue(lossGuestSocket, lossHostSocket.sends[2].payload,
        HOST_ADDRESS, HOST_PORT)
    lossHost:update()
    lossGuest:update()
    local lossHostCursor, lossGuestCursor = #lossHostSocket.sends, #lossGuestSocket.sends
    lossHostCursor = deliverNew(lossHostSocket, lossGuestSocket,
        HOST_ADDRESS, HOST_PORT, lossHostCursor - 1, true)
    lossGuestCursor = deliverNew(lossGuestSocket, lossHostSocket,
        GUEST_ADDRESS, GUEST_PORT, lossGuestCursor - 1, true)
    lossHost:update()
    lossGuest:update()
    now = 303.249
    lossHost:update()
    lossGuest:update()
    local lossStillConfirming = not lossHost:isReady() and not lossGuest:isReady()
    now = 303.25
    lossHost:update()
    lossGuest:update()
    check("direct_opening_survives_loss_reordering_and_duplicate_authenticated_packets",
        lossStillConfirming and lossHost:isReady() and lossGuest:isReady()
        and lossProvider.states[1].receiveCalls >= 2
        and lossProvider.states[2].receiveCalls >= 2)
    lossHost:close()
    lossGuest:close()

    local function convergesAfterDroppedFinal(dropRole, startedAt)
        now = startedAt
        local firstSocket, secondSocket = fakeSocket(), fakeSocket()
        local finalProvider = fakeProvider()
        local first = DirectOpening.create(controllerOptions(
            "host", firstSocket, finalProvider, clock, false))
        local second = DirectOpening.create(controllerOptions(
            "guest", secondSocket, finalProvider, clock, false))

        -- Exchange only the initial flights.  Each side then creates the
        -- authenticated flight which can make the peer native-ready.
        enqueue(firstSocket, secondSocket.sends[1].payload,
            GUEST_ADDRESS, GUEST_PORT)
        enqueue(secondSocket, firstSocket.sends[1].payload,
            HOST_ADDRESS, HOST_PORT)
        first:update()
        second:update()

        local readySide, waitingSide, readySocket, waitingSocket
        local readySourceAddress, readySourcePort
        local waitingSourceAddress, waitingSourcePort
        if dropRole == "host" then
            readySide, waitingSide = first, second
            readySocket, waitingSocket = firstSocket, secondSocket
            readySourceAddress, readySourcePort = HOST_ADDRESS, HOST_PORT
            waitingSourceAddress, waitingSourcePort = GUEST_ADDRESS, GUEST_PORT
        else
            readySide, waitingSide = second, first
            readySocket, waitingSocket = secondSocket, firstSocket
            readySourceAddress, readySourcePort = GUEST_ADDRESS, GUEST_PORT
            waitingSourceAddress, waitingSourcePort = HOST_ADDRESS, HOST_PORT
        end

        -- Deliver only the waiting side's peer-ready flight.  The ready side
        -- now emits its LOCAL_VERIFIED/final flight; deliberately drop it as
        -- well as the preceding copy, reproducing the reviewed failure.
        enqueue(readySocket, waitingSocket.sends[2].payload,
            waitingSourceAddress, waitingSourcePort)
        readySide:update()
        local droppedFinalIndex = #readySocket.sends
        local nativeReadyButHidden = readySide.status == "confirming"
            and not readySide:isReady() and waitingSide.status == "opening"

        -- The waiting side retransmits.  Native replay rejection on the ready
        -- side is false, but the controller's independent timer must still
        -- retransmit the dropped final flight from this same socket.
        now = startedAt + DirectOpening.RETRY_SECONDS
        waitingSide:update()
        enqueue(readySocket, waitingSocket.sends[#waitingSocket.sends].payload,
            waitingSourceAddress, waitingSourcePort)
        local readyReceiveBefore = finalProvider.states[
            dropRole == "host" and 1 or 2].receiveCalls
        local readyRejectBefore = finalProvider.states[
            dropRole == "host" and 1 or 2].rejectedCalls
        local readySendBefore = #readySocket.sends
        readySide:update()
        local replayWasRejectedButRetrySent = finalProvider.states[
            dropRole == "host" and 1 or 2].receiveCalls == readyReceiveBefore + 1
            and finalProvider.states[
                dropRole == "host" and 1 or 2].rejectedCalls
                    == readyRejectBefore + 1
            and #readySocket.sends == readySendBefore + 1
            and droppedFinalIndex == 3
        enqueue(waitingSocket, readySocket.sends[#readySocket.sends].payload,
            readySourceAddress, readySourcePort)
        waitingSide:update()
        local bothNativeReady = finalProvider.states[1].ready
            and finalProvider.states[2].ready
            and readySide.status == "confirming"
            and waitingSide.status == "confirming"

        now = startedAt + DirectOpening.READY_LINGER_SECONDS
        first:update()
        second:update()
        local firstGraceIsIndependent = readySide:isReady()
            and not waitingSide:isReady()
        now = startedAt + DirectOpening.READY_LINGER_SECONDS
            + DirectOpening.RETRY_SECONDS
        first:update()
        second:update()
        local converged = first:isReady() and second:isReady()
        first:close()
        second:close()
        return nativeReadyButHidden and replayWasRejectedButRetrySent
            and bothNativeReady and firstGraceIsIndependent and converged
    end

    check("direct_opening_host_final_flight_loss_recovers_during_authenticated_linger",
        convergesAfterDroppedFinal("host", 350))
    check("direct_opening_guest_final_flight_loss_recovers_during_authenticated_linger",
        convergesAfterDroppedFinal("guest", 360))

    now = 370
    local boundedSocket = fakeSocket()
    local boundedProvider = fakeProvider({ initialReady = true })
    local bounded = DirectOpening.create(controllerOptions(
        "host", boundedSocket, boundedProvider, clock, false))
    for index = 1, 100 do
        enqueue(boundedSocket, string.rep("x", DirectOpening.PACKET_BYTES),
            OTHER_ADDRESS, 31000 + index)
    end
    local readsBeforeConfirmationFlood = boundedSocket.receiveCalls
    local remainedHidden = bounded.status == "confirming" and not bounded:isReady()
    local maximumConfirmationReceiveWork = 0
    for step = 1, 11 do
        now = 370 + step * DirectOpening.RETRY_SECONDS
        local readsBeforeUpdate = boundedSocket.receiveCalls
        bounded:update()
        maximumConfirmationReceiveWork = math.max(maximumConfirmationReceiveWork,
            boundedSocket.receiveCalls - readsBeforeUpdate)
        remainedHidden = remainedHidden and not bounded:isReady()
    end
    local confirmationReads = boundedSocket.receiveCalls
        - readsBeforeConfirmationFlood
    now = 370 + DirectOpening.READY_LINGER_SECONDS
    bounded:update()
    check("direct_opening_confirmation_phase_has_fixed_time_send_and_receive_bounds",
        DirectOpening.READY_LINGER_SECONDS == 3
        and remainedHidden and bounded:isReady()
        and #boundedSocket.sends == 13
        and boundedProvider.states[1].receiveCalls == 0
        and confirmationReads >= 100
        and maximumConfirmationReceiveWork
            <= DirectOpening.MAX_RECEIVES_PER_UPDATE)
    bounded:close()

    now = 380
    local phaseTimeoutSocket = fakeSocket()
    local phaseTimeoutProvider = fakeProvider({ initialReady = true })
    local phaseTimeoutOptions = controllerOptions(
        "guest", phaseTimeoutSocket, phaseTimeoutProvider, clock, true)
    phaseTimeoutOptions.timeoutSeconds = 2
    local phaseTimeout = DirectOpening.create(phaseTimeoutOptions)
    now = 382
    local phaseTimeoutStatus = phaseTimeout:update()
    check("direct_opening_overall_timeout_still_bounds_native_ready_confirmation",
        phaseTimeoutStatus == "failed" and not phaseTimeout:isReady()
        and phaseTimeoutProvider.states[1].closeCalls == 1
        and phaseTimeoutSocket.closeCalls == 1)

    now = 400
    local sourceSocket, sourceProvider = fakeSocket(), fakeProvider()
    local source = DirectOpening.create(controllerOptions(
        "host", sourceSocket, sourceProvider, clock, false))
    local peerPacket = packet("G", false)
    enqueue(sourceSocket, peerPacket, OTHER_ADDRESS, GUEST_PORT)
    enqueue(sourceSocket, peerPacket, GUEST_ADDRESS, GUEST_PORT + 1)
    enqueue(sourceSocket, peerPacket:sub(1, -2), GUEST_ADDRESS, GUEST_PORT)
    source:update()
    local callsBeforeExact = sourceProvider.states[1].receiveCalls
    enqueue(sourceSocket, peerPacket,
        "2001:4860:4860:0:0:0:0:8888", GUEST_PORT)
    source:update()
    check("direct_opening_requires_the_exact_global_ipv6_source_and_port_before_native_receive",
        callsBeforeExact == 0 and sourceProvider.states[1].receiveCalls == 1
        and source.status == "opening")
    source:close()

    now = 500
    local floodSocket, floodProvider = fakeSocket(), fakeProvider()
    local flood = DirectOpening.create(controllerOptions(
        "host", floodSocket, floodProvider, clock, false))
    for index = 1, 100 do
        enqueue(floodSocket, string.rep("x", DirectOpening.PACKET_BYTES),
            OTHER_ADDRESS, 30000 + index)
    end
    local readsBeforeFlood = floodSocket.receiveCalls
    flood:update()
    check("direct_opening_wrong_source_flood_is_bounded_without_native_allocation",
        floodSocket.receiveCalls - readsBeforeFlood
            == DirectOpening.MAX_RECEIVES_PER_UPDATE
        and #floodSocket.inbound == 100 - DirectOpening.MAX_RECEIVES_PER_UPDATE
        and #floodProvider.states == 1
        and floodProvider.states[1].receiveCalls == 0
        and flood.status == "opening")
    flood:close()

    now = 600
    local rejectSocket, rejectProvider =
        fakeSocket(), fakeProvider({ rejectReceive = true })
    local rejected = DirectOpening.create(controllerOptions(
        "host", rejectSocket, rejectProvider, clock, false))
    enqueue(rejectSocket, peerPacket, GUEST_ADDRESS, GUEST_PORT)
    local rejectedStatus, rejectedError = rejected:update()
    check("direct_opening_ordinary_native_authentication_rejection_is_silent_and_nonfatal",
        rejectedStatus == "opening" and rejectedError == nil
        and rejected.lastError == nil and #rejectSocket.sends == 1
        and rejectProvider.states[1].receiveCalls == 1)
    rejected:close()

    now = 700
    local timeoutSocket, timeoutProvider = fakeSocket(), fakeProvider()
    local timeoutOptions = controllerOptions(
        "guest", timeoutSocket, timeoutProvider, clock, true)
    timeoutOptions.timeoutSeconds = 1
    local timed = DirectOpening.create(timeoutOptions)
    now = 701
    local timedStatus, timedError = timed:update()
    check("direct_opening_monotonic_timeout_fails_closed_and_cleans_owned_resources",
        timedStatus == "failed" and timedError == "Direct opening timed out."
        and not timed:isReady() and timeoutProvider.states[1].closeCalls == 1
        and timeoutSocket.closeCalls == 1 and not containsSecret(timedError))
    timed:close()
    check("direct_opening_timeout_cleanup_and_close_are_idempotent",
        timeoutProvider.states[1].closeCalls == 1 and timeoutSocket.closeCalls == 1)

    now = 800
    local infrastructureSocket = fakeSocket()
    local infrastructureProvider = fakeProvider({ failReceive = true })
    local infrastructure = DirectOpening.create(controllerOptions(
        "host", infrastructureSocket, infrastructureProvider, clock, true))
    enqueue(infrastructureSocket, peerPacket, GUEST_ADDRESS, GUEST_PORT)
    local failureStatus, failureError = infrastructure:update()
    check("direct_opening_native_infrastructure_error_is_generic_and_cleans_up",
        failureStatus == "failed" and not containsSecret(failureError)
        and infrastructureProvider.states[1].closeCalls == 1
        and infrastructureSocket.closeCalls == 1)

    now = 900
    local receiveSocket, receiveProvider = fakeSocket(), fakeProvider()
    local receiveFailure = DirectOpening.create(controllerOptions(
        "guest", receiveSocket, receiveProvider, clock, true))
    receiveSocket.failReceive = true
    local socketStatus, socketError = receiveFailure:update()
    check("direct_opening_socket_infrastructure_error_is_generic_and_cleans_up",
        socketStatus == "failed" and not containsSecret(socketError)
        and receiveProvider.states[1].closeCalls == 1
        and receiveSocket.closeCalls == 1)

    now = 1000
    local closeSocket, closeProvider = fakeSocket(), fakeProvider()
    closeSocket.failClose = true
    local closeFailure = DirectOpening.create(controllerOptions(
        "host", closeSocket, closeProvider, clock, true))
    closeProvider.overrides.failClose = true
    local closeOk, closeError = closeFailure:close()
    local closeAgain, closeAgainError = closeFailure:close()
    check("direct_opening_cleanup_failure_is_redacted_bounded_and_idempotent",
        closeOk == false and closeAgain == false
        and closeError == "Direct opening cleanup failed."
        and closeAgainError == closeError and not containsSecret(closeError)
        and closeProvider.states[1].closeCalls == 1 and closeSocket.closeCalls == 1)

    now = 1100
    local badNextSocket, badNextProvider = fakeSocket(), fakeProvider({ failNext = true })
    local failedCreate, failedCreateError = DirectOpening.create(controllerOptions(
        "host", badNextSocket, badNextProvider, clock, true))
    local raisedProvider = fakeProvider({ raiseConstructor = true })
    local raisedSocket = fakeSocket()
    local raisedCreate, raisedCreateError = DirectOpening.create(controllerOptions(
        "guest", raisedSocket, raisedProvider, clock, true))
    check("direct_opening_initialization_errors_never_echo_endpoints_codes_or_secrets",
        failedCreate == nil and raisedCreate == nil
        and not containsSecret(failedCreateError)
        and not containsSecret(raisedCreateError)
        and failedCreateError == "Direct opening initialization failed."
        and raisedCreateError == failedCreateError
        and badNextProvider.states[1].closeCalls == 1
        and badNextSocket.closeCalls == 1 and raisedSocket.closeCalls == 1)

    local tamperedRecords = openingRecords()
    tamperedRecords.response.responseTag = RESPONSE_TAG:sub(1, 31) .. "X"
    local tamperedSocket, tamperedProvider = fakeSocket(), fakeProvider()
    local tamperedController, tamperedError = DirectOpening.create({
        role = "host",
        host = tamperedRecords.host,
        response = tamperedRecords.response,
        socket = tamperedSocket,
        provider = tamperedProvider,
        clock = clock,
    })
    local verifierSocket, verifierProvider = fakeSocket(),
        fakeProvider({ failVerify = true })
    local verifierController, verifierError = DirectOpening.create({
        role = "guest",
        host = tamperedRecords.host,
        response = openingRecords().response,
        socket = verifierSocket,
        provider = verifierProvider,
        clock = clock,
    })
    check("direct_opening_authenticates_response_before_socket_or_state_activity",
        tamperedController == nil and verifierController == nil
        and tamperedError == "Direct opening response authentication failed."
        and verifierError == tamperedError
        and not containsSecret(tamperedError) and not containsSecret(verifierError)
        and #tamperedProvider.verifierCalls == 1
        and #verifierProvider.verifierCalls == 1
        and #tamperedProvider.constructorCalls == 0
        and #verifierProvider.constructorCalls == 0
        and #tamperedSocket.timeoutCalls == 0 and #tamperedSocket.sends == 0
        and #verifierSocket.timeoutCalls == 0 and #verifierSocket.sends == 0
        and tamperedSocket.closeCalls == 0 and verifierSocket.closeCalls == 0)

    local invalidRecords = openingRecords()
    invalidRecords.response.address = "fe80::1"
    invalidRecords.response.guestAddress = "fe80::1"
    local invalidController = DirectOpening.create({
        role = "host",
        host = invalidRecords.host,
        response = invalidRecords.response,
        socket = fakeSocket(),
        provider = fakeProvider(),
        clock = clock,
    })
    local mismatchedRecords = openingRecords()
    mismatchedRecords.response.invitationId = string.rep("X", 16)
    local mismatchController = DirectOpening.create({
        role = "guest",
        host = mismatchedRecords.host,
        response = mismatchedRecords.response,
        socket = fakeSocket(),
        provider = fakeProvider(),
        clock = clock,
    })
    local invalidRole = DirectOpening.create({ role = "observer" })
    local excessiveTimeoutOptions = controllerOptions(
        "host", fakeSocket(), fakeProvider(), clock, false)
    excessiveTimeoutOptions.timeoutSeconds =
        DirectOpening.MAX_TIMEOUT_SECONDS + 0.001
    local excessiveTimeout = DirectOpening.create(excessiveTimeoutOptions)
    check("direct_opening_rejects_invalid_role_non_global_endpoint_and_unmatched_records",
        invalidController == nil and mismatchController == nil
        and invalidRole == nil and excessiveTimeout == nil)

    now = 1200
    local rollbackSocket, rollbackProvider = fakeSocket(), fakeProvider()
    local rollback = DirectOpening.create(controllerOptions(
        "guest", rollbackSocket, rollbackProvider, clock, true))
    now = 1199.999
    local rollbackStatus, rollbackError = rollback:update()
    check("direct_opening_rejects_a_non_monotonic_clock_and_cleans_up",
        rollbackStatus == "failed"
        and rollbackError == "Direct opening clock failed."
        and not containsSecret(rollbackError)
        and rollbackProvider.states[1].closeCalls == 1
        and rollbackSocket.closeCalls == 1)
end

return Test
