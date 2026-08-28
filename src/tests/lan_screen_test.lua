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
end

return Test
