local Test = {}

local function closeRoute(context, screen, inputKind)
    local closeState = context.State.new()
    closeState.screen = screen
    closeState.machineType = screen == "machine" and "cutter" or nil
    closeState.currentOffer = screen == "job_offer" and { id = "CLOSE-TEST" } or nil
    local result = { customerCancels = 0, vendorCancels = 0, vendorResolves = 0, saves = 0 }
    local closeContext = {
        state = closeState,
        wrapper = { canExit = function() return true end },
        world = {
            cancelCustomerReview = function(testState)
                result.customerCancels = result.customerCancels + 1
                testState.message = "Customer is waiting."
                return true
            end,
            cancelVendorReview = function(testState)
                result.vendorCancels = result.vendorCancels + 1
                testState.message = "Vendor is waiting."
                return true
            end,
            resolveVendor = function() result.vendorResolves = result.vendorResolves + 1 end,
        },
        saveCurrent = function() result.saves = result.saves + 1; return true end,
        jobOfferScreen = context.jobOfferScreen,
        vendorScreen = context.vendorScreen,
        truckInventoryScreen = context.truckInventoryScreen,
        machineScreen = context.machineScreen,
        computerScreen = context.computerScreen,
    }
    if inputKind == "keyboard" then
        context.input.keypressed("escape", closeContext)
    else
        local x, y
        if screen == "job_offer" then x, y = context.jobOfferScreen.buttonCenter("back")
        elseif screen == "vendor" then x, y = context.vendorScreen.closeCenter()
        elseif screen == "truck_inventory" then x, y = context.truckInventoryScreen.closeCenter()
        elseif screen == "machine" then x, y = context.machineScreen.exitCenter()
        else x, y = context.computerScreen.closeCenter() end
        context.input.mousepressed(x, y, 1, closeContext)
    end
    result.screen = closeState.screen
    result.message = closeState.message
    result.offerCleared = closeState.currentOffer == nil
    return result
end

function Test.run(context, check)
    for _, screen in ipairs({ "job_offer", "vendor", "truck_inventory", "machine", "computer" }) do
        local keyboard = closeRoute(context, screen, "keyboard")
        local mouse = closeRoute(context, screen, "mouse")
        check(screen .. "_back_escape_parity",
            keyboard.screen == "world" and mouse.screen == "world"
            and keyboard.message == mouse.message
            and keyboard.customerCancels == mouse.customerCancels
            and keyboard.vendorCancels == mouse.vendorCancels
            and keyboard.vendorResolves == 0 and mouse.vendorResolves == 0
            and keyboard.saves == 1 and mouse.saves == 1
            and keyboard.offerCleared == mouse.offerCleared)
    end

    local state = context.State.new()
    local bought, order = context.procurement.buy(state, 1, 1)
    local rows = context.computerScreen.deliveryRows(state)
    local inventory = context.procurement.inventoryRows(state)
    check("domain_office_purchase_order_projection", bought and rows[1] == order
        and context.computerScreen.statusLabel(order.delivery.status) == "Awaiting truck schedule")
    check("domain_office_inventory_projection", #inventory == 4
        and inventory[1].id == "house_sheets"
        and inventory[4].id == "stretch_film")
end

return Test
