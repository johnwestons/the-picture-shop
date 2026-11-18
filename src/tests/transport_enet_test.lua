local Address = require("src.net.address")
local DirectTransport = require("src.net.transport_direct")
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
    function peer:throttle_configure(interval, acceleration, deceleration)
        log[#log + 1] = { "throttle", interval, acceleration, deceleration }
    end
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
        function host:destroy()
            self.log[#self.log + 1] = { "destroy" }
            if result.failDestroy then error("synthetic destroy failure") end
        end
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
    local androidHotspot = Address.parse("192.168.43.1")
    local phoneHotspot = Address.parse("172.20.10.1")
    check("lan_address_accepts_common_android_and_phone_hotspot_ipv4_ranges",
        androidHotspot and androidHotspot.host == "192.168.43.1"
        and phoneHotspot and phoneHotspot.host == "172.20.10.1")

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

    local selectedLocalNetwork = Address.detectLanAddress({ candidates = {
        { address = "192.168.42.129", prefixLength = 24,
            interfaceName = "rndis0", isUsb = true },
        { address = "10.11.148.123", prefixLength = 24,
            interfaceName = "rmnet_data0", isUsb = false },
        { address = "172.20.10.4", prefixLength = 24,
            interfaceName = "wlan0", isUsb = false },
    } })
    check("lan_auto_address_prefers_wifi_over_usb_and_cellular_interfaces",
        selectedLocalNetwork == "172.20.10.4")

    local originalInterfaceDetector = Address.detectLanInterfaces
    Address.detectLanInterfaces = function()
        return {
            { address = "192.168.42.129", prefixLength = 24,
                interfaceName = "rndis0", isUsb = true },
            { address = "172.20.10.4", prefixLength = 24,
                interfaceName = "wlan0", isUsb = false },
        }
    end
    local defaultAutoAddress = Address.detectLanAddress()
    Address.detectLanInterfaces = originalInterfaceDetector
    check("lan_auto_host_uses_best_local_interface_instead_of_ui_sort_order",
        defaultAutoAddress == "172.20.10.4")

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
        and hostEnet.creations[1].peers == 3 and hostEnet.creations[1].channels == 3
        and transport.maxGuests == 3 and transport.peerCapacity == 3)

    check('enet_missing_rtt_telemetry_is_optional',transport:peerRoundTripTime(peer)==nil)
    peer.round_trip_time=function(_,...)assert(select('#',...)==0,'RTT getter must never set native estimates');return 156 end
    check('enet_rtt_telemetry_reads_native_milliseconds_without_mutation',transport:peerRoundTripTime(peer)==156)
    peer.round_trip_time=function()error('native peer unavailable')end
    check('enet_rtt_telemetry_contains_native_read_failures',transport:peerRoundTripTime(peer)==nil)
    peer.round_trip_time=function()return 0/0 end
    check('enet_rtt_telemetry_rejects_nonfinite_results',transport:peerRoundTripTime(peer)==nil)
    peer.round_trip_time=nil

    local directCapacityEnet = fakeEnet()
    local directCapacity = Transport.createHost({
        enet = directCapacityEnet,
        maxGuests = 3,
        peerCapacity = 12,
    })
    check("enet_direct_host_can_reserve_separate_pre_auth_peer_capacity",
        directCapacity and directCapacityEnet.creations[1].peers == 12
        and directCapacity.maxGuests == 3 and directCapacity.peerCapacity == 12)
    if directCapacity then directCapacity:close() end

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
        and events[1].code == 4
        and events[2].type == "receive" and events[2].payload == "hello"
        and events[2].channel == 2 and events[3].code == 9)
    local throttle = callNamed(native.log, "throttle")
    check("enet_lan_relearns_rtt_without_disabling_congestion_backoff",
        throttle and throttle[2] == 500 and throttle[3] == 2 and throttle[4] == 2)

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
    local flagStart=#native.log
    transport:send(peer,'motion',Transport.STATE_CHANNEL,false)
    transport:broadcast('physics',{channel=Transport.STATE_CHANNEL,reliable=false})
    transport:send(peer,'explicit-reliable',Transport.STATE_CHANNEL,true)
    check('enet_state_packets_allow_cross_family_reordering_without_changing_reliability',
        native.log[flagStart+1][4]=='unsequenced'and native.log[flagStart+2][4]=='unsequenced'
        and native.log[flagStart+3][4]=='reliable')
    local sequencedEnet=fakeEnet()
    local sequenced=assert(Transport.createHost({enet=sequencedEnet,unsequencedState=false}))
    sequencedEnet.hosts[1].events={{type='connect',peer=sequencedEnet.hosts[1].peer}}
    sequenced:service()
    sequenced:send(sequencedEnet.hosts[1].peer,'ordered-state',Transport.STATE_CHANNEL,false)
    check('enet_state_sequencing_can_be_preserved_by_secure_wrappers',
        callNamed(sequencedEnet.hosts[1].log,'send')[4]=='unreliable')
    check('enet_secure_wrappers_keep_default_native_throttle',
        not callNamed(sequencedEnet.hosts[1].log,'throttle'))
    sequenced:close()

    -- Re-add the connected peer because the synthetic disconnect event above
    -- correctly removed it from the transport's live peer set.
    transport._peers[peer] = true
    local closed = transport:close()
    check("enet_close_disconnects_flushes_and_destroys_cleanly",
        closed and callNamed(native.log, "disconnect")
        and callNamed(native.log, "flush") and callNamed(native.log, "destroy")
        and transport.closed and transport.nativeHost == nil)
    check('enet_closed_transport_does_not_read_peer_rtt',transport:peerRoundTripTime(peer)==nil)

    local failingEnet = fakeEnet()
    failingEnet.failDestroy = true
    local failingTransport = assert(Transport.createHost({ enet = failingEnet }))
    local firstFailedClose, firstFailedError = failingTransport:close()
    local secondFailedClose, secondFailedError = failingTransport:close()
    local destroyCalls = 0
    for _, call in ipairs(failingEnet.hosts[1].log) do
        if call[1] == "destroy" then destroyCalls = destroyCalls + 1 end
    end
    check("enet_repeated_close_never_upgrades_unverified_native_cleanup",
        firstFailedClose == false and type(firstFailedError) == "string"
        and secondFailedClose == false and secondFailedError == firstFailedError
        and destroyCalls == 1)

    local clientEnet = fakeEnet()
    local client = Transport.createClient("game-pc.local", { enet = clientEnet })
    local clientHost = clientEnet.hosts[1]
    local connect = clientHost and callNamed(clientHost.log, "connect")
    check("enet_client_uses_default_port_without_binding_a_real_socket_in_tests",
        client and clientEnet.creations[1].endpoint == nil
        and connect and connect[2] == "game-pc.local:22122" and connect[3] == 3)
    clientHost.events={{type='connect',peer=clientHost.peer}}
    client:service()
    local clientThrottle=callNamed(clientHost.log,'throttle')
    check('enet_lan_client_relearns_rtt_with_normal_congestion_backoff',
        clientThrottle and clientThrottle[2]==500 and clientThrottle[3]==2 and clientThrottle[4]==2)
    if client then client:close() end

    for _,behavior in ipairs({'missing','throwing'})do
        local optionalEnet=fakeEnet()
        local optional=assert(Transport.createHost({enet=optionalEnet}))
        local optionalHost=optionalEnet.hosts[1]
        optionalHost.peer.throttle_configure=behavior=='throwing'and function()error('unsupported native tuning')end or nil
        optionalHost.events={{type='connect',peer=optionalHost.peer},{type='receive',peer=optionalHost.peer,data='still connected',channel=0}}
        local optionalEvents,optionalError=optional:service()
        check('enet_optional_throttle_'..behavior..'_does_not_interrupt_events',
            not optionalError and #optionalEvents==2 and optionalEvents[2].data=='still connected')
        optional:close()
    end

    local directKey = string.rep("d", DirectTransport.KEY_BYTES)
    local admissionTokenKey
    local expectedAdmissionToken = 1357911
    local provider = {
        productionReady = true,
        admissionToken = function(key)
            admissionTokenKey = key
            return expectedAdmissionToken
        end,
        newInitiator = function() return nil end,
        newResponder = function() return nil end,
    }
    local directHostFactory = DirectTransport.newFactory({
        baseFactory = Transport,
        cryptoProvider = provider,
        key = directKey,
    })
    local directHostEnet = fakeEnet()
    local directHost = directHostFactory.createHost({
        enet = directHostEnet,
        maxGuests = 3,
        channels = 3,
        unsequencedState = true,
    })
    local directClientFactory = DirectTransport.newFactory({
        baseFactory = Transport,
        cryptoProvider = provider,
        key = directKey,
    })
    local directClientEnet = fakeEnet()
    local directClient = directClientFactory.createClient("direct.example:22122", {
        enet = directClientEnet,
        channels = 3,
        unsequencedState = true,
    })
    local directConnect = directClientEnet.hosts[1]
        and callNamed(directClientEnet.hosts[1].log, "connect")
    check("enet_direct_wrapper_reserves_peers_and_carries_invitation_prefilter",
        directHost and directHostEnet.creations[1].peers
            == DirectTransport.DEFAULT_PEER_CAPACITY
        and admissionTokenKey == directKey
        and directConnect and directConnect[4] == expectedAdmissionToken)
    check('enet_direct_host_and_client_keep_native_crypto_replay_semantics',
        directHost and directClient and directHost.base.unsequencedState==false
        and directClient.base.unsequencedState==false)
    for _,direct in ipairs({directHostEnet,directClientEnet})do
        direct.hosts[1].events={{type='connect',peer=direct.hosts[1].peer}}
    end
    directHost.base:service();directClient.base:service()
    check('enet_direct_host_and_client_never_reconfigure_native_throttle',
        not callNamed(directHostEnet.hosts[1].log,'throttle')
        and not callNamed(directClientEnet.hosts[1].log,'throttle'))
    if directClient then directClient:close() end
    if directHost then directHost:close() end
end

return Test
