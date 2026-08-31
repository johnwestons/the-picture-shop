local Suites = {}

local DOMAIN_SUITES = {
    require("src.tests.ip_scope_test"),
    require("src.tests.ipv6_address_test"),
    require("src.tests.gateway_discovery_test"),
    require("src.tests.pcp_test"),
    require("src.tests.nat_pmp_test"),
    require("src.tests.reachability_test"),
    require("src.tests.upnp_igd_test"),
    require("src.tests.direct_invite_test"),
    require("src.tests.direct_opening_code_test"),
    require("src.tests.direct_opening_test"),
    require("src.tests.direct_bridge_test"),
    require("src.tests.transport_ipv6_bridge_test"),
    require("src.tests.direct_connection_test"),
    require("src.tests.direct_transport_test"),
    require("src.tests.direct_session_test"),
    require("src.tests.network_protocol_test"),
    require("src.tests.multiplayer_session_test"),
    require("src.tests.workshop_authority_test"),
    require("src.tests.multiplayer_hud_test"),
    require("src.tests.lan_screen_test"),
    require("src.tests.direct_screen_test"),
    require("src.tests.direct_composite_transport_test"),
    require("src.tests.direct_composite_session_integration_test"),
    require("src.tests.transport_enet_test"),
    require("src.tests.interaction_test"),
    require("src.tests.player_controller_test"),
    require("src.tests.customer_motion_test"),
    require("src.tests.asset_pack_test"),
    require("src.tests.sound_test"),
    require("src.tests.pallet_state_test"),
    require("src.tests.save_contract_test"),
    require("src.tests.input_status_test"),
    require("src.tests.machine_fleet_test"),
    require("src.tests.press_economics_test"),
    require("src.tests.windmill_integration_test"),
}

function Suites.runDomain(context, check)
    for _, suite in ipairs(DOMAIN_SUITES) do suite.run(context, check) end
end

function Suites.verifyAuditCoverage(passed, check)
    require("src.tests.audit_coverage").run(passed, check)
end

return Suites
