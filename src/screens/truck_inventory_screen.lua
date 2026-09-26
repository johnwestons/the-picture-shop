local Logistics = require("src.pallet_logistics")
local JobService = require("src.job_service")
local MachineFleet = require("src.machine_fleet")
local BackButton = require("src.screens.back_button")
local Config = require("src.config")
local Ui = require("src.screens.ui")

local Screen = {}
local CLOSE = { x = 744, y = 60, width = 140, height = 42 }
local DOOR = { x = 650, y = 570, width = 220, height = 42 }
local PREVIOUS = {x=82,y=410,width=150,height=38}
local NEXT = {x=728,y=410,width=150,height=38}
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

local function manifest(state, snapshot)
    if snapshot.mode == "pickup" then return JobService.pickupInventory(state, snapshot.jobId) end
    if snapshot.mode == "machine_delivery" then return MachineFleet.truckInventory(state, snapshot.jobId) end
    return Logistics.truckInventory(state, snapshot.jobId)
end

local function remainingCargo(state, snapshot)
    if snapshot.mode == "pickup" then return JobService.remainingPickup(state, snapshot.jobId) end
    if snapshot.mode == "machine_delivery" then return MachineFleet.remainingOnTruck(state, snapshot.jobId) end
    return Logistics.remainingOnTruck(state, snapshot.jobId)
end

local function available(item, pickup, machineDelivery)
    if machineDelivery then return item ~= nil end
    if pickup then return item.location == "warehouse" or item.location == "cutter_output" or item.location == "press_output" end
    return item.location == "awaiting_delivery"
end

function Screen.draw(state, world, assets, pointerX, pointerY, remoteView)
    local snapshot = remoteView and {mode=remoteView.mode,state=remoteView.state,jobId=remoteView.manifestId}
        or world.truckSnapshot()
    local pickup = snapshot.mode == "pickup"
    local machineDelivery = snapshot.mode == "machine_delivery"
    local job, inventory = manifest(state, snapshot)
    local totalItems = #inventory
    if remoteView then
        local page={}
        for index,record in ipairs(remoteView.items) do
            local item=inventory[(remoteView.page-1)*3+index]
            page[index]=item or {display=record}
        end
        inventory=page
    end
    local vendorDelivery = snapshot.mode == "vendor_delivery"
    box(52, 42, 856, 592, { 0.045, 0.06, 0.075, 0.99 }, { 0.40, 0.64, 0.70, 1 }, 6)
    love.graphics.setColor(0.96, 0.82, 0.26)
    local title = machineDelivery and "FLATBED / MACHINE DELIVERY"
        or (pickup and "TRUCK CARGO / OUTBOUND PICKUP" or "TRUCK CARGO / INBOUND PALLETS")
    love.graphics.print(title, 82, 68)
    BackButton.draw(assets, CLOSE, "BACK", pointerX, pointerY, false)

    love.graphics.setColor(0.78, 0.85, 0.87)
    if job then
        if machineDelivery then
            love.graphics.print(string.format("%s  •  %s  •  Unit %s", job.id, job.company, job.machineId), 82, 105)
        else
            local source = job.company or job.vendor
                or (vendorDelivery and "Supply shipment" or "Delivery")
            love.graphics.print(string.format("%s  •  %s  •  %d pallet%s", job.id, source,
                totalItems, totalItems == 1 and "" or "s"), 82, 105)
        end
    else
        love.graphics.print(remoteView and (remoteView.manifestId .. "  •  " .. remoteView.title)
            or "No delivery manifest is attached to this truck.", 82, 105)
    end

    for index, item in ipairs(inventory) do
        local row, button = rowRect(index), unloadRect(index)
        local canMove = available(item, pickup, machineDelivery)
        if remoteView then canMove=remoteView.items[index].available end
        box(row.x, row.y, row.width, row.height,
            canMove and { 0.08, 0.12, 0.15, 1 } or { 0.07, 0.16, 0.12, 1 },
            canMove and { 0.25, 0.40, 0.46, 1 } or { 0.25, 0.62, 0.42, 1 }, 4)
        love.graphics.setColor(0.94, 0.96, 0.94)
        if item.display then
            love.graphics.print(item.display.label,row.x+18,row.y+13)
        elseif machineDelivery then
            love.graphics.print(string.format("MACHINE  •  %s", item.id), row.x + 18, row.y + 13)
        else
            love.graphics.print(string.format("PALLET %d  •  %s", item.number, item.id), row.x + 18, row.y + 13)
        end
        love.graphics.setColor(0.70, 0.79, 0.81)
        if item.display then
            love.graphics.print(item.display.detail,row.x+18,row.y+38)
        elseif machineDelivery then
            local model = MachineFleet.definition(item.modelId)
            love.graphics.print(string.format("%s  |  %s %.1f%% condition", model.shortName,
                MachineFleet.conditionStatus(item.condition), item.condition), row.x + 18, row.y + 38)
        elseif pickup then
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
            canMove and { 0.16, 0.42, 0.55, 1 } or { 0.11, 0.25, 0.18, 1 },
            canMove and { 0.48, 0.82, 0.94, 1 } or { 0.25, 0.55, 0.36, 1 }, 3)
        love.graphics.setColor(0.92, 0.96, 0.95)
        local buttonLabel = pickup
            and (canMove and "LOAD" or "ON TRUCK")
            or (canMove and "UNLOAD" or (machineDelivery and "RECEIVED" or "ON FLOOR"))
        love.graphics.printf(buttonLabel, button.x, button.y + 12, button.width, "center")
    end

    local remaining = remainingCargo(state, snapshot)
    if remoteView then remaining=remoteView.remaining end
    local receiving = not machineDelivery and Logistics.receivingStatus(
        state, Config.palletLogistics.spawnPoints) or nil
    local readyState = machineDelivery and snapshot.state == "parked_closed" or snapshot.state == "cargo_open"
    local ready = remaining == 0 and readyState
    if remoteView then ready=remoteView.canClose end
    if remoteView and remoteView.pageCount>1 then
        for _,r in ipairs({PREVIOUS,NEXT}) do
            box(r.x,r.y,r.width,r.height,{0.08,0.12,0.15,1},{0.40,0.64,0.70,1},4)
        end
        love.graphics.setColor(0.94,0.96,0.94)
        love.graphics.printf("< PREVIOUS",PREVIOUS.x,PREVIOUS.y+12,PREVIOUS.width,"center")
        love.graphics.printf("NEXT >",NEXT.x,NEXT.y+12,NEXT.width,"center")
        love.graphics.printf(string.format("PAGE %d / %d",remoteView.page,remoteView.pageCount),300,422,360,"center")
    end
    box(DOOR.x, DOOR.y, DOOR.width, DOOR.height,
        ready and { 0.18, 0.46, 0.30, 1 } or { 0.16, 0.17, 0.18, 1 },
        ready and { 0.48, 0.86, 0.58, 1 } or { 0.35, 0.38, 0.40, 1 }, 4)
    love.graphics.setColor(ready and 0.94 or 0.58, ready and 0.98 or 0.62, ready and 0.94 or 0.64)
    local readyLabel = machineDelivery and "RELEASE FLATBED TRUCK" or "CLOSE CARGO DOOR"
    local remainingLabel = machineDelivery and (remaining .. " MACHINE REMAINS")
        or (remaining .. " PALLET(S) REMAIN")
    love.graphics.printf(ready and readyLabel or remainingLabel,
        DOOR.x, DOOR.y + 14, DOOR.width, "center")
    love.graphics.setColor(0.68, 0.75, 0.77)
    local instruction = machineDelivery
        and "Click Unload to receive this machine, then release the empty flatbed."
        or (pickup and "Click a manifest row to load that wrapped pallet into the customer truck."
            or "Click a manifest row to place that pallet outside the truck.")
    love.graphics.print(instruction, 82, 588)
    if not pickup and not machineDelivery then
        love.graphics.print(string.format("Receiving lanes: %d / %d open", receiving.open, receiving.total), 82, 608)
    end
    if not pickup and not machineDelivery and state.message and state.message:find("Receiving lanes", 1, true) then
        love.graphics.setColor(0.96, 0.48, 0.34)
        love.graphics.printf(state.message, 300, 608, 578, "right")
    end
end

function Screen.mousepressed(state, world, x, y, button)
    if button ~= 1 then return nil end
    if inside(CLOSE, x, y) then return { action = "close" } end
    local snapshot = world.truckSnapshot()
    local pickup = snapshot.mode == "pickup"
    local machineDelivery = snapshot.mode == "machine_delivery"
    local _, inventory = manifest(state, snapshot)
    for index, item in ipairs(inventory) do
        local canMove = available(item, pickup, machineDelivery)
        if inside(unloadRect(index), x, y) and canMove then
            local succeeded, cargo, remaining
            if pickup then
                succeeded, cargo, remaining = world.loadPickupPallet(state, item.id)
            elseif machineDelivery then
                succeeded, cargo, remaining = world.unloadTruckMachine(state, item.id)
            else
                succeeded, cargo, remaining = world.unloadTruckPallet(state, item.id)
            end
            if succeeded then
                return {
                    action = pickup and "loaded" or "unloaded",
                    pallet = not machineDelivery and cargo or nil,
                    machine = machineDelivery and cargo or nil,
                    remaining = remaining,
                }
            end
            return { action = "blocked" }
        end
    end
    if inside(DOOR, x, y) then
        local remaining = remainingCargo(state, snapshot)
        if remaining > 0 then
            state.message = pickup and "Load every pickup pallet before closing the truck cargo door."
                or (machineDelivery and "Unload the machine before releasing the flatbed truck."
                    or "Unload every pallet before closing the truck cargo door.")
            return { action = "blocked" }
        end
        if world.closeTruckAfterUnload(state) then
            return { action = machineDelivery and "truck_departing" or "door_closing" }
        end
    end
    return nil
end

function Screen.remoteIntent(view,x,y)
    if inside(CLOSE,x,y) then return "close" end
    for index,record in ipairs(view.items or {}) do
        if inside(unloadRect(index),x,y) and record.available then return "move_item",{itemIndex=index} end
    end
    if inside(DOOR,x,y) and view.canClose then return "close_truck",{} end
    if view.pageCount>1 then
        if inside(PREVIOUS,x,y) and view.page>1 then return "page_previous",{} end
        if inside(NEXT,x,y) and view.page<view.pageCount then return "page_next",{} end
    end
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
