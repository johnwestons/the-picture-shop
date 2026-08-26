local Suites = {}

local DOMAIN_SUITES = {
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
