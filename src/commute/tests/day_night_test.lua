local Light=require('src.commute.day_night')
local Renderer=require('src.commute.renderer')
local Test={}
local function at(month,day,hour)
    return {year=2026,month=month,day=day,elapsed=hour/24*1200,secondsPerDay=1200}
end
function Test.run(check)
    local morning=Light.sample(at(6,21,8))
    local noon=Light.sample(at(6,21,12))
    local evening=Light.sample(at(6,21,18))
    local midnight=Light.sample(at(6,21,0))
    check('commute_sun_moves_from_east_to_west_with_calendar_hour',morning.sunDirection[1]>0
        and evening.sunDirection[1]<0 and noon.sunDirection[2]>morning.sunDirection[2])
    check('commute_night_has_darker_sky_ground_and_structures',midnight.daylight==0
        and midnight.sunlight==0 and midnight.ambient<noon.ambient
        and midnight.sky[2]<noon.sky[2] and midnight.sceneShade>noon.sceneShade)
    check('commute_summer_day_outlasts_winter_day',Light.sample(at(6,21,18)).daylight
        >Light.sample(at(12,21,18)).daylight)
    local sent={};local shader={hasUniform=function()return true end,send=function(_,name,value)sent[name]=value end}
    local structureLight
    local renderer=setmetatable({ground={shader=shader},clock=0,calendar=at(6,21,0),
        world={size=512,maxHeight=84},radius=64,structures={setLighting=function(_,value)structureLight=value end}},Renderer)
    local camera={centerX=0,centerZ=0,send=function()end,firstPerson=false}
    renderer:shader(camera)
    local dark=sent.sunlight
    renderer.calendar=at(6,21,12);renderer:shader(camera)
    check('commute_renderer_sends_live_sun_moon_fog_to_shaders',dark==0 and sent.sunlight>dark
        and sent.sunDirection[2]>0 and sent.fogColor==structureLight.sky
        and sent.ambientLight==structureLight.ambient)
end
return Test
