-- Canonical Local Play capability registry.
--
-- Every interaction kind exposed by World must be declared here before it can
-- be added to the interaction selector. This keeps new single-player features
-- from silently becoming inaccessible or unsafe for Guest Workers.
local Capabilities = {}

Capabilities.MODES = {
    full = true,
    candidate = true,
    read_only = true,
    mixed = true,
    planned = true,
}

Capabilities.INTERACTIONS = {
    computer = {
        label = "Office computer",
        mode = "candidate",
        resourceId = "office_computer",
        supported = { "inspect_shop", "inspect_jobs", "request_pickup", "send_estimate", "decline_email",
            "send_promotion", "archive_email", "checkout", "sell_machine", "pay_bills", "shared_host_gui" },
        physicalAcceptance = { "typed_estimate_and_promotion", "exact_once_checkout", "offline_host_save_reload" },
    },
    workPhone = {
        label = "Wall-mounted work phone",
        mode = "candidate",
        resourceId = "work_phone",
        supported = { "see_phone", "see_call_light", "answer_calls", "place_phone_orders", "respond", "dismiss" },
        physicalAcceptance = { "two_guest_contention", "exact_once_phone_order", "disconnect_and_reacquire" },
    },
    customer = {
        label = "Reception customer",
        mode = "full",
        resourceId = "reception_customer",
        supported = { "review_offer", "request_email_details" },
    },
    vendor = {
        label = "Supplier representative",
        mode = "candidate",
        resourceId = "vendor",
        roadmapStep = "vendor_purchasing",
        supported = { "inspect_catalog", "purchase_stock", "purchase_machine", "dismiss" },
        physicalAcceptance = {
            "two_guest_contention", "exact_once_purchase",
            "synchronized_cash_and_purchase_order", "used_machine_purchase",
            "disconnect_and_reacquire", "offline_host_save_reload",
        },
    },
    loadingBayDoor = {
        label = "Loading-bay door",
        mode = "full",
        supported = { "open", "close" },
    },
    truckCargoDoor = {
        label = "Delivery truck",
        mode = "candidate",
        resourceId = "truck",
        roadmapStep = "truck_delivery_pickup",
        supported = {
            "inspect_manifest", "receive_delivery", "receive_machine",
            "load_completed_pickup", "release_truck",
        },
        physicalAcceptance = {
            "two_guest_contention", "exact_once_cargo_move", "paged_manifest",
            "synchronized_delivery_and_pickup", "disconnect_and_reacquire",
            "offline_host_save_reload",
        },
    },
    palletWorkOrder = {
        label = "Pallet work order",
        mode = "read_only",
        supported = { "inspect_work_order" },
    },
    cutter = {
        label = "Polar cutter",
        mode = "candidate",
        resourceId = "cutter",
        supported = {
            "production", "safety_controls", "lubrication", "blade_service",
            "technician_scheduling", "machine_relocation",
        },
        roadmapSteps = { "cutter_maintenance", "machine_relocation" },
        physicalAcceptance = {
            "two_guest_contention", "lubrication_sequence", "exact_once_kit_consumption",
            "blade_and_technician_sequence", "disconnect_and_reacquire",
            "offline_host_save_reload", "all_three_machine_relocations",
            "invalid_and_valid_placement", "relocation_disconnect_recovery",
        },
    },
    skidWrapper = {
        label = "Skid wrapper",
        mode = "candidate",
        resourceId = "skid_wrapper",
        supported = {
            "select_pallet", "start_cycle", "wrapper_service", "machine_relocation",
        },
        roadmapSteps = { "wrapper_maintenance", "machine_relocation" },
        physicalAcceptance = {
            "two_guest_contention", "four_component_service_sequence",
            "host_scored_misses", "exact_once_kit_consumption",
            "production_interlock", "disconnect_and_reacquire",
            "offline_host_save_reload", "all_three_machine_relocations",
            "invalid_and_valid_placement", "relocation_disconnect_recovery",
        },
    },
    windmill = {
        label = "Heidelberg Windmill",
        mode = "candidate",
        resourceId = "windmill",
        supported = {
            "production", "plate_work", "maintenance", "safety_controls",
            "machine_relocation",
        },
        roadmapSteps = { "machine_relocation" },
        physicalAcceptance = {
            "all_three_machine_relocations", "two_guest_contention",
            "invalid_and_valid_placement", "synchronized_live_pose",
            "disconnect_recovery", "offline_host_save_reload",
        },
    },
    palletJack = {
        label = "Pallet jack",
        mode = "candidate",
        resourceId = "pallet_jack",
        supported = {
            "drive", "lift_pallet", "lower_pallet", "park",
            "initiate_machine_relocation", "rotate_machine", "place_machine",
        },
        roadmapSteps = { "machine_relocation" },
        physicalAcceptance = {
            "all_three_machine_relocations", "two_guest_contention",
            "invalid_and_valid_placement", "synchronized_live_pose",
            "disconnect_recovery", "offline_host_save_reload",
        },
    },
}

-- Authority plumbing can precede a selectable world interaction. Keep its
-- policy explicit without advertising unfinished gameplay as an interaction.
Capabilities.RESERVED_RESOURCES = {
    warehouse = {
        label = "Warehouse expansion",
        mode = "planned",
        roadmapStep = "warehouse_integration",
    },
}

Capabilities.ROADMAP = {
    "capability_registry",
    "vendor_purchasing",
    "truck_delivery_pickup",
    "cutter_maintenance",
    "wrapper_maintenance",
    "machine_relocation",
    "guest_experience_ux",
    "lan_discovery_reconnect",
    "warehouse_integration",
    "physical_acceptance",
    "clean_tester_release",
}

function Capabilities.forInteraction(kind)
    return type(kind) == "string" and Capabilities.INTERACTIONS[kind] or nil
end

function Capabilities.requireInteraction(kind)
    local capability = Capabilities.forInteraction(kind)
    assert(capability, "Local Play capability is not declared for interaction: " .. tostring(kind))
    return capability
end

function Capabilities.validate()
    local resourceOwners = {}
    for kind, capability in pairs(Capabilities.INTERACTIONS) do
        if type(kind) ~= "string" or kind == "" then
            return false, "interaction keys must be non-empty strings"
        end
        if type(capability) ~= "table" or type(capability.label) ~= "string"
            or not Capabilities.MODES[capability.mode]
        then
            return false, "invalid capability declaration for " .. tostring(kind)
        end
        if capability.resourceId then
            if resourceOwners[capability.resourceId] then
                return false, "duplicate authority resource " .. capability.resourceId
            end
            resourceOwners[capability.resourceId] = kind
        end
        if capability.mode == "planned" and not capability.roadmapStep then
            return false, kind .. " must name its roadmap step"
        end
        if capability.mode == "mixed"
            and (type(capability.supported) ~= "table" or #capability.supported == 0
                or type(capability.missing) ~= "table" or #capability.missing == 0)
        then
            return false, kind .. " must declare supported and missing facets"
        end
    end
    for resourceId, capability in pairs(Capabilities.RESERVED_RESOURCES) do
        if type(resourceId) ~= "string" or resourceId == "" or resourceOwners[resourceId]
            or type(capability) ~= "table" or type(capability.label) ~= "string"
            or capability.mode ~= "planned" or type(capability.roadmapStep) ~= "string"
            or capability.roadmapStep == ""
        then
            return false, "invalid reserved authority resource " .. tostring(resourceId)
        end
    end
    return true
end

return Capabilities
