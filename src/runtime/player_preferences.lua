-- Player appearance and game-clock preferences.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.isAndroidPlatform()
        return love and love.system and love.system.getOS
            and love.system.getOS() == "Android"
    end

    Runtime.App.syncPlayerColorways = function()
        if not Runtime.World.player then return end
        local settings = Runtime.App.settings or Runtime.Settings.DEFAULTS
        Runtime.World.player.furColorway = settings.furColorway or 1
        Runtime.World.player.overallsColorway = settings.overallsColorway or 1
        local name=Runtime.multiplayer and Runtime.multiplayer:isActive() and Runtime.multiplayer.localName
            or require('src.player_profile').name(settings)
        if Runtime.TitleScreen then Runtime.TitleScreen.profileSettings=settings end
        Runtime.World.player.name=name
        if Runtime.multiplayer and Runtime.multiplayer:isActive() then
            Runtime.multiplayer.localFurColorway=settings.furColorway or 1
            Runtime.multiplayer.localOverallsColorway=settings.overallsColorway or 1
            local own=Runtime.multiplayer.players[Runtime.multiplayer.localId]
            if own then own.name=name end
        end
        if Runtime.state.home and not Runtime.multiplayer:isClient()
            and require('src.home_residents').setName(Runtime.state,Runtime.World.player,name) then
            if Runtime.multiplayer:isHost() then Runtime.multiplayer:markShopDirty(true) end
            if Runtime.state.activeSlot and Runtime.saveCurrent then Runtime.saveCurrent() end
        end
    end
    Runtime.App.syncPlayerProfile=function()
        local name=require('src.player_profile').name(Runtime.App.settings)
        if Runtime.multiplayer and Runtime.multiplayer:isActive() then Runtime.multiplayer.localName=name end
        if Runtime.lanReconnect and Runtime.lanReconnect.target then Runtime.lanReconnect.target.playerName=name end
        if Runtime.privateServerReconnect then Runtime.privateServerReconnect.playerName=name end
        if Runtime.pendingDirectSession then Runtime.pendingDirectSession.name=name end
        if Runtime.DirectIpv4Runtime and Runtime.DirectIpv4Runtime.pending then Runtime.DirectIpv4Runtime.pending.name=name end
        Runtime.App.syncPlayerColorways()
    end

    Runtime.App.gameClockSpeed = 1
    Runtime.App.gameClockSyncClock = 0
    Runtime.App.gameClockSaveClock = 0
    Runtime.App.setGameClockSpeed = function(speed)
        if require("src.weekend_flow").atHome(Runtime.state) then
            Runtime.state.message="At home, use Sleep & Alarms. Time speeds up only when everyone chooses sleep."
            return false
        end
        if Runtime.multiplayer:isClient() then
            Runtime.state.message = "Only the host can change game speed."
            return false
        end
        if speed ~= 1 and speed ~= 2 and speed ~= 5 and speed ~= 10 then
            Runtime.state.message = "Choose 1x, 2x, 5x, or 10x game speed."
            return false
        end
        local changed = Runtime.App.gameClockSpeed ~= speed
        Runtime.App.gameClockSpeed = speed
        if changed and Runtime.multiplayer:isHost() then
            Runtime.App.gameClockSyncClock = 0
            Runtime.multiplayer:markShopDirty(true)
        end
        Runtime.state.message = speed == 1 and "Game speed set to normal."
            or ("Game speed set to " .. tostring(speed) .. "x.")
        return true
    end
end

return Component
