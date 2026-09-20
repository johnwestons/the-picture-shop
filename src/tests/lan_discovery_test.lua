local Discovery = require("src.net.lan_discovery")

local Test = {}

local function fakeNetwork()
    local network = { sockets = {}, nextPort = 30000, nextIp = 10 }
    local socketModule = {}

    function socketModule.udp()
        local udp = {
            ip = "192.168.50." .. tostring(network.nextIp),
            port = nil,
            queue = {},
            closed = false,
            sent = {},
        }
        network.nextIp = network.nextIp + 10
        network.sockets[#network.sockets + 1] = udp
        function udp:setoption() return true end
        function udp:settimeout() return true end
        function udp:setsockname(address, port)
            if port == 0 then
                network.nextPort = network.nextPort + 1
                port = network.nextPort
            end
            self.bindAddress = address
            self.port = port
            return true
        end
        function udp:sendto(packet, address, port)
            self.sent[#self.sent + 1] = { packet = packet, address = address, port = port }
            for _, target in ipairs(network.sockets) do
                local broadcast = address == "255.255.255.255"
                    or address:match("%.255$") ~= nil
                if not target.closed and target ~= self and target.port == port
                    and (broadcast or target.ip == address)
                then
                    target.queue[#target.queue + 1] = {
                        packet = packet, address = self.ip, port = self.port,
                    }
                end
            end
            return #packet
        end
        function udp:receivefrom()
            local item = table.remove(self.queue, 1)
            if not item then return nil, "timeout" end
            return item.packet, item.address, item.port
        end
        function udp:close() self.closed = true; return true end
        return udp
    end
    return network, socketModule
end

function Test.run(_, check)
    local now = 10
    local network, sockets = fakeNetwork()
    local host = Discovery.new({ socket = sockets, clock = function() return now end })
    local guest = Discovery.new({
        socket = sockets,
        clock = function() return now end,
        nonceFactory = function() return "0123456789abcdef" end,
    })
    local hosted = host:startHost({ gamePort = 22122, name = "Shop | Host\n" })
    local searching = guest:startSearch({ localAddress = "192.168.50.20" })
    check("lan_discovery_binds_ipv4_wildcard_for_ipv4_broadcast",
        hosted and searching
        and network.sockets[1].bindAddress == "0.0.0.0"
        and network.sockets[2].bindAddress == "0.0.0.0")
    guest:update(0)
    host:update(0)
    guest:update(0)
    local results = guest:results()
    check("lan_discovery_finds_host_with_bounded_sanitized_address_hint",
        hosted and searching and #results == 1
        and results[1].address == "192.168.50.10"
        and results[1].port == 22122
        and results[1].name == "Shop ? Host?"
        and results[1].sessionId == nil and results[1].save == nil)

    guest:update(0)
    host:update(0)
    guest:update(0)
    check("lan_discovery_deduplicates_repeat_replies",
        #guest:results() == 1)

    local automaticGuest = Discovery.new({
        socket = sockets,
        clock = function() return now end,
        nonceFactory = function() return "fedcba9876543210" end,
        addressDetector = function(options)
            return options.socket == sockets and "192.168.50.30" or nil
        end,
    })
    local automaticSearch = automaticGuest:startSearch()
    automaticGuest:update(0)
    local automaticSocket = network.sockets[#network.sockets]
    local sawDirected = false
    for _, send in ipairs(automaticSocket.sent) do
        if send.address == "192.168.50.255" and send.port == Discovery.PORT then
            sawDirected = true
        end
    end
    check("lan_discovery_detects_address_and_sends_directed_wifi_broadcast",
        automaticSearch and sawDirected)
    automaticGuest:stop()

    local guestSocket = network.sockets[2]
    guestSocket.queue[#guestSocket.queue + 1] = {
        packet = "TPSLAN1|H|ffffffffffffffff|14|22122|Spoof",
        address = "192.168.50.99", port = 22123,
    }
    guestSocket.queue[#guestSocket.queue + 1] = {
        packet = "TPSLAN1|H|0123456789abcdef|999|22122|Wrong version",
        address = "192.168.50.98", port = 22123,
    }
    guestSocket.queue[#guestSocket.queue + 1] = {
        packet = string.rep("x", Discovery.MAX_PACKET_BYTES + 1),
        address = "192.168.50.97", port = 22123,
    }
    guest:update(0)
    check("lan_discovery_rejects_wrong_nonce_version_and_oversized_packets",
        #guest:results() == 1)

    results[1].name = "tampered"
    check("lan_discovery_returns_detached_results",
        guest:results()[1].name == "Shop ? Host?")

    now = now + Discovery.RESULT_TTL + 0.1
    guest:update(0)
    check("lan_discovery_expires_stale_hosts_and_keeps_manual_fallback",
        #guest:results() == 0
        and select(2, guest:status()):find("Searching", 1, true) ~= nil)

    local missing = Discovery.new({ socket = false })
    local missingOk, missingError = missing:startSearch()
    check("lan_discovery_socket_failure_is_nonfatal_manual_fallback",
        not missingOk and missingError:find("manually", 1, true) ~= nil)

    local hostSocket, guestSocketRef = network.sockets[1], network.sockets[2]
    host:stop()
    guest:stop()
    check("lan_discovery_stop_closes_both_roles",
        hostSocket.closed and guestSocketRef.closed
        and select(1, host:status()) == "idle"
        and select(1, guest:status()) == "idle")
end

return Test
