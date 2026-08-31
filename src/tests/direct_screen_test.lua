local DirectScreen = require("src.screens.direct_screen")
local TitleScreen = require("src.screens.title_screen")

local Test = {}

local HOST_CODE = "TPS2H.ABC_def-123"
local RESPONSE_CODE = "TPS2R.XYZ_def-456"
local HOST_ADDRESS = "2606:4700:4700::1111"
local GUEST_ADDRESS = "2001:4860:4860::8888"

local function click(name)
    local x, y = DirectScreen.buttonCenter(name)
    return DirectScreen.mousepressed(x, y, 1)
end

function Test.run(_, check)
    local directSlot
    TitleScreen.enter(function() end, function() end, function(slot) directSlot = slot end)
    TitleScreen.keypressed("down")
    local directOpened = TitleScreen.keypressed("i")
    check("title_screen_exposes_direct_entry_only_when_the_production_callback_exists",
        directOpened and directSlot == 2 and TitleScreen.buttonCenter("directPlay") ~= nil)
    TitleScreen.enter(function() end, function() end)
    local lockedDirect = TitleScreen.keypressed("i")
    check("title_screen_keeps_direct_play_unselectable_when_the_production_gate_is_closed",
        lockedDirect == false and TitleScreen.buttonCenter("directPlay") == nil
        and TitleScreen.message:find("not available", 1, true) ~= nil)

    local clipboard = ""
    local hostRequest, submittedResponse, cancellations = nil, nil, 0
    DirectScreen.enter({
        slot = 2,
        readClipboard = function() return clipboard end,
        writeClipboard = function(value) clipboard = value; return true end,
        host = function(slot, name, address)
            hostRequest = { slot = slot, name = name, address = address }
            return true, HOST_CODE
        end,
        response = function(code) submittedResponse = code; return true end,
        cancel = function() cancellations = cancellations + 1; return true end,
    })
    local choseHost = DirectScreen.keypressed("h")
    local enteredHostAddress = DirectScreen.textinput(HOST_ADDRESS)
    local createdHostCode = DirectScreen.keypressed("return")
    check("direct_screen_host_entry_uses_selected_save_and_manual_global_ipv6",
        choseHost and enteredHostAddress and createdHostCode
        and DirectScreen.mode == "host_reply"
        and hostRequest and hostRequest.slot == 2
        and hostRequest.address == HOST_ADDRESS
        and type(hostRequest.name) == "string"
        and DirectScreen.displayCode == HOST_CODE)

    local copiedHost = click("copy")
    clipboard = RESPONSE_CODE
    local pastedReply = click("paste")
    local connectedHost = click("connect")
    check("direct_screen_host_copy_paste_submits_reply_without_echoing_it_in_status",
        copiedHost and pastedReply and connectedHost
        and submittedResponse == RESPONSE_CODE
        and DirectScreen.mode == "opening_host"
        and DirectScreen.displayCode == nil and DirectScreen.responseInput == ""
        and not DirectScreen.message:find(RESPONSE_CODE, 1, true))
    check("direct_screen_does_not_erase_clipboard_content_the_player_replaced",
        clipboard == RESPONSE_CODE)

    DirectScreen.showError("The authenticated opening failed.")
    check("direct_screen_error_clears_all_sensitive_fields_before_returning_to_menu",
        DirectScreen.mode == "menu" and DirectScreen.displayCode == nil
        and DirectScreen.hostCodeInput == "" and DirectScreen.responseInput == ""
        and DirectScreen.localAddress == "")

    local guestRequest
    DirectScreen.enter({
        slot = 3,
        readClipboard = function() return clipboard end,
        writeClipboard = function(value) clipboard = value; return true end,
        join = function(hostCode, address, name)
            guestRequest = { hostCode = hostCode, address = address, name = name }
            return true, RESPONSE_CODE
        end,
        cancel = function() cancellations = cancellations + 1; return true end,
    })
    DirectScreen.keypressed("j")
    clipboard = HOST_CODE
    local pastedHost = click("paste")
    local enteredGuestAddress = DirectScreen.textinput(GUEST_ADDRESS)
    local startedGuest = DirectScreen.keypressed("return")
    local guestDraws = pcall(DirectScreen.draw)
    local copiedResponse = click("copy")
    local cancelledGuest = click("cancel")
    check("direct_screen_guest_pastes_host_code_and_returns_a_private_reply_code",
        pastedHost and enteredGuestAddress and startedGuest and guestDraws and copiedResponse
        and guestRequest and guestRequest.hostCode == HOST_CODE
        and guestRequest.address == GUEST_ADDRESS
        and DirectScreen.mode == "menu" and cancelledGuest)
    check("direct_screen_cancel_clears_only_the_code_it_placed_on_the_clipboard",
        clipboard == "" and cancellations == 1
        and DirectScreen.displayCode == nil and DirectScreen.hostCodeInput == ""
        and DirectScreen.responseInput == "" and DirectScreen.localAddress == "")

    DirectScreen.enter({
        readClipboard = function() return "not a code with spaces" end,
    })
    DirectScreen.keypressed("j")
    local invalidPaste = click("paste")
    check("direct_screen_rejects_malformed_clipboard_text_without_retaining_it",
        invalidPaste == false and DirectScreen.hostCodeInput == ""
        and DirectScreen.message:find("valid Direct code", 1, true) ~= nil)
    DirectScreen.leave()

    local inviteRequest, inviteCancelled
    DirectScreen.enter({
        inviteOnly = true,
        slot = 4,
        host = function(slot, name, address)
            inviteRequest = { slot = slot, name = name, address = address }
            return true, HOST_CODE
        end,
        cancel = function() inviteCancelled = true; return true end,
    })
    local inviteStartsAtHost = DirectScreen.mode == "host_setup"
        and DirectScreen.focused == "address"
    local enteredInviteAddress = DirectScreen.textinput(HOST_ADDRESS)
    local createdInvite = DirectScreen.keypressed("return")
    local cancelledInvite = DirectScreen.keypressed("escape")
    check("direct_screen_invite_only_starts_a_fresh_host_code_without_exposing_join_mode",
        inviteStartsAtHost and enteredInviteAddress and createdInvite and cancelledInvite
        and inviteCancelled == true and inviteRequest and inviteRequest.slot == 4
        and inviteRequest.address == HOST_ADDRESS
        and DirectScreen.displayCode == nil and DirectScreen.localAddress == "")
    DirectScreen.leave()

    local cleanupAttempts = 0
    DirectScreen.enter({
        inviteOnly = true,
        cancel = function()
            cleanupAttempts = cleanupAttempts + 1
            if cleanupAttempts == 1 then
                return false, "Direct cleanup could not be verified."
            end
            return true
        end,
    })
    local firstCleanup = DirectScreen.keypressed("escape")
    local retainedCleanupMode = DirectScreen.mode == "cleanup_failed"
        and DirectScreen.displayCode == nil and DirectScreen.localAddress == ""
    local secondCleanup = click("cancel")
    check("direct_screen_never_claims_cancellation_before_cleanup_is_verified",
        firstCleanup == false and retainedCleanupMode and secondCleanup == true
        and cleanupAttempts == 2 and DirectScreen.mode == "menu")
    DirectScreen.leave()
end

return Test
