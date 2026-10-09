-- Seated body height is shorter than standing height. Register the posterior
-- on the cushion, while the visitor's logical position remains its route contact.
local Art = require("src.client_seating_art")
local Seating = { bodyHeightRatio = .703125 }

function Seating.supports(character)
    return Art.anchors[character] ~= nil
end

function Seating.transform(visitor, characterAssets, frame, normalization)
    local scale = visitor.drawScale * normalization * Seating.bodyHeightRatio
    local pose = visitor.seat and visitor.seat.seatedPose
    if pose then
        return visitor.x + pose.x - visitor.seat.x,
            visitor.y + pose.y - visitor.seat.y, scale, pose.mirror
    end
    -- Older/custom seat definitions still use a feet contact.
    local _, anchorY = characterAssets.getAnchor(visitor.character, "sit", frame)
    local _, _, _, bottom = characterAssets.getVisibleBounds(visitor.character, "sit", frame)
    return visitor.x, visitor.y - (bottom - anchorY) * scale, scale, -visitor.facing
end

return Seating
