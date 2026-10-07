local Calendar = require("src.business_calendar")
local Weather = require("src.outdoor_weather")

local Test = {}

function Test.run(context, check)
    local _, total = Calendar.monthlyCharges()
    local rent = context.config.businessCalendar.monthlyExpenses.rent
    check("warehouse_rent_uses_small_industrial_lease_estimate", rent == 3500 and total == 3950)

    check("outdoor_daylight_tracks_game_clock", Weather.daylightForHour(2) == 0
        and Weather.daylightForHour(12) == 1 and Weather.daylightForHour(22) == 0)
    local dawn, dusk = Weather.daylightForHour(6), Weather.daylightForHour(19)
    check("outdoor_daylight_transitions_smoothly_at_dawn_and_dusk",
        dawn > 0 and dawn < 1 and dusk > 0 and dusk < 1)

    local rainyDay, dryDay, rainyDays = nil, nil, 0
    for day = 0, 120 do
        local conditions = Weather.conditionsForDay(day)
        if conditions.rain then
            rainyDays = rainyDays + 1
            if not rainyDay then rainyDay = conditions end
        end
        if not conditions.rain and not dryDay then dryDay = conditions end
    end
    local varied = rainyDay and dryDay and rainyDays >= 20 and rainyDays <= 48
    if rainyDay then
        local repeated = Weather.conditionsForDay(rainyDay.day)
        local _, raining = Weather.sampleAtHours(rainyDay.day * 24 + rainyDay.rainStart + 0.1)
        local _, ended = Weather.sampleAtHours(rainyDay.day * 24 + rainyDay.rainEnd + 0.1)
        varied = varied and repeated.rain and repeated.rainStart == rainyDay.rainStart
            and repeated.rainEnd == rainyDay.rainEnd and raining and not ended
    end
    check("outdoor_rain_is_deterministic_but_varies_by_day_and_window", varied)

    local state = context.State.new()
    state.calendar.totalDays = 12
    state.calendar.elapsed = state.calendar.secondsPerDay * 12 / 24
    local gameDaylight, _, _, gameHour = Weather.sample(state)
    check("outdoor_weather_reads_the_saved_game_clock",
        math.abs(gameHour - 12) < 0.001 and gameDaylight == 1)
end

return Test
