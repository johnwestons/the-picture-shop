local Capabilities = require("src.multiplayer_capabilities")
local WorkshopAuthority = require("src.workshop_authority")

local Test = {}

local EXPECTED_INTERACTIONS = {
    computer = true,
    workPhone = true,
    customer = true,
    vendor = true,
    loadingBayDoor = true,
    truckCargoDoor = true,
    palletWorkOrder = true,
    cutter = true,
    skidWrapper = true,
    windmill = true,
    palletJack = true,
}

function Test.run(context, check)
    local valid, validationError = Capabilities.validate()
    check("multiplayer_capability_registry_is_valid", valid, validationError)

    local exactKinds = true
    for kind in pairs(EXPECTED_INTERACTIONS) do
        exactKinds = exactKinds and Capabilities.forInteraction(kind) ~= nil
    end
    for kind in pairs(Capabilities.INTERACTIONS) do
        exactKinds = exactKinds and EXPECTED_INTERACTIONS[kind] == true
    end
    check("multiplayer_every_world_interaction_has_capability_policy", exactKinds)

    local authorityResourcesCovered = true
    local coveredResources = {}
    for _, capability in pairs(Capabilities.INTERACTIONS) do
        if capability.resourceId then coveredResources[capability.resourceId] = true end
    end
    for resourceId in pairs(Capabilities.RESERVED_RESOURCES) do
        coveredResources[resourceId] = true
        authorityResourcesCovered = authorityResourcesCovered and WorkshopAuthority.RESOURCES[resourceId] == true
    end
    for resourceId in pairs(WorkshopAuthority.RESOURCES) do
        authorityResourcesCovered = authorityResourcesCovered and coveredResources[resourceId] == true
    end
    check("multiplayer_every_workshop_resource_has_capability_policy",
        authorityResourcesCovered)

    check("multiplayer_reserved_warehouse_is_not_advertised_as_playable",
        Capabilities.RESERVED_RESOURCES.warehouse.mode == "planned"
        and Capabilities.forInteraction("warehouse") == nil)
    Capabilities.RESERVED_RESOURCES.cutter = Capabilities.RESERVED_RESOURCES.warehouse
    local duplicateReservedValid = Capabilities.validate()
    Capabilities.RESERVED_RESOURCES.cutter = nil
    check("multiplayer_reserved_resource_cannot_duplicate_playable_resource", not duplicateReservedValid)

    local vendor = Capabilities.forInteraction("vendor")
    local truck = Capabilities.forInteraction("truckCargoDoor")
    local cutter = Capabilities.forInteraction("cutter")
    local wrapper = Capabilities.forInteraction("skidWrapper")
    local windmill = Capabilities.forInteraction("windmill")
    local palletJack = Capabilities.forInteraction("palletJack")
    local workPhone = Capabilities.forInteraction("workPhone")
    check("multiplayer_unfinished_guest_work_is_explicitly_classified",
        vendor.mode == "candidate" and vendor.roadmapStep == "vendor_purchasing"
        and vendor.resourceId == "vendor" and #vendor.physicalAcceptance == 6
        and truck.mode == "candidate" and truck.resourceId == "truck"
        and truck.roadmapStep == "truck_delivery_pickup"
        and #truck.physicalAcceptance == 6
        and cutter.mode == "candidate" and cutter.missing == nil
        and #cutter.physicalAcceptance == 9
        and wrapper.mode == "candidate" and wrapper.missing == nil
        and #wrapper.physicalAcceptance == 10
        and windmill.mode == "candidate" and windmill.missing == nil
        and #windmill.physicalAcceptance == 6
        and workPhone.mode == "candidate" and workPhone.resourceId == "work_phone"
        and workPhone.missing == nil and #workPhone.physicalAcceptance == 3
        and palletJack.mode == "candidate" and palletJack.missing == nil
        and #palletJack.physicalAcceptance == 6)

    check("multiplayer_guest_roadmap_order_is_stable",
        Capabilities.ROADMAP[1] == "capability_registry"
        and Capabilities.ROADMAP[2] == "vendor_purchasing"
        and Capabilities.ROADMAP[3] == "truck_delivery_pickup"
        and Capabilities.ROADMAP[#Capabilities.ROADMAP] == "clean_tester_release")

    local rejected, message = pcall(Capabilities.requireInteraction,
        "future_undeclared_interaction")
    check("multiplayer_undeclared_interaction_is_rejected_at_runtime",
        not rejected and tostring(message):find("future_undeclared_interaction", 1, true) ~= nil)
end

return Test
