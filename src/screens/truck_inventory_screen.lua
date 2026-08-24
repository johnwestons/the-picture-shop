local Logistics = require("src.pallet_logistics")
local JobService = require("src.job_service")
local BackButton = require("src.screens.back_button")
local Config = require("src.config")
local Ui = require("src.screens.ui")

local Screen = {}
local CLOSE = { x = 744, y = 60, width = 140, height = 42 }
local DOOR = { x = 650, y = 570, width = 220, height = 42 }
local ROW = { x = 82, y = 154, width = 796, height = 66, gap = 10 }

local box, inside = Ui.box, Ui.contains

local function rowRect(index)
    return { x = ROW.x, y = ROW.y + (index - 1) * (ROW.height + ROW.gap), width = ROW.width, height = ROW.height }
end

local function unloadRect(index)
    local row = rowRect(index)
    return { x = row.x + row.width - 146, y = row.y + 14, width = 126, height = 38 }
end

local commaNumber = Ui.commaNumber

function Screen.draw(state, world, assets, pointerX, pointerY)
    local snapshot = world.truckSnapshot()
    local pickup = snapshot.mode == "pickup"
    local job, inventory
    if pickup then
        job, inventory = JobService.pickupInventory(state, snapshot.jobId)
    else
        job, inventory = Logistics.truckInventory(state, snapshot.jobId)
    end
    local vendorDelivery = snapshot.mode == "vendor_delivery"
    box(52, 42, 856, 592, { 0.045, 0.06, 0.075, 0.99 }, { 0.40, 0.64, 0.70, 1 }, 6)
    love.graphics.setColor(0.96, 0.82, 0.26)
    love.graphics.print(pickup and "TRUCK CARGO / OUTBOUND PICKUP" or "TRUCK CARGO / INBOUND PALLETS", 82, 68)
    BackButton.draw(assets, CLOSE, "BACK", pointerX, pointerY, false)

    love.graphics.setColor(0.78, 0.85, 0.87)
    if job then
        love.graphics.print(string.format("%s  •  %s  •  %d pallet%s", job.id, job.company,
            #inventory, #inventory == 1 and "" or "s"), 82, 105)
    else
        love.graphics.print("No delivery manifest is attached to this truck.", 82, 105)
    end

    for index, item in ipairs(inventory) do
        local row, button = rowRect(index), unloadRect(index)
        local available = pickup
            and (item.location == "warehouse" or item.location == "cutter_output")
            or item.location == "awaiting_delivery"
        box(row.x, row.y, row.width, row.height,
            available and { 0.08, 0.12, 0.15, 1 } or { 0.07, 0.16, 0.12, 1 },
            available and { 0.25, 0.40, 0.46, 1 } or { 0.25, 0.62, 0.42, 1 }, 4)
        love.graphics.setColor(0.94, 0.96, 0.94)
        love.graphics.print(string.format("PALLET %d  •  %s", item.number, item.id), row.x + 18, row.y + 13)
        love.graphics.setColor(0.70, 0.79, 0.81)
        if pickup then
            love.graphics.print(string.format("%s finished sheets  |  %s  |  %s",
                commaNumber(item.sheets), tostring(item.pallet.packagedAs or item.pallet.packaging),
                tostring(item.status)), row.x + 18, row.y + 38)
        elseif vendorDelivery then
            love.graphics.print(string.format("%s  |  %s %s", item.productName,
                tostring(item.quantity), item.unit), row.x + 18, row.y + 38)
        else
            local paper = item.paper
            local size = paper and paper.currentSize
            love.graphics.print(string.format("%s sheets  |  Paper %s  |  %.2f x %.2f in",
                commaNumber(item.sheets), paper and paper.id or "unassigned",
                size and size.width or 0, size and size.height or 0), row.x + 18, row.y + 38)
        end
        box(button.x, button.y, button.width, button.height,
            available and { 0.16, 0.42, 0.55, 1 } or { 0.11, 0.25, 0.18, 1 },
            available and { 0.48, 0.82, 0.94, 1 } or { 0.25, 0.55, 0.36, 1 }, 3)
        love.graphics.setColor(0.92, 0.96, 0.95)
        local buttonLabel = pickup
            and (available and "LOAD" or "ON TRUCK")
            or (available and "UNLOAD" or "ON FLOOR")
        love.graphics.printf(buttonLabel, button.x, button.y + 12, button.width, "center")
    end

    local remaining = pickup
        and JobService.remainingPickup(state, snapshot.jobId)
        or Logistics.remainingOnTruck(state, snapshot.jobId)
    local receiving = Logistics.receivingStatus(state, Config.palletLogistics.spawnPoints)
    local ready = remaining == 0 and snapshot.state == "cargo_open"
    box(DOOR.x, DOOR.y, DOOR.width, DOOR.height,
        ready and { 0.18, 0.46, 0.30, 1 } or { 0.16, 0.17, 0.18, 1 },
        ready and { 0.48, 0.86, 0.58, 1 } or { 0.35, 0.38, 0.40, 1 }, 4)
    love.graphics.setColor(ready and 0.94 or 0.58, ready and 0.98 or 0.62, ready and 0.94 or 0.64)
    love.graphics.printf(ready and "CLOSE CARGO DOOR" or (remaining .. " PALLET(S) REMAIN"),
        DOOR.x, DOOR.y + 14, DOOR.width, "center")
    love.graphics.setColor(0.68, 0.75, 0.77)
    love.graphics.print(pickup
        and "Click a manifest row to load that wrapped pallet into the customer truck."
        or "Click a manifest row to place that pallet outside the truck.", 82, 588)
    if not pickup then
        love.graphics.print(string.format("Receiving lanes: %d / %d open", receiving.open, receiving.total), 82, 608)
    end
    if not pickup and state.message and state.message:find("Receiving lanes", 1, true) then
        love.graphics.setColor(0.96, 0.48, 0.34)
        love.graphics.printf(state.message, 300, 608, 578, "right")
    end
end

function Screen.mousepressed(state, world, x, y, button)
    if button ~= 1 then return nil end
    if inside(CLOSE, x, y) then return { action = "close" } end
    local snapshot = world.truckSnapshot()
    local pickup = snapshot.mode == "pickup"
    local _, inventory
    if pickup then
        _, inventory = JobService.pickupInventory(state, snapshot.jobId)
    else
        _, inventory = Logistics.truckInventory(state, snapshot.jobId)
    end
    for index, item in ipairs(inventory) do
        local available = pickup
            and (item.location == "warehouse" or item.location == "cutter_output")
            or item.location == "awaiting_delivery"
        if inside(unloadRect(index), x, y) and available then
            local succeeded, pallet, remaining
            if pickup then
                succeeded, pallet, remaining = world.loadPickupPallet(state, item.id)
            else
                succeeded, pallet, remaining = world.unloadTruckPallet(state, item.id)
            end
            if succeeded then
                return { action = pickup and "loaded" or "unloaded", pallet = pallet, remaining = remaining }
            end
            return { action = "blocked" }
        end
    end
    if inside(DOOR, x, y) then
        local remaining = pickup
            and JobService.remainingPickup(state, snapshot.jobId)
            or Logistics.remainingOnTruck(state, snapshot.jobId)
        if remaining > 0 then
            state.message = pickup
                and "Load every pickup pallet before closing the truck cargo door."
                or "Unload every pallet before closing the truck cargo door."
            return { action = "blocked" }
        end
        if world.closeTruckAfterUnload(state) then return { action = "door_closing" } end
    end
    return nil
end

function Screen.unloadButtonCenter(index)
    local button = unloadRect(index)
    return button.x + button.width / 2, button.y + button.height / 2
end

function Screen.closeDoorCenter()
    return DOOR.x + DOOR.width / 2, DOOR.y + DOOR.height / 2
end

function Screen.closeCenter()
    return CLOSE.x + CLOSE.width / 2, CLOSE.y + CLOSE.height / 2
end

return Screen
