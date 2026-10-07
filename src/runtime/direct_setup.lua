-- Direct transport creation and host setup.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    Runtime.closeDirectConnection = function()
        local connection = Runtime.directConnection
        if not connection then
            Runtime.pendingDirectSession = nil
            return true
        end
        local called, cleaned = pcall(connection.close, connection)
        if not called or cleaned ~= true then
            return false,
                "Direct connection cleanup could not be verified; restart the game before creating another invitation."
        end
        Runtime.directConnection = nil
        Runtime.pendingDirectSession = nil
        return true
    end

    Runtime.closeDirectHostComposite = function()
        local controller = Runtime.directHostComposite
        if controller then
            local called, cleaned = pcall(controller.close, controller)
            if not called or cleaned ~= true then
                return false,
                    "Direct host cleanup could not be verified; restart the game before hosting again."
            end
            Runtime.directHostComposite = nil
        end

        local cleanupPending = false
        for index = #Runtime.DirectIpv4Runtime.hosts, 1, -1 do
            local record = Runtime.DirectIpv4Runtime.hosts[index]
            record.closing = true
            if Runtime.DirectIpv4Runtime.pending == record then Runtime.DirectIpv4Runtime.pending = nil end
            local called, cleaned = pcall(record.host.stop, record.host)
            if called and cleaned == true then
                table.remove(Runtime.DirectIpv4Runtime.hosts, index)
            else
                cleanupPending = true
            end
        end
        if cleanupPending then
            return false,
                "IPv4 router-mapping cleanup is still pending. Keep the game open and retry cleanup."
        end
        Runtime.directHostInvitationGeneration = 0
        return true
    end

    function Runtime.disposeDirectTransportFactory(factory)
        if type(factory) ~= "table" or type(factory.close) ~= "function" then
            return false
        end
        local called, cleaned = pcall(factory.close, factory)
        return called and cleaned == true
    end

    Runtime.DirectIpv4Runtime.portSlots = {
        { loopback = 22122, outer = 22123 },
        { loopback = 22124, outer = 22125 },
        { loopback = 22126, outer = 22127 },
    }

    function Runtime.DirectIpv4Runtime.hostingAvailable()
        return Runtime.CryptoNative.productionReady == true
            and Runtime.DirectIpv4Runtime.Host.productionReady == true
            and jit ~= nil and jit.os == "Windows" and jit.arch == "x64"
    end

    function Runtime.DirectIpv4Runtime.hostingUnavailableMessage()
        if Runtime.CryptoNative.productionReady ~= true
            or Runtime.DirectIpv4Runtime.Host.productionReady ~= true then
            return "IPv4 Direct hosting is still behind its release-readiness gates."
        end
        return "IPv4 Direct hosting currently requires 64-bit Windows."
    end

    function Runtime.DirectIpv4Runtime.portInUse(port)
        for _, record in ipairs(Runtime.DirectIpv4Runtime.hosts) do
            if record.port == port then return true end
        end
        return false
    end

    function Runtime.DirectIpv4Runtime.nextPort()
        for _, slot in ipairs(Runtime.DirectIpv4Runtime.portSlots) do
            if not Runtime.DirectIpv4Runtime.portInUse(slot.outer) then return slot.outer end
        end
        return nil
    end

    function Runtime.directHostCanInvite()
        if Runtime.directConnection or Runtime.DirectIpv4Runtime.pending or not Runtime.directHostComposite
            or not Runtime.multiplayer:isHost() or Runtime.multiplayer.networkKind ~= "direct"
        then
            return false
        end
        local countOk, count = pcall(Runtime.directHostComposite.linkCount, Runtime.directHostComposite)
        local capacityOk, capacity = pcall(Runtime.directHostComposite.capacity, Runtime.directHostComposite)
        local hudOk, info = pcall(Runtime.multiplayer.hudInfo, Runtime.multiplayer)
        return countOk and capacityOk and type(count) == "number" and type(capacity) == "number"
            and hudOk and type(info) == "table"
            and (tonumber(info.pendingJoinCount) or 0) == 0
            and count >= 0 and count < capacity
    end

    function Runtime.createDirectConnection(loopbackHostPort)
        local ok, socketModule = pcall(require, "socket")
        if not ok then return nil, "Direct Internet sockets are unavailable on this device." end
        return Runtime.RuntimeDependencies.DirectConnection.new({
            provider = Runtime.CryptoNative,
            socketModule = socketModule,
            loopbackHostPort = loopbackHostPort,
        })
    end

    function Runtime.startDirectHostConnection(localAddress)
        local slotCount = #Runtime.DirectIpv4Runtime.portSlots
        local firstSlot = (Runtime.directHostInvitationGeneration % slotCount) + 1
        local lastError = "No Direct guest port slot is available."
        for offset = 0, slotCount - 1 do
            local slotIndex = ((firstSlot + offset - 1) % slotCount) + 1
            local slot = Runtime.DirectIpv4Runtime.portSlots[slotIndex]
            local connection, connectionError = Runtime.createDirectConnection(slot.loopback)
            if not connection then return nil, connectionError end
            local started, codeOrError = connection:startHost(localAddress, slot.outer)
            if started then
                Runtime.directHostInvitationGeneration = slotIndex
                return connection, codeOrError
            end
            lastError = codeOrError or lastError
            local closeOk, cleaned = pcall(connection.close, connection)
            if not closeOk or cleaned ~= true then
                return nil,
                    "A Direct port attempt could not be cleaned up safely; restart the game before hosting again.",
                    connection
            end
        end
        return nil, lastError
    end

    function Runtime.prepareDirectHost(slot, playerName, localAddress)
        local connectionClean, connectionError = Runtime.closeDirectConnection()
        if not connectionClean then return false, connectionError end
        local hostClean, hostError = Runtime.closeDirectHostComposite()
        if not hostClean then return false, hostError end
        local payload, mode, loadError = Runtime.prepareHostSave(slot)
        if not payload then return false, loadError end
        local connection, codeOrError, cleanupOwner = Runtime.startDirectHostConnection(localAddress)
        if not connection then
            if cleanupOwner then Runtime.directConnection = cleanupOwner end
            return false, codeOrError
        end
        Runtime.directConnection = connection
        Runtime.pendingDirectSession = {
            role = "host",
            kind = "initial_host",
            payload = payload,
            saveMode = mode,
            name = tostring(playerName or "Direct Worker"):gsub("Worker", "Host"),
        }
        return true, codeOrError
    end

    function Runtime.DirectIpv4Runtime.beginHost(kind, playerName, payload, saveMode)
        if not Runtime.DirectIpv4Runtime.hostingAvailable() then
            return false, Runtime.DirectIpv4Runtime.hostingUnavailableMessage()
        end
        if Runtime.DirectIpv4Runtime.pending then
            return false, "Another IPv4 Direct invitation is still being prepared."
        end
        if kind == "additional" and not Runtime.directHostCanInvite() then
            return false, "Direct guest capacity is full or another invitation is active."
        end
        local port = Runtime.DirectIpv4Runtime.nextPort()
        if not port then return false, "No safe IPv4 guest port is available." end
        local host, hostError = Runtime.DirectIpv4Runtime.Host.new({ provider = Runtime.CryptoNative })
        if not host then return false, hostError end
        local record = {
            kind = kind,
            host = host,
            port = port,
            name = playerName,
            payload = payload,
            saveMode = saveMode,
            closing = false,
            attached = false,
            linkHandle = nil,
        }
        local started, startError = host:start(port)
        if not started then
            record.closing = true
            local called, cleaned = pcall(host.stop, host)
            if not called or cleaned ~= true then
                Runtime.DirectIpv4Runtime.hosts[#Runtime.DirectIpv4Runtime.hosts + 1] = record
                Runtime.DirectIpv4Runtime.pending = record
                return false,
                    "IPv4 host setup failed and cleanup could not be verified; restart the game before retrying."
            end
            return false, startError
        end
        Runtime.DirectIpv4Runtime.hosts[#Runtime.DirectIpv4Runtime.hosts + 1] = record
        Runtime.DirectIpv4Runtime.pending = record
        return true
    end

    function Runtime.DirectIpv4Runtime.prepareHost(slot, playerName)
        if Runtime.multiplayer:isActive() then
            return false, "Close the active multiplayer session before starting a new Direct host."
        end
        local payload, mode, loadError = Runtime.prepareHostSave(slot)
        if not payload then return false, loadError end
        local name = tostring(playerName or "Direct Worker"):gsub("Worker", "Host")
        return Runtime.DirectIpv4Runtime.beginHost("initial", name, payload, mode)
    end
end

return Component
