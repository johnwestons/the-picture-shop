local Game = require("src.regal_folder_game")
local Test = {}

function Test.run(context, check)
    local run = Game.new()
    Game.dispatch(run, "proof")
    check("folder_rejects_unset_proof", not run.proof and run.spoiled == 1)
    Game.dispatch(run, "fold_up")
    Game.dispatch(run, "fold_up")
    Game.dispatch(run, "fold_up")
    Game.dispatch(run, "guide_up")
    Game.dispatch(run, "air")
    Game.dispatch(run, "air")
    Game.dispatch(run, "proof")
    check("folder_accepts_matched_fold_guides_and_air", run.proof == true)
    Game.dispatch(run, "start_stop")
    for _ = 1, 600 do
        Game.update(run, 0.1)
        if run.stock == 0 and run.fed < run.target then
            Game.dispatch(run, "refill")
            if run.phase == "paused" then Game.dispatch(run, "start_stop") end
        end
        if run.delivery > 0 then Game.dispatch(run, "catch") end
        if run.held == 6 or (run.fed == run.target and #run.inTransit == 0
            and run.delivery == 0 and run.held > 0) then
            Game.dispatch(run, "box")
        end
        if run.phase == "complete" then break end
    end
    check("folder_two_stations_finish_24_pieces_in_four_boxes",
        run.phase == "complete" and run.fed == 24 and run.boxed == 24
        and run.boxes == 4 and run.jams == 0)

    local jam = Game.new()
    jam.fold, jam.guide, jam.air = jam.targetFold, jam.targetGuide, 2
    Game.dispatch(jam, "proof")
    Game.dispatch(jam, "start_stop")
    for _ = 1, 400 do
        Game.update(jam, 0.1)
        if jam.stock == 0 and jam.fed < jam.target then
            Game.dispatch(jam, "refill")
            if jam.phase == "paused" then Game.dispatch(jam, "start_stop") end
        end
        if jam.phase == "jammed" then break end
    end
    check("folder_delivery_backup_causes_jam", jam.phase == "jammed"
        and jam.jams == 1 and jam.spoiled > 0)
    Game.dispatch(jam, "clear_jam")
    Game.dispatch(jam, "start_stop")
    check("folder_jam_requires_fresh_proof", jam.phase == "paused" and not jam.proof)

    local Screen = require("src.screens.regal_folder_screen")
    Screen.enter()
    local image = context.assets.get("regalFolderDirections")
    local sprite = context.assets.getQuad("regalFolderDirection1")
    local drawn = pcall(function()
        love.graphics.push("all")
        Screen.draw({}, context.assets, 0, 0)
        love.graphics.pop()
    end)
    check("folder_screen_draws_registered_sprite_sheet", image ~= nil
        and sprite ~= nil and drawn)
    check("folder_screen_rotates_all_eight_views",
        Screen.keypressed("v") and Screen.run.view == 2)
    local Fleet = require("src.machine_fleet")
    local Schema = require("src.save_schema")
    local state = context.State.new()
    local world = context.appRuntime.World
    local player = world.player
    local oldState, oldSelected = world._state, world.selectedInteraction
    local oldX, oldY, oldScene = player.x, player.y, player.sceneId
    local station = require("src.config").regalFolderPlacement
    world._state, world.selectedInteraction = state, nil
    player.x, player.y, player.sceneId = station.spawnX, station.spawnY + 38, "warehouse"
    local selected = world.interactionAt(station.spawnX, station.spawnY, false)
    check("folder_absent_from_new_and_existing_unpurchased_shops",
        #Fleet.installedUnits(state, "regal_moll") == 0
        and (not selected or selected.kind ~= "regalFolder")
        and #Fleet.installedUnits(Schema.snapshot(state), "regal_moll") == 0)
    local offers = Fleet.offers("dealer")
    local index
    for number, offer in ipairs(offers) do
        if offer.modelId == "regal_moll" then index = number end
    end
    check("folder_available_in_both_machine_catalogs", index
        and Fleet.offers("online")[index].modelId == "regal_moll")
    state.money = 0
    check("folder_purchase_requires_payment", not Fleet.buy(state, "dealer", index)
        and #Fleet.installedUnits(state, "regal_moll") == 0)
    state.money = 100000
    local bought, machine = Fleet.buy(state, "dealer", index)
    check("folder_purchase_places_paid_machine", bought and machine.world
        and state.money == 100000 - offers[index].price)
    player.x, player.y = machine.world.x, machine.world.y + 38
    world.selectedInteraction = nil
    selected = world.interactionAt(machine.world.x, machine.world.y, false)
    check("folder_purchased_machine_opens_interaction", selected
        and selected.kind == "regalFolder" and selected.target.machineId == machine.id)
    local saved = Schema.snapshot(state)
    local restored = saved and Fleet.installed(saved, "regal_moll")
    check("folder_purchase_and_position_survive_save_reload", saved and Schema.validState(saved)
        and restored and restored.world.x == machine.world.x and restored.world.y == machine.world.y)
    local sold = Fleet.sell(state, machine.id, "online")
    world.selectedInteraction = nil
    selected = world.interactionAt(machine.world.x, machine.world.y, false)
    check("folder_sale_removes_floor_interaction", sold
        and #Fleet.installedUnits(state, "regal_moll") == 0
        and (not selected or selected.kind ~= "regalFolder"))
    local ordered, order = Fleet.orderOnline(state, index)
    check("folder_online_purchase_waits_for_delivery", ordered
        and #Fleet.installedUnits(state, "regal_moll") == 0)
    local pending = Schema.snapshot(state)
    local unloaded, delivered = Fleet.unloadDelivery(pending, order.id, order.machineId)
    check("folder_saved_online_order_unloads_to_floor", unloaded and delivered.world
        and #Fleet.installedUnits(pending, "regal_moll") == 1
        and Schema.validState(Schema.snapshot(pending)))
    local Computer = require("src.screens.computer_screen").new()
    Computer.tab, Computer.wwwSite = "www", 5
    local buyX, buyY = Computer.machineBuyCenter(index)
    local added = Computer.mousepressed(state, buyX, buyY, 1)
    check("folder_fourth_market_row_is_visible_and_adds_to_cart", buyY + 21 < 598
        and added and added.action == "cart_item_added"
        and Computer.cart[#Computer.cart].modelId == "regal_moll")
    local Vendor = require("src.screens.vendor_screen")
    state.vendorCategory = 5
    local dealerX, dealerY = Vendor.buyButtonCenter(index)
    local dealerPurchase = Vendor.mousepressed(state, dealerX, dealerY, 1)
    check("folder_fourth_dealer_row_is_visible_and_buyable", dealerY + 24 < 486
        and dealerPurchase and dealerPurchase.action == "machine_purchased"
        and dealerPurchase.machine.modelId == "regal_moll")
    world._state, world.selectedInteraction = oldState, oldSelected
    player.x, player.y, player.sceneId = oldX, oldY, oldScene
    if os.getenv("PICTURE_SHOP_FOLDER_PREVIEW") == "1" then
        for _, page in ipairs({"www", "credit", "vendor"}) do
            local preview = love.graphics.newCanvas(960, 678)
            love.graphics.push("all")
            love.graphics.setCanvas(preview)
            love.graphics.clear(0, 0, 0, 1)
            Computer.tab = page
            if page == "vendor" then Vendor.draw(state, context.assets, 0, 0)
            else Computer.draw(state, 0, 0, context.assets) end
            love.graphics.pop()
            preview:newImageData():encode("png", "regal-folder-" .. page .. ".png")
        end
        Screen.enter()
        local canvas = love.graphics.newCanvas(960, 640)
        love.graphics.push("all")
        love.graphics.setCanvas(canvas)
        love.graphics.clear(0, 0, 0, 1)
        Screen.draw({}, context.assets, 0, 0)
        love.graphics.pop()
        canvas:newImageData():encode("png", "regal-folder-preview.png")
    end
end

return Test
