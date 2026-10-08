-- One selection policy for fork controls, mouse/touch targets and world highlights.
local Jack = require("src.pallet_jack")
local Pickup = {}

function Pickup.snapshot(state, config, player, cursorX, cursorY)
    local view = { candidates = {}, byId = {} }
    local jack = state and state.palletJack
    local playerId = player and tonumber(player.id) or 1
    if not jack or not jack.operating or jack.operatorPlayerId ~= playerId
        or jack.carriedPalletId or (player and player.sceneId and player.sceneId ~= "warehouse")
        or (state.cutter and state.cutter.moving) or (state.wrapper and state.wrapper.moving)
        or (state.windmill and state.windmill.moving) then return view end
    view.hasPointer = type(cursorX) == "number" and type(cursorY) == "number"
    view.candidates = Jack.pickupCandidates(state, config)
    local hovered, hoverDistance
    for _, item in ipairs(view.candidates) do
        local world = item.pallet.world
        local progress = world.spawnProgress or 1
        item.x = (world.fromX or world.x) + (world.x - (world.fromX or world.x)) * progress
        item.y = (world.fromY or world.y) + (world.y - (world.fromY or world.y)) * progress
        view.byId[item.pallet.id] = item
        -- Match the visible skid's generous mouse/touch area, independently of
        -- the operator's feet. Authoritative eligibility is measured at the jack.
        local bodyHit = view.hasPointer and cursorX >= item.x - 54 and cursorX <= item.x + 54
            and cursorY >= item.y - 82 and cursorY <= item.y + 10
        local labelHit = view.hasPointer and cursorX >= item.x - 25 and cursorX <= item.x + 25
            and cursorY >= item.y - 99 and cursorY <= item.y - 81
        if bodyHit or labelHit then
            local distance = (cursorX - item.x) ^ 2 + (cursorY - (item.y - 36)) ^ 2
            if not hovered or distance < hoverDistance
                or (distance == hoverDistance and item.y > hovered.y) then
                hovered, hoverDistance = item, distance
            end
        end
    end
    view.hovered = hovered ~= nil
    view.selected = hovered or view.candidates[1]
    return view
end

function Pickup.interaction(view, player, ordinary)
    local item = view.selected
    if not item then return ordinary end
    -- Deliberate clicks on another shop control remain available. Otherwise
    -- lifting takes priority over nearby machinery, paperwork and prompt stickiness.
    if view.hasPointer and not view.hovered and ordinary and ordinary.hovered
        and ordinary.kind ~= "palletJack" and ordinary.kind ~= "palletWorkOrder" then return ordinary end
    return { kind = "palletJack", hovered = view.hovered,
        distance = item.pickupDistance, playerDistance = math.sqrt((player.x - item.x) ^ 2 + (player.y - item.y) ^ 2),
        target = { x = item.x, y = item.y, item = item, pickup = true,
            candidatePalletId = item.pallet.id, ownsJack = true,
            prompt = "Click / tap or L: lift " .. item.pallet.id .. "  |  F: park jack" } }
end

function Pickup.selectedId(selected)
    local target = selected and selected.target
    if target and (target.pickup or (selected.kind == "palletWorkOrder" and selected.hovered)) then
        return target.item and target.item.pallet and target.item.pallet.id
    end
end

return Pickup
