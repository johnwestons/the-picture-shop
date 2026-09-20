local Machine = require("src.machine")
local MachineScreen = require("src.screens.machine_screen")
local PaperWork = require("src.paper_work")
local Presentation = require("src.screens.cutter_presentation")
local Remote = require("src.screens.workshop_remote_screen")

local Test = {}

local function view(overrides)
    local result = {
        runtimeRevision = 1, step = "loaded", phasePermille = 0,
        loaded = true, clamp = false, clampPermille = 0, bladePermille = 0,
        barrierClear = true, emergencyStopped = false, gaugeCentiInch = 1250,
        programIndex = 1, memoryCentiInch = { 1250 },
        paper = { palletId = "PREVIEW-P01", orientation = 90, status = "uncut",
            activeCut = 1, cutCount = 4, activeLift = 1, requiredLifts = 2,
            remainingSheets = 750, selectedCut = { number = 1, edge = "right",
                marginCentiInch = 50, gaugeCentiInch = 1250, orientation = 90, active = true } },
    }
    for key, value in pairs(overrides or {}) do result[key] = value end
    return result
end

local function enter(state, current)
    Remote.enter({ resourceId = "cutter", leaseId = "preview-lease", revision = 1,
        view = current, message = "Host connected · Your controls are live" }, state)
end

function Test.run(context, check)
    local source = PaperWork.createStockPaper()
    local state = context.State.new()
    state.jobs.active = { { id = "PREVIEW", company = "Critter Print Co.",
        pallets = { { id = "PREVIEW-P01", paper = source } } } }
    local current = view()
    local presentation = Presentation.new()
    presentation:accept(current)
    local model = presentation:model(state, current)
    check("cutter_presentation_uses_host_ticket_without_mutating_it",
        model.paper.orientation == 90 and source.orientation == 0
        and model.paper.currentSize.width == 13 and model.paper.artworkKey == source.artworkKey
        and model.paper ~= source and model.paper.currentSize ~= source.currentSize)
    current.paper.activeCut = 3
    model = presentation:model(state, current)
    check("cutter_presentation_confirmed_cuts_precede_durable_snapshot",
        model.paper.currentSize.width == 12.5 and model.paper.currentSize.height == 9.5
        and #model.paper.history == 2 and #source.history == 0 and source.currentSize.width == 13)
    current.paper.activeCut = 1
    current.paper.activeLift = 2
    model = presentation:model(state, current)
    check("cutter_presentation_next_lift_restores_full_stock",
        model.paper.currentSize.width == 13 and model.paper.currentSize.height == 10
        and #model.paper.history == 0)
    current.paper.palletId = "STOCK-P01"
    check("cutter_presentation_generic_stock_matches_local_stock",
        presentation:model({}, current).paper.currentSize.width == source.currentSize.width)
    current.paper.palletId = "UNKNOWN-P01"
    check("cutter_presentation_missing_ticket_does_not_invent_customer_art",
        presentation:model(state, current).paper == nil)
    current.paper.palletId = "PREVIEW-P01"

    current.step, current.phasePermille = "cutting", 200
    presentation:accept(current)
    current.phasePermille = 600
    current.runtimeRevision = 2
    presentation:accept(current)
    presentation:update(0.05)
    local middle = presentation.phase
    presentation:update(10)
    local finalPhase = presentation.phase
    presentation:update(10)
    check("cutter_presentation_interpolates_only_confirmed_motion_and_freezes_on_loss",
        math.abs(middle - 0.4) < 0.001 and math.abs(finalPhase - 0.6) < 0.001
        and presentation.phase == finalPhase and current.phasePermille == 600)
    current.runtimeRevision, current.step, current.emergencyStopped = 3, "blocked", true
    current.phasePermille = 0
    presentation:accept(current)
    check("cutter_presentation_safety_transition_cancels_blade_animation",
        presentation.phase == 0 and presentation:model(state, current).step == "blocked"
        and not presentation:accept(view()) and presentation.revision == 3)

    local sent = {}
    local function send(action, args)
        sent[#sent + 1] = { action = action, args = args }
        return true
    end
    local shortcuts = { g = "auto_gauge", m = "save_gauge", v = "recall_gauge",
        q = "rotate_paper", p = "position_paper", ["2"] = "select_program",
        ["]"] = "select_program" }
    local shortcutsOk = true
    for key, action in pairs(shortcuts) do
        enter(state, view())
        Remote.keypressed(key, state, send)
        shortcutsOk = shortcutsOk and sent[#sent].action == action
    end
    enter(state, view({ step = "positioned" }))
    Remote.keypressed("space", state, send)
    check("remote_cutter_keyboard_controls_match_host_bindings",
        shortcutsOk and sent[#sent].action == "set_clamp" and sent[#sent].args.clamp == true)
    enter(state, view())
    Remote.keypressed("p", state, send)
    local count = #sent
    Remote.keypressed("g", state, send)
    Remote.keypressed("x", state, send)
    check("remote_cutter_keyboard_pending_blocks_ordinary_but_not_estop",
        #sent == count + 1 and sent[#sent].action == "emergency_stop"
        and Remote.waiting and Remote.safetyWaiting)
    enter(state, view())
    local gx, gy = Remote.cutterGaugeInputCenter()
    Remote.mousepressed(state, gx, gy, 1, send)
    count = #sent
    Remote.keypressed("2", state, send)
    Remote.textinput("2")
    Remote.keypressed("return", state, send)
    check("remote_cutter_typing_does_not_change_program_or_reject_wrong_size",
        #sent == count + 1 and sent[#sent].action == "set_gauge"
        and sent[#sent].args.gaugeCentiInch == 200)

    enter(state, view({ step = "clamped", clamp = true, clampPermille = 1000 }))
    local x, y = Remote.cutterButtonCenter("cut_right")
    Remote.mousepressed(state, x, y, 1, send)
    check("remote_cutter_visible_cut_target_has_no_hidden_service_hitbox",
        sent[#sent].action == "guarded_cut" and Remote.cutterTab == "production")
    enter(state, view())
    Remote.applyCutterSnapshot({ resourceRevision = 5, view = view({ runtimeRevision = 10,
        step = "cutting", phasePermille = 400 }) })
    Remote.applyResult({ resourceId = "cutter", revision = 4, accepted = true,
        action = "position_paper", view = view({ runtimeRevision = 11 }) })
    check("remote_cutter_stale_resource_result_cannot_replace_live_presentation",
        Remote.view.step == "cutting" and Remote.cutterPresentation.revision == 10)
    Remote.clear()
    check("remote_cutter_close_discards_animation_and_asset_pack",
        Remote.cutterPresentation.revision == nil and Remote.requiredAssetPack() == nil)

    local assets, previousPack = context.assets, context.assets.activePack
    enter(state, view())
    check("remote_cutter_loads_the_same_animation_pack_as_host",
        Remote.requiredAssetPack() == "cutter" and assets.activatePack(Remote.requiredAssetPack())
        and assets.get("cutterClamp") ~= nil and assets.getQuad("cutterBlade5") ~= nil)
    local canvas = love.graphics.newCanvas(960, 680)
    local function pixels(draw)
        love.graphics.push("all")
        love.graphics.setCanvas(canvas)
        love.graphics.clear(0, 0, 0, 1)
        draw()
        love.graphics.pop()
        return canvas:newImageData()
    end
    local function digest(data)
        local result = love.data.hash("sha256", data:getString())
        data:release()
        return result
    end
    local machineStep, machineProgress, machinePaper = Machine.step, Machine.progress, Machine.paper
    local firstFrame, lastFrame, framesMatch = nil, nil, true
    for _, phase in ipairs({ 0, 250, 500, 750, 1000 }) do
        local frameView = view({ step = "cutting", phasePermille = phase,
            clamp = true, clampPermille = 1000 })
        local framePresentation = Presentation.new()
        framePresentation:accept(frameView)
        local guest = framePresentation:model(state, frameView)
        local hostPaper = PaperWork.createStockPaper()
        hostPaper.orientation = 90
        local host = { step = "cutting", loaded = true, paper = hostPaper,
            progress = phase / 1000 * Machine.cycleTime,
            cycleTime = Machine.cycleTime, transferTime = Machine.transferTime, clampProgress = 1 }
        local rect = { x = 400, y = 78, width = 520, height = 347 }
        local guestHash = digest(pixels(function() MachineScreen.drawCutterScene(assets, guest, rect) end))
        local hostHash = digest(pixels(function() MachineScreen.drawCutterScene(assets, host, rect) end))
        framesMatch = framesMatch and guestHash == hostHash
        if phase == 0 then firstFrame = guestHash elseif phase == 500 then lastFrame = guestHash end
    end
    check("remote_cutter_all_blade_frames_pixel_match_host_and_animate",
        framesMatch and firstFrame ~= lastFrame)
    local transferMatch, transferMoves = true, true
    for _, step in ipairs({ "loading", "positioning", "unloading", "lift_returning" }) do
        local hashes = {}
        for _, phase in ipairs({ 0, 500, 1000 }) do
            local frameView = view({ step = step, phasePermille = phase })
            local framePresentation = Presentation.new()
            framePresentation:accept(frameView)
            local guest = framePresentation:model(state, frameView)
            local hostPaper = PaperWork.createStockPaper()
            hostPaper.orientation = 90
            local host = { step = step, loaded = true, paper = hostPaper,
                progress = phase / 1000 * Machine.transferTime,
                cycleTime = Machine.cycleTime, transferTime = Machine.transferTime, clampProgress = 0 }
            local rect = { x = 400, y = 78, width = 520, height = 347 }
            local guestHash = digest(pixels(function() MachineScreen.drawCutterScene(assets, guest, rect) end))
            local hostHash = digest(pixels(function() MachineScreen.drawCutterScene(assets, host, rect) end))
            hashes[#hashes + 1] = guestHash
            transferMatch = transferMatch and guestHash == hostHash
        end
        transferMoves = transferMoves and hashes[1] ~= hashes[3]
    end
    check("remote_cutter_load_position_unload_and_lift_return_pixel_match_host",
        transferMatch and transferMoves)
    enter(state, view({ step = "cutting", phasePermille = 500, clamp = true, clampPermille = 1000 }))
    local preview = pixels(function() Remote.draw(state, -1, -1, assets) end)
    preview:encode("png", "cutter-guest-preview.png")
    preview:release()
    enter(state, view({ step = "idle", loaded = false, paper = false,
        candidates = { { palletId = "PREVIEW-P01", distancePixels = 15 } } }))
    preview = pixels(function() Remote.draw(state, -1, -1, assets) end)
    preview:encode("png", "cutter-guest-unloaded-preview.png")
    preview:release()
    check("remote_cutter_rendering_never_advances_local_machine_or_paper",
        Machine.step == machineStep and Machine.progress == machineProgress
        and Machine.paper == machinePaper and source.orientation == 0 and #source.history == 0)
    canvas:release()
    Remote.clear()
    assets.activatePack(previousPack)
end

return Test
