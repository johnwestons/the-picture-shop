local MultiplayerHud = require("src.screens.multiplayer_hud")

local Test = {}

local function directHost(overrides)
    local info = {
        mode = "host",
        networkKind = "direct",
        canManage = true,
        canInvite = true,
        playerCount = 2,
        pendingJoins = {
            { requestId = 41, name = "Waiting Worker", character = "rabbit-worker" },
        },
        connectedGuests = {
            { playerId = 2, name = "Joined Worker" },
        },
    }
    for key, value in pairs(overrides or {}) do info[key] = value end
    return info
end

local function lanGuest(overrides)
    local info = {
        mode = "client",
        networkKind = "lan",
        status = "3/4 workers connected",
        playerCount = 3,
        localPlayerId = 3,
        rtt = 47.6,
        players = {
            { playerId = 1, name = "PC Host", isHost = true },
            { playerId = 2, name = "Press Worker" },
            { playerId = 3, name = "Android Worker", isLocal = true },
        },
        workshopResources = {
            { resourceId = "cutter", occupied = true, ownerPlayerId = 2 },
            { resourceId = "pallet_jack", occupied = false },
        },
    }
    for key, value in pairs(overrides or {}) do info[key] = value end
    return info
end

local function click(kind, identifier, info)
    local x, y = MultiplayerHud.buttonCenter(kind, identifier, info)
    if not x then return false end
    return MultiplayerHud.mousepressed(x, y, 1, info)
end

function Test.run(_, check)
    local host = directHost()
    MultiplayerHud.reset()
    check("multiplayer_hud_direct_host_can_open_with_p",
        not MultiplayerHud.isOpen()
        and MultiplayerHud.keypressed("p", host) == true
        and MultiplayerHud.isOpen())

    local layout = MultiplayerHud.layout(host)
    check("multiplayer_hud_uses_mobile_sized_actions_and_self_entered_name_note",
        layout.open and layout.toggle.height >= 40
        and layout.pending[1].approve.height >= 40
        and layout.pending[1].deny.height >= 40
        and layout.guests[1].remove.height >= 40
        and layout.invite.height >= 38
        and layout.note:find("self%-entered") ~= nil)

    local invite = click("invite", nil, host)
    check("multiplayer_hud_invite_returns_no_player_or_connection_data",
        type(invite) == "table" and invite.kind == "invite"
        and invite.requestId == nil and invite.playerId == nil
        and invite.name == nil and invite.peer == nil)

    local approve = click("approve", 41, host)
    check("multiplayer_hud_approve_returns_only_an_opaque_request_id",
        type(approve) == "table" and approve.kind == "approve"
        and approve.requestId == 41 and approve.playerId == nil
        and approve.name == nil and approve.peer == nil)

    local deny = click("deny", 41, host)
    check("multiplayer_hud_deny_returns_only_an_opaque_request_id",
        type(deny) == "table" and deny.kind == "deny"
        and deny.requestId == 41 and deny.playerId == nil
        and deny.name == nil and deny.peer == nil)

    local firstRemove = click("remove", 2, host)
    local secondRemove = click("remove", 2, host)
    check("multiplayer_hud_remove_requires_a_second_confirmation_tap",
        firstRemove == true and type(secondRemove) == "table"
        and secondRemove.kind == "remove" and secondRemove.playerId == 2
        and secondRemove.requestId == nil and secondRemove.name == nil
        and secondRemove.peer == nil)

    click("remove", 2, host)
    local approveAfterRemove = click("approve", 41, host)
    local removeAfterOtherAction = click("remove", 2, host)
    check("multiplayer_hud_other_action_cancels_remove_confirmation",
        type(approveAfterRemove) == "table" and removeAfterOtherAction == true)

    local panel = MultiplayerHud.layout(host).panel
    check("multiplayer_hud_panel_background_consumes_clicks",
        MultiplayerHud.mousepressed(panel.x + 10, panel.y + 10, 1, host) == true)
    local outside = MultiplayerHud.mousepressed(20, 620, 1, host)
    check("multiplayer_hud_outside_click_closes_and_passes_through",
        outside == false and not MultiplayerHud.isOpen())

    check("multiplayer_hud_direct_host_toggle_hit_target_opens",
        click("toggle", nil, host) == true and MultiplayerHud.isOpen())
    check("multiplayer_hud_escape_closes_the_panel",
        MultiplayerHud.keypressed("escape", host) == true
        and not MultiplayerHud.isOpen())

    local guest = lanGuest()
    MultiplayerHud.reset()
    check("multiplayer_hud_lan_guest_can_open_read_only_session_panel",
        MultiplayerHud.keypressed("p", guest) == true and MultiplayerHud.isOpen())
    local guestLayout = MultiplayerHud.layout(guest)
    check("multiplayer_hud_guest_panel_identifies_authority_roster_link_and_busy_control",
        guestLayout.viewable and not guestLayout.manageable
        and guestLayout.open and guestLayout.toggle.height >= 40
        and #guestLayout.statusPlayers == 3
        and guestLayout.statusPlayers[1].badge == "HOST"
        and guestLayout.statusPlayers[3].badge == "YOU"
        and guestLayout.summary.authority:find("HOST DEVICE") ~= nil
        and guestLayout.summary.connection == "CONNECTED • 48 MS • GOOD"
        and guestLayout.summary.control == "Press Worker USING • POLAR CUTTER"
        and guestLayout.pending[1] == nil and guestLayout.guests[1] == nil
        and guestLayout.invite == nil)
    check("multiplayer_hud_guest_panel_has_no_management_actions",
        MultiplayerHud.buttonCenter("approve", 1, guest) == nil
        and MultiplayerHud.buttonCenter("deny", 1, guest) == nil
        and MultiplayerHud.buttonCenter("remove", 2, guest) == nil
        and MultiplayerHud.buttonCenter("invite", nil, guest) == nil)

    local waiting = MultiplayerHud.statusSummary(lanGuest({
        rtt = 181,
        activeResourceId = "cutter",
        pendingActivity = { kind = "workshop_acquire", resourceId = "windmill" },
    }))
    local urgent = MultiplayerHud.statusSummary(lanGuest({
        pendingActivity = { kind = "urgent_safety", resourceId = "cutter" },
    }))
    check("multiplayer_hud_guest_panel_prioritizes_pending_host_feedback",
        waiting.connection == "CONNECTED • 181 MS • SLOW"
        and waiting.control == "REQUESTING WINDMILL • WAITING FOR HOST"
        and urgent.control == "URGENT SAFETY SENT • WAITING FOR HOST • POLAR CUTTER")

    local lanHost = lanGuest({ mode = "host", localPlayerId = 1 })
    MultiplayerHud.reset()
    check("multiplayer_hud_lan_host_gets_read_only_status_without_direct_controls",
        click("toggle", nil, lanHost) == true
        and MultiplayerHud.layout(lanHost).viewable
        and not MultiplayerHud.layout(lanHost).manageable
        and MultiplayerHud.layout(lanHost).summary.authority:find("THIS DEVICE") ~= nil)

    local deniedModes = { { mode = "offline" }, {}, nil }
    local denied = true
    for _, info in ipairs(deniedModes) do
        MultiplayerHud.reset()
        local deniedLayout = MultiplayerHud.layout(info)
        denied = denied and not deniedLayout.viewable and not deniedLayout.manageable
            and deniedLayout.toggle == nil
            and MultiplayerHud.keypressed("p", info) == false
            and MultiplayerHud.mousepressed(820, 120, 1, info) == false
            and not MultiplayerHud.isOpen()
    end
    check("multiplayer_hud_offline_and_invalid_modes_have_no_session_panel", denied)

    local fullHost = directHost({ canInvite = false })
    MultiplayerHud.reset()
    MultiplayerHud.open(fullHost)
    check("multiplayer_hud_hides_invite_when_direct_capacity_is_unavailable",
        MultiplayerHud.layout(fullHost).invite == nil
        and MultiplayerHud.buttonCenter("invite", nil, fullHost) == nil)

    MultiplayerHud.reset()
    MultiplayerHud.open(host)
    local hostOnly = directHost({
        pendingJoins = {},
        connectedGuests = {
            { playerId = 1, name = "Host" },
            { playerId = 3, name = "Guest Three" },
        },
    })
    local hostOnlyLayout = MultiplayerHud.layout(hostOnly)
    check("multiplayer_hud_never_offers_to_remove_the_host",
        #hostOnlyLayout.guests == 1 and hostOnlyLayout.guests[1].playerId == 3
        and MultiplayerHud.buttonCenter("remove", 1, hostOnly) == nil)

    MultiplayerHud.reset()
end

return Test
