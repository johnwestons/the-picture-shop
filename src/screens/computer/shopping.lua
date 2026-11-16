-- Supplier shopping and cart checkout.
-- Runtime is private to this screen instance; shared state remains live across components.
local Component = {}
local DeliveryService=require("src.delivery_service")

function Component.install(Runtime)
    function Runtime.wwwSiteRect(index)
        return { x = Runtime.WWW_SITE.x + (index - 1) * (Runtime.WWW_SITE.width + Runtime.WWW_SITE.gap), y = Runtime.WWW_SITE.y,
            width = Runtime.WWW_SITE.width, height = Runtime.WWW_SITE.height }
    end

    function Runtime.wwwProductRect(index)
        return { x = Runtime.WWW_PRODUCT.x,
            y = Runtime.WWW_PRODUCT.y + (index - 1) * (Runtime.WWW_PRODUCT.rowHeight + Runtime.WWW_PRODUCT.gap),
            width = Runtime.WWW_PRODUCT.width, height = Runtime.WWW_PRODUCT.rowHeight }
    end

    function Runtime.cartContainsPaper()
        for _,entry in ipairs(Runtime.ComputerScreen.cart or {}) do
            local category=entry.kind=="supply" and Runtime.Procurement.categories[entry.categoryIndex]
            if category and category.id=="paper" then return true end
        end
        return false
    end

    function Runtime.cartShippingCents(deliveryService)
        local service=DeliveryService.normalize(deliveryService,
            Runtime.ComputerScreen.deliveryService or DeliveryService.SAME_DAY)
        if not service then return nil end
        local cents=0
        for _,entry in ipairs(Runtime.ComputerScreen.cart or {}) do
            if entry.kind=="supply" then
                local fee=Runtime.Procurement.paperShippingFeeCents(entry.categoryIndex,entry.itemIndex,
                    "computer",service)
                if fee==nil then return nil end
                cents=cents+fee*(tonumber(entry.quantity) or 1)
            end
        end
        return cents
    end

    function Runtime.retailBuyRect(index)
        local row = Runtime.wwwProductRect(index)
        return { x = row.x + row.width - 122, y = row.y + 6, width = 108, height = row.height - 12 }
    end

    function Runtime.cartTotal(deliveryService)
        local total, count = 0, 0
        for _, entry in ipairs(Runtime.ComputerScreen.cart or {}) do
            local quantity = math.max(1, math.floor(tonumber(entry.quantity) or 1))
            total = total + (tonumber(entry.price) or 0) * quantity
            count = count + quantity
        end
        local shipping=Runtime.cartShippingCents(deliveryService)
        if shipping==nil then return math.huge,count end
        return total+shipping/100, count
    end

    function Runtime.addToCart(entry)
        Runtime.ComputerScreen.cart = type(Runtime.ComputerScreen.cart) == "table" and Runtime.ComputerScreen.cart or {}
        for _, current in ipairs(Runtime.ComputerScreen.cart) do
            if current.key == entry.key then
                current.quantity = (current.quantity or 1) + 1
                return current
            end
        end
        entry.quantity = 1
        Runtime.ComputerScreen.cart[#Runtime.ComputerScreen.cart + 1] = entry
        return entry
    end

    function Runtime.cartRemoveRect(visibleIndex)
        return { x = 724, y = 248 + (visibleIndex - 1) * 40, width = 82, height = 32 }
    end

    function Runtime.checkoutCart(state,deliveryService)
        deliveryService=DeliveryService.normalize(deliveryService,
            Runtime.ComputerScreen.deliveryService or DeliveryService.SAME_DAY)
        if not deliveryService then return false,"Choose same-day or three-day paper delivery." end
        local total, count = Runtime.cartTotal(deliveryService)
        if count == 0 then return false, "Your online cart is empty." end
        if (state.money or 0) < total then return false, "Not enough money to check out this cart." end
        for _, entry in ipairs(Runtime.ComputerScreen.cart) do
            if entry.kind == "supply" then
                local category = Runtime.Procurement.categories[entry.categoryIndex]
                local item = category and category.items[entry.itemIndex]
                local currentPrice = item and Runtime.Procurement.retailPrice(state, entry.categoryIndex, entry.itemIndex)
                if not item or item.available == false or currentPrice ~= entry.price then
                    return false, "A product's availability or sale price changed. Review the cart and try again."
                end
            elseif entry.kind == "machine" then
                local offer = Runtime.MachineFleet.offers("online")[entry.offerIndex]
                if not offer or offer.price ~= entry.price or offer.modelId ~= entry.modelId then
                    return false, "A machine listing in the cart has changed."
                end
            else
                return false, "The cart contains an unknown item."
            end
        end
        local orders = {}
        for _, entry in ipairs(Runtime.ComputerScreen.cart) do
            for _ = 1, entry.quantity do
                local succeeded, result
                if entry.kind == "supply" then
                    succeeded, result = Runtime.Procurement.buyRetail(state, entry.categoryIndex, entry.itemIndex,
                        Runtime.Procurement.categories[entry.categoryIndex].id=="paper" and deliveryService or nil)
                else
                    succeeded, result = Runtime.MachineFleet.orderOnline(state, entry.offerIndex)
                end
                if not succeeded then return false, tostring(result) end
                orders[#orders + 1] = result
            end
        end
        Runtime.ComputerScreen.cart, Runtime.ComputerScreen.cartOpen, Runtime.ComputerScreen.cartPage = {}, false, 1
        return true, { orders = orders, total = total, count = count }
    end

    function Runtime.ComputerScreen.checkout(state, entries,deliveryService)
        Runtime.ComputerScreen.cart = entries
        return Runtime.checkoutCart(state,deliveryService)
    end
end

return Component
