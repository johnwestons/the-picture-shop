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
            { id = "black_ink", name = "Black ink, 6 cans", price = 84, quantity = 6, unit = "cans" },
            { id = "press_chemistry", name = "Press chemistry case", price = 68, quantity = 1, unit = "case" },
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
            { id = "maintenance_kit", name = "Machine maintenance kit", price = 145, quantity = 1, unit = "kit" },
            { id = "safety_supplies", name = "Warehouse safety case", price = 110, quantity = 1, unit = "case" },
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
            state.inventory.stock[pallet.productId] = (state.inventory.stock[pallet.productId] or 0) + pallet.quantity
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
