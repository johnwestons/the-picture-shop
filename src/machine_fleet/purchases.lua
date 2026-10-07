-- Machine pricing, offers, orders, and delivery unloading.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.Fleet.priceFor(modelId, condition, channel)
        local model = Runtime.definition(modelId)
        if not model then return 0 end
        condition = Runtime.clamp(tonumber(condition) or 0, 0, 100)
        -- Both catalogs list used equipment. Condition drives the asking price;
        -- the dealer channel represents a lower-condition unit, not an extra
        -- unexplained discount on top of its condition.
        return Runtime.rounded(model.basePrice * (0.25 + condition / 100 * 0.75))
    end

    function Runtime.Fleet.resaleValue(item, channel)
        local market = Runtime.Fleet.priceFor(item.modelId, Runtime.Fleet.condition(item), "online")
        return Runtime.rounded(market * (channel == "dealer" and 0.48 or 0.62))
    end

    function Runtime.Fleet.offers(channel)
        channel = channel == "dealer" and "dealer" or "online"
        local result = {}
        for index, modelId in ipairs(Runtime.Fleet.order) do
            local model = Runtime.definition(modelId)
            local condition = channel == "dealer" and model.dealerCondition or model.onlineCondition
            result[#result + 1] = {
                id = string.format("%s-%s-%02d", channel:upper(), modelId, index),
                channel = channel,
                modelId = modelId,
                name = model.name,
                condition = condition,
                conditionStatus = Runtime.Fleet.conditionStatus(condition),
                price = Runtime.Fleet.priceFor(modelId, condition, channel),
            }
        end
        return result
    end

    function Runtime.Fleet.pendingDeliveries(state)
        local result = {}
        for _, order in ipairs(Runtime.Fleet.ensure(state).deliveries) do
            if order.delivery.status ~= "received" then result[#result + 1] = order end
        end
        return result
    end

    function Runtime.Fleet.orderById(state, orderId)
        for _, order in ipairs(Runtime.Fleet.ensure(state).deliveries) do
            if order.id == orderId then return order end
        end
    end

    function Runtime.Fleet.nextInbound(state)
        for _, order in ipairs(Runtime.Fleet.ensure(state).deliveries) do
            -- Truck motion is intentionally transient. Any undelivered unit is
            -- schedulable again after loading a save, even if its last saved
            -- manifest state said scheduled/backing/at_bay.
            if order.delivery.status ~= "received" and order.item then return order end
        end
    end

    function Runtime.Fleet.orderOnline(state, offerIndex, payment)
        local offer = Runtime.Fleet.offers("online")[tonumber(offerIndex) or 0]
        if not offer then return false, "That machine listing is no longer available." end
        payment = type(payment) == "table" and payment or {}
        local cashPayment = math.max(0, math.floor(tonumber(payment.cashPayment) or offer.price))
        if cashPayment > offer.price then return false, "Cash payment exceeds the machine price." end
        if cashPayment < offer.price and (type(payment.loanId) ~= "string" or not payment.loanId:match("^CR%-%d+$")) then
            return false, "A machine loan is required for a partial cash payment."
        end
        if (state.money or 0) < cashPayment then return false, "Not enough money for this machine down payment." end
        local fleet = Runtime.Fleet.ensure(state)
        local machineId = string.format("MCH-%04d", fleet.nextId)
        local orderId = string.format("MDO-%04d", fleet.nextDeliveryId)
        fleet.nextId = fleet.nextId + 1
        fleet.nextDeliveryId = fleet.nextDeliveryId + 1
        local item = Runtime.createItem(machineId, offer.modelId, offer.condition, "online", "stored", offer.price)
        local order = {
            id = orderId,
            company = "CritterNet Machine Market",
            machineId = machineId,
            modelId = offer.modelId,
            machineName = offer.name,
            condition = item.condition,
            price = offer.price,
            item = item,
            loanId = payment.loanId,
            delivery = {
                status = "awaiting_delivery",
                orderedAt = os.time(),
                expectedAtHours = Runtime.BusinessCalendar.absoluteHours(state),
            },
        }
        fleet.deliveries[#fleet.deliveries + 1] = order
        state.money = state.money - cashPayment
        local receiptBody = payment.loanId and string.format(
            "Machine price: $%d. Down payment: $%d. Financing agreement %s covers $%d.",
            offer.price, cashPayment, payment.loanId, offer.price - cashPayment)
            or string.format("Order %s total: $%d.", orderId, offer.price)
        Runtime.Inbox.addNotice(state, {
            id = "RECEIPT-" .. orderId,
            sender = "CritterNet Machine Market",
            subject = "Receipt for " .. orderId,
            body = string.format(
                "Order for %s at %.0f%% condition from www.thecritternet.com. %s Keep this email as your receipt. Flatbed delivery will bring unit %s to the shop.",
                offer.name, item.condition, receiptBody, machineId),
            noticeKind = "receipt",
            orderId = orderId,
            total = offer.price,
        })
        return true, order
    end

    function Runtime.Fleet.truckInventory(state, orderId)
        local order = Runtime.Fleet.orderById(state, orderId)
        if not order or order.delivery.status == "received" or not order.item then return order, {} end
        return order, { order.item }
    end

    function Runtime.Fleet.remainingOnTruck(state, orderId)
        local order = Runtime.Fleet.orderById(state, orderId)
        return order and order.delivery.status ~= "received" and order.item and 1 or 0
    end

    function Runtime.Fleet.unloadDelivery(state, orderId, machineId, now)
        local fleet = Runtime.Fleet.ensure(state)
        local order = Runtime.Fleet.orderById(state, orderId)
        if not order or order.delivery.status == "received" or not order.item then
            return false, "That machine is no longer on the flatbed."
        end
        if order.item.id ~= machineId then return false, "That machine is not on this delivery manifest." end
        local item = order.item
        local additional = false
        for _, candidate in ipairs(fleet.items) do
            if candidate.modelId == item.modelId and candidate.status == "installed" then
                additional = true
                break
            end
        end
        if additional and not Runtime.assignFloorPosition(state, fleet, item) then
            return false, "Clear floor space before unloading this machine."
        end
        item.status = "installed"
        fleet.items[#fleet.items + 1] = item
        order.item = nil
        order.delivery.status = "received"
        order.delivery.receivedAt = now or os.time()
        order.delivery.receivedAtHours = Runtime.BusinessCalendar.absoluteHours(state)
        return true, item, 0
    end

    function Runtime.Fleet.buy(state, channel, offerIndex, payment)
        if channel ~= "dealer" then return Runtime.Fleet.orderOnline(state, offerIndex, payment) end
        local offers = Runtime.Fleet.offers(channel)
        local offer = offers[tonumber(offerIndex) or 0]
        if not offer then return false, "That machine listing is no longer available." end
        payment = type(payment) == "table" and payment or {}
        local cashPayment = math.max(0, math.floor(tonumber(payment.cashPayment) or offer.price))
        if cashPayment > offer.price then return false, "Cash payment exceeds the machine price." end
        if cashPayment < offer.price and (type(payment.loanId) ~= "string" or not payment.loanId:match("^CR%-%d+$")) then
            return false, "A machine loan is required for a partial cash payment."
        end
        if (state.money or 0) < cashPayment then return false, "Not enough money for this machine payment." end
        local fleet = Runtime.Fleet.ensure(state)
        local id = string.format("MCH-%04d", fleet.nextId)
        fleet.nextId = fleet.nextId + 1
        local additional = Runtime.Fleet.installed(state, offer.modelId) ~= nil
        local item = Runtime.createItem(id, offer.modelId, offer.condition, offer.channel, "installed", offer.price)
        Runtime.normalizeItem(item)
        if additional and not Runtime.assignFloorPosition(state, fleet, item) then
            fleet.nextId = fleet.nextId - 1
            return false, "Clear floor space before buying another machine."
        end
        fleet.items[#fleet.items + 1] = item
        state.money = state.money - cashPayment
        return true, item
    end
end

return Component
