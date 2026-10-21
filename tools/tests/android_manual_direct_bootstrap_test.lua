local Test = {}

function Test.run(root, check)
    local realLove, realRequire = love, require
    local mainPath = root .. "/tools/probes/android_manual_direct/main.lua"
    local function runCandidate(changes, failStage)
        local provider = { available = true, candidateReady = true,
            engineeringReady = true, engineeringOnly = true, productionReady = false }
        for name, value in pairs(changes or {}) do provider[name] = value end
        local observed = { provider = provider, drawn = {}, bootstrap = 0, started = 0 }
        _G.love = {
            graphics = {
                clear = function() end, setColor = function() end,
                getDimensions = function() return 960, 678 end,
                printf = function(text) observed.drawn[#observed.drawn + 1] = text end,
            },
            event = { quit = function() observed.quit = true end },
        }
        _G.require = function(name)
            if name == "src.net.crypto_native" then
                if failStage == "native" then error("private-load-detail") end
                return provider
            elseif name == "tools.probes.android_manual_direct.ui_setup" then
                return { install = function()
                    if failStage == "setup" then error("private-setup-detail") end
                end }
            elseif name == "src.bootstrap" then
                return { install = function()
                    observed.bootstrap = observed.bootstrap + 1
                    love.load = function()
                        if failStage == "load" then error("private-startup-detail") end
                        observed.started = observed.started + 1
                    end
                end }
            end
            error("Unexpected module load: " .. name)
        end
        local ok, message = pcall(function()
            assert(loadfile(mainPath))()
            love.load()
            if love.draw then love.draw() end
        end)
        _G.love, _G.require = realLove, realRequire
        assert(ok, message)
        observed.text = table.concat(observed.drawn, "\n")
        return observed
    end

    local valid = runCandidate()
    check("manual_direct_verified_candidate_installs_real_bootstrap_once",
        valid.provider.productionReady == true and valid.bootstrap == 1 and valid.started == 1)
    for _, field in ipairs({ "available", "candidateReady", "engineeringReady", "engineeringOnly" }) do
        local rejected = runCandidate({ [field] = false })
        check("manual_direct_rejects_missing_" .. field,
            rejected.provider.productionReady == false and rejected.bootstrap == 0
            and rejected.text:find("native_candidate_unavailable", 1, true) ~= nil)
    end
    local missing = runCandidate(nil, "native")
    check("manual_direct_missing_native_has_visible_sanitized_failure",
        missing.bootstrap == 0 and missing.text:find("native_candidate_unavailable", 1, true)
        and not missing.text:find("private", 1, true))
    local setup = runCandidate(nil, "setup")
    check("manual_direct_failed_bootstrap_revokes_opt_in",
        setup.provider.productionReady == false and setup.bootstrap == 0
        and setup.text:find("bootstrap_unavailable", 1, true)
        and not setup.text:find("private", 1, true))
    local load = runCandidate(nil, "load")
    check("manual_direct_failed_game_load_is_visible_and_revokes_opt_in",
        load.provider.productionReady == false and load.started == 0
        and load.text:find("game_startup_failed", 1, true)
        and not load.text:find("private", 1, true))

    local entered, detected, parsed = nil, {}, {}
    local realGetenv = os.getenv
    local directScreen = { enter = function(options) entered = options; return "entered" end }
    _G.require = function(name)
        if name == "src.screens.direct_screen" then return directScreen end
        if name == "src.net.direct_opening_code" then
            return { parseHost = function(code)
                parsed[#parsed + 1] = code
                if code == "valid-host" then return { address = "peer-address" } end
            end }
        end
        if name == "src.net.local_ipv6" then
            return {
                detect = function(options)
                    detected[#detected + 1] = options
                    return "local-address"
                end,
                messageFor = function() return "No usable IPv6 address." end,
            }
        end
        error("Unexpected module load: " .. name)
    end
    local ok, message = pcall(function()
        local setupModule = assert(loadfile(root .. "/tools/probes/android_manual_direct/ui_setup.lua"))()
        setupModule.install()
        check("manual_direct_install_performs_no_address_detection", #detected == 0)
        local options = { onCancel = function() end }
        check("manual_direct_preserves_full_game_callbacks_and_does_not_mutate_caller",
            directScreen.enter(options) == "entered" and entered.onCancel == options.onCancel
            and options.detectLocalIpv6 == nil and #detected == 0)
        check("manual_direct_host_detection_waits_for_user_callback",
            entered.detectLocalIpv6(nil) == "local-address" and #detected == 1
            and detected[1].peerAddress == nil)
        check("manual_direct_guest_uses_parsed_peer_route",
            entered.detectLocalIpv6("valid-host") == "local-address" and #detected == 2
            and detected[2].peerAddress == "peer-address")
        check("manual_direct_invalid_invite_does_not_detect_or_connect",
            entered.detectLocalIpv6("invalid") == nil and #detected == 2)
        local explicitSelector = function() return "caller-address" end
        directScreen.enter({ detectLocalIpv6 = explicitSelector })
        check("manual_direct_respects_explicit_caller_selector",
            entered.detectLocalIpv6 == explicitSelector
            and entered.detectLocalIpv6() == "caller-address" and #detected == 2)
        os.getenv = function(name)
            if name == "PICTURE_SHOP_SMOKE" then return "1" end
            return realGetenv(name)
        end
        directScreen.enter({})
        check("manual_direct_smoke_does_not_inject_machine_route_selection",
            entered.detectLocalIpv6 == nil and #detected == 2)
    end)
    _G.require = realRequire
    os.getenv = realGetenv
    assert(ok, message)
end

return Test
