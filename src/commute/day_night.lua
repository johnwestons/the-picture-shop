-- Calendar-driven outdoor light shared by both commute cameras.
local Light={}
local pi=math.pi
local function clamp(v)return math.max(0,math.min(1,v))end
local function smooth(v)v=clamp(v);return v*v*(3-2*v)end
local function mix(a,b,t)return a+(b-a)*t end
local function yearDay(calendar)
    local month=math.max(1,math.min(12,calendar.month or 1))
    local days={31,28,31,30,31,30,31,31,30,31,30,31}
    local year=calendar.year or 2026
    if year%400==0 or year%4==0 and year%100~=0 then days[2]=29 end
    local value=calendar.day or 1
    for i=1,month-1 do value=value+days[i] end
    return value
end
function Light.sample(calendar)
    calendar=calendar or {}
    local hour=((calendar.elapsed or 0)/math.max(1,calendar.secondsPerDay or 1200)*24)%24
    local latitude=35.8*pi/180
    local longitude=2*pi*(yearDay(calendar)-81)/365.25
    local declination=23.44*pi/180*math.sin(longitude)
    local angle=(hour-12)*pi/12
    local altitude=math.sin(latitude)*math.sin(declination)
        +math.cos(latitude)*math.cos(declination)*math.cos(angle)
    local east=-math.cos(declination)*math.sin(angle)
    local north=math.cos(latitude)*math.sin(declination)
        -math.sin(latitude)*math.cos(declination)*math.cos(angle)
    local daylight=smooth((altitude+.075)/.34)
    local dusk=smooth(1-math.abs(altitude-.04)/.3)*(1-smooth((altitude-.12)/.3))
    local warmth=clamp(dusk*.8)
    local night=1-daylight
    return {
        hour=hour,daylight=daylight,sunDirection={east,altitude,-north},
        sunColor={1,1-.22*warmth,1-.42*warmth},
        sunlight=.47*daylight,ambient=.39+.27*daylight,
        moonlight=.11*night,moonDirection={-east,math.max(.14,-altitude),north},
        sky={mix(.09,.22,daylight),mix(.12,.27,daylight),mix(.18,.26,daylight)},
        horizon={mix(.14,.53,daylight),mix(.20,.65,daylight),mix(.28,.69,daylight)},
        dusk=dusk,night=night,sceneShade=.12*night,
    }
end
return Light
