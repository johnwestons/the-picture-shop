local Interaction = {}

local function distance(a, b)
    local dx = (tonumber(a and a.x) or 0) - (tonumber(b and b.x) or 0)
    local dy = (tonumber(a and a.y) or 0) - (tonumber(b and b.y) or 0)
    return math.sqrt(dx * dx + dy * dy)
end

-- Adapted from Mouse Frontier's interaction chooser. Only targets within the
-- player's operating radius are candidates. A hovered target wins strongly;
-- otherwise cursor proximity leads and player proximity breaks close ties.
-- When no cursor is supplied, its position falls back to the player so
-- keyboard, touch-button, and controller interaction remains nearest-first.
function Interaction.select(player, interactables, cursorX, cursorY, previous, options)
    options = options or {}
    local cursorSupplied = tonumber(cursorX) ~= nil and tonumber(cursorY) ~= nil
    local cursor = {
        x = tonumber(cursorX) or tonumber(player and player.x) or 0,
        y = tonumber(cursorY) or tonumber(player and player.y) or 0,
    }
    local intentX = tonumber(player and player.intentX) or tonumber(player and player.facing) or 1
    local intentY = tonumber(player and player.intentY) or 0
    local intentLength = math.sqrt(intentX * intentX + intentY * intentY)
    if intentLength > 0 then intentX, intentY = intentX / intentLength, intentY / intentLength end
    local best, bestScore
    for name, target in pairs(interactables) do
        local playerDistance = distance(player, target)
        local radius = math.max(0, tonumber(target.radius) or 0)
        if playerDistance <= radius then
            local cursorDistance = distance(cursor, target)
            local hovered = cursorDistance <= math.max(0, tonumber(target.hoverRadius) or 42)
            local facingPenalty = 0
            if not cursorSupplied and playerDistance > 0 and intentLength > 0 then
                local targetX = (target.x - player.x) / playerDistance
                local targetY = (target.y - player.y) / playerDistance
                local alignment = targetX * intentX + targetY * intentY
                facingPenalty = (1 - alignment) * math.max(0, tonumber(options.facingWeight) or 0)
            end
            local sticky = previous and previous.kind == name
                and math.max(0, tonumber(options.stickiness) or 0) or 0
            local score = cursorDistance + playerDistance * 0.001 + facingPenalty
                - (hovered and 10000 or 0) - sticky
            if not bestScore or score < bestScore
                or (score == bestScore and tostring(name) < tostring(best.kind))
            then
                bestScore = score
                best = {
                    kind = name,
                    distance = playerDistance * playerDistance,
                    playerDistance = playerDistance,
                    cursorDistance = cursorDistance,
                    hovered = hovered,
                    score = score,
                    target = target,
                }
            end
        end
    end
    return best
end

function Interaction.prompt(selected)
    if not selected then return nil end
    if selected.target and selected.target.prompt then return selected.target.prompt end
    if selected.kind == "computer" then return "E: use office computer" end
    if selected.kind == "cutter" then return "E: use Polar 115" end
    if selected.kind == "skidWrapper" then return "E: use skid wrapper" end
    return nil
end

return Interaction
