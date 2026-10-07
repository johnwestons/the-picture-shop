-- Direct host activation and host-link lifecycle.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.directScreenError(message, keepActiveHost)
        local cleaned, cleanupError = Runtime.closeDirectConnection()
        if not cleaned then
            Runtime.state.screen = "direct"
            Runtime.DirectScreen.showCleanupError(cleanupError)
            if Runtime.syncMobileKeyboard then Runtime.syncMobileKeyboard() end
            return
        end
        if keepActiveHost and Runtime.multiplayer:isHost() and Runtime.multiplayer.networkKind == "direct" then
            Runtime.DirectScreen.leave()
            Runtime.state.screen = "world"
            Runtime.state.message = tostring(message or "The additional Direct invitation could not start.")
            if Runtime.syncMobileKeyboard then Runtime.syncMobileKeyboard() end
            return
        end
        Runtime.state.screen = "direct"
        Runtime.DirectScreen.showError(message or "The Direct connection could not start.")
        if Runtime.syncMobileKeyboard then Runtime.syncMobileKeyboard() end
    end

    function Runtime.DirectIpv4Runtime.removeHostRecord(record)
        if Runtime.DirectIpv4Runtime.pending == record then Runtime.DirectIpv4Runtime.pending = nil end
        for index, item in ipairs(Runtime.DirectIpv4Runtime.hosts) do
            if item == record then table.remove(Runtime.DirectIpv4Runtime.hosts, index); break end
        end
    end

    function Runtime.DirectIpv4Runtime.retireHostLink(record)
        if not record.linkHandle or not Runtime.directHostComposite then return true end
        local hasCall, hasLink = pcall(
            Runtime.directHostComposite.hasLink, Runtime.directHostComposite, record.linkHandle)
        if not hasCall then return false, "The IPv4 guest link could not be checked safely." end
        if not hasLink then return true end
        local called, retired, retireError = pcall(
            Runtime.directHostComposite.retireLink, Runtime.directHostComposite,
            record.linkHandle, 0, true)
        if not called or retired ~= true then
            return false, retireError or "The IPv4 guest link could not be retired safely."
        end
        return true
    end

    function Runtime.DirectIpv4Runtime.reportHostError(record, message)
        local linkRetired, retireError = Runtime.DirectIpv4Runtime.retireHostLink(record)
            if not linkRetired then
                record.closing = true
                Runtime.DirectScreen.showCleanupError(retireError)
            Runtime.state.screen = "direct"
            return
        end
        record.closing = true
        if record.kind == "initial" then
            local sessionCalled, sessionClean = pcall(
                Runtime.multiplayer.stop, Runtime.multiplayer, "Direct IPv4 host setup failed")
            if not sessionCalled or sessionClean ~= true then
                Runtime.DirectScreen.showCleanupError(
                    "The Direct host session could not be closed safely. Keep the game open and retry cleanup.")
                Runtime.state.screen = "direct"
                return
            end
            Runtime.clearWorkshopAuthority("host_start_failed")
            local hostClean, hostError = Runtime.closeDirectHostComposite()
            if not hostClean then
                if not Runtime.presentManualHostCleanup(record, hostError) then
                    Runtime.DirectScreen.showCleanupError(hostError)
                end
                Runtime.state.screen = "direct"
                return
            end
            Runtime.DirectScreen.showError(message or "The IPv4 invitation could not be created.")
            Runtime.state.screen = "direct"
            return
        end
        local called, cleaned = pcall(record.host.stop, record.host)
        if called and cleaned == true then Runtime.DirectIpv4Runtime.removeHostRecord(record) end
        if called and cleaned ~= true then
            local cleanupMessage =
                "IPv4 router-mapping cleanup is still pending. Keep the game open and retry cleanup."
            if not Runtime.presentManualHostCleanup(record, cleanupMessage) then
                Runtime.DirectScreen.showCleanupError(cleanupMessage)
            end
            Runtime.state.screen = "direct"
        elseif record.kind == "additional" and Runtime.multiplayer:isHost()
            and Runtime.multiplayer.networkKind == "direct" then
            Runtime.DirectScreen.leave()
            Runtime.state.screen = "world"
            Runtime.state.message = tostring(message or "The IPv4 invitation could not be created.")
        else
            Runtime.DirectScreen.showError(message or "The IPv4 invitation could not be created.")
        end
    end

    function Runtime.DirectIpv4Runtime.activateHost(record)
        local compositeFactory = nil
        local controller = Runtime.directHostComposite
        if record.kind == "initial" then
            if controller then
                return false, "A Direct host transport is already active."
            end
            local factory, newController, factoryError = Runtime.RuntimeDependencies.DirectCompositeTransport.newFactory({
                maxGuests = 3,
                channels = 3,
                firstConnectTimeoutSeconds = 120,
            })
            if not factory or not newController then
                return false, factoryError or "The multi-worker Direct host transport could not start."
            end
            compositeFactory, controller = factory, newController
            Runtime.directHostComposite = controller
        elseif not controller then
            return false, "The active Direct host transport is unavailable."
        end

        local linkHandle, attachError = record.host:attachToSession(controller)
        if not linkHandle then return false, attachError end
        record.linkHandle = linkHandle
        record.attached = true

        if record.kind == "initial" then
            Runtime.workshopAuthority = Runtime.createWorkshopAuthority()
            Runtime.localWorkshopLease = nil
            Runtime.localWorkshopRequestId = 0
            Runtime.activeCutterRemote = nil
            Runtime.activeWrapperRemote = nil
            Runtime.activeWindmillRemote = nil
            local hosted, hostError = Runtime.multiplayer:startHost({
                port = 22122,
                name = record.name,
                character = Runtime.Config.player.character,
                furColorway = Runtime.App.settings and Runtime.App.settings.furColorway or 1,
                overallsColorway = Runtime.App.settings and Runtime.App.settings.overallsColorway or 1,
                networkKind = "direct",
                transportFactory = compositeFactory,
            })
            if not hosted then
                Runtime.clearWorkshopAuthority("host_start_failed")
                return false, hostError
            end
            local started, startError = Runtime.startGame(record.payload, record.saveMode)
            if not started then
                Runtime.multiplayer:stop("Direct host save could not be opened")
                Runtime.clearWorkshopAuthority("host_save_failed")
                return false, startError
            end
        end

        local code = record.host:invitation()
        if type(code) ~= "string" then
            return false, "The IPv4 invitation expired before it could be shown."
        end
        record.invitationScreenActive = true
        Runtime.state.screen = "direct"
        if record.manual == true then
            Runtime.DirectScreen.showManualIpv4HostInvitation(code, record.manualDetails)
        else
            Runtime.DirectScreen.showIpv4HostInvitation(code)
        end
        return true
    end

    function Runtime.DirectIpv4Runtime.updateHosts()
        for index = #Runtime.DirectIpv4Runtime.hosts, 1, -1 do
            local record = Runtime.DirectIpv4Runtime.hosts[index]
            local updated, hostState, hostError = pcall(record.host.update,
                record.host)
            if not updated then
                hostState = "failed"
                hostError = "The IPv4 mapping status could not be checked safely."
            end
            if record.manual == true and record.host.manualRouteInvalidated == true
                and Runtime.state.screen == "direct"
                and Runtime.DirectScreen.mode == "ipv4_manual_rule" then
                local statusCalled, hostStatus = pcall(record.host.status, record.host)
                Runtime.DirectScreen.showManualSetupInvalidated(statusCalled
                    and type(hostStatus) == "table"
                    and hostStatus.listenerClosedBeforeCleanup == true)
            end
            local linkPresent, linkCheckFailed = false, false
            if record.linkHandle and Runtime.directHostComposite then
                local called, result = pcall(Runtime.directHostComposite.hasLink,
                    Runtime.directHostComposite, record.linkHandle)
                linkPresent = called and result == true
                linkCheckFailed = not called
            end
            if record.closing then
                local called, cleaned = pcall(record.host.stop, record.host)
                if called and cleaned == true then
                    Runtime.DirectIpv4Runtime.removeHostRecord(record)
                elseif not record.manualCleanupPrompted
                    and Runtime.presentManualHostCleanup(record,
                        "Remove the manual UDP rule before returning to play.") then
                    record.manualCleanupPrompted = true
                end
            elseif linkCheckFailed then
                Runtime.DirectIpv4Runtime.reportHostError(record,
                    "The IPv4 guest link could not be checked safely.")
            elseif record.linkHandle and not linkPresent then
                if record.invitationScreenActive and Runtime.state.screen == "direct" then
                    Runtime.DirectScreen.showError(
                        "The IPv4 invitation expired or its guest disconnected. Create a fresh invitation to reconnect.")
                end
                record.closing = true
                local called, cleaned = pcall(record.host.stop, record.host)
                if called and cleaned == true then
                    Runtime.DirectIpv4Runtime.removeHostRecord(record)
                elseif Runtime.presentManualHostCleanup(record,
                    "Remove the manual UDP rule before returning to play.") then
                    record.manualCleanupPrompted = true
                end
            elseif record.attached
                and (hostState == "failed" or hostState == "unavailable"
                    or hostState == "cleanup_required") then
                Runtime.DirectIpv4Runtime.reportHostError(record, hostError
                    or "The IPv4 network mapping is no longer safe to use.")
            elseif record.attached and record.invitationScreenActive then
                local code = record.host:invitation()
                if type(code) == "string" and Runtime.DirectScreen.mode ~= "ipv4_host_ready"
                    and Runtime.state.screen == "direct" then
                    if record.manual == true then
                        Runtime.DirectScreen.showManualIpv4HostInvitation(
                            code, record.manualDetails)
                    else
                        Runtime.DirectScreen.showIpv4HostInvitation(code)
                    end
                elseif not code and Runtime.state.screen == "direct"
                    and Runtime.DirectScreen.mode == "ipv4_host_ready" then
                    Runtime.DirectScreen.showIpv4HostPending(
                        "The router mapping changed. Waiting for a safe replacement before sharing a new code.")
                end
            elseif not record.attached and hostState == "ready" then
                local activated, activateError = Runtime.DirectIpv4Runtime.activateHost(record)
                if not activated then Runtime.DirectIpv4Runtime.reportHostError(record, activateError) end
            elseif not record.attached
                and (hostState == "failed" or hostState == "unavailable"
                    or hostState == "cleanup_required") then
                Runtime.DirectIpv4Runtime.reportHostError(record, hostError
                    or "Automatic IPv4 router mapping is unavailable on this network.")
            end
        end
    end
end

return Component
