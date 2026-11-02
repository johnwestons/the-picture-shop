local Game = require("src.chandler_price_game")
local Test = {}

local function setUp(run)
    Game.dispatch(run,"die")
    for _=1,Game.job(run).gauge do Game.dispatch(run,"gauge_up") end
    for _=2,Game.job(run).packing do Game.dispatch(run,"packing_up") end
    Game.dispatch(run,"grippers")
    Game.dispatch(run,"impression")
    Game.dispatch(run,"proof")
end

local function finish(run)
    setUp(run)
    Game.dispatch(run,"start_stop")
    for _=1,2000 do
        if run.phase == "running" and Game.platenOpen(run) and run.pending == 0
            and run.stock > 0 then Game.dispatch(run,"feed") end
        Game.update(run,0.1)
        if run.delivery > 0 then Game.dispatch(run,"collect") end
        if run.held == Game.job(run).bundle then Game.dispatch(run,"box") end
        if run.phase == "paused" and run.fed < Game.job(run).target then
            if run.stock == 0 then Game.dispatch(run,"restock") end
            Game.dispatch(run,"start_stop")
        end
        if run.phase == "complete" then break end
    end
end

function Test.run(context,check)
    check("platen_has_exactly_two_starter_job_layouts",#Game.jobs == 2
        and Game.jobs[1].id == "two_pocket_folder" and Game.jobs[2].id == "box_layout")
    local bad = Game.new(1)
    Game.dispatch(bad,"proof")
    check("platen_rejects_unset_die_and_consumes_proof_stock",not bad.proof
        and bad.spoiled == 1 and bad.stock == 11)
    local folder = Game.new(1)
    finish(folder)
    check("platen_folder_runs_proof_to_boxed_flat_blanks",folder.phase == "complete"
        and folder.fed == 12 and folder.boxed == 12 and folder.boxes == 2)
    local box = Game.new(2)
    finish(box)
    check("platen_box_runs_proof_to_boxed_flat_blanks",box.phase == "complete"
        and box.fed == 12 and box.boxed == 12 and box.boxes == 2)
    local automatic = Game.new(1)
    setUp(automatic)
    Game.dispatch(automatic,"start_stop")
    for _=1,2000 do
        Game.update(automatic,0.1)
        if automatic.delivery > 0 then Game.dispatch(automatic,"collect") end
        if automatic.held == Game.job(automatic).bundle then Game.dispatch(automatic,"box") end
        if automatic.phase == "paused" and automatic.fed < Game.job(automatic).target then
            if automatic.stock == 0 then Game.dispatch(automatic,"restock") end
            Game.dispatch(automatic,"start_stop")
        end
        if automatic.phase == "complete" then break end
    end
    check("platen_runs_from_start_to_boxed_without_manual_sheet_feeds",
        automatic.phase == "complete" and automatic.fed == 12 and automatic.boxed == 12)
    local unattended = Game.new(1)
    setUp(unattended)
    Game.dispatch(unattended,"start_stop")
    for _=1,250 do
        Game.update(unattended,0.1)
        if unattended.phase == "jammed" then break end
    end
    check("platen_auto_feed_allows_eight_deliveries_before_backlog_jam",
        unattended.phase == "jammed" and unattended.fed == 8
        and unattended.spoiled == 9)
    local gate = Game.new(1)
    setUp(gate)
    Game.dispatch(gate,"start_stop")
    gate.cycle = 1.3
    local _,accepted = Game.dispatch(gate,"feed")
    check("platen_blocks_hand_feed_during_closing_stroke",not accepted and gate.fed == 0)
    gate.cycle = 0
    Game.dispatch(gate,"feed")
    Game.dispatch(gate,"start_stop")
    check("platen_mid_cycle_stop_releases_pending_sheet",gate.phase == "paused"
        and gate.pending == 0 and gate.spoiled == 2)
    local Screen = require("src.screens.chandler_price_screen")
    Screen.enter("MCH-CP-A")
    Screen.act("view")
    Screen.enter("MCH-CP-B")
    check("platen_duplicate_units_keep_separate_local_runs",Screen.run().view == 1)
    Screen.enter("MCH-CP-A")
    check("platen_uses_all_eight_machine_angles",Screen.run().view == 2)
    local helpRun = Screen.run()
    setUp(helpRun)
    Game.dispatch(helpRun,"start_stop")
    Screen.mousepressed(750,35,1)
    local beforeCycle,beforeFed = helpRun.cycle,helpRun.fed
    Screen.update(0.1)
    Screen.keypressed("space")
    Screen.mousepressed(730,545,1)
    check("platen_help_pauses_and_blocks_run_controls",Screen.helpOpen()
        and Screen.helpPage == 2 and helpRun.cycle == beforeCycle
        and helpRun.fed == beforeFed)
    for _=1,4 do Screen.mousepressed(730,545,1) end
    check("platen_help_navigation_stays_on_last_page",Screen.helpPage == 4)
    local helpDrawn = pcall(function()
        love.graphics.push("all")
        Screen.draw({},context.assets,0,0)
        love.graphics.pop()
    end)
    check("platen_help_draws_on_fourth_page",helpDrawn)
    local helpContext = {state={screen="chandler_price"},chandlerPriceScreen=Screen}
    require("src.input").closeScreen(helpContext)
    check("platen_escape_closes_help_without_leaving_console",
        not Screen.helpOpen() and helpContext.state.screen == "chandler_price")
    Screen.enter("MCH-CP-A")
    Screen.act("new_run")
    local drawn = pcall(function()
        love.graphics.push("all")
        Screen.draw({},context.assets,0,0)
        love.graphics.pop()
    end)
    check("platen_console_draws_machine_and_two_dielines",drawn)
    if os.getenv("PICTURE_SHOP_CP_PREVIEW") == "1" then
        local function preview(fileName)
            local canvas = love.graphics.newCanvas(960,640)
            love.graphics.push("all")
            love.graphics.setCanvas(canvas)
            love.graphics.clear(0,0,0,1)
            Screen.draw({},context.assets,0,0)
            love.graphics.setCanvas()
            love.graphics.pop()
            canvas:newImageData():encode("png",fileName)
        end
        preview("chandler-price-folder-preview.png")
        Screen.mousepressed(750,35,1)
        preview("chandler-price-help-preview.png")
        Screen.closeHelp()
        Screen.act("job_next")
        preview("chandler-price-box-preview.png")
    end

    local Fleet = require("src.machine_fleet")
    local Schema = require("src.save_schema")
    local state = context.State.new()
    local offers = Fleet.offers("dealer")
    local index
    for i,offer in ipairs(offers) do
        if offer.modelId == "chandler_price_platen" then index = i end
    end
    check("platen_listed_as_fifth_market_machine",index == 5
        and Fleet.offers("online")[index].modelId == "chandler_price_platen")
    state.money = 50000
    local purchased,unit = Fleet.buy(state,"dealer",index)
    check("platen_purchase_installs_interactable_unit",purchased and unit.world
        and Fleet.isInstalled(state,"chandler_price_platen"))
    check("platen_purchase_survives_save_contract",Schema.validState(Schema.snapshot(state)))
    Screen.enter(unit.id,state)
    setUp(Screen.run())
    Screen.act("start_stop")
    for _=1,30 do
        Screen.update(0.1,state)
        if unit.cycles == 1 then break end
    end
    local withRun = Schema.snapshot(state)
    local savedUnit = withRun and Fleet.byId(withRun,unit.id)
    check("platen_run_and_machine_wear_persist_per_unit",unit.cycles == 1
        and savedUnit and savedUnit.platenRun and savedUnit.platenRun.fed == 1
        and Schema.validState(withRun))
    local world = context.appRuntime.World
    local player = world.player
    local oldState,oldSelected = world._state,world.selectedInteraction
    local oldX,oldY,oldScene = player.x,player.y,player.sceneId
    world._state,world.selectedInteraction = state,nil
    player.x,player.y,player.sceneId = unit.world.x,unit.world.y + 28,"warehouse"
    local selected = world.interactionAt(unit.world.x,unit.world.y,false)
    check("platen_purchased_unit_has_world_interaction",selected
        and selected.kind == "chandlerPrice" and selected.target.machineId == unit.id)
    world._state,world.selectedInteraction = oldState,oldSelected
    player.x,player.y,player.sceneId = oldX,oldY,oldScene
    local Computer = require("src.screens.computer_screen").new()
    local _,cy = Computer.machineBuyCenter(5)
    local Vendor = require("src.screens.vendor_screen")
    local _,vy = Vendor.buyButtonCenter(5)
    check("platen_fifth_market_buttons_fit_visible_panels",cy < 598 and vy < 486)
end

return Test
