-- Manual host mapping and cleanup obligations.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.DirectIpv4Runtime.beginManualHost(kind, playerName, payload, saveMode,
            externalAddress)
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
        local host, hostError = Runtime.DirectIpv4Runtime.Host.new({
            provider = Runtime.CryptoNative,
            manualOnly = true,
        })
        if not host then return false, hostError end
        local record = {
            kind = kind,
            host = host,
            port = port,
            name = playerName,
            payload = payload,
            saveMode = saveMode,
            manual = true,
            closing = false,
            attached = false,
            linkHandle = nil,
        }
        local started, details = host:startManualSetup(port, {
            externalAddress = externalAddress,
            externalPort = port,
            lifetimeSeconds = 15 * 60,
        })
        if not started then
            record.closing = true
            local called, cleaned = pcall(host.stop, host)
            if not called or cleaned ~= true then
                Runtime.DirectIpv4Runtime.hosts[#Runtime.DirectIpv4Runtime.hosts + 1] = record
                Runtime.DirectIpv4Runtime.pending = record
                return false,
                    "The secure listener could not be closed safely; retry cleanup before hosting again."
            end
            return false, details
        end
        record.manualDetails = details
        Runtime.DirectIpv4Runtime.hosts[#Runtime.DirectIpv4Runtime.hosts + 1] = record
        Runtime.DirectIpv4Runtime.pending = record
        return true, details
    end

    function Runtime.DirectIpv4Runtime.prepareManualHost(slot, playerName, externalAddress)
        if Runtime.multiplayer:isActive() then
            return false, "Close the active multiplayer session before starting a new Direct host."
        end
        local payload, mode, loadError = Runtime.prepareHostSave(slot)
        if not payload then return false, loadError end
        local name = tostring(playerName or "Direct Worker"):gsub("Worker", "Host")
        return Runtime.DirectIpv4Runtime.beginManualHost(
            "initial", name, payload, mode, externalAddress)
    end

    function Runtime.DirectIpv4Runtime.prepareAdditionalManualHost(_, playerName, externalAddress)
        local connectionClean, connectionError = Runtime.closeDirectConnection()
        if not connectionClean then return false, connectionError end
        return Runtime.DirectIpv4Runtime.beginManualHost(
            "additional", playerName, nil, nil, externalAddress)
    end

    function Runtime.DirectIpv4Runtime.startManualHostFromScreen(slot, playerName, externalAddress)
        if Runtime.multiplayer:isHost() and Runtime.multiplayer.networkKind == "direct" then
            return Runtime.DirectIpv4Runtime.prepareAdditionalManualHost(
                slot, playerName, externalAddress)
        end
        return Runtime.DirectIpv4Runtime.prepareManualHost(slot, playerName, externalAddress)
    end

    function Runtime.DirectIpv4Runtime.confirmManualHost()
        local record = Runtime.DirectIpv4Runtime.pending
        if not record or record.manual ~= true then
            return false, "No manual IPv4 router setup is waiting for confirmation."
        end
        local called, confirmed, invitationOrError = pcall(
            record.host.confirmManualSetup, record.host)
        if not called or confirmed ~= true then
            return false, invitationOrError
                or "Manual IPv4 setup could not be confirmed safely."
        end
        record.manualConfirmed = true
        return true
    end

    function Runtime.DirectIpv4Runtime.manualCleanupInfo()
        for index = #Runtime.DirectIpv4Runtime.hosts, 1, -1 do
            local record = Runtime.DirectIpv4Runtime.hosts[index]
            local called, details = pcall(record.host.manualCleanupDetails, record.host)
            if called and type(details) == "table" then return details end
        end
        return nil
    end

    function Runtime.DirectIpv4Runtime.hasManualCleanupObligation()
        for _, record in ipairs(Runtime.DirectIpv4Runtime.hosts) do
            local called, status = pcall(record.host.status, record.host)
            if called and type(status) == "table"
                and (status.manualRuleConfirmed == true
                    or status.cleanupKind == "manual") then
                return true
            end
        end
        return false
    end

    function Runtime.DirectIpv4Runtime.acknowledgeManualCleanup()
        for index = #Runtime.DirectIpv4Runtime.hosts, 1, -1 do
            local record = Runtime.DirectIpv4Runtime.hosts[index]
            local called, details = pcall(record.host.manualCleanupDetails, record.host)
            if called and type(details) == "table" then
                local acknowledged, result = pcall(
                    record.host.acknowledgeManualCleanup, record.host)
                if not acknowledged or result ~= true then
                    return false, "The manual router-rule cleanup could not be verified."
                end
                Runtime.DirectIpv4Runtime.removeHostRecord(record)
                return true
            end
        end
        return false, "No closed manual IPv4 listener is waiting for cleanup confirmation."
    end

    function Runtime.DirectIpv4Runtime.cancelManualWithRule()
        local record = Runtime.DirectIpv4Runtime.pending
        if record and record.manual == true
            and record.host.state == "manual_setup" then
            local called, marked = pcall(
                record.host.requireManualCleanup, record.host)
            if not called or marked ~= true then
                return false, "The manual router-rule cleanup could not be recorded safely."
            end
        end
        return Runtime.DirectIpv4Runtime.cancelPlayAttempt()
    end

    function Runtime.enterDirectCleanupScreen(message, retry)
        Runtime.state.screen = "direct"
        Runtime.DirectScreen.enter({
            slot = Runtime.lastDirectSlot,
            allowIpv4Host = false,
            cancel = retry or Runtime.DirectIpv4Runtime.cancelPlayAttempt,
            back = retry or Runtime.DirectIpv4Runtime.cancelPlayAttempt,
            manualCleanupInfo = Runtime.DirectIpv4Runtime.manualCleanupInfo,
            acknowledgeManualCleanup = Runtime.DirectIpv4Runtime.acknowledgeManualCleanup,
        })
        local details = Runtime.DirectIpv4Runtime.manualCleanupInfo()
        if details then
            Runtime.DirectScreen.showManualCleanup(details, message)
        else
            Runtime.DirectScreen.showCleanupError(message)
        end
    end

    function Runtime.presentManualHostCleanup(record, message)
        local manualDetails = Runtime.DirectIpv4Runtime.manualCleanupInfo()
        if not manualDetails then return false end
        local function finish()
            if Runtime.DirectIpv4Runtime.manualCleanupInfo() then
                return false, "Remove and acknowledge the displayed manual UDP rule first."
            end
            if Runtime.multiplayer:isHost() and Runtime.multiplayer.networkKind == "direct" then
                Runtime.DirectScreen.leave()
                Runtime.state.screen = "world"
                Runtime.state.message = "The manual UDP rule was removed. Existing Direct workers stayed online."
                return true
            end
            return Runtime.DirectIpv4Runtime.cancelPlayAttempt()
        end
        Runtime.enterDirectCleanupScreen(message, finish)
        return true
    end

    function Runtime.cancelAdditionalManualWithRule()
        local record = Runtime.DirectIpv4Runtime.pending
        if not record or record.manual ~= true then
            return false, "No manual IPv4 invitation is waiting for cancellation."
        end
        local called, marked = pcall(
            record.host.requireManualCleanup, record.host)
        if not called or marked ~= true then
            return false, "The manual router-rule cleanup could not be recorded safely."
        end
        return Runtime.DirectIpv4Runtime.cancelPendingInvite()
    end
end

return Component
