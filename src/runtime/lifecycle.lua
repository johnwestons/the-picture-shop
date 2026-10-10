-- Focus changes and shutdown cleanup.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.App.focus(focused)
        if Runtime.state.screen=="critter_kombat" then
            require("src.screens.critter_kombat_screen").cancelInputs(not focused)
        end
        if focused then
            if Runtime.App.multiplayerFocusGrace:isExpired() then
                Runtime.App.multiplayerFocusGrace:clear()
                Runtime.App.expireBackgroundMultiplayer()
            else
                Runtime.App.multiplayerFocusGrace:clear()
            end
            if Runtime.multiplayer:isHost() and Runtime.isAndroidPlatform()
                and love.window and love.window.setDisplaySleepEnabled then
                love.window.setDisplaySleepEnabled(false)
            end
        elseif Runtime.multiplayer:isActive() then
            Runtime.App.multiplayerFocusGrace:start()
        else
            Runtime.App.multiplayerFocusGrace:clear()
        end

        if not focused and Runtime.mobileControls then
            Runtime.mobileControls:cancelAll()
        end
        if not focused then
            Runtime.Assets.clearCache()
            Runtime.CharacterAssets.clearCache()
            Runtime.WorldRenderer.clearCache()
            Runtime.multiplayer:sendNeutralInput()
            if Runtime.controller then Runtime.controller:cancelAll() end
            Runtime.saveCurrent()
            local activeDirectHost = Runtime.multiplayer:isHost()
                and Runtime.multiplayer.networkKind == "direct"
            if Runtime.directConnection then
                local cleaned, cleanupError = Runtime.closeDirectConnection()
                if not cleaned then
                    Runtime.state.screen = "direct"
                    Runtime.DirectScreen.showCleanupError(cleanupError)
                elseif activeDirectHost and not Runtime.isAndroidPlatform() then
                    Runtime.DirectScreen.leave()
                    Runtime.state.screen = "world"
                    Runtime.state.message = "The pending Direct invitation was cancelled because the app lost focus; connected workers stayed online."
                elseif not activeDirectHost then
                    Runtime.state.screen = "direct"
                    Runtime.DirectScreen.showError(
                        "Direct setup was cancelled safely because the app left the foreground.")
                end
                Runtime.syncMobileKeyboard()
            elseif Runtime.state.screen == "direct" and Runtime.multiplayer:isClient()
                and Runtime.multiplayer.networkKind == "direct"
                and not Runtime.App.multiplayerFocusGrace:isTracking() then
                Runtime.multiplayer:stop("Direct client left the foreground during setup")
                Runtime.openDirectPlay(Runtime.lastDirectSlot)
                Runtime.DirectScreen.showError(
                    "Direct setup ended safely because this device left the foreground.")
                Runtime.syncMobileKeyboard()
            end
        end
        if Runtime.App.sound then Runtime.App.sound:setPaused(not focused) end
    end

    function Runtime.App.quit()
        if not Runtime.spriteLabActive then Runtime.saveCurrent() end
        Runtime.lanDiscovery:stop()
        Runtime.lanReconnect:cancel(true)
        local sessionClean, sessionError = Runtime.multiplayer:stop("Application closed")
        Runtime.clearWorkshopAuthority("application_closed")
        local connectionClean, connectionError = Runtime.closeDirectConnection()
        local hostClean, hostError = Runtime.closeDirectHostComposite()
        if not sessionClean or not connectionClean or not hostClean then
            Runtime.enterDirectCleanupScreen(sessionError or connectionError or hostError,
                Runtime.DirectIpv4Runtime.cancelPlayAttempt)
            if Runtime.syncMobileKeyboard then Runtime.syncMobileKeyboard() end
            return true
        end
        Runtime.DirectScreen.leave()
        if Runtime.isAndroidPlatform() and love.window and love.window.setDisplaySleepEnabled then
            love.window.setDisplaySleepEnabled(true)
        end
        if Runtime.App.sound then Runtime.App.sound:shutdown() end
        return false
    end

    Runtime.App.multiplayer = Runtime.multiplayer
end

return Component
