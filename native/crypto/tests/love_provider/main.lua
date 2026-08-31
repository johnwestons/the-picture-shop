local function assertValue(condition, label)
    if not condition then error("native provider check failed: " .. label, 2) end
end

local PROBE_OK = "TPS_ANDROID_CRYPTO_PROBE_OK"
local PROBE_FAIL = "TPS_ANDROID_CRYPTO_PROBE_FAIL"

local function byteSequence(first, last)
    local bytes = {}
    for value = first, last do bytes[#bytes + 1] = string.char(value) end
    return table.concat(bytes)
end

local function decodeHex(value)
    return (value:gsub("..", function(pair)
        return string.char(assert(tonumber(pair, 16)))
    end))
end

local function run()
    local root = os.getenv("TPS_REPO_ROOT") or love.filesystem.getWorkingDirectory()
    root = root:gsub("\\", "/")
    package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path

    package.loaded["src.net.crypto_native"] = nil
    local provider = require("src.net.crypto_native")
    assertValue(provider.available == true, provider.loadError or "provider load")
    assertValue(provider.engineeringReady == true, "engineering readiness")
    assertValue(provider.candidateReady == true, "candidate readiness")
    assertValue(provider.engineeringOnly == true, "engineering-only marker")
    assertValue(provider.productionReady == false, "production gate remains closed")
    print("TPS_ANDROID_CRYPTO_PROBE_INFO abi=" .. tostring(provider.abiVersion)
        .. " engineeringOnly=" .. tostring(provider.engineeringOnly)
        .. " productionReady=" .. tostring(provider.productionReady))

    local key = string.rep(string.char(0x42), 32)
    local wrongKey = string.rep(string.char(0x24), 32)
    local random = assert(provider.randomBytes(32))
    assertValue(#random == 32 and random ~= string.rep("\0", 32), "native random")
    local token = assert(provider.admissionToken(key))
    assertValue(token >= 0 and token <= 2147483647, "31-bit admission token")
    assertValue(token == assert(provider.admissionToken(key)), "stable admission token")
    assertValue(token ~= assert(provider.admissionToken(wrongKey)),
        "key-separated admission token")

    local responseKey = byteSequence(0x20, 0x3f)
    local responseTranscript = decodeHex(
        "545053322d524553504f4e53452d7631"
        .. "02010600650102030258566a26064700470000000000000000001111"
        .. "000102030405060708090a0b0c0d0e0f"
        .. "02020600650102030258700e20014860486000000000000000008888"
        .. "000102030405060708090a0b0c0d0e0f"
        .. "a0a1a2a3a4a5a6a7a8a9aaabacadaeaf")
    local expectedResponseTag = decodeHex(
        "0124c94b1be6f885a41dd40f699ce4e03d7f69c9df73c595e028656016995bdd")
    local responseTag = assert(provider.responseTag(
        responseKey, responseTranscript))
    assertValue(#responseTag == 32 and responseTag == expectedResponseTag,
        "response authentication fixed vector")
    assertValue(responseTag == assert(provider.responseTag(
        responseKey, responseTranscript)),
        "response authentication deterministic vector")
    assertValue(provider.verifyResponseTag(
        responseKey, responseTranscript, responseTag) == true,
        "response authentication verification")
    local changedResponseTag = responseTag:sub(1, 31)
        .. string.char((responseTag:byte(32) + 1) % 256)
    local changedVerified, changedVerifyError = provider.verifyResponseTag(
        responseKey, responseTranscript, changedResponseTag)
    assertValue(changedVerified == false and changedVerifyError == nil,
        "response authentication failure is a boolean boundary")
    local shortTagResult, shortTagError = provider.verifyResponseTag(
        responseKey, responseTranscript, changedResponseTag:sub(1, 31))
    assertValue(shortTagResult == nil and type(shortTagError) == "string"
        and shortTagError:find(responseKey, 1, true) == nil
        and shortTagError:find(responseTranscript, 1, true) == nil,
        "response authentication input failure is opaque")

    local invitationId = string.rep(string.char(0x49), 16)
    local guestNonce = string.rep(string.char(0x4e), 16)
    local invalidOpening, invalidOpeningError = provider.newOpeningHost(
        key, invitationId:sub(1, 15), guestNonce)
    assertValue(invalidOpening == nil and type(invalidOpeningError) == "string"
        and invalidOpeningError:find(key, 1, true) == nil,
        "opening inputs are length checked and opaque")

    local tamperHost = assert(provider.newOpeningHost(
        key, invitationId, guestNonce))
    local tamperGuest = assert(provider.newOpeningGuest(
        key, invitationId, guestNonce))
    local tamperPacket = assert(tamperHost:next())
    assertValue(#tamperPacket == 92, "opening packet size")
    tamperPacket = tamperPacket:sub(1, 91)
        .. string.char((tamperPacket:byte(92) + 1) % 256)
    assertValue(tamperGuest:receive(tamperPacket) == false,
        "opening packet tamper rejection")
    assertValue(tamperHost:close() == true and tamperGuest:close() == true,
        "tampered opening state cleanup")

    local wrongOpeningHost = assert(provider.newOpeningHost(
        key, invitationId, guestNonce))
    local wrongOpeningGuest = assert(provider.newOpeningGuest(
        wrongKey, invitationId, guestNonce))
    assertValue(wrongOpeningGuest:receive(
        assert(wrongOpeningHost:next())) == false,
        "wrong-key opening packet rejection")
    assertValue(wrongOpeningHost:close() == true
        and wrongOpeningGuest:close() == true,
        "wrong-key opening state cleanup")

    local openingHost = assert(provider.newOpeningHost(
        key, invitationId, guestNonce))
    local openingGuest = assert(provider.newOpeningGuest(
        key, invitationId, guestNonce))
    assertValue(openingHost:isReady() == false
        and openingGuest:isReady() == false,
        "opening states begin unready")
    assertValue(openingHost:receive("malformed") == false,
        "malformed opening wire rejection")
    local hostFirst = assert(openingHost:next())
    assertValue(#hostFirst == 92 and openingGuest:receive(hostFirst) == true,
        "simultaneous opening host challenge")
    local replayAccepted, replayError = openingGuest:receive(hostFirst)
    assertValue(replayAccepted == false and replayError == nil,
        "opening replay rejection is a boolean boundary")
    local guestFirst = assert(openingGuest:next())
    assertValue(#guestFirst == 92 and openingHost:receive(guestFirst) == true,
        "simultaneous opening guest challenge and echo")
    local hostSecond = assert(openingHost:next())
    assertValue(#hostSecond == 92 and openingGuest:receive(hostSecond) == true
        and openingGuest:isReady() == true and openingHost:isReady() == false,
        "simultaneous opening host confirmation")
    local guestSecond = assert(openingGuest:next())
    assertValue(#guestSecond == 92 and openingHost:receive(guestSecond) == true,
        "simultaneous opening guest confirmation")
    assertValue(openingHost:isReady() == true
        and openingGuest:isReady() == true,
        "simultaneous opening convergence")
    assertValue(openingHost:close() == true and openingHost:close() == true
        and openingGuest:close() == true and openingGuest:close() == true,
        "opening state cleanup is idempotent")
    local closedOpeningPacket, closedOpeningError = openingHost:next()
    assertValue(closedOpeningPacket == nil and type(closedOpeningError) == "string",
        "closed opening state fails opaquely")

    local bridgeHost = assert(provider.newBridgeHost(
        key, invitationId, guestNonce))
    local bridgeGuest = assert(provider.newBridgeGuest(
        key, invitationId, guestNonce))
    local bridgeAad = "TPSB" .. string.char(1, 1, 2, 0)
        .. invitationId .. string.char(0, 0, 0, 1, 0, 1, 4, 152)
    local bridgePlaintext = string.rep("b", 1176)
    local bridgeWire = assert(bridgeGuest:seal(bridgePlaintext, bridgeAad))
    assertValue(#bridgeAad == 32 and #bridgeWire == 1200,
        "maximum bridge fragment respects IPv6 payload budget")
    local changedBridgeAad = bridgeAad:sub(1, 27)
        .. string.char((bridgeAad:byte(28) + 1) % 256)
        .. bridgeAad:sub(29)
    local changedBridgeResult, changedBridgeError = bridgeHost:open(
        bridgeWire, changedBridgeAad)
    assertValue(changedBridgeResult == false and changedBridgeError == nil,
        "bridge fragment metadata is authenticated")
    assertValue(assert(bridgeHost:open(bridgeWire, bridgeAad)) == bridgePlaintext,
        "bridge authentication failure does not consume valid traffic")
    local bridgeReplay, bridgeReplayError = bridgeHost:open(
        bridgeWire, bridgeAad)
    assertValue(bridgeReplay == false and bridgeReplayError == nil,
        "bridge fragment replay rejection")
    local bridgeReply = assert(bridgeHost:seal("host bridge reply", bridgeAad))
    assertValue(assert(bridgeGuest:open(bridgeReply, bridgeAad))
        == "host bridge reply", "bridge direction separation")
    assertValue(bridgeHost:close() == true and bridgeHost:close() == true
        and bridgeGuest:close() == true and bridgeGuest:close() == true,
        "bridge state cleanup is idempotent")

    local initiator = assert(provider.newInitiator(key))
    local responder = assert(provider.newResponder(key))
    local responderStart, responderStartError = responder:start()
    assertValue(responderStart == nil and responderStartError == nil, "responder start")
    local flight1 = assert(initiator:start())
    assertValue(#flight1 == 80, "flight 1 size")
    local flight2 = assert(responder:handshake(flight1))
    assertValue(#flight2 == 80 and responder:isReady() == false, "flight 2")
    local finish = assert(initiator:handshake(flight2))
    assertValue(#finish == 56 and initiator:isReady() == false, "encrypted finish")
    local acknowledgement = assert(responder:handshake(finish))
    assertValue(#acknowledgement == 56 and responder:isReady() == true,
        "encrypted acknowledgement")
    local acknowledgementOutput, acknowledgementError =
        initiator:handshake(acknowledgement)
    assertValue(acknowledgementOutput == nil and acknowledgementError == nil
        and initiator:isReady() == true, "initiator key confirmation")

    local aad = "TPSD" .. string.char(1, 2, 2)
    local ciphertext = assert(initiator:seal("co-op payload", aad))
    assertValue(#ciphertext == #"co-op payload" + 24, "data overhead")
    assertValue(assert(responder:open(ciphertext, aad)) == "co-op payload",
        "authenticated Lua round trip")
    local replay, replayError = responder:open(ciphertext, aad)
    assertValue(replay == nil and type(replayError) == "string", "Lua replay rejection")

    local reverse = assert(responder:seal("host reply", aad))
    assertValue(assert(initiator:open(reverse, aad)) == "host reply",
        "reverse-direction Lua round trip")

    local wrongInitiator = assert(provider.newInitiator(key))
    local wrongResponder = assert(provider.newResponder(wrongKey))
    assertValue(select(1, wrongResponder:start()) == nil, "wrong responder start")
    local wrongFlight1 = assert(wrongInitiator:start())
    local wrongReply, wrongError = wrongResponder:handshake(wrongFlight1)
    assertValue(wrongReply == nil and type(wrongError) == "string",
        "wrong invitation rejected in Lua")

    assertValue(initiator:close() == true and responder:close() == true,
        "authenticated state cleanup")
    assertValue(wrongInitiator:close() == true and wrongResponder:close() == true,
        "failed state cleanup")
    print("TPS_LUA_CRYPTO_OK")
end

function love.load()
    local ok, message = pcall(run)
    if not ok then
        local failure = tostring(message):gsub("[\r\n]+", " ")
        print(PROBE_FAIL .. " " .. failure)
        io.stderr:write(failure, "\n")
        love.event.quit(1)
        return
    end
    print(PROBE_OK)
    love.event.quit(0)
end
