-- Optional GPS preference and persistent visits after Grandpa's handoff.
-- Older Story saves omit these optional fields and remain valid.
local Progress={}
local Condition=require('src.warehouse_condition')
local function story(R)
    local c=R and R.state and Condition.of(R.state)
    return c and c.mode=='story' and c.grandpaMet and not c.grandOpened and c or nil
end
local function kind(R,id)
    if id=='warehouse' then return 'warehouse' end
    if id==R.state.home.apartmentId then return 'home' end
end
function Progress.choose(R,id)
    local c=story(R)
    local chosen=c and kind(R,id)
    if not chosen then return false end
    if c.firstDestination~=chosen then
        c.firstDestination=chosen
        if R.multiplayer:isHost() then R.multiplayer:markShopDirty(true) end
    end
    return true
end
function Progress.clearRoute(R)
    local c=story(R)
    if not c or not c.firstDestination then return false end
    c.firstDestination=nil
    if R.multiplayer:isHost() then R.multiplayer:markShopDirty(true) end
    return true
end
function Progress.visit(R,id)
    local c=story(R)
    local place=c and kind(R,id)
    if not place then return false end
    local field=place=='home' and 'visitedApartment' or 'visitedShop'
    Progress.clearRoute(R)
    if c[field] then return false end
    c[field]=true
    if R.multiplayer:isHost() then R.multiplayer:markShopDirty(true) end
    R.state.message=place=='home' and 'You have seen your apartment. The Picture Shop is marked on the town map.'
        or 'You have reached the closed Picture Shop. Restore it before the grand opening.'
    return true
end
function Progress.reconcile(R)
    local c=story(R)
    local place=c and kind(R,R.World.player.sceneId)
    if place then return Progress.visit(R,R.World.player.sceneId) end
    return false
end
return Progress
