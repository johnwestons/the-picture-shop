local Test = {}
local Controller = require("src.controller")

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

    local dismissState = context.State.new()
    dismissState.screen = "vendor"
    local dismissed, dismissSaves = nil, 0
    local dismissContext = {
        state = dismissState,
        world = {
            resolveVendor = function(_, decision)
                dismissed = decision
                return true
            end,
        },
        vendorScreen = context.vendorScreen,
        saveCurrent = function() dismissSaves = dismissSaves + 1 end,
    }
    local dismissX, dismissY = context.vendorScreen.noThanksCenter()
    context.input.mousepressed(dismissX, dismissY, 1, dismissContext)
    check("vendor_no_thanks_dismisses_and_saves", dismissed == "declined"
        and dismissState.screen == "world" and dismissSaves == 1)

    local state = context.State.new()
    local bought, order = context.procurement.buy(state, 1, 1)
    local rows = context.computerScreen.deliveryRows(state)
    local inventory = context.procurement.inventoryRows(state)
    check("domain_office_purchase_order_projection", bought and rows[1] == order
        and context.computerScreen.statusLabel(order.delivery.status) == "Awaiting truck schedule")
    check("domain_office_inventory_projection", #inventory >= 10
        and inventory[1].id == "house_sheets"
        and inventory[4].id == "stretch_film"
        and inventory[5].id == "maintenance_kit"
        and inventory[6].id == "black_ink"
        and inventory[10].id == "raw_press_plates")

    local pressed, released, pointerEvents = {}, {}, {}
    local controllerScreen, controllerMachine = "world", nil
    local controller = Controller.new({
        pressKey = function(key) pressed[#pressed + 1] = key end,
        releaseKey = function(key) released[#released + 1] = key end,
        pressPointer = function(x, y) pointerEvents[#pointerEvents + 1] = { "down", x, y } end,
        releasePointer = function(x, y) pointerEvents[#pointerEvents + 1] = { "up", x, y } end,
        screenInfo = function() return controllerScreen, controllerMachine end,
        worldMenuAction = function() pressed[#pressed + 1] = "menu" end,
    })
    local gamepad = { isGamepad = function() return true end }
    controller:gamepadpressed(gamepad, "a")
    controller:gamepadreleased(gamepad, "a")
    controller:gamepadpressed(gamepad, "y")
    controller:gamepadreleased(gamepad, "y")
    check("controller_world_context_buttons", pressed[1] == "e" and released[1] == "e"
        and pressed[2] == "m" and released[2] == "m")

    controllerScreen, controllerMachine = "machine", "cutter"
    controller:gamepadpressed(gamepad, "leftshoulder")
    controller:gamepadpressed(gamepad, "rightshoulder")
    check("controller_cutter_two_hand_guard", pressed[3] == "j" and pressed[4] == "k")
    controller:gamepadreleased(gamepad, "leftshoulder")
    controller:gamepadreleased(gamepad, "rightshoulder")

    controllerScreen, controllerMachine = "computer", nil
    controller:gamepadpressed(gamepad, "a")
    controller:gamepadreleased(gamepad, "a")
    check("controller_menu_cursor_click", #pointerEvents == 2
        and pointerEvents[1][1] == "down" and pointerEvents[2][1] == "up"
        and pointerEvents[1][2] == pointerEvents[2][2]
        and pointerEvents[1][3] == pointerEvents[2][3])
end

return Test
