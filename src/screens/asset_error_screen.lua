local Screen = {}

function Screen.normalize(...)
    local result = {}
    local function add(value)
        if type(value) == "table" then
            for _, entry in ipairs(value) do add(entry) end
        elseif type(value) == "string" then
            for line in value:gmatch("[^\r\n]+") do
                if line ~= "" then result[#result + 1] = line end
            end
        end
    end
    for index = 1, select("#", ...) do add(select(index, ...)) end
    return result
end

function Screen.draw(errors)
    errors = Screen.normalize(errors)
    love.graphics.clear(0.055, 0.025, 0.03)
    love.graphics.setColor(0.20, 0.055, 0.065, 1)
    love.graphics.rectangle("fill", 42, 34, 876, 612, 6, 6)
    love.graphics.setColor(0.92, 0.30, 0.30)
    love.graphics.setLineWidth(3)
    love.graphics.rectangle("line", 42, 34, 876, 612, 6, 6)
    love.graphics.setColor(1, 0.86, 0.38)
    love.graphics.print("ASSET STARTUP ERROR", 72, 64)
    love.graphics.setColor(0.94, 0.90, 0.90)
    love.graphics.printf(
        "The shop could not start because required artwork is missing or malformed. "
            .. "Restore the listed files or dimensions, then restart the game.",
        72, 104, 816, "left")
    love.graphics.setColor(0.10, 0.035, 0.04, 1)
    love.graphics.rectangle("fill", 72, 164, 816, 390, 4, 4)
    love.graphics.setColor(1, 0.72, 0.72)
    for index = 1, math.min(#errors, 12) do
        love.graphics.printf(string.format("%d. %s", index, errors[index]),
            92, 184 + (index - 1) * 29, 776, "left")
    end
    if #errors > 12 then
        love.graphics.print(string.format("...and %d more error(s).", #errors - 12), 92, 532)
    end
    love.graphics.setColor(0.72, 0.76, 0.78)
    love.graphics.print("Press Esc or Q to close.", 72, 590)
end

return Screen
