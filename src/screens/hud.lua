local Config = require("src.config")
local BackButton = require("src.screens.back_button")

local Hud = {}
local EXIT = { x = 816, y = 14, width = 126, height = 40 }

local function shadowedPrint(text, x, y, color)
    love.graphics.setColor(0.04, 0.05, 0.06, 0.9)
    love.graphics.print(text, x + 2, y + 2)
    love.graphics.setColor(color)
    love.graphics.print(text, x, y)
end

local function shadowedPrintf(text, x, y, width, color)
    love.graphics.setColor(0.04, 0.05, 0.06, 0.9)
    love.graphics.printf(text, x + 2, y + 2, width, "left")
    love.graphics.setColor(color)
    love.graphics.printf(text, x, y, width, "left")
end

function Hud.draw(state, prompt, assets, pointerX, pointerY)
    shadowedPrint("$" .. state.money, 24, 20, { 0.95, 0.84, 0.30 })
    shadowedPrint("Paper: " .. state.inventory.paper, 92, 20, { 0.88, 0.92, 0.94 })
    shadowedPrint("Finished: " .. state.inventory.prints, 190, 20, { 0.88, 0.92, 0.94 })
    BackButton.draw(assets, EXIT, "EXIT TO MENU", pointerX, pointerY, false)
    if state.message then
        shadowedPrintf(state.message, 24, 48, Config.baseWidth - 48, { 0.88, 0.92, 0.94 })
    end
    if prompt then
        shadowedPrint(prompt, 360, Config.baseHeight - 52, { 0.95, 0.85, 0.35 })
    end
    shadowedPrint(
        "WASD / arrows: move    E: interact",
        22,
        Config.baseHeight - 28,
        { 0.82, 0.86, 0.88 }
    )
end

function Hud.hitTest(x, y)
    return BackButton.contains(EXIT, x, y) and "exit" or nil
end

return Hud
