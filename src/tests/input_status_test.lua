local Test = {}
local Controller = require("src.controller")
local MobileCamera = require("src.mobile_camera")
local MobileControls = require("src.mobile_controls")
local PlacementGrid = require("src.placement_grid")

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
    local gridCells = PlacementGrid.cells(96, 96, {
        cellWidth = 32, cellHeight = 24, previewRadius = 1, selectionRadius = 50,
    }, function(x) return x >= 96 end)
    local greenCell = PlacementGrid.hit(gridCells, 128, 96, {
        cellWidth = 32, cellHeight = 24,
    })
    local redCell = PlacementGrid.hit(gridCells, 64, 96, {
        cellWidth = 32, cellHeight = 24,
    })
    check("warehouse_placement_grid_marks_and_hits_valid_cells",
        greenCell and greenCell.valid and redCell and not redCell.valid)

    context.jobOfferScreen.enter({ id = "KEYBOARD-FOCUS", quote = { totalPrice = 1250 } })
    check("counter_job_review_never_requests_quote_keyboard",
        not context.jobOfferScreen.wantsTextInput())

    local keyboardState = context.State.new()
    context.machineScreen.enter()
    check("cutter_screen_does_not_request_keyboard_on_open",
        not context.machineScreen.wantsTextInput())
    local gaugeX, gaugeY = context.machineScreen.gaugeInputCenter()
    context.machineScreen.mousepressed(keyboardState, gaugeX, gaugeY, 1)
    check("cutter_screen_requests_keyboard_after_field_tap",
        context.machineScreen.wantsTextInput())
    context.machineScreen.mousepressed(keyboardState, 10, 10, 1)
    check("cutter_screen_releases_keyboard_after_outside_tap",
        not context.machineScreen.wantsTextInput())

    context.computerScreen.enter(keyboardState)
    context.computerScreen.tab = "email"
    context.computerScreen.promoJobId = "PROMO-FOCUS"
    check("promotion_composer_does_not_request_keyboard_on_open",
        not context.computerScreen.wantsTextInput())
    local promoX, promoY = context.computerScreen.textInputCenter("promotion")
    context.computerScreen.mousepressed(keyboardState, promoX, promoY, 1)
    check("promotion_composer_requests_keyboard_after_field_tap",
        context.computerScreen.wantsTextInput())
    context.computerScreen.mousepressed(keyboardState, 10, 10, 1)
    check("promotion_composer_releases_keyboard_after_outside_tap",
        not context.computerScreen.wantsTextInput())

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

    local pressState, pressSaves = context.State.new(), 0
    pressState.screen = "press"
    local pressContext = {
        state = pressState,
        pressScreen = { keypressed = function() return true end },
        saveCurrent = function() pressSaves = pressSaves + 1 end,
    }
    context.input.keypressed("m", pressContext)
    check("press_keyboard_action_saves_like_mouse", pressSaves == 1)
    pressContext.pressScreen.keypressed = function() return false, "Proof allowance exhausted." end
    context.input.keypressed("v", pressContext)
    check("press_keyboard_error_is_visible_without_saving",
        pressSaves == 1 and pressState.message == "Proof allowance exhausted.")

    local guestUseState = context.State.new()
    guestUseState.screen = "world"
    local guestSelected = {
        kind = "loadingBayDoor",
        target = { x = 300, y = 285, radius = 62 },
    }
    local networkUseCalls, localDoorCalls, faceCalls = {}, 0, 0
    local guestUseContext = {
        state = guestUseState,
        assets = {},
        world = {
            getInteraction = function() return guestSelected end,
            faceInteraction = function() faceCalls = faceCalls + 1; return true end,
            toggleBayDoor = function()
                localDoorCalls = localDoorCalls + 1
                return true
            end,
        },
        networkInteraction = function(selected)
            networkUseCalls[#networkUseCalls + 1] = selected
            return true
        end,
        saveCurrent = function() error("network USE must not save locally") end,
    }
    local guestUseHandled = context.input.keypressed("e", guestUseContext)
    check("guest_use_routes_selected_target_through_network_hook_once",
        guestUseHandled and #networkUseCalls == 1
        and networkUseCalls[1] == guestSelected
        and networkUseCalls[1].kind == "loadingBayDoor"
        and faceCalls == 1)
    check("guest_use_never_executes_local_world_interaction",
        localDoorCalls == 0 and guestUseState.screen == "world")

    local computerOpenCalls = 0
    guestSelected = { kind = "computer", target = { x = 500, y = 235, radius = 58 } }
    guestUseContext.computerScreen = {
        enter = function() computerOpenCalls = computerOpenCalls + 1 end,
    }
    context.input.keypressed("e", guestUseContext)
    check("guest_nonallowlisted_use_remains_host_only",
        #networkUseCalls == 2 and networkUseCalls[2] == guestSelected
        and computerOpenCalls == 0 and guestUseState.screen == "world")

    local mirroredWorkOrder = {
        job = { id = "LAN-JOB-READ-ONLY", company = "Mirror Print Co." },
        pallet = { id = "LAN-JOB-READ-ONLY-P01", location = "warehouse" },
    }
    local openedWorkOrder, workOrderSaves = nil, 0
    guestSelected = {
        kind = "palletWorkOrder",
        target = { x = 420, y = 360, radius = 92, item = mirroredWorkOrder },
    }
    guestUseContext.palletWorkOrderScreen = {
        enter = function(item) openedWorkOrder = item end,
        mousepressed = function() return { action = "close" } end,
    }
    guestUseContext.saveCurrent = function() workOrderSaves = workOrderSaves + 1 end
    local networkCallsBeforePaperwork = #networkUseCalls
    check("guest_pallet_work_order_opens_mirrored_record_without_network_request",
        context.input.keypressed("e", guestUseContext)
        and guestUseState.screen == "pallet_work_order"
        and openedWorkOrder == mirroredWorkOrder
        and #networkUseCalls == networkCallsBeforePaperwork
        and workOrderSaves == 0)
    check("guest_pallet_work_order_close_is_read_only_and_save_free",
        context.input.mousepressed(0, 0, 1, guestUseContext)
        and guestUseState.screen == "world"
        and #networkUseCalls == networkCallsBeforePaperwork
        and workOrderSaves == 0)
    local paperworkJackRoutes = 0
    guestUseState.palletJack.operating = true
    guestUseState.palletJack.operatorPlayerId = 2
    guestUseContext.world.player = { id = 2 }
    guestUseContext.palletJackControl = function()
        paperworkJackRoutes = paperworkJackRoutes + 1
        return true
    end
    openedWorkOrder = nil
    check("pallet_work_order_use_remains_available_while_pushing_jack",
        context.input.keypressed("e", guestUseContext)
        and guestUseState.screen == "pallet_work_order"
        and openedWorkOrder == mirroredWorkOrder
        and paperworkJackRoutes == 0)

    local relocationState = context.State.new()
    relocationState.screen = "world"
    relocationState.cutter.moving = true
    local relocationPlaced, relocationSaves = 0, 0
    local relocationJackRoutes, relocationNetworkRoutes = 0, 0
    local relocationFaces = 0
    local relocationHandled = context.input.keypressed("e", {
        state = relocationState,
        assets = {},
        world = {
            getInteraction = function()
                return { kind = "palletJack", target = relocationState.palletJack }
            end,
            faceInteraction = function() relocationFaces = relocationFaces + 1 end,
            placeCutter = function()
                relocationPlaced = relocationPlaced + 1
                relocationState.cutter.moving = false
                return true
            end,
        },
        palletJackControl = function()
            relocationJackRoutes = relocationJackRoutes + 1
            return true
        end,
        networkInteraction = function()
            relocationNetworkRoutes = relocationNetworkRoutes + 1
            return true
        end,
        saveCurrent = function() relocationSaves = relocationSaves + 1 end,
    })
    check("moving_machine_place_owns_use_before_pallet_jack_routing",
        relocationHandled and relocationPlaced == 1 and relocationSaves == 1
        and relocationFaces == 1 and relocationJackRoutes == 0
        and relocationNetworkRoutes == 0 and not relocationState.cutter.moving)

    local guestRelocationState = context.State.new()
    guestRelocationState.screen = "world"
    guestRelocationState.cutter.moving = true
    local guestPlacements, guestRelocationSaves = 0, 0
    local guestNetworkRoutes = 0
    local guestJackRoutes, guestJackBlocks = 0, 0
    local guestRelocationHandled = context.input.keypressed("e", {
        state = guestRelocationState,
        assets = {},
        isNetworkClient = function() return true end,
        world = {
            getInteraction = function()
                return { kind = "loadingBayDoor", target = {} }
            end,
            placeCutter = function()
                guestPlacements = guestPlacements + 1
                guestRelocationState.cutter.moving = false
                return true
            end,
        },
        networkInteraction = function(selected)
            guestNetworkRoutes = guestNetworkRoutes + 1
            return selected and selected.kind == "loadingBayDoor"
        end,
        palletJackControl = function(action, selected)
            guestJackRoutes = guestJackRoutes + 1
            local targetsPalletJack = action == "park"
                or (action == "use" and selected and selected.kind == "palletJack")
            if guestRelocationState.cutter.moving and targetsPalletJack then
                guestJackBlocks = guestJackBlocks + 1
                return true
            end
            return false
        end,
        saveCurrent = function() guestRelocationSaves = guestRelocationSaves + 1 end,
    })
    check("guest_observer_routes_unrelated_use_during_host_machine_move",
        guestRelocationHandled and guestPlacements == 0 and guestRelocationSaves == 0
        and guestJackRoutes == 0 and guestJackBlocks == 0
        and guestNetworkRoutes == 1 and guestRelocationState.cutter.moving)

    local ownerState = context.State.new()
    ownerState.screen = "world"
    ownerState.palletJack.operating = true
    ownerState.palletJack.operatorPlayerId = 2
    local routedActions = {}
    local ownerContext = {
        state = ownerState,
        assets = {},
        isNetworkClient = function() return true end,
        world = {
            player = { id = 2 },
            getInteraction = function() return { kind = "cutter", target = {} } end,
        },
        palletJackControl = function(action)
            routedActions[#routedActions + 1] = action
            return true
        end,
    }
    context.input.keypressed("m", ownerContext)
    ownerState.cutter.moving = true
    context.input.keypressed("q", ownerContext)
    context.input.keypressed("e", ownerContext)
    check("guest_relocation_owner_routes_move_turn_and_place_intent",
        routedActions[1] == "move_machine"
        and routedActions[2] == "rotate_machine"
        and routedActions[3] == "place_machine")

    local state = context.State.new()
    local bought, order = context.procurement.buy(state, 1, 1)
    local rows = context.computerScreen.deliveryRows(state)
    local inventory = context.procurement.inventoryRows(state)
    check("domain_office_purchase_order_projection", bought and rows[1] == order
        and context.computerScreen.statusLabel(order.delivery.status) == "Awaiting truck schedule"
        and state.clientEmails.inbox[1].noticeKind == "salesman_confirmation"
        and state.clientEmails.inbox[1].body:find("Thanks so much", 1, true))
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
    controller:gamepadpressed(gamepad, "leftshoulder")
    controller:gamepadreleased(gamepad, "leftshoulder")
    check("controller_world_fork_button", pressed[3] == "l" and released[3] == "l")

    controllerScreen, controllerMachine = "machine", "cutter"
    controller:gamepadpressed(gamepad, "leftshoulder")
    controller:gamepadpressed(gamepad, "rightshoulder")
    check("controller_cutter_two_hand_guard", pressed[4] == "j" and pressed[5] == "k")
    controller:gamepadreleased(gamepad, "leftshoulder")
    controller:gamepadreleased(gamepad, "rightshoulder")

    controllerScreen, controllerMachine = "computer", nil
    controller:gamepadpressed(gamepad, "start")
    check("controller_start_opens_options_from_any_screen", pressed[#pressed] == "menu")
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
    camera:endGesture()
    camera:selectView("computer", false)
    local computerFit = camera:snapshot()
    camera:beginGesture(480, 339, 200)
    camera:updateGesture(480, 339, 320)
    camera:endGesture()
    local computerZoomed = camera:snapshot()
    camera:selectView("world", true)
    local worldFill = camera:snapshot()
    camera:selectView("computer", false)
    local computerRestored = camera:snapshot()
    check("mobile_gui_starts_fit_and_remembers_its_camera", computerFit.zoom == 1
        and computerZoomed.zoom > 1.5 and worldFill.zoom > 1.52
        and math.abs(computerRestored.zoom - computerZoomed.zoom) < 0.001)

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
    mobile:touchpressed("small-move", 310, 210)
    mobile:touchmoved("small-move", 318, 216, 8, 6)
    mobile:touchreleased("small-move", 318, 216)
    check("mobile_tap_activates_press_origin_not_release_target", #taps == 4
        and taps[3][2] == 310 and taps[3][3] == 210
        and taps[4][2] == 310 and taps[4][3] == 210)
    mobile:touchpressed("drag-release", 120, 180)
    mobile:touchmoved("drag-release", 520, 360, 400, 180)
    mobile:touchreleased("drag-release", 700, 420)
    check("mobile_drag_release_never_clicks_an_object", #taps == 4)

    local placementTap = {}
    local placementState = context.State.new()
    placementState.screen = "world"
    context.input.mousepressed(210, 140, 1, {
        state = placementState,
        assets = {},
        hud = { hitTest = function() return nil end },
        worldPointerCoordinates = function(x, y) return x + 300, y + 200 end,
        world = {
            selectPlacement = function(_, _, x, y, readOnly)
                placementTap.x, placementTap.y, placementTap.readOnly = x, y, readOnly
                return true
            end,
        },
        isNetworkClient = function() return true end,
    })
    check("mobile_guest_placement_tap_uses_camera_coordinates_read_only",
        placementTap.x == 510 and placementTap.y == 340
        and placementTap.readOnly == true)

    local panelTaps, panelGestures = {}, 0
    local panelMobile = MobileControls.new({
        enabled = true,
        toGame = function(x, y) return x, y end,
        pressKey = function() end,
        releaseKey = function() end,
        pressPointer = function() panelTaps[#panelTaps + 1] = "down" end,
        movePointer = function() end,
        releasePointer = function() panelTaps[#panelTaps + 1] = "up" end,
        gameplayActive = function() return false end,
        gestureActive = function() return true end,
        beginGesture = function() panelGestures = panelGestures + 1 end,
        updateGesture = function() end,
        endGesture = function() end,
    })
    panelMobile:touchpressed("panel-first", 98, 574)
    panelMobile:touchpressed("panel-second", 500, 300)
    panelMobile:touchreleased("panel-second", 500, 300)
    panelMobile:touchreleased("panel-first", 98, 574)
    check("mobile_gui_gesture_works_over_world_control_positions",
        panelGestures == 1 and #panelTaps == 0)
end

return Test
