-- This replaces only the entry point of the isolated Direct Test APK.
-- The shared source and ordinary game packages keep their readiness gates.
local function showStartupFailure(reason)
    function love.load() end
    function love.update() end
    function love.draw()
        love.graphics.clear(0.055, 0.07, 0.09, 1)
        love.graphics.setColor(1, 1, 1, 1)
        local width, height = love.graphics.getDimensions()
        love.graphics.printf("Picture Shop Direct Test", 30, height * 0.25,
            width - 60, "center")
        love.graphics.printf("The test game could not start.\nStatus: " .. reason
            .. "\nClose the app and report this status.", 30, height * 0.40,
            width - 60, "center")
    end
    function love.keypressed(key)
        if key == "escape" or key == "back" then love.event.quit() end
    end
    -- Bootstrap.install may have partially installed callbacks. None should
    -- enter an incompletely initialized game after a startup failure.
    for _, name in ipairs({ "keyreleased", "textinput", "mousepressed",
        "mousereleased", "mousemoved", "wheelmoved", "touchpressed",
        "touchmoved", "touchreleased", "gamepadpressed", "gamepadreleased",
        "gamepadaxis", "focus", "quit" }) do
        love[name] = function() end
    end
end

local loaded, CryptoNative = pcall(require, "src.net.crypto_native")
if not loaded or type(CryptoNative) ~= "table"
    or CryptoNative.available ~= true
    or CryptoNative.candidateReady ~= true
    or CryptoNative.engineeringReady ~= true
    or CryptoNative.engineeringOnly ~= true
    or CryptoNative.productionReady ~= false
then
    showStartupFailure("native_candidate_unavailable")
    return
end

-- A process-local engineering opt-in, never a change to shared source or a
-- production-readiness claim. The packaged native library remains a candidate.
CryptoNative.productionReady = true
local installed = pcall(function()
    require("tools.probes.android_manual_direct.ui_setup").install()
    require("src.bootstrap").install()
end)
if not installed then
    CryptoNative.productionReady = false
    showStartupFailure("bootstrap_unavailable")
    return
end

local originalLoad = love.load
function love.load(...)
    local started = pcall(originalLoad, ...)
    if not started then
        CryptoNative.productionReady = false
        showStartupFailure("game_startup_failed")
    end
end
