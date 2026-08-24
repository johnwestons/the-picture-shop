local Procurement = {}
local PalletState = require("src.pallet_state")
local Receiving = require("src.receiving")
local Config = require("src.config")

Procurement.categories = {
    {
        id = "paper", name = "PAPER & BOARD", salesman = "Milo Stockwell", character = "tan-cat", assetRow = 1,
        items = {
            { id = "house_sheets", name = "House paper, 1,000 sheets", price = 90, quantity = 1000, unit = "sheets" },
            { id = "cover_stock", name = "Cover stock, 500 sheets", price = 125, quantity = 500, unit = "sheets" },
        },
    },
    {
        id = "press", name = "PRESS SUPPLIES", salesman = "Iris Inkwell", character = "blue-coaler-cat", assetRow = 2,
        items = {
            { id = "black_ink", name = "Black ink, 6 cans", price = 84, quantity = 6, unit = "cans",
                available = false, unavailableReason = "Available when the picture press enters production." },
            { id = "press_chemistry", name = "Press chemistry case", price = 68, quantity = 1, unit = "case",
                available = false, unavailableReason = "Available when the picture press enters production." },
        },
    },
    {
        id = "packaging", name = "PACKAGING", salesman = "Cora Carton", character = "green-blazer-cat", assetRow = 3,
        items = {
            { id = "shipping_cartons", name = "Shipping cartons, 100", price = 72, quantity = 100, unit = "cartons" },
            { id = "stretch_film", name = "Stretch film, 12 rolls", price = 96, quantity = 12, unit = "rolls" },
        },
    },
    {
        id = "equipment", name = "TOOLS & MAINTENANCE", salesman = "Otis Wrench", character = "tan-cat", assetRow = 4,
        items = {
            { id = "maintenance_kit", name = "Machine maintenance kit", price = 145, quantity = 1, unit = "kit",
                available = false, unavailableReason = "Available when machine maintenance is implemented." },
            { id = "safety_supplies", name = "Warehouse safety case", price = 110, quantity = 1, unit = "case",
                available = false, unavailableReason = "Available when safety supplies have a consumer." },
        },
    },
}

local function ensure(state)
    state.procurement = type(state.procurement) == "table" and state.procurement or {}
    state.procurement.orders = type(state.procurement.orders) == "table" and state.procurement.orders or {}
    state.procurement.nextOrderId = tonumber(state.procurement.nextOrderId) or 1
    state.inventory.stock = type(state.inventory.stock) == "table" and state.inventory.stock or {}
    return state.procurement
end

function Procurement.ensure(state) return ensure(state) end

function Procurement.category(index)
    return Procurement.categories[((tonumber(index) or 1) - 1) % #Procurement.categories + 1]
end

function Procurement.buy(state, categoryIndex, itemIndex)
    local procurement = ensure(state)
    local category = Procurement.category(categoryIndex)
    local item = category.items[tonumber(itemIndex) or 0]
    if not item then return false, "That product is not in this sales catalog." end
    if item.available == false then return false, item.unavailableReason or "That product is not available yet." end
    if (state.money or 0) < item.price then return false, "Not enough money for this purchase." end
    local number = procurement.nextOrderId
    procurement.nextOrderId = number + 1
    local id = string.format("PO-%04d", number)
    local pallet = {
        id = id .. "-PALLET", number = 1, kind = "vendor_product",
        category = category.id, categoryName = category.name, assetRow = category.assetRow,
        productId = item.id, productName = item.name, quantity = item.quantity, unit = item.unit,
        location = "awaiting_delivery", status = "purchased",
    }
    local order = {
        id = id, vendor = category.salesman, company = category.name,
        category = category.id, item = item.id, productName = item.name,
        price = item.price, status = "awaiting_delivery", orderedAt = os.time(),
        delivery = { status = "awaiting_schedule" }, pallets = { pallet },
    }
    procurement.orders[#procurement.orders + 1] = order
    state.money = state.money - item.price
    return true, order
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
    }
end

function Procurement.orderById(state, orderId)
    for _, order in ipairs(ensure(state).orders) do if order.id == orderId then return order end end
end

function Procurement.nextInbound(state)
    for _, order in ipairs(ensure(state).orders) do
        if order.status == "awaiting_delivery" and order.delivery.status ~= "received" then return order end
    end
end

function Procurement.truckInventory(state, orderId)
    local order = Procurement.orderById(state, orderId)
    local inventory = {}
    for _, pallet in ipairs(order and order.pallets or {}) do
        inventory[#inventory + 1] = {
            id = pallet.id, number = pallet.number, location = pallet.location,
            status = pallet.status, pallet = pallet, productName = pallet.productName,
            quantity = pallet.quantity, unit = pallet.unit, vendorProduct = true,
        }
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
    local order = Procurement.orderById(state, orderId)
    if not order then return false, "The purchase order is no longer available." end
    for index, pallet in ipairs(order.pallets) do
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
            else
                state.inventory.stock[pallet.productId] =
                    (state.inventory.stock[pallet.productId] or 0) + pallet.quantity
            end
            order.status = "received"
            order.delivery.status, order.delivery.receivedAt = "received", os.time()
            return true, pallet, 0
        end
    end
    return false, "The product pallet was not found on this truck."
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
