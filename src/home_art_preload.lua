-- Presentation-only streaming. In-flight household actions keep their complete
-- phase family; other families are evicted to limit phone texture residency.
local Loader=require("src.image_loader")
local Images=require("src.home_art_resources")
local Preload={BUDGET_BYTES=96*1024*1024,IDLE_SECONDS=20}
local modules={washing="home_washing_art",laundry="home_laundry_art",
    wipe="home_wipe_art",trash="home_trash_art",sweep="home_sweep_art",
    cooking="home_cooking_art",pose="home_activity_pose",held="home_held_art",
    props="home_routine_props",privacy="home_privacy_art",food="home_food_art",
    alarm_clock="home_alarm_clock_art"}
local active,lastUsed={},{}
local allReady=true
function Preload.beginFrame() active={};allReady=true;Images.beginFrame() end
function Preload.wait() allReady=false end
function Preload.want(family,prepare)
    active[family]=true;lastUsed[family]=love.timer.getTime();Images.protect(family)
    if not Loader.enabled then return true end
    local ready=prepare()==true
    allReady=allReady and ready
    return ready
end
function Preload.endFrame()
    local now=love.timer.getTime()
    local unused={}
    for family,used in pairs(lastUsed) do
        if not active[family] then
            Images.cancelPending(family)
            unused[#unused+1]={family=family,used=used}
        end
    end
    table.sort(unused,function(a,b)return a.used<b.used end)
    local bytes=Images.bytes()
    for _,row in ipairs(unused) do
        if bytes>Preload.BUDGET_BYTES or now-row.used>Preload.IDLE_SECONDS then
            local before=Images.bytes(row.family)
            require("src."..modules[row.family]).release()
            lastUsed[row.family]=nil;bytes=math.max(0,bytes-before)
        end
    end
end
function Preload.ready() return allReady and not Images.failure() end
function Preload.failure() return Images.failure() end
function Preload.pending() return not Preload.ready() end
function Preload.bytes() return Images.bytes() end
function Preload.reset() active,lastUsed,allReady={}, {}, true;Images.beginFrame() end
return Preload
