local Procurement = {}
local PalletState = require("src.pallet_state")
local Receiving = require("src.receiving")
local Config = require("src.config")
local BusinessCalendar = require("src.business_calendar")

local GROUP_WINDOW_HOURS = 1
local DELIVERY_DELAY_HOURS = 4

Procurement.categories = {
    {
        id = "paper", name = "PAPER & BOARD", salesman = "Milo Stockwell", character = "tan-cat", assetRow = 1,
        items = {
            { id = "house_sheets", name = "House paper, 1,000 sheets", price = 90, quantity = 1000, unit = "sheets",
                retailName = "House paper, 250 sheets", retailPrice = 28, retailQuantity = 250 },
            { id = "cover_stock", name = "Cover stock, 500 sheets", price = 125, quantity = 500, unit = "sheets",
                retailName = "Cover stock, 100 sheets", retailPrice = 30, retailQuantity = 100 },
        },
    },
    {
        id = "press", name = "PRESS SUPPLIES", salesman = "Iris Inkwell", character = "blue-coaler-cat", assetRow = 2,
        items = {
            { id = "black_ink", name = "Black ink, four 2.2 lb cans", price = 168, quantity = 140, unit = "oz",
                retailName = "Black ink, 2.2 lb can", retailPrice = 46, retailQuantity = 35 },
            { id = "color_ink", name = "Spot-color ink, four cans", price = 296, quantity = 140, unit = "oz",
                retailName = "Spot-color ink, 1 can", retailPrice = 82, retailQuantity = 35 },
            { id = "press_wash", name = "Compatible press wash case", price = 118, quantity = 24, unit = "cleanups",
                retailName = "Compatible press wash", retailPrice = 34, retailQuantity = 6 },
            { id = "tympan_sheets", name = "Windmill tympan, 50 sheets", price = 45, quantity = 50, unit = "sheets",
                retailName = "Windmill tympan, 10 sheets", retailPrice = 10, retailQuantity = 10 },
            { id = "plate_room_kit", name = "In-house plate materials, 10 jobs", price = 290, quantity = 10, unit = "kits",
                retailName = "In-house plate materials", retailPrice = 34, retailQuantity = 1 },
        },
    },
    {
        id = "packaging", name = "PACKAGING", salesman = "Cora Carton", character = "green-blazer-cat", assetRow = 3,
        items = {
            { id = "shipping_cartons", name = "Shipping cartons, 100", price = 72, quantity = 100, unit = "cartons",
                retailName = "Shipping cartons, 20", retailPrice = 20, retailQuantity = 20 },
            { id = "stretch_film", name = "Stretch film, 12 rolls", price = 96, quantity = 12, unit = "rolls",
                retailName = "Stretch film, 2 rolls", retailPrice = 20, retailQuantity = 2 },
        },
    },
    {
        id = "equipment", name = "TOOLS & MAINTENANCE", salesman = "Otis Wrench", character = "tan-cat", assetRow = 4,
        items = {
            { id = "maintenance_kit", name = "Machine maintenance kit", price = 145, quantity = 1, unit = "kit",
                retailName = "Machine maintenance kit", retailPrice = 175, retailQuantity = 1 },
            { id = "safety_supplies", name = "Warehouse safety case", price = 110, quantity = 1, unit = "case",
                retailName = "Warehouse safety case", retailPrice = 135, retailQuantity = 1,
                available = false, unavailableReason = "Requires the warehouse safety upgrade." },
        },
    },
    {
        id = "machines", name = "USED MACHINERY", salesman = "Rufus Gearbox",
        character = "blue-coaler-cat", kind = "machines", items = {},
    },
}

local function ensure(state)
    state.procurement = type(state.procurement) == "table" and state.procurement or {}
    state.procurement.orders = type(state.procurement.orders) == "table" and state.procurement.orders or {}
    state.procurement.nextOrderId = tonumber(state.procurement.nextOrderId) or 1
    state.procurement.shipments = type(state.procurement.shipments) == "table" and state.procurement.shipments or {}
    state.procurement.nextShipmentId = tonumber(state.procurement.nextShipmentId) or 1
    -- Migrate older one-order/one-truck saves into explicit grouped shipments.
    for _, order in ipairs(state.procurement.orders) do
        if not order.shipmentId then
            local shipmentNumber = state.procurement.nextShipmentId
            state.procurement.nextShipmentId = shipmentNumber + 1
            local shipmentId = string.format("SHIP-%04d", shipmentNumber)
            order.shipmentId = shipmentId
            local delivery = order.delivery or {}
            state.procurement.shipments[#state.procurement.shipments + 1] = {
                id = shipmentId, orderIds = { order.id }, status = order.status or "awaiting_delivery",
                openedAtHours = delivery.expectedAtHours or BusinessCalendar.absoluteHours(state),
                closesAtHours = delivery.expectedAtHours or BusinessCalendar.absoluteHours(state),
                delivery = {
                    status = delivery.status or "awaiting_schedule",
                    expectedAtHours = delivery.expectedAtHours or BusinessCalendar.absoluteHours(state),
                    receivedAt = delivery.receivedAt, receivedAtHours = delivery.receivedAtHours,
                },
            }
        end
    end
    state.inventory.stock = type(state.inventory.stock) == "table" and state.inventory.stock or {}
    return state.procurement
end

function Procurement.ensure(state) return ensure(state) end

function Procurement.category(index)
    return Procurement.categories[((tonumber(index) or 1) - 1) % #Procurement.categories + 1]
end

function Procurement.buy(state, categoryIndex, itemIndex, channel)
    local procurement = ensure(state)
    local category = Procurement.category(categoryIndex)
    local item = category.items[tonumber(itemIndex) or 0]
    if not item then return false, "That product is not in this sales catalog." end
    if item.available == false then return false, item.unavailableReason or "That product is not available yet." end
    channel = channel == "computer" and "computer" or "salesman"
    local price = channel == "computer" and item.retailPrice or item.price
    local quantity = channel == "computer" and item.retailQuantity or item.quantity
    local productName = channel == "computer" and item.retailName or item.name
    if not price or not quantity then return false, "That product is not offered through this sales channel." end
    if (state.money or 0) < price then return false, "Not enough money for this purchase." end
    local number = procurement.nextOrderId
    procurement.nextOrderId = number + 1
    local id = string.format("PO-%04d", number)
    local now = BusinessCalendar.absoluteHours(state)
    local shipment
    for index = #procurement.shipments, 1, -1 do
        local candidate = procurement.shipments[index]
        if candidate.status == "awaiting_delivery"
            and candidate.delivery and candidate.delivery.status == "awaiting_schedule"
            and now <= (candidate.closesAtHours or -1)
        then shipment = candidate; break end
    end
    if not shipment then
        local shipmentNumber = procurement.nextShipmentId
        procurement.nextShipmentId = shipmentNumber + 1
        shipment = {
            id = string.format("SHIP-%04d", shipmentNumber), orderIds = {},
            status = "awaiting_delivery", openedAtHours = now,
            closesAtHours = now + GROUP_WINDOW_HOURS,
            delivery = { status = "awaiting_schedule", expectedAtHours = now + DELIVERY_DELAY_HOURS },
        }
        procurement.shipments[#procurement.shipments + 1] = shipment
    end
    local pallet = {
        id = id .. "-PALLET", number = 1, kind = "vendor_product",
        category = category.id, categoryName = category.name, assetRow = category.assetRow,
        productId = item.id, productName = productName, quantity = quantity, unit = item.unit,
        location = "awaiting_delivery", status = "purchased",
    }
    local order = {
        id = id, vendor = channel == "computer" and "Office Supply Catalog" or category.salesman,
        company = channel == "computer" and "OFFICE SUPPLY DELIVERY" or category.name,
        category = category.id, item = item.id, productName = productName, channel = channel,
        price = price, status = "awaiting_delivery", orderedAt = os.time(), shipmentId = shipment.id,
        delivery = {
            status = "awaiting_schedule",
            expectedAtHours = shipment.delivery.expectedAtHours,
        }, pallets = { pallet },
    }
    procurement.orders[#procurement.orders + 1] = order
    shipment.orderIds[#shipment.orderIds + 1] = order.id
    state.money = state.money - price
    return true, order
end

function Procurement.retailCatalog()
    local result = {}
    for categoryIndex, category in ipairs(Procurement.categories) do
        for itemIndex, item in ipairs(category.items) do
            result[#result + 1] = {
                categoryIndex = categoryIndex, itemIndex = itemIndex,
                category = category, item = item,
                available = item.available ~= false and item.retailPrice ~= nil,
            }
        end
    end
    return result
end

function Procurement.buyRetail(state, categoryIndex, itemIndex)
    return Procurement.buy(state, categoryIndex, itemIndex, "computer")
end

local paperProducts = { "house_sheets", "cover_stock" }

function Procurement.paperAvailable(state)
    ensure(state)
    local available = math.max(0, state.inventory.paper or 0)
    for _, productId in ipairs(paperProducts) do
        available = available + math.max(0, state.inventory.stock[productId] or 0)
    end
    return available
end

function Procurement.consumePaper(state, quantity)
    ensure(state)
    local remaining = math.max(0, math.floor(quantity or 1))
    if remaining == 0 then return true end
    if Procurement.paperAvailable(state) < remaining then return false, "Not enough production paper." end
    for _, productId in ipairs(paperProducts) do
        local available = math.max(0, state.inventory.stock[productId] or 0)
        local used = math.min(available, remaining)
        state.inventory.stock[productId] = available - used
        remaining = remaining - used
        if remaining == 0 then return true end
    end
    state.inventory.paper = math.max(0, (state.inventory.paper or 0) - remaining)
    return true
end

function Procurement.cartonsAvailable(state)
    ensure(state)
    return math.max(0, state.inventory.stock.shipping_cartons or 0)
end

function Procurement.consumeCartons(state, quantity)
    ensure(state)
    local needed = math.max(0, math.floor(quantity or 1))
    local available = Procurement.cartonsAvailable(state)
    if available < needed then return false, "Not enough shipping cartons." end
    state.inventory.stock.shipping_cartons = available - needed
    return true
end

function Procurement.inventoryRows(state)
    ensure(state)
    return {
        { id = "house_sheets", label = "House paper", quantity = state.inventory.stock.house_sheets or 0, unit = "sheets" },
        { id = "cover_stock", label = "Cover stock", quantity = state.inventory.stock.cover_stock or 0, unit = "sheets" },
        { id = "shipping_cartons", label = "Shipping cartons", quantity = state.inventory.stock.shipping_cartons or 0, unit = "cartons" },
        { id = "stretch_film", label = "Stretch film", quantity = state.inventory.plasticWrapRolls or 0, unit = "rolls" },
        { id = "maintenance_kit", label = "Maintenance kits", quantity = state.inventory.stock.maintenance_kit or 0, unit = "kits" },
        { id = "black_ink", label = "Black letterpress ink", quantity = state.inventory.stock.black_ink or 0, unit = "oz" },
        { id = "color_ink", label = "Spot-color ink", quantity = state.inventory.stock.color_ink or 0, unit = "oz" },
        { id = "press_wash", label = "Press wash", quantity = state.inventory.stock.press_wash or 0, unit = "cleanups" },
        { id = "tympan_sheets", label = "Windmill tympan", quantity = state.inventory.stock.tympan_sheets or 0, unit = "sheets" },
        { id = "raw_press_plates", label = "Raw photopolymer plates", quantity = state.inventory.stock.raw_press_plates or 0, unit = "plates" },
    }
end

function Procurement.orderById(state, orderId)
    local procurement = ensure(state)
    for _, shipment in ipairs(procurement.shipments) do if shipment.id == orderId then return shipment end end
    for _, order in ipairs(procurement.orders) do if order.id == orderId then return order end end
end

function Procurement.nextInbound(state)
    local now = BusinessCalendar.absoluteHours(state)
    for _, shipment in ipairs(ensure(state).shipments) do
        if shipment.status == "awaiting_delivery" and shipment.delivery.status == "awaiting_schedule"
            and now >= (shipment.delivery.expectedAtHours or math.huge)
        then return shipment end
    end
end

local function shipmentOrders(procurement, manifest)
    if not manifest then return {} end
    if manifest.pallets then return { manifest } end
    local wanted, result = {}, {}
    for _, id in ipairs(manifest.orderIds or {}) do wanted[id] = true end
    for _, order in ipairs(procurement.orders) do
        if wanted[order.id] then result[#result + 1] = order end
    end
    return result
end

function Procurement.truckInventory(state, orderId)
    local procurement = ensure(state)
    local order = Procurement.orderById(state, orderId)
    local inventory = {}
    for _, purchase in ipairs(shipmentOrders(procurement, order)) do
        for _, pallet in ipairs(purchase.pallets or {}) do
            inventory[#inventory + 1] = {
                id = pallet.id, number = pallet.number, location = pallet.location,
                status = pallet.status, pallet = pallet, productName = pallet.productName,
                quantity = pallet.quantity, unit = pallet.unit, vendorProduct = true,
                purchaseOrderId = purchase.id,
            }
        end
    end
    return order, inventory
end

function Procurement.remainingOnTruck(state, orderId)
    local _, inventory = Procurement.truckInventory(state, orderId)
    local count = 0
    for _, item in ipairs(inventory) do if item.location == "awaiting_delivery" then count = count + 1 end end
    return count
end

function Procurement.unload(state, orderId, palletId, spawnPoints, origin)
    local procurement = ensure(state)
    local manifest = Procurement.orderById(state, orderId)
    if not manifest then return false, "The purchase order is no longer available." end
    local deliveryManifest = manifest
    if manifest.pallets and manifest.shipmentId then
        for _, shipment in ipairs(procurement.shipments) do
            if shipment.id == manifest.shipmentId then deliveryManifest = shipment; break end
        end
    end
    for _, order in ipairs(shipmentOrders(procurement, manifest)) do
      for _, pallet in ipairs(order.pallets or {}) do
        if pallet.id == palletId then
            if pallet.location ~= "awaiting_delivery" then return false, "That product pallet is already unloaded." end
            local point, laneError = Receiving.claim(
                state, spawnPoints, Config.palletLogistics.receivingLaneRadius, pallet.id)
            if not point then return false, laneError end
            local world = { x = point.x, y = point.y, direction = "northwest", rotation = 1,
                fromX = origin and origin.x or point.x, fromY = origin and origin.y or point.y, spawnProgress = 0 }
            local transitioned, transitionError = PalletState.transition(state, pallet, "warehouse", {
                status = "stocked",
                world = world,
            })
            if not transitioned then return false, transitionError end
            if pallet.productId == "stretch_film" then
                local inventory = state.inventory
                inventory.plasticWrapRolls = (inventory.plasticWrapRolls or 0) + pallet.quantity
                if (inventory.plasticWrapUses or 0) == 0 and inventory.plasticWrapRolls > 0 then
                    inventory.plasticWrapUses = 11
                end
            elseif pallet.productId == "plate_room_kit" then
                for _, id in ipairs({ "raw_press_plates", "negative_film", "plate_adhesive", "plate_chemistry" }) do
                    state.inventory.stock[id] = (state.inventory.stock[id] or 0) + pallet.quantity
                end
            else
                state.inventory.stock[pallet.productId] =
                    (state.inventory.stock[pallet.productId] or 0) + pallet.quantity
            end
            order.status = "received"
            order.delivery.status, order.delivery.receivedAt = "received", os.time()
            order.delivery.receivedAtHours = BusinessCalendar.absoluteHours(state)
            local remaining = Procurement.remainingOnTruck(state, deliveryManifest.id)
            if remaining == 0 then
                deliveryManifest.status = "received"
                deliveryManifest.delivery.status, deliveryManifest.delivery.receivedAt = "received", os.time()
                deliveryManifest.delivery.receivedAtHours = BusinessCalendar.absoluteHours(state)
            else
                deliveryManifest.delivery.status = "unloading"
            end
            return true, pallet, remaining
        end
      end
    end
    return false, "The product pallet was not found on this truck."
end

function Procurement.consumePhysicalProduct(state, productId, quantity)
    local needed = math.max(0, math.floor(quantity or 1))
    if needed == 0 then return true end
    for _, order in ipairs(ensure(state).orders) do
        for _, pallet in ipairs(order.pallets or {}) do
            if pallet.productId == productId and pallet.location == "warehouse" then
                pallet.remainingQuantity = tonumber(pallet.remainingQuantity) or tonumber(pallet.quantity) or 0
                local used = math.min(needed, pallet.remainingQuantity)
                pallet.remainingQuantity = pallet.remainingQuantity - used
                needed = needed - used
                if pallet.remainingQuantity <= 0 then
                    PalletState.transition(state, pallet, "none", { status = "consumed", world = false })
                    pallet.world = nil
                end
                if needed == 0 then return true end
            end
        end
    end
    return needed == 0
end

function Procurement.physicalPallets(state)
    local result = {}
    for _, order in ipairs(ensure(state).orders) do
        for _, pallet in ipairs(order.pallets or {}) do
            if pallet.world and pallet.location == "warehouse" then
                local progress = pallet.world.spawnProgress or 1
                local fromX, fromY = pallet.world.fromX or pallet.world.x, pallet.world.fromY or pallet.world.y
                result[#result + 1] = { job = order, pallet = pallet, vendor = true,
                    x = fromX + (pallet.world.x - fromX) * progress,
                    y = fromY + (pallet.world.y - fromY) * progress }
            end
        end
    end
    return result
end

return Procurement
