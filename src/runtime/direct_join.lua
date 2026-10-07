-- Direct invites, joining, and returning to the title.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.prepareDirectGuest(hostCode, localAddress, playerName)
        local connectionClean, connectionError = Runtime.closeDirectConnection()
        if not connectionClean then return false, connectionError end
        local hostClean, hostError = Runtime.closeDirectHostComposite()
        if not hostClean then return false, hostError end
        local connection, connectionError = Runtime.createDirectConnection()
        if not connection then return false, connectionError end
        local started, codeOrError = connection:startGuest(hostCode, localAddress)
        if not started then
            local closeCalled, cleaned = pcall(connection.close, connection)
            if not closeCalled or cleaned ~= true then
                Runtime.directConnection = connection
                return false,
                    "Direct guest setup failed and its cleanup could not be verified; restart the game before trying again."
            end
            return false, codeOrError
        end
        Runtime.directConnection = connection
        Runtime.pendingDirectSession = {
            role = "guest",
            name = tostring(playerName or "Direct Worker"),
        }
        return true, codeOrError
    end

    function Runtime.DirectIpv4Runtime.prepareGuest(hostCode, playerName)
        local connectionClean, connectionError = Runtime.closeDirectConnection()
        if not connectionClean then return false, connectionError end
        local hostClean, hostError = Runtime.closeDirectHostComposite()
        if not hostClean then return false, hostError end
        local transportFactory, endpoint = Runtime.DirectIpv4Runtime.Listener.clientFactory(hostCode, {
            provider = Runtime.CryptoNative,
        })
        if not transportFactory then return false, endpoint end
        local joined, joinError = Runtime.multiplayer:startClient(endpoint, {
            name = tostring(playerName or "Direct Worker"),
            character = Runtime.Config.player.character,
            furColorway = Runtime.App.settings and Runtime.App.settings.furColorway or 1,
            overallsColorway = Runtime.App.settings and Runtime.App.settings.overallsColorway or 1,
            networkKind = "direct",
            transportFactory = transportFactory,
        })
        if not joined then
            local cleaned = Runtime.disposeDirectTransportFactory(transportFactory)
            if not cleaned then
                return false,
                    "The IPv4 Direct invitation could not be cleaned up; restart the game before trying again."
            end
            return false, joinError
        end
        Runtime.state.screen = "direct"
        return true
    end

    function Runtime.DirectIpv4Runtime.cancelPlayAttempt()
        local connectionClean, connectionError = Runtime.closeDirectConnection()
        if not connectionClean then return false, connectionError end
        -- Stop even if a prior stop left the session offline but still owning an
        -- unverified transport; Session:stop retries that retained cleanup.
        local sessionClean, sessionError = Runtime.multiplayer:stop("Direct connection cancelled")
        if not sessionClean then return false, sessionError end
        return Runtime.closeDirectHostComposite()
    end

    function Runtime.prepareAdditionalDirectHost(_, _, localAddress)
        local connectionClean, connectionError = Runtime.closeDirectConnection()
        if not connectionClean then return false, connectionError end
        if not Runtime.directHostCanInvite() then
            return false, "Direct guest capacity is full or another invitation is still being prepared."
        end
        local connection, codeOrError, cleanupOwner = Runtime.startDirectHostConnection(localAddress)
        if not connection then
            if cleanupOwner then Runtime.directConnection = cleanupOwner end
            return false, codeOrError
        end
        Runtime.directConnection = connection
        Runtime.pendingDirectSession = {
            role = "host",
            kind = "additional_host",
        }
        return true, codeOrError
    end

    function Runtime.DirectIpv4Runtime.prepareAdditionalHost(_, playerName)
        local connectionClean, connectionError = Runtime.closeDirectConnection()
        if not connectionClean then return false, connectionError end
        return Runtime.DirectIpv4Runtime.beginHost("additional", playerName)
    end

    function Runtime.DirectIpv4Runtime.startHostFromScreen(slot, playerName)
        if Runtime.multiplayer:isHost() and Runtime.multiplayer.networkKind == "direct" then
            return Runtime.DirectIpv4Runtime.prepareAdditionalHost(slot, playerName)
        end
        return Runtime.DirectIpv4Runtime.prepareHost(slot, playerName)
    end

    function Runtime.submitDirectResponse(responseCode)
        if not Runtime.directConnection or not Runtime.pendingDirectSession
            or Runtime.pendingDirectSession.role ~= "host" then
            return false, "No Direct host invitation is waiting for a reply."
        end
        return Runtime.directConnection:submitResponse(responseCode)
    end

    function Runtime.DirectIpv4Runtime.enterShop()
        if not Runtime.multiplayer:isHost() or Runtime.multiplayer.networkKind ~= "direct" then
            return false, "The Direct host session is not ready."
        end
        Runtime.DirectScreen.leave()
        if Runtime.DirectIpv4Runtime.pending then
            Runtime.DirectIpv4Runtime.pending.invitationScreenActive = false
            Runtime.DirectIpv4Runtime.pending = nil
        end
        Runtime.state.screen = "world"
        Runtime.state.message = "Direct host active. Approve every worker in the Players panel."
        return true
    end

    function Runtime.DirectIpv4Runtime.cancelPendingInvite()
        local record = Runtime.DirectIpv4Runtime.pending
        if not record or record.kind ~= "additional" then return true end
        if record.linkHandle and Runtime.directHostComposite
            and Runtime.directHostComposite:hasLink(record.linkHandle) then
            local retired, retireError = Runtime.directHostComposite:retireLink(
                record.linkHandle, 0, true)
            if not retired then return false, retireError end
        end
        record.closing = true
        local called, cleaned = pcall(record.host.stop, record.host)
        if called and cleaned == true then
            if Runtime.DirectIpv4Runtime.pending == record then Runtime.DirectIpv4Runtime.pending = nil end
            for index, item in ipairs(Runtime.DirectIpv4Runtime.hosts) do
                if item == record then table.remove(Runtime.DirectIpv4Runtime.hosts, index); break end
            end
            return true
        end
        return false,
            "IPv4 router-mapping cleanup is still pending. Keep the game open and retry cleanup."
    end

    Runtime.openDirectPlay = function(slot)
        Runtime.lanDiscovery:stop()
        Runtime.lanReconnect:cancel(true)
        Runtime.lanReconnectArmed = false
        local sessionClean, sessionError = Runtime.multiplayer:stop("Opening Direct Play")
        Runtime.clearWorkshopAuthority("session_closed")
        local connectionClean, connectionError = Runtime.closeDirectConnection()
        local hostClean, hostError = Runtime.closeDirectHostComposite()
        if not sessionClean or not connectionClean or not hostClean then
            Runtime.state.screen = "direct"
            Runtime.DirectScreen.showCleanupError(sessionError or connectionError or hostError)
            return false
        end
        Runtime.DirectScreen.leave()
        Runtime.lastDirectSlot = tonumber(slot) or Runtime.lastDirectSlot or 1
        Runtime.state.screen = "direct"
        Runtime.DirectScreen.enter({
            slot = Runtime.lastDirectSlot,
            host = Runtime.prepareDirectHost,
            hostIpv4 = Runtime.DirectIpv4Runtime.startHostFromScreen,
            hostIpv4Manual = Runtime.DirectIpv4Runtime.startManualHostFromScreen,
            join = Runtime.prepareDirectGuest,
            joinIpv4 = Runtime.DirectIpv4Runtime.prepareGuest,
            response = Runtime.submitDirectResponse,
            enterShop = Runtime.DirectIpv4Runtime.enterShop,
            allowIpv4Host = Runtime.DirectIpv4Runtime.hostingAvailable(),
            cancel = Runtime.DirectIpv4Runtime.cancelPlayAttempt,
            cancelManualWithRule = Runtime.DirectIpv4Runtime.cancelManualWithRule,
            confirmIpv4Manual = Runtime.DirectIpv4Runtime.confirmManualHost,
            manualCleanupInfo = Runtime.DirectIpv4Runtime.manualCleanupInfo,
            acknowledgeManualCleanup = Runtime.DirectIpv4Runtime.acknowledgeManualCleanup,
            back = function()
                local cleaned, cleanupError = Runtime.DirectIpv4Runtime.cancelPlayAttempt()
                if not cleaned then
                    Runtime.DirectScreen.showCleanupError(cleanupError)
                    return false, cleanupError
                end
                Runtime.state.screen = "title"
                Runtime.TitleScreen.enter(Runtime.startGame, Runtime.openLocalPlay,
                    Runtime.CryptoNative.productionReady == true and Runtime.openDirectPlay or nil)
                return true
            end,
        })
    end

    Runtime.openDirectInvite = function()
        if not Runtime.directHostCanInvite() then
            Runtime.state.message = "Direct guest capacity is full or another invitation is still active."
            return false
        end
        Runtime.MultiplayerHud.close()
        Runtime.state.screen = "direct"
        Runtime.DirectScreen.enter({
            slot = Runtime.lastDirectSlot,
            inviteOnly = true,
            host = Runtime.prepareAdditionalDirectHost,
            hostIpv4 = Runtime.DirectIpv4Runtime.prepareAdditionalHost,
            hostIpv4Manual = Runtime.DirectIpv4Runtime.prepareAdditionalManualHost,
            response = Runtime.submitDirectResponse,
            enterShop = Runtime.DirectIpv4Runtime.enterShop,
            allowIpv4Host = Runtime.DirectIpv4Runtime.hostingAvailable(),
            cancelManualWithRule = Runtime.cancelAdditionalManualWithRule,
            confirmIpv4Manual = Runtime.DirectIpv4Runtime.confirmManualHost,
            manualCleanupInfo = Runtime.DirectIpv4Runtime.manualCleanupInfo,
            acknowledgeManualCleanup = Runtime.DirectIpv4Runtime.acknowledgeManualCleanup,
            cancel = function()
                local cleaned, cleanupError = Runtime.closeDirectConnection()
                if not cleaned then return false, cleanupError end
                local ipv4Cleaned, ipv4Error = Runtime.DirectIpv4Runtime.cancelPendingInvite()
                if not ipv4Cleaned then return false, ipv4Error end
                Runtime.DirectScreen.leave()
                Runtime.state.screen = "world"
                Runtime.state.message = "The pending Direct invitation was cancelled; connected workers stayed online."
                return true
            end,
            back = function()
                local cleaned, cleanupError = Runtime.closeDirectConnection()
                if not cleaned then return false, cleanupError end
                local ipv4Cleaned, ipv4Error = Runtime.DirectIpv4Runtime.cancelPendingInvite()
                if not ipv4Cleaned then return false, ipv4Error end
                Runtime.DirectScreen.leave()
                Runtime.state.screen = "world"
                return true
            end,
        })
        if Runtime.syncMobileKeyboard then Runtime.syncMobileKeyboard() end
        return true
    end

    Runtime.returnToTitle = function()
        Runtime.saveCurrent()
        Runtime.lanDiscovery:stop()
        Runtime.lanReconnect:cancel(true)
        Runtime.lanReconnectArmed = false
        local sessionClean, sessionError = Runtime.multiplayer:stop("Returned to title")
        Runtime.clearWorkshopAuthority("session_closed")
        local connectionClean, connectionError = Runtime.closeDirectConnection()
        local hostClean, hostError = Runtime.closeDirectHostComposite()
        if not sessionClean or not connectionClean or not hostClean then
            Runtime.enterDirectCleanupScreen(sessionError or connectionError or hostError,
                Runtime.returnToTitle)
            return false
        end
        Runtime.DirectScreen.leave()
        if Runtime.isAndroidPlatform() and love.window and love.window.setDisplaySleepEnabled then
            love.window.setDisplaySleepEnabled(true)
        end
        Runtime.state.screen = "title"
        Runtime.TitleScreen.enter(Runtime.startGame, Runtime.openLocalPlay,
            Runtime.CryptoNative.productionReady == true and Runtime.openDirectPlay or nil)
    end
end

return Component
