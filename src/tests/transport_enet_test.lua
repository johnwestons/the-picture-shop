local Address = require("src.net.address")
local Transport = require("src.net.transport_enet")

local Test = {}

local function fakePeer(log)
    local peer = {}
    function peer:send(payload, channel, flag)
        log[#log + 1] = { "send", payload, channel, flag }
        return 0
    end
    function peer:disconnect(code) log[#log + 1] = { "disconnect", code } end
    function peer:disconnect_now(code) log[#log + 1] = { "disconnect_now", code } end
    function peer:connect_id() return 77 end
    function peer:index() return 2 end
    function peer:state() return "connected" end
    return peer
end

local function fakeEnet()
    local result = { creations = {}, hosts = {} }
    function result.host_create(endpoint, peers, channels)
        local log, peer = {}, fakePeer({})
        local host = { events = {}, log = log, peer = peer }
        peer = fakePeer(log)
        host.peer = peer
        function host:service(timeout)
            self.log[#self.log + 1] = { "service", timeout }
            return table.remove(self.events, 1)
        end
        function host:connect(address, channelCount, data)
            self.log[#self.log + 1] = { "connect", address, channelCount, data }
            return self.peer
        end
        function host:broadcast(payload, channel, flag)
            self.log[#self.log + 1] = { "broadcast", payload, channel, flag }
        end
        function host:flush() self.log[#self.log + 1] = { "flush" } end
        function host:destroy() self.log[#self.log + 1] = { "destroy" } end
        result.creations[#result.creations + 1] = {
            endpoint = endpoint, peers = peers, channels = channels,
        }
        result.hosts[#result.hosts + 1] = host
        return host
    end
    return result
end

local function callNamed(log, name)
    for _, call in ipairs(log or {}) do if call[1] == name then return call end end
end

function Test.run(_, check)
    local parsed = Address.parse(" 192.168.1.24 ")
    check("lan_address_defaults_to_picture_shop_port",
        parsed and parsed.host == "192.168.1.24" and parsed.port == 22122
        and parsed.endpoint == "192.168.1.24:22122")

    local named = Address.parse("Shop-PC.local:23000")
    check("lan_address_accepts_safe_hostname_and_explicit_port",
        named and named.host == "shop-pc.local" and named.port == 23000)
    check("lan_address_rejects_urls", Address.parse("http://192.168.1.2") == nil)
    check("lan_address_rejects_invalid_ipv4", Address.parse("999.1.1.1") == nil)
    check("lan_address_rejects_nondecimal_ports", Address.parse("shop.local:1e3") == nil)
    check("lan_address_rejects_empty_hostname_labels", Address.parse("shop..local") == nil)

    local selected = Address.chooseLanAddress({
        "127.0.0.1", "25.12.4.9", "8.8.8.8", "10.0.0.42", "192.168.50.8",
    })
    check("lan_address_detection_avoids_loopback_and_prefers_private_adapters",
        selected == "192.168.50.8")

    local dnsUdpOpened = false
    local detected = Address.detectLanAddress({ socket = {
        dns = {
            gethostname = function() return "picture-shop-pc" end,
            getaddrinfo = function()
                return { { addr = "127.0.0.1" }, { addr = "25.8.8.8" }, { addr = "172.20.1.9" } }
            end,
        },
        udp = function() dnsUdpOpened = true end,
    } })
    check("lan_address_detection_uses_injected_lookup_without_opening_socket",
        detected == "172.20.1.9" and not dnsUdpOpened)

    local routeProbe = { opened = 0, connected = 0, inspected = 0, closed = 0 }
    local routed = Address.detectLanAddress({ socket = {
        dns = {
            gethostname = function() return "localhost" end,
            getaddrinfo = function() return { { addr = "127.0.0.1" } } end,
        },
        udp = function()
            routeProbe.opened = routeProbe.opened + 1
            local udp = {}
            function udp:setpeername(host, port)
                routeProbe.connected = routeProbe.connected + 1
                routeProbe.host, routeProbe.port = host, port
                return 1
            end
            function udp:getsockname()
                routeProbe.inspected = routeProbe.inspected + 1
                return "192.168.1.137", 49152, "inet"
            end
            function udp:close() routeProbe.closed = routeProbe.closed + 1 end
            return udp
        end,
    } })
    check("lan_address_detection_uses_non_sending_route_fallback_for_android_hostname",
        routed == "192.168.1.137" and routeProbe.opened == 1
        and routeProbe.connected == 1 and routeProbe.inspected == 1 and routeProbe.closed == 1
        and routeProbe.host == "192.0.2.1" and routeProbe.port == 9)

    local hostEnet = fakeEnet()
    local transport = Transport.createHost({ enet = hostEnet })
    local native = hostEnet.hosts[1]
    local peer = native and native.peer
    check("enet_host_caps_guests_and_uses_three_channels",
        transport and hostEnet.creations[1].endpoint == "*:22122"
        and hostEnet.creations[1].peers == 3 and hostEnet.creations[1].channels == 3)

    native.events = {
        { type = "connect", peer = peer, data = 4 },
        { type = "receive", peer = peer, data = "hello", channel = 2 },
        { type = "disconnect", peer = peer, data = 9 },
    }
    local events = transport:service()
    local allNonblocking = true
    for _, call in ipairs(native.log) do
        if call[1] == "service" and call[2] ~= 0 then allNonblocking = false end
    end
    check("enet_service_normalizes_events_and_never_blocks",
        events and #events == 3 and allNonblocking
        and events[1].type == "connect" and events[1].connectionId == 77
        and events[2].type == "receive" and events[2].payload == "hello"
        and events[2].channel == 2 and events[3].code == 9)

    transport:send(peer, "motion", 2, false)
    transport:send(peer, "hello", { channel = 0, reliable = true })
    transport:broadcast("snapshot", 2, false)
    local firstSend, secondSend, broadcast
    for _, call in ipairs(native.log) do
        if call[1] == "send" and not firstSend then firstSend = call
        elseif call[1] == "send" then secondSend = call
        elseif call[1] == "broadcast" then broadcast = call end
    end
    check("enet_packets_are_reliable_only_when_explicitly_requested",
        firstSend and firstSend[4] == "unreliable"
        and secondSend and secondSend[4] == "reliable"
        and broadcast and broadcast[4] == "unreliable")

    -- Re-add the connected peer because the synthetic disconnect event above
    -- correctly removed it from the transport's live peer set.
    transport._peers[peer] = true
    local closed = transport:close()
    check("enet_close_disconnects_flushes_and_destroys_cleanly",
        closed and callNamed(native.log, "disconnect")
        and callNamed(native.log, "flush") and callNamed(native.log, "destroy")
        and transport.closed and transport.nativeHost == nil)

    local clientEnet = fakeEnet()
    local client = Transport.createClient("game-pc.local", { enet = clientEnet })
    local clientHost = clientEnet.hosts[1]
    local connect = clientHost and callNamed(clientHost.log, "connect")
    check("enet_client_uses_default_port_without_binding_a_real_socket_in_tests",
        client and clientEnet.creations[1].endpoint == nil
        and connect and connect[2] == "game-pc.local:22122" and connect[3] == 3)
    if client then client:close() end
end

return Test
