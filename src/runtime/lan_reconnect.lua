-- LAN errors, discovery, and reconnect handling.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.showConnectionError(message, stopReason)
        local direct = Runtime.multiplayer.networkKind == "direct"
        if not direct and tostring(stopReason or ""):match("^Invalid") then
            -- Malformed authoritative state is not a transient link failure. Do
            -- not loop back into the same incompatible or unsafe snapshot.
            Runtime.lanReconnect:cancel(false)
            Runtime.lanReconnectArmed = false
        end
        local cleaned, cleanupError = Runtime.multiplayer:stop(stopReason or "Connection error")
        if not cleaned then
            if direct then
                Runtime.state.screen = "direct"
                Runtime.DirectScreen.showCleanupError(cleanupError)
            else
                Runtime.state.screen = "lan"
                Runtime.LanScreen.showError(cleanupError)
            end
            Runtime.syncMobileKeyboard()
            return
        end
        if direct then
            Runtime.openDirectPlay(Runtime.lastDirectSlot)
            Runtime.DirectScreen.showError(message or "The Direct connection ended.")
        else
            Runtime.state.screen = "lan"
            Runtime.LanScreen.showError(message or "The LAN connection ended.")
            Runtime.startLanSearch()
        end
        Runtime.syncMobileKeyboard()
    end

    Runtime.FATAL_LAN_RECONNECT_ERRORS = {
        invalid_join = true,
        shop_full = true,
        kicked = true,
        protocol_mismatch = true,
        message_not_allowed = true,
    }

    function Runtime.handleLanReconnectFailure(message)
        local snapshot = Runtime.lanReconnect:snapshot()
        if snapshot.active and snapshot.state == "waiting" then
            -- An error and its following disconnect may arrive in the same drain.
            -- The first event already scheduled the next attempt.
            return true
        end
        if not snapshot.active and not Runtime.lanReconnectArmed then return false end
        local cleaned, cleanupError = Runtime.multiplayer:stop("Preparing LAN reconnect")
        if not cleaned then
            Runtime.lanReconnect:cancel(false)
            Runtime.lanReconnectArmed = false
            Runtime.state.screen = "lan"
            Runtime.LanScreen.showError(cleanupError)
            Runtime.startLanSearch()
            return true
        end
        local scheduled, scheduleError
        if snapshot.active and snapshot.state == "connecting" then
            scheduled, scheduleError = Runtime.lanReconnect:failed(message)
        elseif not snapshot.active then
            scheduled, scheduleError = Runtime.lanReconnect:begin(message)
        else
            return true
        end
        Runtime.clearWorkshopAuthority("transport_failed")
        Runtime.WorkshopRemoteScreen.clear()
        Runtime.state.screen = "lan"
        Runtime.startLanSearch()
        if scheduled then
            Runtime.LanScreen.showReconnect(Runtime.lanReconnect:snapshot())
        else
            Runtime.lanReconnectArmed = false
            Runtime.LanScreen.showError(scheduleError or
                "Automatic reconnect ended. Choose a found shop or enter its address.")
        end
        Runtime.syncMobileKeyboard()
        return true
    end

    function Runtime.updateLanConvenience(dt)
        Runtime.lanDiscovery:update(dt)
        if Runtime.state.screen == "lan" and not Runtime.lanReconnect:isActive() then
            local _, discoveryMessage = Runtime.lanDiscovery:status()
            Runtime.LanScreen.setDiscovery(Runtime.lanDiscovery:results(), discoveryMessage)
        end
        local attempt = Runtime.lanReconnect:update(dt)
        if not attempt then
            if Runtime.state.screen == "lan" and Runtime.lanReconnect:isActive() then
                Runtime.LanScreen.showReconnect(Runtime.lanReconnect:snapshot())
            end
            return
        end
        local cleaned, cleanupError = Runtime.multiplayer:stop("Starting LAN reconnect attempt")
        local connected, connectError = false, cleanupError
        if cleaned then
            connected, connectError = Runtime.startLanClient(
                attempt.address, attempt.playerName, true)
        end
        if not connected then
            local scheduled, exhaustedMessage = Runtime.lanReconnect:failed(connectError)
            Runtime.startLanSearch()
            if not scheduled then
                Runtime.lanReconnectArmed = false
                Runtime.state.screen = "lan"
                Runtime.LanScreen.showError(exhaustedMessage)
                return
            end
        end
        Runtime.state.screen = "lan"
        Runtime.LanScreen.showReconnect(Runtime.lanReconnect:snapshot())
    end
end

return Component
