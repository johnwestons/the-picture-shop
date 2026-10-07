-- Supplier shopping and cart checkout.
-- Runtime is private to this screen instance; shared state remains live across components.
local Component = {}

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

    function Runtime.retailBuyRect(index)
        local row = Runtime.wwwProductRect(index)
        return { x = row.x + row.width - 122, y = row.y + 6, width = 108, height = row.height - 12 }
    end

    function Runtime.cartTotal()
        local total, count = 0, 0
        for _, entry in ipairs(Runtime.ComputerScreen.cart or {}) do
            local quantity = math.max(1, math.floor(tonumber(entry.quantity) or 1))
            total = total + (tonumber(entry.price) or 0) * quantity
            count = count + quantity
        end
        return total, count
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

    function Runtime.checkoutCart(state)
        local total, count = Runtime.cartTotal()
        if count == 0 then return false, "Your online cart is empty." end
        if (state.money or 0) < total then return false, "Not enough money to check out this cart." end
        for _, entry in ipairs(Runtime.ComputerScreen.cart) do
            if entry.kind == "supply" then
                local category = Runtime.Procurement.categories[entry.categoryIndex]
                local item = category and category.items[entry.itemIndex]
                if not item or item.available == false or item.retailPrice ~= entry.price then
                    return false, "A supply item in the cart is no longer available."
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
                    succeeded, result = Runtime.Procurement.buyRetail(state, entry.categoryIndex, entry.itemIndex)
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

    function Runtime.ComputerScreen.checkout(state, entries)
        Runtime.ComputerScreen.cart = entries
        return Runtime.checkoutCart(state)
    end
end

return Component
