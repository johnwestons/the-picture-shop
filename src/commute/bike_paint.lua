-- Cosmetic service paid from shared household funds. Only the host commits it.
local M=require('src.commute.vendor.mathx')
local Upgrades=require('src.commute.bike_upgrades')
local Paint={DEFAULT='bronze',COST_CENTS=12500,MAX_REVISION=1000000000000}
Paint.CATALOG={
    {id='bronze',name='Original bronze',color={.69,.49,.27}},
    {id='red',name='Signal red',color={.71,.28,.24}},
    {id='blue',name='Cobalt blue',color={.26,.49,.76}},
    {id='green',name='Forest green',color={.32,.50,.30}},
    {id='cream',name='Warm cream',color={.91,.85,.69}},
    {id='graphite',name='Graphite',color={.25,.27,.30}},
    {id='purple',name='Plum purple',color={.50,.35,.66}},
    {id='teal',name='Ocean teal',color={.20,.60,.58}},
}
local byId={}
for _,finish in ipairs(Paint.CATALOG)do finish.costCents=Paint.COST_CENTS;byId[finish.id]=finish end
function Paint.valid(id)return type(id)=='string' and byId[id]~=nil end
function Paint.get(id)if id==nil then id=Paint.DEFAULT end;return byId[id]end
function Paint.validRevision(value)
    return type(value)=='number' and value>=0 and value<=Paint.MAX_REVISION and value%1==0
end
function Paint.quote(state,player,id)
    local offer=Paint.get(id)
    if not Paint.valid(id) or not state or not state.home or type(player)~='table' then return nil end
    local resident=require('src.home_residents').get(state,player)
    if not resident then return nil end
    local currentId=resident.ridingPaintId or Paint.DEFAULT
    local revision=resident.ridingPaintRevision or 0
    if not Paint.valid(currentId) or not Paint.validRevision(revision) then return nil end
    local price=id==currentId and 0 or Paint.COST_CENTS
    local balance=state.home.balanceCents
    return {offer=offer,current=Paint.get(currentId),paintId=currentId,revision=revision,
        expectedPaintRevision=revision,priceCents=price,balanceCents=balance,
        shortfallCents=math.max(0,price-balance),
        status=id==currentId and 'current' or balance<price and 'unaffordable' or 'available'}
end
function Paint.purchase(state,player,trip,world,intent)
    if type(intent)~='table' or not trip or intent.token~=trip.token then return false,'That ride has ended.' end
    if not Paint.valid(intent.paintId) or not Paint.validRevision(intent.expectedPaintRevision) then
        return false,'Choose a valid paint finish and review its current quote.'
    end
    local okay,message,resident,bike=Upgrades.canVisit(state,player,trip,world)
    if not okay then return false,message end
    local current=resident.ridingPaintId or Paint.DEFAULT
    local revision=resident.ridingPaintRevision or 0
    if not Paint.valid(current) or not Paint.validRevision(revision) or (bike.paintId or Paint.DEFAULT)~=current then
        return false,'The motorcycle paint record is out of sync.'
    end
    if intent.expectedPaintRevision~=revision then return false,'Your bike paint changed. Review the updated quote.' end
    if intent.paintId==current then return true,'Your motorcycle already has '..Paint.get(current).name..' paint.' end
    if revision>=Paint.MAX_REVISION then return false,'The paint service record cannot accept another change.' end
    if not M.finite(state.home.balanceCents) or state.home.balanceCents<Paint.COST_CENTS then
        return false,'Not enough household money for this paint finish.'
    end
    -- Never accept a client-supplied price. A monotonic paint revision protects
    -- repeated purchases even when the selected finish cycles A -> B -> A.
    state.home.balanceCents=state.home.balanceCents-Paint.COST_CENTS
    resident.ridingPaintId=intent.paintId;resident.ridingPaintRevision=revision+1
    resident.revision=resident.revision+1;bike.paintId=intent.paintId
    state.home.revision=state.home.revision+1
    return true,Paint.get(intent.paintId).name..' paint applied.'
end
return Paint
