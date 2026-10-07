local FocusGrace = require("src.net.focus_grace")

local Test = {}

function Test.run(_, check)
    local now = 10
    local grace = FocusGrace.new({
        clock = function() return now end,
        timeoutSeconds = 120,
    })

    check("focus_grace_does_not_track_until_focus_is_lost",
        not grace:isTracking() and not grace:isExpired() and grace:elapsed() == nil)

    check("focus_grace_starts_once_and_keeps_original_loss_time",
        grace:start() and not grace:start() and grace:elapsed() == 0)

    now = 129.9
    check("focus_grace_keeps_session_before_two_minutes",
        not grace:isExpired() and math.abs(grace:elapsed() - 119.9) < 0.001)

    now = 130
    check("focus_grace_keeps_session_at_exactly_two_minutes",
        not grace:isExpired())

    now = 130.01
    check("focus_grace_expires_only_after_two_minutes",
        grace:isExpired())

    check("focus_grace_resume_clears_the_pending_timeout",
        grace:clear() and not grace:isTracking() and not grace:isExpired())

    now = 500
    grace:start()
    now = 621
    check("focus_grace_tracks_a_new_background_period",
        grace:isExpired() and grace:clear() and not grace:isExpired())
end

return Test
