local Config = require("src.config")

local MultiplayerHud = {}

function MultiplayerHud.draw(info)
    if type(info) ~= "table" or info.mode == "offline" then return end
    local role = info.mode == "host" and "LAN HOST" or "LAN GUEST"
    local players = tonumber(info.playerCount) or 1
    local line = role .. "  •  " .. tostring(players) .. "/4 WORKERS"
    if info.mode == "host" and info.address then
        line = line .. "  •  " .. tostring(info.address) .. ":" .. tostring(info.port or 22122)
    elseif info.rtt then
        line = line .. "  •  " .. tostring(math.floor(info.rtt + 0.5)) .. " ms"
    end
    local width = math.min(500, math.max(290, love.graphics.getFont():getWidth(line) + 24))
    local x = Config.baseWidth - width - 18
    love.graphics.setColor(0.025, 0.04, 0.05, 0.91)
    love.graphics.rectangle("fill", x, 84, width, 25, 4, 4)
    love.graphics.setColor(info.mode == "host" and { 0.95, 0.78, 0.23, 1 }
        or { 0.38, 0.80, 0.76, 1 })
    love.graphics.rectangle("line", x, 84, width, 25, 4, 4)
    love.graphics.printf(line, x + 8, 90, width - 16, "center")
end

return MultiplayerHud
