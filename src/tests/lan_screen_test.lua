local LanScreen = require("src.screens.lan_screen")
local TitleScreen = require("src.screens.title_screen")
local WorkshopRemoteScreen = require("src.screens.workshop_remote_screen")

local Test = {}

function Test.run(context, check)
    local selectedSlot
    TitleScreen.enter(function() end, function(slot) selectedSlot = slot end)
    TitleScreen.keypressed("down")
    local openedByKeyboard = TitleScreen.keypressed("l")
    check("lan_screen_title_local_play_uses_selected_save_slot",
        openedByKeyboard == true and selectedSlot == 2)

    local hostSlot, hostName, joinAddress, joinName, cancellations = nil, nil, nil, nil, 0
    LanScreen.enter({
        slot = 3,
        host = function(slot, name)
            hostSlot, hostName = slot, name
            return true
        end,
        join = function(address, name)
            joinAddress, joinName = address, name
            return true
        end,
        cancel = function() cancellations = cancellations + 1 end,
    })
    check("lan_screen_role_copy_allows_android_or_windows_host",
        LanScreen.message:find("host device", 1, true) ~= nil
        and LanScreen.message:find("host PC", 1, true) == nil)
    check("lan_screen_host_uses_selected_slot_and_platform_worker_name",
        LanScreen.keypressed("h") == true and hostSlot == 3
        and type(hostName) == "string" and hostName:find("Worker", 1, true) ~= nil)

    LanScreen.enter({
        slot = 3,
        join = function(address, name)
            joinAddress, joinName = address, name
            return true
        end,
        cancel = function() cancellations = cancellations + 1 end,
    })
    local openedJoin = LanScreen.keypressed("j")
    local acceptedText = LanScreen.textinput("192.168.1.246:22122")
    local startedJoin = LanScreen.keypressed("return")
    check("lan_screen_manual_ipv4_and_port_enters_connecting_state",
        openedJoin == true and acceptedText == true and startedJoin == true
        and joinAddress == "192.168.1.246:22122"
        and type(joinName) == "string" and LanScreen.mode == "connecting")

    local cancelled = LanScreen.keypressed("escape")
    check("lan_screen_connecting_cancel_returns_to_role_menu",
        cancelled == true and cancellations == 1 and LanScreen.mode == "menu")

    LanScreen.enter({
        join = function(address) joinAddress = address; return true end,
    })
    LanScreen.keypressed("j")
    local emptyJoin = LanScreen.keypressed("return")
    check("lan_screen_empty_address_is_rejected_before_transport",
        emptyJoin == false and joinAddress == "192.168.1.246:22122"
        and LanScreen.message:find("IPv4", 1, true) ~= nil
        and LanScreen.message:find("host PC", 1, true) == nil)

    local wrapperState = { screen = "world" }
    context.wrapper.reset(wrapperState)
    local sent = {}
    local function sendWrapperCommand(action, args)
        sent[#sent + 1] = { action = action, args = args }
        return true
    end
    local wrapperGrant = {
        resourceId = "skid_wrapper", leaseId = "wrapper-test", revision = 1,
        view = { pallets = {} },
    }
    WorkshopRemoteScreen.enter(wrapperGrant, wrapperState)
    local confirmX, confirmY = WorkshopRemoteScreen.confirmCenter()
    local emptyHandled = WorkshopRemoteScreen.mousepressed(
        wrapperState, confirmX, confirmY, 1, sendWrapperCommand)
    check("remote_wrapper_empty_state_disables_start_cycle",
        not WorkshopRemoteScreen.wrapperStartEnabled(wrapperState)
        and emptyHandled == true and #sent == 0)

    local liveListApplied = WorkshopRemoteScreen.applySnapshot({
        revision = 2,
        wrapper = {
            step = "idle", progress = 0, cycleTime = 3,
            pallets = {
                { palletId = "JOB-LIVE-P01", jobLabel = "Live Client · JOB-LIVE",
                    packaging = "boxed", distance = 24 },
            },
        },
    })
    local liveRowX, liveRowY = WorkshopRemoteScreen.rowCenter(1)
    local liveRowSelected = WorkshopRemoteScreen.mousepressed(
        wrapperState, liveRowX, liveRowY, 1, sendWrapperCommand)
    check("remote_wrapper_open_panel_updates_empty_to_eligible_pallet_list_live",
        liveListApplied and liveRowSelected == true and #sent == 1
        and sent[1].action == "select_pallet"
        and sent[1].args.palletId == "JOB-LIVE-P01")
    WorkshopRemoteScreen.clear()
    sent = {}

    wrapperGrant.view = { pallets = {
        { palletId = "JOB-0001-P01", jobLabel = "Client · JOB-0001", packaging = "flat" },
    } }
    WorkshopRemoteScreen.enter(wrapperGrant, wrapperState)
    local unselectedHandled = WorkshopRemoteScreen.mousepressed(
        wrapperState, confirmX, confirmY, 1, sendWrapperCommand)
    check("remote_wrapper_requires_explicit_pallet_selection",
        not WorkshopRemoteScreen.wrapperStartEnabled(wrapperState)
        and unselectedHandled == true and #sent == 0
        and WorkshopRemoteScreen.status == "Select a nearby finished pallet first.")

    local rowX, rowY = WorkshopRemoteScreen.rowCenter(1)
    local selected = WorkshopRemoteScreen.mousepressed(
        wrapperState, rowX, rowY, 1, sendWrapperCommand)
    WorkshopRemoteScreen.applyResult({
        resourceId = "skid_wrapper", action = "select_pallet", accepted = true,
        palletId = "JOB-0001-P01", revision = 2, message = "Pallet selected.",
    })
    local enabledAfterSelection = WorkshopRemoteScreen.wrapperStartEnabled(wrapperState)
    local started = WorkshopRemoteScreen.mousepressed(
        wrapperState, confirmX, confirmY, 1, sendWrapperCommand)
    check("remote_wrapper_selected_pallet_enables_start_cycle",
        selected == true and enabledAfterSelection and started == true and #sent == 2
        and sent[1].action == "select_pallet"
        and sent[1].args.palletId == "JOB-0001-P01"
        and sent[2].action == "start_cycle"
        and sent[2].args.palletId == "JOB-0001-P01")
    WorkshopRemoteScreen.clear()
    context.wrapper.reset(wrapperState)

    local cutterState = {
        screen = "world",
        jobs = { active = {
            { id = "JOB-CUT", company = "Remote Client", pallets = { { id = "JOB-CUT-P01" } } },
        } },
    }
    local cutterView = {
        runtimeRevision = 1, step = "idle", phasePermille = 0,
        loaded = false, clamp = false, clampPermille = 0, bladePermille = 0,
        barrierClear = true, emergencyStopped = false,
        gaugeCentiInch = 0, programIndex = 1, memoryCentiInch = {},
        candidates = { { palletId = "JOB-CUT-P01", distancePixels = 22 } },
        genericSheets = 100,
    }
    WorkshopRemoteScreen.enter({
        resourceId = "cutter", leaseId = "cutter-test", revision = 4, view = cutterView,
    }, cutterState)
    sent = {}
    local candidateX, candidateY = WorkshopRemoteScreen.cutterCandidateCenter(1)
    local loadRequested = WorkshopRemoteScreen.mousepressed(
        cutterState, candidateX, candidateY, 1, sendWrapperCommand)
    check("remote_cutter_candidate_sends_exact_host_load_request",
        loadRequested == true and #sent == 1 and sent[1].action == "load_pallet"
        and sent[1].args.palletId == "JOB-CUT-P01")

    local loadedView = {
        runtimeRevision = 2, step = "positioned", phasePermille = 1000,
        loaded = true, clamp = false, clampPermille = 0, bladePermille = 0,
        barrierClear = true, emergencyStopped = false,
        gaugeCentiInch = 0, programIndex = 1, memoryCentiInch = {},
        paper = { palletId = "JOB-CUT-P01", orientation = 0, status = "uncut",
            activeCut = 1, cutCount = 0, activeLift = 1, requiredLifts = 1,
            remainingSheets = 100,
            selectedCut = { number = 1, edge = "right", marginCentiInch = 25,
                gaugeCentiInch = 1234, orientation = 0, active = true } },
    }
    WorkshopRemoteScreen.applyResult({
        resourceId = "cutter", action = "load_pallet", accepted = true,
        revision = 5, view = loadedView,
    })
    local loadedMergeClearedIdleChoices = WorkshopRemoteScreen.view.candidates == nil
        and WorkshopRemoteScreen.view.genericSheets == nil
    WorkshopRemoteScreen.applyResult({
        resourceId = "cutter", action = "select_program", accepted = true,
        revision = 6, view = {
            runtimeRevision = 1, gaugeCentiInch = 999, step = "loaded", loaded = true,
        },
    })
    local staleResource = WorkshopRemoteScreen.applyCutterSnapshot({
        resourceRevision = 5,
        view = { runtimeRevision = 3, gaugeCentiInch = 777, step = "loaded", loaded = true },
    })
    local freshSnapshot = WorkshopRemoteScreen.applyCutterSnapshot({
        resourceRevision = 6,
        view = { runtimeRevision = 3, gaugeCentiInch = 500, step = "positioned", loaded = true },
    })
    WorkshopRemoteScreen.applySnapshot({ revision = 9000, wrapper = {} })
    local interleavedCutterSnapshot = WorkshopRemoteScreen.applyCutterSnapshot({
        resourceRevision = 6,
        view = { runtimeRevision = 4, gaugeCentiInch = 625, step = "positioned", loaded = true },
    })
    sent = {}
    local positionX, positionY = WorkshopRemoteScreen.cutterButtonCenter("position_paper")
    WorkshopRemoteScreen.mousepressed(
        cutterState, positionX, positionY, 1, sendWrapperCommand)
    WorkshopRemoteScreen.applyCutterSnapshot({
        resourceRevision = 6,
        view = { runtimeRevision = 5, gaugeCentiInch = 625, step = "loading", loaded = true },
    })
    local rotateX, rotateY = WorkshopRemoteScreen.cutterButtonCenter("rotate_paper")
    WorkshopRemoteScreen.mousepressed(cutterState, rotateX, rotateY, 1, sendWrapperCommand)
    WorkshopRemoteScreen.mousepressed(cutterState, positionX, positionY, 1, sendWrapperCommand)
    local transitionControlsStayedDisabled = #sent == 0
    WorkshopRemoteScreen.applyCutterSnapshot({
        resourceRevision = 6,
        view = { runtimeRevision = 6, gaugeCentiInch = 625, step = "positioned", loaded = true },
    })
    check("remote_cutter_rejects_stale_result_and_resource_snapshot_views",
        loadedMergeClearedIdleChoices and not staleResource and freshSnapshot
        and interleavedCutterSnapshot and transitionControlsStayedDisabled
        and WorkshopRemoteScreen.workshopTick == 9000
        and WorkshopRemoteScreen.revision == 6
        and WorkshopRemoteScreen.view.runtimeRevision == 6
        and WorkshopRemoteScreen.view.gaugeCentiInch == 625)

    WorkshopRemoteScreen.applyCutterSnapshot({
        resourceRevision = 6,
        view = {
            runtimeRevision = 7, step = "repeat_ready", loaded = false,
            paper = loadedView.paper, candidates = nil, genericSheets = nil,
        },
    })
    local repeatReadyKeptPaperWithoutIdleChoices = WorkshopRemoteScreen.view.paper ~= nil
        and WorkshopRemoteScreen.view.candidates == nil
        and WorkshopRemoteScreen.view.genericSheets == nil
    WorkshopRemoteScreen.applyCutterSnapshot({
        resourceRevision = 6,
        view = {
            runtimeRevision = 8, step = "idle", loaded = false,
            candidates = {}, genericSheets = nil,
        },
    })
    check("remote_cutter_merge_clears_stale_candidates_and_generic_stock",
        repeatReadyKeptPaperWithoutIdleChoices
        and WorkshopRemoteScreen.view.paper == nil
        and type(WorkshopRemoteScreen.view.candidates) == "table"
        and #WorkshopRemoteScreen.view.candidates == 0
        and WorkshopRemoteScreen.view.genericSheets == nil)

    WorkshopRemoteScreen.applyCutterSnapshot({
        resourceRevision = 6,
        view = { runtimeRevision = 9, gaugeCentiInch = 625, step = "positioned", loaded = true,
            paper = loadedView.paper },
    })

    sent = {}
    local gaugeX, gaugeY = WorkshopRemoteScreen.cutterGaugeInputCenter()
    WorkshopRemoteScreen.mousepressed(cutterState, gaugeX, gaugeY, 1, sendWrapperCommand)
    local gaugeTyped = WorkshopRemoteScreen.textinput("12.34")
    local setX, setY = WorkshopRemoteScreen.cutterButtonCenter("set_gauge")
    WorkshopRemoteScreen.mousepressed(cutterState, setX, setY, 1, sendWrapperCommand)
    check("remote_cutter_gauge_entry_uses_wire_safe_centi_inches",
        gaugeTyped and #sent == 1 and sent[1].action == "set_gauge"
        and sent[1].args.gaugeCentiInch == 1234)

    WorkshopRemoteScreen.applyResult({
        resourceId = "cutter", action = "set_gauge", accepted = true,
        revision = 7, view = {
            runtimeRevision = 10, gaugeCentiInch = 1234, step = "clamped",
            loaded = true, clamp = true, barrierClear = true, emergencyStopped = false,
        },
    })
    sent = {}
    local leftX, leftY = WorkshopRemoteScreen.cutterButtonCenter("cut_left")
    local rightX, rightY = WorkshopRemoteScreen.cutterButtonCenter("cut_right")
    WorkshopRemoteScreen.mousepressed(cutterState, leftX, leftY, 1, sendWrapperCommand)
    check("remote_cutter_left_button_sends_one_guarded_cut",
        #sent == 1 and sent[1].action == "guarded_cut")

    local emergencyX, emergencyY = WorkshopRemoteScreen.cutterButtonCenter("emergency_stop")
    WorkshopRemoteScreen.mousepressed(
        cutterState, emergencyX, emergencyY, 1, sendWrapperCommand)
    local safetySentDuringOrdinaryWait = #sent == 2
        and sent[2].action == "emergency_stop"
        and WorkshopRemoteScreen.waiting and WorkshopRemoteScreen.safetyWaiting

    WorkshopRemoteScreen.applyResult({
        resourceId = "cutter", action = "guarded_cut", accepted = false,
        revision = 8, view = {
            runtimeRevision = 11, gaugeCentiInch = 1234, step = "clamped",
            loaded = true, clamp = true, barrierClear = true, emergencyStopped = false,
        },
    })
    local ordinaryReplyKeptSafetyPending = not WorkshopRemoteScreen.waiting
        and WorkshopRemoteScreen.safetyWaiting
    WorkshopRemoteScreen.applyResult({
        resourceId = "cutter", action = "emergency_stop", accepted = true,
        urgentSafety = true, revision = 9, view = {
            runtimeRevision = 12, gaugeCentiInch = 1234, step = "blocked",
            loaded = true, clamp = true, barrierClear = true, emergencyStopped = true,
        },
    })
    local safetyReplyClearedOnlySafetyWait = not WorkshopRemoteScreen.waiting
        and not WorkshopRemoteScreen.safetyWaiting
    WorkshopRemoteScreen.applyCutterSnapshot({
        resourceRevision = 9,
        view = {
            runtimeRevision = 13, gaugeCentiInch = 1234, step = "clamped",
            loaded = true, clamp = true, barrierClear = true, emergencyStopped = false,
        },
    })
    check("remote_cutter_estop_bypasses_ordinary_wait_with_independent_result_tracking",
        safetySentDuringOrdinaryWait and ordinaryReplyKeptSafetyPending
        and safetyReplyClearedOnlySafetyWait)
    sent = {}
    WorkshopRemoteScreen.mousepressed(cutterState, rightX, rightY, 1, sendWrapperCommand)
    check("remote_cutter_right_button_sends_one_guarded_cut",
        #sent == 1 and sent[1].action == "guarded_cut")
    WorkshopRemoteScreen.clear()
end

return Test
