-- Direct connection polling and shop entry.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    Runtime.DirectIpv4Runtime.updateConnection = function()
        local connection = Runtime.directConnection
        if not connection then return end
        local connectionState, connectionError = connection:update()
        if connectionState == "failed" then
            Runtime.directScreenError(connectionError,
                Runtime.pendingDirectSession and Runtime.pendingDirectSession.kind == "additional_host")
            return
        end
        if connectionState ~= "ready" then return end

        local transportFactory, roleOrError = connection:takeTransportFactory()
        if not transportFactory then
            Runtime.directScreenError(roleOrError,
                Runtime.pendingDirectSession and Runtime.pendingDirectSession.kind == "additional_host")
            return
        end
        local pending = Runtime.pendingDirectSession
        Runtime.directConnection = nil
        Runtime.pendingDirectSession = nil
        connection:close()
        if not pending or pending.role ~= roleOrError then
            local disposed = Runtime.disposeDirectTransportFactory(transportFactory)
            if not disposed then
                Runtime.DirectScreen.showCleanupError(
                    "The Direct connection role failed and its cleanup could not be verified; restart the game.")
                return
            end
            Runtime.directScreenError("The Direct connection role could not be verified.",
                pending and pending.kind == "additional_host")
            return
        end

        if roleOrError == "host" then
            if pending.kind == "additional_host" then
                if not Runtime.directHostComposite or type(Runtime.directHostComposite.attachFactory) ~= "function" then
                    if not Runtime.disposeDirectTransportFactory(transportFactory) then
                        Runtime.DirectScreen.showCleanupError(
                            "The additional Direct link could not be attached or cleaned up; restart the game.")
                        return
                    end
                    Runtime.directScreenError("The active Direct host cannot accept another encrypted link.", true)
                    return
                end
                local attached, attachError = Runtime.directHostComposite:attachFactory(
                    transportFactory, { channels = 3 })
                if not attached then
                    Runtime.directScreenError(attachError or
                        "The additional encrypted Direct link could not start.", true)
                    return
                end
                Runtime.DirectScreen.leave()
                Runtime.state.screen = "world"
                Runtime.state.message = "The new encrypted link is ready. Approve that worker in the Players panel when requested."
                if Runtime.syncMobileKeyboard then Runtime.syncMobileKeyboard() end
                return
            end

            local compositeFactory, compositeController = Runtime.RuntimeDependencies.DirectCompositeTransport.newFactory({
                maxGuests = 3,
                channels = 3,
            })
            if not compositeFactory or not compositeController then
                if not Runtime.disposeDirectTransportFactory(transportFactory) then
                    Runtime.DirectScreen.showCleanupError(
                        "The first Direct link could not be attached or cleaned up; restart the game.")
                    return
                end
                Runtime.directScreenError(compositeController or
                    "The multi-worker Direct host transport could not start.")
                return
            end
            -- Retain the controller before attachment so any unverified cleanup
            -- remains owned and blocks another invitation until process restart.
            Runtime.directHostComposite = compositeController
            local attached, attachError = compositeController:attachFactory(
                transportFactory, { channels = 3 })
            if not attached then
                local cleaned, cleanupError = Runtime.closeDirectHostComposite()
                if not cleaned then
                    Runtime.DirectScreen.showCleanupError(cleanupError)
                    return
                end
                Runtime.directScreenError(attachError or "The first encrypted Direct link could not start.")
                return
            end
            Runtime.workshopAuthority = Runtime.createWorkshopAuthority()
            Runtime.localWorkshopLease = nil
            Runtime.localWorkshopRequestId = 0
            Runtime.activeCutterRemote = nil
            Runtime.activeWrapperRemote = nil
            Runtime.activeWindmillRemote = nil
            local hosted, hostError = Runtime.multiplayer:startHost({
                port = 22122,
                name = pending.name,
                character = Runtime.Config.player.character,
                furColorway = Runtime.App.settings and Runtime.App.settings.furColorway or 1,
                overallsColorway = Runtime.App.settings and Runtime.App.settings.overallsColorway or 1,
                networkKind = "direct",
                transportFactory = compositeFactory,
            })
            if not hosted then
                local cleaned, cleanupError = Runtime.closeDirectHostComposite()
                Runtime.clearWorkshopAuthority("host_start_failed")
                if not cleaned then
                    Runtime.DirectScreen.showCleanupError(cleanupError)
                    return
                end
                Runtime.directScreenError(hostError)
                return
            end
            local started, startError = Runtime.startGame(pending.payload, pending.saveMode)
            if not started then
                Runtime.multiplayer:stop("Direct host save could not be opened")
                local cleaned, cleanupError = Runtime.closeDirectHostComposite()
                Runtime.clearWorkshopAuthority("host_save_failed")
                if not cleaned then
                    Runtime.DirectScreen.showCleanupError(cleanupError)
                    return
                end
                Runtime.directScreenError(startError)
                return
            end
            Runtime.DirectScreen.leave()
            if Runtime.isAndroidPlatform() and love.window and love.window.setDisplaySleepEnabled then
                love.window.setDisplaySleepEnabled(false)
            end
            Runtime.state.message = "Direct host active. Each worker uses a fresh invitation and must be approved before joining."
        else
            local joined, joinError = Runtime.multiplayer:startClient("127.0.0.1:22122", {
                name = pending.name,
                character = Runtime.Config.player.character,
                furColorway = Runtime.App.settings and Runtime.App.settings.furColorway or 1,
                overallsColorway = Runtime.App.settings and Runtime.App.settings.overallsColorway or 1,
                networkKind = "direct",
                transportFactory = transportFactory,
            })
            if not joined then
                Runtime.directScreenError(joinError)
                return
            end
            Runtime.state.screen = "direct"
            Runtime.DirectScreen.setMessage(
                "Encrypted request is ready. Waiting for the host to approve this player.",
                "connecting")
            if Runtime.syncMobileKeyboard then Runtime.syncMobileKeyboard() end
        end
    end
end

return Component
