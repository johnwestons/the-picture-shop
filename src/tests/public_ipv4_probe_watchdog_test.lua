local Watchdog = require("src.net.public_ipv4_probe_watchdog")

local Test = {}

local function expiresAt(state, seconds, reason)
    local watchdog = Watchdog.new(120)
    return watchdog and watchdog:transition(state, 10)
        and watchdog:timeout(10 + seconds - 0.001) == nil
        and watchdog:timeout(10 + seconds) == reason
end

function Test.run(_, check)
    check("public_ipv4_probe_watchdog_enforces_host_phase_deadlines",
        expiresAt("host_initial_exchange", 30, "challenge_failed")
        and expiresAt("host_waiting_renewal", 150, "renewal_failed")
        and expiresAt("host_renewed_exchange", 30, "challenge_failed"))

    check("public_ipv4_probe_watchdog_enforces_guest_phase_deadlines",
        expiresAt("guest_connected", 30, "challenge_failed")
        and expiresAt("guest_waiting_renewal", 180, "challenge_failed")
        and expiresAt("guest_renewed_exchange", 30, "challenge_failed"))

    local fixed = Watchdog.new(120)
    local idempotent = fixed:transition("host_initial_exchange", 0)
        and fixed:transition("host_initial_exchange", 20)
        and fixed:timeout(29.999) == nil
        and fixed:timeout(30) == "challenge_failed"
    check("public_ipv4_probe_watchdog_duplicate_progress_cannot_extend_deadline",
        idempotent)

    local exact = Watchdog.new(120)
    local late = Watchdog.new(120)
    check("public_ipv4_probe_watchdog_progress_cannot_cross_expired_boundary",
        exact:transition("host_initial_exchange", 0)
        and not exact:transition("host_waiting_renewal", 30)
        and exact:timeout(30) == "challenge_failed"
        and late:transition("guest_connected", 0)
        and not late:transition("guest_waiting_renewal", 30.001)
        and late:timeout(30.001) == "challenge_failed")

    local forward = Watchdog.new(120)
    local transitioned = forward:transition("host_initial_exchange", 0)
        and forward:timeout(29) == nil
        and forward:transition("host_waiting_renewal", 29)
        and forward:timeout(178.999) == nil
        and forward:timeout(179) == "renewal_failed"
    check("public_ipv4_probe_watchdog_forward_progress_gets_one_fresh_deadline",
        transitioned)

    local cleared = Watchdog.new(120)
    local clearPass = cleared:transition("guest_connected", 0)
        and cleared:transition("guest_waiting_close", 1)
        and cleared:timeout(999) == nil
    cleared:transition("guest_connected", 1000)
    cleared:clear()
    check("public_ipv4_probe_watchdog_unwatched_and_finished_states_clear",
        clearPass and cleared:timeout(9999) == nil)

    local backward = Watchdog.new(120)
    local backwardTransition = Watchdog.new(120)
    local invalid = Watchdog.new(120)
    check("public_ipv4_probe_watchdog_invalid_or_backward_time_fails_closed",
        backward:transition("host_initial_exchange", 10)
        and backward:timeout(9) == "challenge_failed"
        and backwardTransition:transition("host_initial_exchange", 10)
        and not backwardTransition:transition("host_waiting_renewal", 9)
        and backwardTransition:timeout(9) == "challenge_failed"
        and invalid:transition("guest_connected", 0)
        and invalid:timeout(0 / 0) == "challenge_failed"
        and not invalid:transition("guest_waiting_renewal", 1)
        and invalid:timeout(1) == "challenge_failed")

    local host = Watchdog.new(120)
    local guest = Watchdog.new(120)
    local happy = host:transition("host_initial_exchange", 0)
        and host:transition("host_waiting_renewal", 12)
        and host:transition("host_renewed_exchange", 75)
        and host:transition("cleaning", 80)
        and host:timeout(999) == nil
        and guest:transition("guest_connected", 0)
        and guest:transition("guest_waiting_renewal", 12)
        and guest:transition("guest_renewed_exchange", 75)
        and guest:transition("guest_waiting_close", 80)
        and guest:timeout(999) == nil
    check("public_ipv4_probe_watchdog_happy_host_and_guest_sequences_clear",
        happy)

    check("public_ipv4_probe_watchdog_rejects_invalid_lease_contracts",
        Watchdog.new(0) == nil and Watchdog.new(3601) == nil
        and Watchdog.new("120") == nil)

    local packagedRuntime = love.filesystem.getInfo("mobile-build.json") ~= nil
    local probePath = "tools/probes/public_ipv4_mapping/main.lua"
    local probeChunk, probeParseError
    if not packagedRuntime then probeChunk, probeParseError = loadfile(probePath) end
    check("public_ipv4_probe_watchdog_probe_launcher_source_parses_or_stays_out_of_runtime",
        packagedRuntime and love.filesystem.getInfo(probePath) == nil
        or type(probeChunk) == "function" and probeParseError == nil)
end

return Test
