local Test = {}
local Controller = require("src.controller")
local MobileCamera = require("src.mobile_camera")
local MobileControls = require("src.mobile_controls")

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

    local camera = MobileCamera.new({ enabled = true, baseWidth = 960, baseHeight = 678 })
    camera:setViewport(1469, 678)
    local initial = camera:snapshot()
    local centerWorldX, centerWorldY = camera:screenToWorld(480, 339)
    check("mobile_camera_fills_ultrawide_screen", initial.zoom > 1.52 and initial.zoom < 1.54
        and math.abs(centerWorldX - 480) < 0.001 and math.abs(centerWorldY - 339) < 0.001)
    local anchorX, anchorY = camera:screenToWorld(480, 300)
    camera:beginGesture(480, 300, 200)
    camera:updateGesture(520, 340, 300)
    local heldX, heldY = camera:screenToWorld(520, 340)
    local pinched = camera:snapshot()
    check("mobile_camera_pinch_preserves_finger_anchor", pinched.zoom > initial.zoom
        and math.abs(anchorX - heldX) < 0.001 and math.abs(anchorY - heldY) < 0.001)

    local taps, gestures = {}, { began = 0, updated = 0, ended = 0 }
    local mobile = MobileControls.new({
        enabled = true,
        toGame = function(x, y) return x, y end,
        pressKey = function() end,
        releaseKey = function() end,
        pressPointer = function(x, y) taps[#taps + 1] = { "down", x, y } end,
        movePointer = function() end,
        releasePointer = function(x, y) taps[#taps + 1] = { "up", x, y } end,
        gameplayActive = function() return true end,
        beginGesture = function() gestures.began = gestures.began + 1 end,
        updateGesture = function() gestures.updated = gestures.updated + 1 end,
        endGesture = function() gestures.ended = gestures.ended + 1 end,
    })
    mobile:touchpressed("first", 400, 300)
    mobile:touchpressed("second", 600, 300)
    mobile:touchmoved("second", 700, 340, 100, 40)
    mobile:touchreleased("second", 700, 340)
    mobile:touchreleased("first", 400, 300)
    check("mobile_two_finger_gesture_never_leaks_taps", gestures.began == 1
        and gestures.updated == 1 and gestures.ended == 1 and #taps == 0)
    mobile:touchpressed("tap", 500, 250)
    mobile:touchreleased("tap", 500, 250)
    check("mobile_single_world_tap_stays_clickable", #taps == 2
        and taps[1][1] == "down" and taps[2][1] == "up")
end

return Test
