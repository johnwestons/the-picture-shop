-- Fuel in litres. A full 4 L tank is about a week of typical town riding.
-- Service wear scales with the longer range so fuel tuning does not make
-- routine maintenance arrive several times sooner per tank.
local S={tank=4,oilLife=63,chainLife=147,tires={},tireOrder={},orders={'fuel','oil'},
    fuelPerMile=.045,throttleFuelPerMile=.025,boostFuelPerMile=.06,idleFuelPerSecond=.00003}
local function tire(id,name,cents,road,dirt,life,roadAcceleration,dirtAcceleration,description)
    S.tires[id]={name=name,price=cents,road=road,dirt=dirt,life=life,
        roadAcceleration=roadAcceleration,dirtAcceleration=dirtAcceleration,description=description}
    S.tireOrder[#S.tireOrder+1]=id
end
tire('street','Street',2600,1.14,.70,84,1.12,.92,'Strong concrete grip and acceleration; slides more on dirt.')
tire('streetplus','Premium street',4900,1.24,.74,161,1.20,.94,'Best concrete grip and acceleration; loses traction quickly on dirt.')
tire('mixed','Standard',3200,1,1,98,1,1,'Factory tires with the current balanced, predictable handling.')
tire('mixedplus','Dual-purpose',5700,1.10,1.15,182,1.06,1.04,'Extra grip on both concrete and dirt with balanced acceleration.')
tire('dirt','Dirt',3700,.82,1.25,77,.92,1.06,'Trades some concrete grip for stronger dirt traction and control.')
tire('dirtplus','Premium dirt',6400,.88,1.36,154,.94,1.10,'Maximum dirt grip and reduced sliding on loose terrain.')
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
function S.acceleration(s,road)
    if not s then return 1 end
    local tire=S.tires[s.tire]
    if not tire then return 1 end
    road=math.max(0,math.min(1,road or 0))
    local surface=tire.dirtAcceleration+(tire.roadAcceleration-tire.dirtAcceleration)*road
    local wear=1-.1*math.min(1,s.tread/tire.life)
    return surface*wear
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
    s.fuel=math.max(0,s.fuel-miles*(S.fuelPerMile+S.throttleFuelPerMile*(bike.throttle or 0)
        +(bike.boosting and S.boostFuelPerMile or 0))-dt*S.idleFuelPerSecond)
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
