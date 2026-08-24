local Suites = {}

local DOMAIN_SUITES = {
    require("src.tests.asset_pack_test"),
    require("src.tests.pallet_state_test"),
    require("src.tests.save_contract_test"),
    require("src.tests.input_status_test"),
}

function Suites.runDomain(context, check)
    for _, suite in ipairs(DOMAIN_SUITES) do suite.run(context, check) end
end

function Suites.verifyAuditCoverage(passed, check)
    require("src.tests.audit_coverage").run(passed, check)
end

return Suites
