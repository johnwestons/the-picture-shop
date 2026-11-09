-- Storage transfers and TV eligibility use host state; commands never supply counts.
local Catalog=require("src.home_furniture_catalog")
local Surface=require("src.home_surfaces")
local Layout=require("src.home_layouts")
local Utilities={ACTIONS={stow=true,retrieve=true}}
function Utilities.pool(state,item)
    local c=require("src.home_chores").ensure(state)
    if item.kind=="wardrobe" then return c.laundry,"clean" end
    if item.kind=="trash_can" then return c,"trash" end
end
function Utilities.transfer(state,item,action)
    local entry=Catalog.ITEMS[item.kind].storage;local pool,key=Utilities.pool(state,item)
    if not entry or not pool then return false,"unavailable","This object has no household storage." end
    for _,r in pairs(state.home.residents) do
        if r.activity and r.activity.furnitureId==item.id then return false,"occupied","Another resident is using this storage." end
    end
    local stored=item.contents[key] or 0
    if action=="stow" then
        if pool[key]<1 then return false,"empty",key=="clean" and "Unload clean laundry first." or "There is no loose household trash to collect." end
        if stored>=entry.capacity then return false,"full","This storage is full." end
        local n=key=="trash" and math.min(8,pool[key],entry.capacity-stored) or 1
        pool[key]=pool[key]-n;item.contents[key]=stored+n
    else
        if stored<1 then return false,"empty","This storage is empty." end
        if pool[key]>=64 then return false,"full","Make room in the shared household supply first." end
        local n=key=="trash" and math.min(8,stored,64-pool[key]) or 1
        pool[key]=pool[key]+n;item.contents[key]=stored-n
    end
    state.home.chores.revision=state.home.chores.revision+1;require("src.home_objects").changed(state,item)
    return true,"changed",key=="clean" and "Clean clothes transferred without changing the household total."
        or action=="stow" and "Loose trash collected in the can." or "Trash bag ready. Take it out using Home routines beside the entrance."
end
function Utilities.canSell(state,item)
    local pool,key=Utilities.pool(state,item)
    return not pool or pool[key]+(item.contents[key] or 0)<=64,"Make room in shared laundry or loose trash before selling this filled storage."
end
function Utilities.emptyForSale(state,item)
    local pool,key=Utilities.pool(state,item)
    if pool then pool[key]=pool[key]+(item.contents[key] or 0);item.contents={};state.home.chores.revision=state.home.chores.revision+1 end
end
local function floorPoint(state,item)
    if item.location=="surface" then
        if item.parentId==0 then local p=Layout.get(state).laptop.approach;return Layout.toWorld(unpack(p)) end
        local parent=Surface.find(state,item.parentId);if parent then return parent.x,parent.y end
    end
    return item.x,item.y
end
function Utilities.visibleTV(state,player,seat,tv)
    if not tv or not Catalog.ITEMS[tv.kind].television or not tv.powered or tv.editor or Surface.editConflict(state,tv)
        or tv.location=="storage" then return false end
    local x,y=seat.kind=="old_tv" and player.x or seat.x,seat.kind=="old_tv" and player.y or seat.y
    local tx,ty=floorPoint(state,tv);local dx,dy=x-tx,(y-ty)*2
    if dx*dx+dy*dy>180^2 then return false end
    local pose=Surface.pose(state,tv);local angle=Catalog.angle(pose.direction)
    if dx*math.cos(angle)+dy*math.sin(angle)<0 then return false end
    local mask=Layout.mask(state.home.apartmentId);local steps=math.max(1,math.ceil(math.sqrt((tx-x)^2+(ty-y)^2)/4))
    for i=1,steps-1 do if mask:getPixel(math.floor(x+(tx-x)*i/steps),math.floor(y+(ty-y)*i/steps))~=1 then return false end end
    return true
end
function Utilities.findTV(state,player,seat)
    for _,tv in ipairs(state.home.furniture.items) do if Utilities.visibleTV(state,player,seat,tv) then return tv end end
end
function Utilities.watchValid(state,player,a)
    local seat=Surface.find(state,a.furnitureId)
    return seat and Utilities.visibleTV(state,player,seat,Surface.find(state,a.tvId))
end
function Utilities.validActivity(a)
    if a.kind~="watch" then return a.tvId==nil end
    return type(a.tvId)=="number" and a.tvId==math.floor(a.tvId) and a.tvId>=1 and a.tvId<1e9
end
return Utilities
