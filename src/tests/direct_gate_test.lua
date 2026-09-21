local DirectGate = require("src.net.direct_gate")

local Test = {}

function Test.run(_, check)
    local production = { productionReady = true }
    local engineering = { productionReady = false, engineeringOnly = true,
        engineeringReady = true, marker = "candidate" }
    local unavailable = { productionReady = false, engineeringOnly = true,
        engineeringReady = false }

    check("direct_gate_accepts_production_provider_without_test_flag",
        DirectGate.mode(production) == "production"
        and DirectGate.enabled(production))
    local proxy, mode = DirectGate.provider(engineering)
    check("direct_gate_exposes_verified_engineering_provider_by_default",
        mode == "engineering" and proxy ~= nil and proxy.productionReady == true
        and proxy.directTestOnly == true and proxy.marker == "candidate"
        and engineering.productionReady == false)
    check("direct_gate_rejects_unready_engineering_provider",
        DirectGate.enabled(unavailable) == false)
end

return Test
