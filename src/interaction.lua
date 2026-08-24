local Interaction = {}

local function distanceSquared(a, b)
    local dx = a.x - b.x
    local dy = a.y - b.y
    return dx * dx + dy * dy
end

function Interaction.select(player, interactables)
    local best
    for name, target in pairs(interactables) do
        local distance = distanceSquared(player, target)
        if distance <= target.radius * target.radius and (not best or distance < best.distance) then
            best = {
                kind = name,
                distance = distance,
                target = target,
            }
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
