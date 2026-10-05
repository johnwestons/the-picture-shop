local DirectScreen = require("src.screens.direct_screen")
local TitleScreen = require("src.screens.title_screen")

local Test = {}

local HOST_CODE = "TPS2H.ABC_def-123"
local RESPONSE_CODE = "TPS2R.XYZ_def-456"
local IPV4_CODE = "TPS1|8.8.8.8:40123|" .. string.rep("ab", 32)
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

    local ipv4Request, ipv4Cancellations
    local ipv4Clipboard = IPV4_CODE
    ipv4Cancellations = 0
    DirectScreen.enter({
        readClipboard = function() return ipv4Clipboard end,
        joinIpv4 = function(code, name)
            ipv4Request = { code = code, name = name }
            return true
        end,
        cancel = function() ipv4Cancellations = ipv4Cancellations + 1; return true end,
    })
    DirectScreen.keypressed("j")
    local pastedIpv4Code = click("paste")
    local joinedIpv4 = click("start")
    local ipv4Draws = pcall(DirectScreen.draw)
    check("direct_screen_ipv4_guest_uses_the_tps1_code_without_requiring_ipv6_or_reply_code",
        pastedIpv4Code and joinedIpv4 and ipv4Draws
        and ipv4Request and ipv4Request.code == IPV4_CODE
        and type(ipv4Request.name) == "string"
        and DirectScreen.mode == "connecting"
        and DirectScreen.hostCodeInput == ""
        and DirectScreen.localAddress == ""
        and DirectScreen.displayCode == nil)
    local cancelledIpv4 = click("cancel")
    check("direct_screen_ipv4_guest_cancel_is_available_while_awaiting_host_approval",
        cancelledIpv4 and ipv4Cancellations == 1 and DirectScreen.mode == "menu")
    DirectScreen.leave()

    DirectScreen.enter({})
    DirectScreen.keypressed("j")
    local typedIpv4Separators = DirectScreen.textinput("TPS1|8.8.8.8:40123|")
    check("direct_screen_ipv4_code_text_input_preserves_endpoint_separators",
        typedIpv4Separators
        and DirectScreen.hostCodeInput == "TPS1|8.8.8.8:40123|")
    DirectScreen.leave()

    local blockedHostInvocations = 0
    DirectScreen.enter({
        hostIpv4 = function() blockedHostInvocations = blockedHostInvocations + 1; return true end,
    })
    local blockedIpv4Host = click("hostIpv4")
    check("direct_screen_hides_ipv4_host_action_without_its_explicit_readiness_gate",
        blockedIpv4Host == false and blockedHostInvocations == 0)
    DirectScreen.leave()

    local ipv4HostStarts, enteredIpv4Shop, hostClipboard = 0, false, ""
    DirectScreen.enter({
        allowIpv4Host = true,
        slot = 2,
        readClipboard = function() return hostClipboard end,
        writeClipboard = function(value) hostClipboard = value; return true end,
        hostIpv4 = function(slot, name)
            ipv4HostStarts = ipv4HostStarts + 1
            return slot == 2 and type(name) == "string"
        end,
        enterShop = function() enteredIpv4Shop = true; return true end,
        cancel = function() return true end,
    })
    local startedIpv4Host = click("hostIpv4")
    local waitingForMapping = DirectScreen.mode == "ipv4_mapping"
    local showedIpv4Invitation = DirectScreen.showIpv4HostInvitation(IPV4_CODE)
    local copiedIpv4HostCode = click("copy")
    local ipv4HostDraws = pcall(DirectScreen.draw)
    local enteredIpv4ShopFromScreen = click("start")
    check("direct_screen_ipv4_host_waits_for_mapping_then_shares_an_expiring_invite",
        startedIpv4Host and waitingForMapping and showedIpv4Invitation
        and copiedIpv4HostCode and ipv4HostDraws and enteredIpv4ShopFromScreen
        and ipv4HostStarts == 1 and enteredIpv4Shop
        and DirectScreen.mode == "menu" and hostClipboard == "")
    DirectScreen.leave()

    local manualDetails = {
        internalAddress = "192.168.1.24",
        internalPort = 40127,
        externalAddress = "8.8.8.8",
        externalPort = 40127,
        lifetimeSeconds = 900,
    }
    local manualStarts, manualConfirms, manualCancels = 0, 0, 0
    local manualCleanupStarted, manualCleanupAcknowledged = false, false
    DirectScreen.enter({
        allowIpv4Host = true,
        slot = 3,
        hostIpv4Manual = function(slot, name, address)
            manualStarts = manualStarts + 1
            return slot == 3 and type(name) == "string"
                and address == "8.8.8.8", manualDetails
        end,
        confirmIpv4Manual = function()
            manualConfirms = manualConfirms + 1
            return true
        end,
        cancelManualWithRule = function()
            manualCleanupStarted = true
            return false, "Remove the manual UDP rule."
        end,
        manualCleanupInfo = function()
            return manualCleanupStarted and manualDetails or nil
        end,
        acknowledgeManualCleanup = function()
            manualCleanupAcknowledged = true
            return true
        end,
        cancel = function()
            manualCancels = manualCancels + 1
            if not manualCleanupAcknowledged then
                manualCleanupStarted = true
                return false, "Remove the manual UDP rule."
            end
            return true
        end,
    })
    local manualChoice = DirectScreen.keypressed("m")
    local typedWan = DirectScreen.textinput("8.8.8.8")
    local manualStarted = DirectScreen.keypressed("return")
    local invitationWithheld = DirectScreen.displayCode == nil
        and DirectScreen.mode == "ipv4_manual_rule"
    local ruleConfirmed = click("manualAdded")
    local manualInviteShown = DirectScreen.showManualIpv4HostInvitation(
        IPV4_CODE, manualDetails)
    local manualInviteDraws = pcall(DirectScreen.draw)
    local manualExitBlocked = click("cancel")
    local exactCleanupShown = DirectScreen.mode == "ipv4_manual_cleanup"
        and DirectScreen.manualDetails.internalAddress == manualDetails.internalAddress
        and DirectScreen.manualDetails.externalPort == manualDetails.externalPort
    local manualCleanupAck = click("manualCleanupAck")
    check("direct_screen_manual_ipv4_withholds_invite_until_confirmation_and_requires_exact_rule_cleanup",
        manualChoice and typedWan and manualStarted and invitationWithheld
        and ruleConfirmed and manualInviteShown and manualInviteDraws
        and manualExitBlocked == false and exactCleanupShown
        and manualCleanupAck and manualStarts == 1 and manualConfirms == 1
        and manualCleanupStarted and manualCleanupAcknowledged
        and manualCancels == 2 and DirectScreen.mode == "menu")
    DirectScreen.leave()

    local manualCancelMarked, manualCancelAck = false, false
    DirectScreen.enter({
        allowIpv4Host = true,
        hostIpv4Manual = function() return true, manualDetails end,
        cancelManualWithRule = function()
            manualCancelMarked = true
            return false, "Remove the manual UDP rule."
        end,
        manualCleanupInfo = function()
            return manualCancelMarked and manualDetails or nil
        end,
        acknowledgeManualCleanup = function()
            manualCancelAck = true
            return true
        end,
        cancel = function() return manualCancelAck end,
    })
    DirectScreen.keypressed("m")
    DirectScreen.textinput("8.8.8.8")
    local pendingManualSetup = DirectScreen.keypressed("return")
    local askedBeforeCancel = DirectScreen.keypressed("escape")
    local manualCancelKeptObligation = click("manualRuleCleanup")
    local manualCancelPrompted = DirectScreen.mode == "ipv4_manual_cleanup"
        and DirectScreen.manualDetails.externalPort == manualDetails.externalPort
    local manualCancelAcknowledged = click("manualCleanupAck")
    check("direct_screen_manual_setup_cancel_records_a_rule_added_before_inviting",
        pendingManualSetup and askedBeforeCancel
        and manualCancelKeptObligation == false and manualCancelPrompted
        and manualCancelAcknowledged and manualCancelMarked and manualCancelAck
        and DirectScreen.displayCode == nil and DirectScreen.mode == "menu")
    DirectScreen.leave()

    local invalidatedManualCancelled = false
    DirectScreen.enter({
        allowIpv4Host = true,
        hostIpv4Manual = function() return true, manualDetails end,
        cancel = function()
            invalidatedManualCancelled = true
            return true
        end,
    })
    DirectScreen.keypressed("m")
    DirectScreen.textinput("8.8.8.8")
    local invalidatedManualStarted = DirectScreen.keypressed("return")
    local invalidationPrompted = DirectScreen.showManualSetupInvalidated(false)
    local invalidationKeepsDetails = DirectScreen.mode == "ipv4_manual_cancel"
        and DirectScreen.manualDetails.externalPort == manualDetails.externalPort
        and DirectScreen.message:find("network changed", 1, true) ~= nil
        and DirectScreen.message:find("not yet verified", 1, true) ~= nil
    local invalidatedManualDiscarded = click("manualDiscard")
    check("direct_screen_manual_setup_route_change_asks_about_rule_and_keeps_cleanup_details",
        invalidatedManualStarted and invalidationPrompted
        and invalidationKeepsDetails and invalidatedManualDiscarded
        and invalidatedManualCancelled and DirectScreen.mode == "menu")
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
