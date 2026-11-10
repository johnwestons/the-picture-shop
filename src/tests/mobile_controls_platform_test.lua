local MobileControls = require("src.mobile_controls")

local Test = {}

local function controlsEnabledFor(osName)
    local previousGetOS = love.system.getOS
    local previousGetenv = os.getenv
    love.system.getOS = function() return osName end
    os.getenv = function(name)
        if name == "PICTURE_SHOP_MOBILE" then return nil end
        return previousGetenv(name)
    end

    local controls = MobileControls.new({
        toGame = function(x, y) return x, y end,
        pressKey = function() end,
        releaseKey = function() end,
        pressPointer = function() end,
        movePointer = function() end,
        releasePointer = function() end,
        gameplayActive = function() return true end,
    })

    love.system.getOS = previousGetOS
    os.getenv = previousGetenv
    return controls:isEnabled()
end

function Test.run(_, check)
    check("mobile_controls_enable_for_android_and_ios_only",
        controlsEnabledFor("Android") and controlsEnabledFor("iOS")
        and not controlsEnabledFor("Windows"))
end

return Test
