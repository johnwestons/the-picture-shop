local Profiles = {}

Profiles.ORDER = { "premium_hss", "carbide_edge" }
local RANK = { standard = 1, premium_hss = 2, carbide_edge = 3 }
Profiles.DATA = {
    standard = {
        id = "standard", name = "Standard service blade", shortName = "STANDARD", wearMultiplier = 1,
        qualityFloor = 0.70, price = 0,
    },
    premium_hss = {
        id = "premium_hss", name = "Premium ground blade", shortName = "PREMIUM HSS", wearMultiplier = 0.68,
        qualityFloor = 0.82, price = 795,
        detail = "Wears 32% slower; worn-edge quality stays above 82%.",
    },
    carbide_edge = {
        id = "carbide_edge", name = "Long-life carbide blade", shortName = "CARBIDE EDGE", wearMultiplier = 0.40,
        qualityFloor = 0.90, price = 1450,
        detail = "Wears 60% slower; worn-edge quality stays above 90%.",
    },
}

function Profiles.get(id)
    return Profiles.DATA[id]
end

function Profiles.isOrderable(id)
    local profile = Profiles.get(id)
    return profile ~= nil and id ~= "standard"
end

function Profiles.isUpgrade(current, target)
    return Profiles.isOrderable(target) and (RANK[target] or 0) > (RANK[current] or 0)
end

return Profiles
