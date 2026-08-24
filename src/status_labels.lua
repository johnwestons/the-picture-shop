local StatusLabels = {}

local LABELS = {
    offered = "Offer",
    awaiting_delivery = "Awaiting inbound delivery",
    awaiting_schedule = "Awaiting truck schedule",
    scheduled = "Truck scheduled",
    arriving = "Truck en route",
    at_bay = "Truck at loading bay",
    cargo_open = "Cargo open",
    unloading = "Unloading",
    received = "Received",
    delivered = "Delivered",
    in_production = "In production",
    cutting = "Cutting in progress",
    ready_for_pickup = "Ready for pickup",
    pickup_in_progress = "Pickup in progress",
    loaded = "Loaded for pickup",
    departing = "Truck departing",
    completed = "Completed and paid",
    declined = "Declined",
    purchased = "Purchased",
    stocked = "Stocked",
    raw = "Raw paper",
    in_process = "In process",
    cut = "Cut",
    wrapped = "Wrapped",
    picked_up = "Picked up",
    cancelled = "Cancelled",
    warehouse = "Warehouse floor",
    on_pallet_jack = "On pallet jack",
    at_cutter = "At cutter",
    cutter_output = "Cutter output",
    truck = "On truck",
    none = "Not in shop",
}

function StatusLabels.get(status)
    return LABELS[status] or tostring(status or "Unknown")
end

return StatusLabels
