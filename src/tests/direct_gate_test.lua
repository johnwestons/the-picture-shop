local DirectGate = require("src.net.direct_gate")

local Test = {}

local function environment(value)
    return function(name)
        return name == "PICTURE_SHOP_ENABLE_DIRECT_TEST" and value or nil
    end
end

function Test.run(_, check)
    local production = { productionReady = true }
    local engineering = { productionReady = false, engineeringOnly = true,
        engineeringReady = true, marker = "candidate" }
    local unavailable = { productionReady = false, engineeringOnly = true,
        engineeringReady = false }

    check("direct_gate_accepts_production_provider_without_test_flag",
        DirectGate.mode(production, environment(nil)) == "production"
        and DirectGate.enabled(production, environment(nil)))
    check("direct_gate_keeps_engineering_provider_closed_by_default",
        DirectGate.mode(engineering, environment(nil)) == nil
        and DirectGate.provider(engineering, environment(nil)) == nil)
    local proxy, mode = DirectGate.provider(engineering, environment("1"))
    check("direct_gate_requires_explicit_engineering_environment_flag",
        mode == "engineering" and proxy ~= nil and proxy.productionReady == true
        and proxy.directTestOnly == true and proxy.marker == "candidate"
        and engineering.productionReady == false)
    check("direct_gate_rejects_unready_engineering_provider",
        DirectGate.enabled(unavailable, environment("1")) == false)
end

return Test
