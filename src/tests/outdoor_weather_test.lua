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

    local image=context.assets.get("loadingBayExterior")
    check("outdoor_parking_scene_is_registered_sprite",image~=nil)
    local draw,stencil=love.graphics.draw,love.graphics.setStencilTest
    local calls,clipped=0,false
    love.graphics.setStencilTest=function(mode,...) clipped=mode=="greater";return stencil(mode,...) end
    love.graphics.draw=function(sprite,x,y,rotation,sx,sy,...)
        if sprite==image then
            calls=calls+1
            check("outdoor_sprite_draw_is_clipped_and_scaled",clipped and sx>0 and sy>0)
        end
        return draw(sprite,x,y,rotation,sx,sy,...)
    end
    local okay,err=pcall(function()
        Weather.drawExterior(state,{progress=0},context.config,context.assets)
        check("outdoor_closed_door_does_not_draw_scene",calls==0)
        Weather.drawExterior(state,{progress=1},context.config,context.assets)
        check("outdoor_open_door_draws_one_sprite",calls==1)
    end)
    love.graphics.draw,love.graphics.setStencilTest=draw,stencil
    if not okay then error(err) end

    local directory=os.getenv("PICTURE_SHOP_EXTERIOR_CAPTURE_DIR")
    if directory then
        local door=context.world.bayDoor
        local oldProgress=door.progress
        local canvas=love.graphics.newCanvas(960,678)
        for _,scene in ipairs({{"day",1,12},{"half",.5,12},{"closed",0,12},{"night",1,23}}) do
            door.progress=scene[2];state.calendar.elapsed=state.calendar.secondsPerDay*scene[3]/24
            love.graphics.push("all");love.graphics.setCanvas({canvas,stencil=true});love.graphics.origin();love.graphics.clear(0,0,0,1)
            context.world.draw(context.assets,context.characterAssets,state,nil,nil,{})
            love.graphics.pop()
            local data=canvas:newImageData();local encoded=data:encode("png")
            local file=assert(io.open(directory.."/garage-"..scene[1]..".png","wb"))
            file:write(encoded:getString());file:close();encoded:release();data:release()
        end
        canvas:release();door.progress=oldProgress
    end
end

return Test
