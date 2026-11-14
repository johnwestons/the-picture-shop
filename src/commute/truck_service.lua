-- Player truck condition, maintenance wear and component upgrades.
-- AI traffic trucks do not receive this record.
local M=require('src.commute.vendor.mathx')
local Service={MAX_REVISION=1000000000000,UPGRADE_MAX=3}
-- These are service intervals in odometer miles. They leave room for the new
-- 50-mile city route legs without requiring service after a single delivery.
local limits={oilMiles=280,oilFilterMiles=400,airFilterMiles=480,sparkPlugMiles=640,
    coolantMiles=1100,tireMiles=360,brakeMiles=320}
Service.MAINTENANCE={
    {id='oil',name='Engine oil change',price=6800,interval=limits.oilMiles},
    {id='oil_filter',name='Oil filter',price=3600,interval=limits.oilFilterMiles},
    {id='air_filter',name='Air filter',price=4200,interval=limits.airFilterMiles},
    {id='spark_plugs',name='Spark plugs and ignition check',price=5900,interval=limits.sparkPlugMiles},
    {id='coolant',name='Coolant service',price=5400,interval=limits.coolantMiles},
    {id='tires',name='Truck tire set',price=24500,interval=limits.tireMiles},
    {id='brakes',name='Brake pads and inspection',price=9800,interval=limits.brakeMiles},
}
Service.UPGRADES={
    engine={name='Engine',offers={{name='Heavy-duty tune',price=52000},{name='High-flow intake',price=84000},{name='Rebuilt powertrain',price=138000}}},
    tires={name='Tires',offers={{name='All-terrain tire package',price=32000},{name='Premium tire package',price=56000},{name='Heavy-load tire package',price=79000}}},
    brakes={name='Brakes',offers={{name='HD brake pads',price=28000},{name='Vented rotor kit',price=47000},{name='Heavy-duty brake set',price=72000}}},
    suspension={name='Suspension',offers={{name='Fresh shocks',price=30000},{name='Load-rated springs',price=51000},{name='Touring suspension kit',price=76000}}},
    durability={name='Durability',offers={{name='Engine guard',price=26000},{name='Reinforced mounts',price=46000},{name='Heavy-duty protection',price=68000}}},
}
local function integer(n,lo,hi)return M.finite(n) and n%1==0 and n>=lo and n<=hi end
local function partsCopy(value)
    local result={}
    for id in pairs(Service.UPGRADES) do result[id]=type(value)=='table' and value[id] or 0 end
    return result
end
function Service.new()
    return {totalMiles=0,oilMiles=0,oilFilterMiles=0,airFilterMiles=0,sparkPlugMiles=0,
        coolantMiles=0,tireMiles=0,brakeMiles=0,failureClock=0,mechanicalFailure=false,
        failureType=nil,revision=0,upgradeRevision=0,upgrades=partsCopy()}
end
function Service.copy(value)
    local result=Service.new();value=value or {}
    for key in pairs(limits) do result[key]=value[key] or 0 end
    for _,key in ipairs({'totalMiles','failureClock','revision','upgradeRevision'}) do result[key]=value[key] or 0 end
    result.mechanicalFailure=value.mechanicalFailure==true
    result.failureType=value.failureType
    result.upgrades=partsCopy(value.upgrades)
    return result
end
function Service.valid(value)
    if type(value)~='table' then return false end
    for key in pairs(limits) do if not M.finite(value[key]) or value[key]<0 or value[key]>1e12 then return false end end
    if not M.finite(value.totalMiles) or value.totalMiles<0 or value.totalMiles>1e12
        or not M.finite(value.failureClock) or value.failureClock<0 or value.failureClock>1e12
        or not integer(value.revision,0,Service.MAX_REVISION)
        or not integer(value.upgradeRevision,0,Service.MAX_REVISION)
        or type(value.mechanicalFailure)~='boolean'
        or value.failureType~=nil and value.failureType~='oil_pressure' and value.failureType~='overheating'
            and value.failureType~='ignition_misfire'
        or type(value.upgrades)~='table' then return false end
    for id in pairs(Service.UPGRADES) do if not integer(value.upgrades[id],0,Service.UPGRADE_MAX) then return false end end
    return true
end
function Service.record(vehicle)
    return {damage=vehicle.damage or 0,repairRevision=vehicle.repairRevision or 0,
        service=Service.copy(vehicle.service)}
end
function Service.validRecord(record)
    return type(record)=='table' and integer(record.damage,0,100)
        and integer(record.repairRevision,0,Service.MAX_REVISION) and Service.valid(record.service)
end
function Service.apply(vehicle,record)
    record=record or {}
    vehicle.damage=integer(record.damage,0,100) and record.damage or 0
    vehicle.repairRevision=integer(record.repairRevision,0,Service.MAX_REVISION) and record.repairRevision or 0
    vehicle.service=Service.copy(record.service)
    if vehicle.service.mechanicalFailure then vehicle.engine=false;vehicle.throttle=0 end
    return vehicle
end
function Service.defaultFleet()
    local box,kei=Service.record({service=Service.new()}),Service.record({service=Service.new()})
    return {box=box,kei=kei}
end
function Service.validFleet(fleet)
    if fleet==nil then return true end
    return type(fleet)=='table' and Service.validRecord(fleet.box) and Service.validRecord(fleet.kei)
end
function Service.normalizeFleet(fleet)
    local result=Service.defaultFleet()
    if Service.validFleet(fleet) and fleet then
        for _,model in ipairs({'box','kei'}) do result[model]=Service.record({
            damage=fleet[model].damage,repairRevision=fleet[model].repairRevision,service=fleet[model].service}) end
    end
    return result
end
function Service.applyFleet(truck,fleet)
    if truck then
        local record=fleet and fleet[truck.model or 'box']
        if Service.validRecord(record) then Service.apply(truck,record)
        elseif not truck.service then Service.apply(truck) end
    end
    return truck
end
function Service.syncFleet(home,trucks)
    if not home then return false end
    home.truckFleet=Service.normalizeFleet(home.truckFleet)
    local changed=false
    for _,truck in ipairs(trucks or {}) do
        if truck.service then
            local record=Service.record(truck);local model=truck.model or 'box'
            local old=home.truckFleet[model]
            if not old or old.damage~=record.damage or old.repairRevision~=record.repairRevision
                or old.service.revision~=record.service.revision
                or old.service.upgradeRevision~=record.service.upgradeRevision
                or old.service.mechanicalFailure~=record.service.mechanicalFailure then
                home.truckFleet[model]=record;changed=true
            elseif old.service.totalMiles~=record.service.totalMiles
                or old.service.oilMiles~=record.service.oilMiles
                or old.service.tireMiles~=record.service.tireMiles
                or old.service.brakeMiles~=record.service.brakeMiles
                or old.service.failureClock~=record.service.failureClock then
                home.truckFleet[model]=record;changed=true
            end
        end
    end
    return changed
end
function Service.ratios(service)
    local s=Service.copy(service)
    return {oil=s.oilMiles/limits.oilMiles,oil_filter=s.oilFilterMiles/limits.oilFilterMiles,
        air_filter=s.airFilterMiles/limits.airFilterMiles,spark_plugs=s.sparkPlugMiles/limits.sparkPlugMiles,
        coolant=s.coolantMiles/limits.coolantMiles,tires=s.tireMiles/limits.tireMiles,
        brakes=s.brakeMiles/limits.brakeMiles}
end
function Service.modifiers(vehicle)
    local s=Service.copy(vehicle.service);local upgrades=s.upgrades;local ratios=Service.ratios(s)
    local engineWear=math.max(ratios.oil,ratios.oil_filter,ratios.air_filter,ratios.spark_plugs,ratios.coolant)
    local tireWear=math.min(1,ratios.tires);local brakeWear=math.min(1,ratios.brakes)
    local damage=math.min(1,(vehicle.damage or 0)/100)
    return {speed=(1+.035*upgrades.engine)*(1-.34*damage)*math.max(.55,1-math.max(0,engineWear-.7)*.13),
        acceleration=(1+.075*upgrades.engine)*(1-.48*damage)*math.max(.55,1-math.max(0,engineWear-.7)*.16),
        brake=(1+.09*upgrades.brakes)*(1-.35*brakeWear),
        grip=(1+.045*upgrades.tires+.04*upgrades.suspension)*(1-.38*tireWear),
        damage=(1-.12*upgrades.durability),engineWear=engineWear}
end
function Service.impact(vehicle,speed)
    if not vehicle or not vehicle.service then return false end
    local excess=math.max(0,(speed or 0)-4.2)
    if excess<=0 then return false end
    local points=math.min(40,math.floor(excess*(.45+.10*excess)+.5))
    points=math.floor(points*Service.modifiers(vehicle).damage+.5)
    if points<=0 then return false end
    vehicle.damage=math.min(100,(vehicle.damage or 0)+points)
    return true
end
function Service.run(vehicle,meters,dt)
    local s=vehicle and vehicle.service
    if not s or meters<=0 then return false end
    local miles=meters/1609.344
    for _,key in ipairs({'totalMiles','oilMiles','oilFilterMiles','airFilterMiles','sparkPlugMiles',
        'coolantMiles','tireMiles','brakeMiles'}) do s[key]=s[key]+miles end
    local ratios=Service.ratios(s)
    local engineWear=math.max(ratios.oil,ratios.oil_filter,ratios.air_filter,ratios.spark_plugs,ratios.coolant)
    if engineWear>1.05 then s.failureClock=s.failureClock+math.max(0,dt or 0)*(engineWear-1)^2*.65 end
    local newlyFailed=false
    if s.failureClock>=75 and not s.mechanicalFailure then
        s.mechanicalFailure=true
        local lubrication=math.max(ratios.oil,ratios.oil_filter)
        local ignition=math.max(ratios.air_filter,ratios.spark_plugs)
        s.failureType=ratios.coolant>=lubrication and ratios.coolant>=ignition and 'overheating'
            or lubrication>=ignition and 'oil_pressure' or 'ignition_misfire'
        vehicle.engine=false;vehicle.throttle=0
        s.revision=s.revision+1
        newlyFailed=true
    end
    return true,newlyFailed
end
function Service.runFleet(home,model,meters,dt)
    if not home or (model~='box' and model~='kei') then return false end
    home.truckFleet=Service.normalizeFleet(home.truckFleet)
    local vehicle={model=model}
    Service.apply(vehicle,home.truckFleet[model])
    local wore,failed=Service.run(vehicle,meters,dt)
    if wore then home.truckFleet[model]=Service.record(vehicle) end
    return wore==true,failed==true
end
function Service.maintenance(id)
    for _,item in ipairs(Service.MAINTENANCE) do if item.id==id then return item end end
end
function Service.upgrade(category,level)
    local entry=Service.UPGRADES[category]
    return entry and entry.offers[level],entry
end
function Service.repairQuote(vehicle,balance)
    local damage=vehicle.damage or 0;local failure=vehicle.service.mechanicalFailure
    local price=damage*220+ (failure and 42000 or 0)
    return {damage=damage,failed=failure,revision=vehicle.repairRevision or 0,priceCents=price,
        failureType=vehicle.service.failureType,
        status=(damage==0 and not failure) and 'healthy' or (balance<price and 'unaffordable' or 'available'),
        shortfallCents=math.max(0,price-balance)}
end
function Service.maintenanceQuote(vehicle,id,balance)
    local item=Service.maintenance(id);if not item then return nil end
    local key=({oil='oilMiles',oil_filter='oilFilterMiles',air_filter='airFilterMiles',
        spark_plugs='sparkPlugMiles',coolant='coolantMiles',tires='tireMiles',brakes='brakeMiles'})[id]
    local used=vehicle.service[key]
    local cost=item.price
    if id=='tires' then cost=vehicle.model=='kei' and 16800 or 24500 end
    if id=='brakes' then cost=vehicle.model=='kei' and 7200 or item.price end
    return {item=item,usedMiles=used,interval=item.interval,revision=vehicle.service.revision,
        priceCents=cost,status=used>=item.interval and (balance>=cost and 'available' or 'unaffordable') or 'healthy',
        shortfallCents=math.max(0,cost-balance)}
end
function Service.upgradeQuote(vehicle,category,balance)
    local entry=Service.UPGRADES[category];if not entry then return nil end
    local level=vehicle.service.upgrades[category];local offer=entry.offers[level+1]
    if not offer then return {category=entry,currentLevel=level,status='maxed',revision=vehicle.service.upgradeRevision} end
    return {category=entry,offer=offer,currentLevel=level,level=level+1,
        revision=vehicle.service.upgradeRevision,status=balance>=offer.price and 'available' or 'unaffordable',
        priceCents=offer.price,shortfallCents=math.max(0,offer.price-balance)}
end
return Service
