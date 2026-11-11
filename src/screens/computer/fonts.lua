-- Typography approved for the job desk, deliberately separate from global UI fonts.
local Fonts = {}
local cache = {}
function Fonts.get(kind, size)
    local key = kind .. size
    if not cache[key] then
        if kind == 'typewriter' then
            cache[key] = love.graphics.newFont('assets/fonts/CourierPrime-Regular.ttf', size)
        elseif kind == 'clock' then
            cache[key] = love.graphics.newFont('assets/fonts/VT323-Regular.ttf', size)
        else
            cache[key] = love.graphics.newFont(size)
        end
        if kind == 'typewriter' then cache[key]:setFallbacks(Fonts.get('sans', size)) end
        -- The whole monitor is scaled on phones; keep text smooth under that fit.
        cache[key]:setFilter('linear', 'linear')
    end
    return cache[key]
end
return Fonts
