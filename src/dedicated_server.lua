-- Headless private-server callbacks. The normal app is not loaded on this path.
local App = require("src.app")

local started = false

return {
    load = function()
        local okay, reason = App.startDedicatedServer()
        if not okay then
            io.stderr:write("[PRIVATE SERVER] Startup failed: " .. tostring(reason) .. "\n")
            io.stderr:flush()
            love.event.quit(1)
            return false
        end
        started = true
        return true
    end,
    update = function(dt)
        if started then
            App.update(dt)
            App.advancePrivateServerRunTimer(dt)
        end
    end,
    quit = function()
        if started then return App.stopDedicatedServer() end
        return false
    end,
}
