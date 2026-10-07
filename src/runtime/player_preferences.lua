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
    end

    Runtime.App.gameClockSpeed = 1
    Runtime.App.gameClockSyncClock = 0
    Runtime.App.gameClockSaveClock = 0
    Runtime.App.setGameClockSpeed = function(speed)
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
