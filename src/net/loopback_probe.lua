local Address = require("src.net.address")
local Protocol = require("src.net.protocol")
local Transport = require("src.net.transport_enet")

local Probe = {}

local function now()
    return love.timer.getTime()
end

local function closeQuietly(transport)
    if transport then pcall(function() transport:close(0, true) end) end
end

function Probe.run(options)
    options = options or {}
    local port = tonumber(options.port) or 22129
    local timeout = tonumber(options.timeout) or 4
    local host, client
    local ok, result = xpcall(function()
        local lanAddress, addressError = Address.detectLanAddress()
        assert(lanAddress, addressError)
        local errorMessage
        host, errorMessage = Transport.createHost({
            port = port,
            bind = "*",
            maxGuests = 1,
            channels = Protocol.CHANNEL_COUNT,
        })
        assert(host, errorMessage)
        client, errorMessage = Transport.createClient("127.0.0.1:" .. tostring(port), {
            channels = Protocol.CHANNEL_COUNT,
        })
        assert(client, errorMessage)

        local hostPeer, clientConnected = nil, false
        local deadline = now() + timeout
        while now() < deadline and (not hostPeer or not clientConnected) do
            for _, event in ipairs(host:service(16) or {}) do
                if event.type == "connect" then hostPeer = event.peer end
            end
            for _, event in ipairs(client:service(16) or {}) do
                if event.type == "connect" then clientConnected = true end
            end
            love.timer.sleep(0.002)
        end
        assert(hostPeer and clientConnected, "ENet host and client did not connect before the timeout")

        local packet = assert(Protocol.encode("ping", {
            sessionId = "loopback-probe",
            nonce = 22129,
        }))
        local channel, delivery = Protocol.route("ping")
        assert(client:sendToServer(packet, channel, delivery == "reliable"))
        client:flush()

        local receivedPing, receivedPong = false, false
        deadline = now() + timeout
        while now() < deadline and not receivedPong do
            for _, event in ipairs(host:service(16) or {}) do
                if event.type == "receive" then
                    local envelope = assert(Protocol.decode(event.payload))
                    assert(envelope.type == "ping", "host received the wrong protocol message")
                    receivedPing = true
                    local reply = assert(Protocol.encode("pong", envelope.payload))
                    local replyChannel, replyDelivery = Protocol.route("pong")
                    assert(host:send(event.peer, reply, replyChannel, replyDelivery == "reliable"))
                    host:flush()
                end
            end
            for _, event in ipairs(client:service(16) or {}) do
                if event.type == "receive" then
                    local envelope = assert(Protocol.decode(event.payload))
                    receivedPong = envelope.type == "pong"
                        and envelope.payload.sessionId == "loopback-probe"
                        and envelope.payload.nonce == 22129
                end
            end
            love.timer.sleep(0.002)
        end
        assert(receivedPing and receivedPong, "protocol ping/pong did not complete before the timeout")
        return string.format("ENet protocol ping/pong succeeded on 127.0.0.1:%d; LAN address %s",
            port, lanAddress)
    end, debug.traceback)
    closeQuietly(client)
    closeQuietly(host)
    if not ok then return false, result end
    return true, result
end

return Probe
