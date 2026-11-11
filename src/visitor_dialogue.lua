local Procurement = require("src.procurement")

local Dialogue = {}

function Dialogue.customer(state)
    local offer = state and state.currentOffer
    if offer and offer.press then
        local colors = tonumber(offer.press.colors) or 0
        if colors > 1 then
            return "Hi! I'd like an estimate for a multi-color letterpress job."
        end
        return "Hi! I'd like an estimate for a letterpress job."
    end
    return "Hello! I'm here to talk through a print job and get an estimate."
end

function Dialogue.vendor(state)
    local category = Procurement.category(state and state.vendorCategory)
    local lines = {
        paper = "I brought paper and board stock for you to look over.",
        press = "I have ink and other pressroom supplies for you.",
        packaging = "I brought cartons and stretch wrap for your shipments.",
        equipment = "I can show you maintenance kits and replacement tools.",
        machines = "I have used warehouse machines available for sale.",
    }
    return "Hi, I'm " .. category.salesman .. ". "
        .. (lines[category.id] or "I brought our latest supply catalog.")
end

return Dialogue
