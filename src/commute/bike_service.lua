-- Fuel in litres. Service intervals are shortened for town-scale rides.
local S={tank=4,oilLife=18,chainLife=42,tires={},orders={'fuel','oil','chain'}}
local function tire(id,name,cents,road,dirt,life)
    S.tires[id]={name=name,price=cents,road=road,dirt=dirt,life=life}
    S.orders[#S.orders+1]=id
end
tire('street','Street',2600,1.14,.78,24)
tire('streetplus','Premium street',4900,1.24,.83,46)
tire('mixed','Dual sport',3200,1,1,28)
tire('mixedplus','Premium dual sport',5700,1.08,1.09,52)
tire('dirt','Off-road',3700,.82,1.25,22)
tire('dirtplus','Premium off-road',6400,.88,1.36,44)
function S.copy(s)
    s=s or {}
    return {fuel=s.fuel or S.tank,miles=s.miles or 0,tread=s.tread or 0,oil=s.oil or 0,
        chain=s.chain or 0,tire=s.tire or 'mixed',revision=s.revision or 0}
end
function S.valid(s)
    if s==nil then return true end
    if type(s)~='table' or not S.tires[s.tire] then return false end
    for _,key in ipairs({'fuel','miles','oil','chain','tread','revision'}) do
        local n=s[key]
        if type(n)~='number' or not (n>=0 and n<=1e12) then return false end
    end
    return s.fuel<=S.tank and s.revision%1==0
end
function S.grip(s,road)
    if not s then return 1 end
    local tire=S.tires[s.tire]
    return (tire.dirt+(tire.road-tire.dirt)*road)*(1-.48*math.min(1,s.tread/tire.life))
end
function S.rough(bike)
    local s=bike.service
    local neglect=s and math.max(s.oil/S.oilLife,s.chain/S.chainLife) or 0
    return math.max(0,math.min(1,((bike.damage or 0)-40)/60),math.min(1,(neglect-.8)*1.5))
end
function S.run(bike,meters,dt,powered)
    local s=bike.service
    local miles=meters/1609.344
    s.miles=s.miles+miles
    s.oil=s.oil+miles
    s.chain=s.chain+miles*(bike.boosting and 1.3 or 1)
    s.tread=s.tread+miles*(1+2*(bike.tireSlip or 0)+(bike.slip or 0))
    if powered==false then return false end
    s.fuel=math.max(0,s.fuel-miles*(.17+.09*(bike.throttle or 0)+(bike.boosting and .12 or 0))-dt*.00012)
    local rough=S.rough(bike)
    bike.stallClock=(bike.stallClock or 0)+dt*rough*rough
    return s.fuel<=0 or bike.stallClock>=32
end
function S.offer(s,id)
    local tire=S.tires[id]
    if tire then return tire.name..' tires',tire.price,s.tire~=id or s.tread>.00001 end
    if id=='fuel' then return 'Fill tank',math.ceil((S.tank-s.fuel)*160),s.fuel<S.tank end
    if id=='oil' then return 'Oil change',850,s.oil>0 end
    if id=='chain' then return 'Chain and sprockets',3800,s.chain>0 end
end
return S
