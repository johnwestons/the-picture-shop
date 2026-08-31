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

    local deniedModes = {
        directHost({ mode = "client" }),
        directHost({ networkKind = "lan" }),
        directHost({ canManage = false }),
    }
    local denied = true
    for _, info in ipairs(deniedModes) do
        MultiplayerHud.reset()
        local deniedLayout = MultiplayerHud.layout(info)
        denied = denied and not deniedLayout.manageable
            and deniedLayout.toggle == nil
            and MultiplayerHud.keypressed("p", info) == false
            and MultiplayerHud.mousepressed(820, 120, 1, info) == false
            and not MultiplayerHud.isOpen()
    end
    check("multiplayer_hud_guest_lan_and_disabled_hosts_have_no_controls", denied)

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
