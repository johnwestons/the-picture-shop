local Reconnect = require("src.net.lan_reconnect")

local Test = {}

function Test.run(_, check)
    local reconnect = Reconnect.new({ delays = { 0, 1, 2 } })
    local missing, missingError = reconnect:begin("lost")
    check("lan_reconnect_requires_a_remembered_public_target",
        not missing and missingError:find("No previous", 1, true) ~= nil)

    local remembered = reconnect:remember("192.168.1.50:22122", "Android Worker")
    local began = reconnect:begin("Wi-Fi changed")
    local first = reconnect:update(0)
    check("lan_reconnect_starts_with_an_immediate_fresh_attempt",
        remembered and began and first
        and first.address == "192.168.1.50:22122"
        and first.playerName == "Android Worker"
        and first.attempt == 1 and first.maxAttempts == 3
        and reconnect:update(10) == nil)

    local rescheduled = reconnect:failed("host offline")
    local waiting = reconnect:snapshot()
    check("lan_reconnect_uses_bounded_backoff_after_failure",
        rescheduled and waiting.active and waiting.state == "waiting"
        and waiting.nextIn == 1 and reconnect:update(0.5) == nil)
    local second = reconnect:update(0.5)
    check("lan_reconnect_emits_each_attempt_once",
        second and second.attempt == 2 and reconnect:update(10) == nil)

    reconnect:failed("still offline")
    reconnect:update(2)
    local continued, exhaustedMessage = reconnect:failed("still offline")
    local exhausted = reconnect:snapshot()
    check("lan_reconnect_exhausts_into_manual_discovery_fallback",
        not continued and exhaustedMessage:find("discovered shop", 1, true) ~= nil
        and not exhausted.active and exhausted.state == "exhausted"
        and exhausted.attempt == 3)

    local detached = exhausted.target
    detached.address = "tampered"
    check("lan_reconnect_snapshot_does_not_expose_mutable_target_state",
        reconnect:snapshot().target.address == "192.168.1.50:22122"
        and reconnect:snapshot().target.sessionId == nil
        and reconnect:snapshot().target.leaseId == nil
        and reconnect:snapshot().target.save == nil)

    reconnect:begin("again")
    reconnect:update(0)
    local succeeded = reconnect:succeeded()
    check("lan_reconnect_success_stops_retrying_but_remembers_host",
        succeeded and not reconnect:isActive()
        and reconnect:snapshot().state == "idle"
        and reconnect:snapshot().target.address == "192.168.1.50:22122")

    reconnect:begin("cancel")
    reconnect:cancel(true)
    check("lan_reconnect_cancel_can_forget_the_previous_host",
        not reconnect:isActive() and reconnect:snapshot().target == nil)
end

return Test
