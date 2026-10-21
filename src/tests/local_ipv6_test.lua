local LocalIpv6 = require("src.net.local_ipv6")

local Test = {}
local ADDRESS = "2606:4700:4700::1111"
local PEER = "2001:4860:4860::8888"

local function fixture(options)
    options = options or {}
    local state = { sockets = {}, sent = 0, dns = 0 }
    local function forbiddenSend()
        state.sent = state.sent + 1
        error("address detection must not send")
    end
    local function forbiddenDns()
        state.dns = state.dns + 1
        error("address detection must not use DNS")
    end
    local module = { dns = { getaddrinfo = forbiddenDns, toip = forbiddenDns } }
    function module.udp6()
        local ordinal = #state.sockets + 1
        if options.createFailure == ordinal then return nil, "private native error" end
        local socket = { closed = 0, ordinal = ordinal }
        state.sockets[ordinal] = socket
        local function result(step)
            if options.throw == step then error("private native error") end
            if options.fail == step then return nil, "private native error" end
            return 1
        end
        function socket:settimeout(timeout)
            self.timeout = timeout
            return result(ordinal == 1 and "route_timeout" or "bind_timeout")
        end
        function socket:setpeername(address, port)
            self.peerAddress, self.peerPort = address, port
            return result("connect")
        end
        function socket:setsockname(address, port)
            self.bindAddress, self.bindPort = address, port
            return result("bind")
        end
        function socket:getsockname()
            if not result(ordinal == 1 and "route_name" or "bind_name") then return nil end
            if ordinal == 1 then return options.address or ADDRESS, 49151 end
            return options.boundAddress or self.bindAddress, options.boundPort or "49152"
        end
        function socket:close()
            self.closed = self.closed + 1
            return result(ordinal == 1 and "route_close" or "bind_close")
        end
        socket.send, socket.sendto = forbiddenSend, forbiddenSend
        socket.receive, socket.receivefrom = forbiddenSend, forbiddenSend
        if options.missingMethod and ordinal == (options.missingOrdinal or 1) then
            socket[options.missingMethod] = nil
        end
        return socket
    end
    return module, state
end

local function closed(state)
    for _, socket in ipairs(state.sockets) do
        if socket.closed ~= 1 then return false end
    end
    return state.sent == 0 and state.dns == 0
end

function Test.run(_, check)
    local module, state = fixture({ address = "2606:4700:4700:0000:0000:0000:0000:1111" })
    local address, reason = LocalIpv6.detect({ socketModule = module })
    check("local_ipv6_selects_canonical_public_host_address_without_sending_or_dns",
        address == ADDRESS and reason == nil and #state.sockets == 2
        and state.sockets[1].peerAddress == "2001:db8::1"
        and state.sockets[1].peerPort == 9 and state.sockets[1].timeout == 0
        and state.sockets[2].timeout == 0 and closed(state))
    check("local_ipv6_verifies_exact_local_bind_and_accepts_android_numeric_string_port",
        state.sockets[2].bindAddress == ADDRESS and state.sockets[2].bindPort == 0)

    module, state = fixture()
    address = LocalIpv6.detect({ socketModule = module,
        peerAddress = "2001:4860:4860:0:0:0:0:8888" })
    check("local_ipv6_guest_selects_the_validated_peer_route",
        address == ADDRESS and state.sockets[1].peerAddress == PEER and closed(state))

    local invalidPeers = { "example.com", "::", "::1", "fe80::1", "fd00::1",
        "2001:db8::1", "ff02::1", "2606:4700::1%wlan0", "[2606:4700::1]:9", "192.0.2.1" }
    local rejectedPeers = true
    for _, peer in ipairs(invalidPeers) do
        module, state = fixture()
        address, reason = LocalIpv6.detect({ socketModule = module, peerAddress = peer })
        rejectedPeers = rejectedPeers and address == nil and reason == "invalid_ipv6_peer"
            and #state.sockets == 0 and closed(state)
    end
    check("local_ipv6_rejects_non_public_or_non_numeric_peers_before_opening_a_socket", rejectedPeers)

    local rejectedLocals = true
    for _, localAddress in ipairs(invalidPeers) do
        module, state = fixture({ address = localAddress })
        address, reason = LocalIpv6.detect({ socketModule = module })
        rejectedLocals = rejectedLocals and address == nil and reason == "no_global_ipv6"
            and #state.sockets == 1 and closed(state)
    end
    check("local_ipv6_rejects_private_scoped_or_invalid_local_addresses_and_closes", rejectedLocals)

    local failures = {
        { "route_timeout", "ipv6_unavailable", 1 },
        { "connect", "no_ipv6_route", 1 },
        { "route_name", "no_global_ipv6", 1 },
        { "bind_timeout", "ipv6_unavailable", 2 },
        { "bind", "ipv6_bind_failed", 2 },
        { "bind_name", "ipv6_bind_failed", 2 },
        { "route_close", "ipv6_cleanup_failed", 1 },
        { "bind_close", "ipv6_cleanup_failed", 2 },
    }
    for _, style in ipairs({ "fail", "throw" }) do
        local allClosed = true
        for _, case in ipairs(failures) do
            module, state = fixture({ [style] = case[1] })
            address, reason = LocalIpv6.detect({ socketModule = module })
            allClosed = allClosed and address == nil and reason == case[2]
                and #state.sockets == case[3] and closed(state)
        end
        check("local_ipv6_handles_" .. style .. "_at_every_native_operation_without_leaking_errors", allClosed)
    end

    module, state = fixture({ boundAddress = PEER })
    address, reason = LocalIpv6.detect({ socketModule = module })
    check("local_ipv6_rejects_exact_bind_returning_a_different_source_address",
        address == nil and reason == "ipv6_bind_failed" and closed(state))
    local badPortsRejected = true
    for _, port in ipairs({ 0, -1, 1.5, 65536, "NaN", "", math.huge }) do
        module, state = fixture({ boundPort = port })
        address, reason = LocalIpv6.detect({ socketModule = module })
        badPortsRejected = badPortsRejected and address == nil
            and reason == "ipv6_bind_failed" and closed(state)
    end
    check("local_ipv6_requires_a_valid_ephemeral_bound_port", badPortsRejected)

    local creationFailuresClosed = true
    for ordinal = 1, 2 do
        module, state = fixture({ createFailure = ordinal })
        address, reason = LocalIpv6.detect({ socketModule = module })
        creationFailuresClosed = creationFailuresClosed and address == nil
            and reason == "ipv6_unavailable" and #state.sockets == ordinal - 1 and closed(state)
    end
    check("local_ipv6_handles_socket_factory_failures", creationFailuresClosed)

    local malformedClosed = true
    for _, method in ipairs({ "settimeout", "getsockname", "setpeername" }) do
        module, state = fixture({ missingMethod = method })
        address, reason = LocalIpv6.detect({ socketModule = module })
        malformedClosed = malformedClosed and address == nil
            and reason == "ipv6_unavailable" and closed(state)
    end
    module, state = fixture({ missingMethod = "setsockname", missingOrdinal = 2 })
    address, reason = LocalIpv6.detect({ socketModule = module })
    check("local_ipv6_closes_malformed_socket_objects",
        malformedClosed and address == nil and reason == "ipv6_unavailable" and closed(state))

    module, state = fixture({ missingMethod = "close" })
    address, reason = LocalIpv6.detect({ socketModule = module })
    check("local_ipv6_never_reports_success_when_socket_cleanup_cannot_be_verified",
        address == nil and reason == "ipv6_cleanup_failed" and #state.sockets == 1)
    address, reason = LocalIpv6.detect({ socketModule = {} })
    check("local_ipv6_reports_missing_ipv6_support_without_native_calls",
        address == nil and reason == "ipv6_unavailable")
    check("local_ipv6_messages_do_not_echo_arbitrary_native_details",
        LocalIpv6.messageFor("private native error " .. ADDRESS):find(ADDRESS, 1, true) == nil
        and LocalIpv6.messageFor("no_ipv6_route"):find("network", 1, true) ~= nil
        and LocalIpv6.messageFor("ipv6_cleanup_failed"):find("Restart", 1, true) ~= nil)
end

return Test
