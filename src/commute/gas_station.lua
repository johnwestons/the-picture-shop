local Station={}
local Service=require('src.commute.bike_service')
local CompanyTruck=require('src.company_delivery_driver')
local Truck=require('src.commute.delivery_truck')
local function near(point,other,radius)
    return point and other and (point.x-other.x)^2+(point.z-other.z)^2<=radius^2
end
local function sites(world)return world and (world.sites or world.roads and world.roads.sites) end
local function stationSite(world)local registry=sites(world);return registry and registry.byId['gas-station'] end
local function stopped(vehicle)return vehicle and (vehicle.speed or 0)<=.08 end
local function contains(rect,x,z)
    return rect and x>=rect.minX and x<=rect.maxX and z>=rect.minZ and z<=rect.maxZ
end
function Station.atCounter(rider,world)
    local site=stationSite(world)
    return site and rider and rider.gear and not rider.gear.mounted and not rider.gear.transition
        and rider.vehicle~='truck' and not rider.ped.crash and near(rider.ped,site.door,2)
end
function Station.nearCounter(rider,world)
    local site=stationSite(world)
    return site and rider and rider.ped and near(rider.ped,site.door,3.5)
end
function Station.bikeAtForecourt(bike,world)
    local site=stationSite(world)
    if not bike or not site or not site.localForecourt then return false end
    local x,z=site:toLocal(bike.x,bike.z)
    return contains(site.localForecourt,x,z) and stopped(bike)
end
function Station.bikeAtPump(rider,world)
    local site=stationSite(world)
    if not rider or not site or not rider.bike or not stopped(rider.bike)
        or not Station.bikeAtForecourt(rider.bike,world) then return false end
    for _,bay in ipairs(site.pumpBays or {}) do
        if near(rider.bike,bay,1.55) then return true end
    end
    return false
end
function Station.truckAtPump(truck,world)
    local site=stationSite(world)
    return truck and site and site.truckPumpBay and stopped(truck) and near(truck,site.truckPumpBay,2.75)
end
local function riderByBike(rider)
    return rider and rider.ped and rider.bike and near(rider.ped,rider.bike,2.5)
end
function Station.pumpMode(rider,truck,world)
    if not rider or not rider.gear or rider.gear.mounted or rider.gear.transition or rider.ped.crash
        or rider.vehicle=='truck' or rider.ped.speed and rider.ped.speed>.08 then return nil end
    if Station.bikeAtPump(rider,world) and riderByBike(rider) then return 'bike' end
    if Station.truckAtPump(truck,world) and near(rider.ped,truck,3.5) then return 'truck' end
end
local function amountLimit(mode,args)
    if mode=='truck' then
        local company=args.companyTruck
        return company and math.max(0,math.floor((CompanyTruck.TANK_LITERS-company.fuelLiters)*1000+1e-6)) or 0
    end
    local service=args.service
    return service and math.max(0,math.floor((Service.tank-service.fuel)*1000+1e-6)) or 0
end
local function selectedAmount(v,args)
    local maximum=amountLimit(v.mode,args)
    if v.mode=='counter' then return 0 end
    if v.amountMl==nil then return maximum end
    v.amountMl=math.max(0,math.min(maximum,math.floor(v.amountMl)))
    return v.amountMl
end
local function cost(mode,amountMl)
    local centsPerLiter=mode=='truck' and CompanyTruck.FUEL_PRICE_CENTS_PER_LITER or 160
    return math.ceil(amountMl*centsPerLiter/1000)
end
local function revision(v,args)
    return v.mode=='truck' and args.companyTruck and args.companyTruck.revision
        or args.service and args.service.revision or 0
end
local function quoteKey(v,args)
    return table.concat({v.mode,revision(v,args) or 0,v.mode=='counter' and 'oil' or selectedAmount(v,args)},':')
end
local function canBuy(v,args)
    local rider=args.rider
    if v.mode=='counter' then
        local _,_,available=Service.offer(args.service,'oil')
        return available and Station.atCounter(rider,args.world) and Station.bikeAtForecourt(rider.bike,args.world)
    elseif v.mode=='bike' then
        return selectedAmount(v,args)>0 and Station.pumpMode(rider,args.truck,args.world)=='bike'
    elseif v.mode=='truck' then
        return selectedAmount(v,args)>0 and Station.pumpMode(rider,args.truck,args.world)=='truck'
            and args.companyTruck and args.companyTruck.fuelLiters<CompanyTruck.TANK_LITERS
    end
    return false
end
function Station.buy(rider,world,wallet,id,expectedRevision,companyTruck,truck,state,amountMl)
    local sitesNow=stationSite(world)
    if not sitesNow then return false,'The gas station is unavailable.' end
    if (id=='fuel' or id=='oil') and state
        and not require('src.commute.town_characters').isOpen(state.home,'gas-station',
            require('src.business_calendar').absoluteHours(state)) then
        return false,'The gas station is closed for the night. It is open 08:00–18:00.'
    end
    if id=='truckfuel' then
        if not companyTruck or not truck then return false,'The delivery truck is unavailable.' end
        if Station.pumpMode(rider,truck,world)~='truck' then
            return false,'Park the delivery truck at its marked gas pump, then walk beside it.'
        end
        if expectedRevision~=companyTruck.revision then return false,'The truck fuel order changed. Review the current price.' end
        local maximum=math.floor((CompanyTruck.TANK_LITERS-companyTruck.fuelLiters)*1000+1e-6)
        if type(amountMl)~='number' or amountMl%1~=0 or amountMl<1 or amountMl>maximum then
            return false,maximum>0 and 'Choose a valid amount of fuel.' or 'The delivery truck tank is already full.'
        end
        local cents=cost('truck',amountMl)
        local paid=require('src.business_calendar').recordPaidExpenseCents(state,
            'Delivery truck fuel',cents,'truck-fuel')
        if not paid then return false,'Not enough company funds to pay for this fuel.' end
        companyTruck.fuelLiters=math.min(CompanyTruck.TANK_LITERS,companyTruck.fuelLiters+amountMl/1000)
        companyTruck.revision=companyTruck.revision+1
        truck.fuel=companyTruck.fuelLiters
        return true,('Delivery truck filled with %.2f L. Company expense: $%.2f.'):format(amountMl/1000,cents/100)
    end
    if id~='fuel' and id~='oil' then return false,'The gas station offers fuel and oil changes only.' end
    local service=rider and rider.bike and rider.bike.service
    if not service then return false,'The motorcycle is unavailable.' end
    if expectedRevision~=service.revision then return false,'The motorcycle service order changed. Review it again.' end
    local label,price,available=Service.offer(service,id)
    if not available then return false,'This service is already up to date.' end
    if id=='fuel' then
        if Station.pumpMode(rider,truck,world)~='bike' then
            return false,'Park your motorcycle beside a marked pump, then walk beside it.'
        end
        local maximum=math.floor((Service.tank-service.fuel)*1000+1e-6)
        if type(amountMl)~='number' or amountMl%1~=0 or amountMl<1 or amountMl>maximum then
            return false,maximum>0 and 'Choose a valid amount of fuel.' or 'The motorcycle tank is already full.'
        end
        price=cost('bike',amountMl)
    else
        if not Station.atCounter(rider,world) then return false,'Walk to the gas station counter for an oil change.' end
        if not Station.bikeAtForecourt(rider.bike,world) then
            return false,'Park your motorcycle on the gas station forecourt for an oil change.'
        end
    end
    if wallet.balanceCents<price then return false,'Not enough household funds.' end
    wallet.balanceCents=wallet.balanceCents-price
    if id=='fuel' then service.fuel=math.min(Service.tank,service.fuel+amountMl/1000)
    else service.oil=0 end
    service.revision=service.revision+1
    local detail=id=='fuel' and ('%.2f L of fuel'):format(amountMl/1000) or label
    if state then require('src.receipt_book').expense(state,id=='fuel' and 'Motorcycle fuel' or 'Motorcycle oil service',price,
        'Gas station','Household',detail) end
    return true,('%s paid. $%.2f'):format(detail,price/100)
end

function Station.open(mode)
    mode=(mode=='truck' or mode=='counter') and mode or 'bike'
    return {page='station',mode=mode,amountMl=nil,quote=nil,notice=nil,clock=0,animation=0}
end
local function buy(v,args)
    local id=v.mode=='counter' and 'oil' or v.mode=='truck' and 'truckfuel' or 'fuel'
    local amount=selectedAmount(v,args)
    if not canBuy(v,args) then
        v.quote=nil
        if v.mode=='counter' then
            if not Station.atCounter(args.rider,args.world) then v.notice='Walk to the gas station counter for an oil change.'
            elseif not Station.bikeAtForecourt(args.rider.bike,args.world) then
                v.notice='Park your motorcycle on the forecourt for counter service.'
            else v.notice='No oil change is needed.' end
        elseif v.mode=='truck' then v.notice='Park the delivery truck in the marked truck bay and stand beside it.'
        else v.notice='Park your motorcycle in a marked pump bay and stand beside it.' end
        return true
    end
    local key=quoteKey(v,args)
    if v.quote~=key then
        v.quote=key
        if v.mode=='counter' then v.notice='Oil change · $8.50. Press Pay again to confirm.'
        else v.notice=('Review %.2f L · $%.2f. Press Pay again to confirm.'):format(amount/1000,cost(v.mode,amount)/100) end
        return true
    end
    v.quote=nil
    local current=revision(v,args) or 0
    local okay,message=args.buy(id,current,amount)
    if okay then
        v.pending={revision=current,elapsed=0,amountMl=amount,item=id}
        v.notice=message or 'Payment submitted. Waiting for the station...'
    else v.notice=message or 'Payment declined.' end
    return true
end
local function changeAmount(v,args,delta)
    local maximum=amountLimit(v.mode,args)
    local current=selectedAmount(v,args)
    v.amountMl=math.max(0,math.min(maximum,current+delta))
    v.quote=nil;v.notice=nil
end
function Station.update(v,dt,args)
    dt=math.max(0,math.min(.1,dt or 0));v.clock=(v.clock or 0)+dt
    selectedAmount(v,args)
    if v.animation>0 then v.animation=math.max(0,v.animation-dt) end
    if v.pending then
        v.pending.elapsed=v.pending.elapsed+dt
        if (revision(v,args) or 0)>v.pending.revision then
            if v.pending.item=='oil' then v.notice='Oil change complete.'
            else v.animation=1.8;v.notice='Fuel is flowing. Your tank is being filled.' end
            v.pending=nil
        elseif v.pending.elapsed>8 then
            v.notice='The station has not confirmed the purchase yet. Check the balance and tank.';v.pending=nil
        end
    end
    return true
end
function Station.key(v,key,args)
    if key=='escape' or key=='back' then args.close()
    elseif v.mode~='counter' and (key=='left' or key=='down' or key=='-' or key=='kp-') then changeAmount(v,args,-250)
    elseif v.mode~='counter' and (key=='right' or key=='up' or key=='+' or key=='kp+') then changeAmount(v,args,250)
    elseif v.mode~='counter' and (key=='home' or key=='f') then
        v.amountMl=amountLimit(v.mode,args);v.quote=nil;v.notice=nil
    elseif key=='return' or key=='kpenter' or key=='e' then buy(v,args) end
    return true
end
function Station.pointer(v,x,y,args)
    if y>=566 and y<=624 and x>=65 and x<=245 then args.close()
    elseif v.mode~='counter' and y>=294 and y<=355 and x>=440 and x<=500 then changeAmount(v,args,-250)
    elseif v.mode~='counter' and y>=294 and y<=355 and x>=575 and x<=635 then changeAmount(v,args,250)
    elseif v.mode~='counter' and y>=367 and y<=415 and x>=440 and x<=635 then
        v.amountMl=amountLimit(v.mode,args);v.quote=nil;v.notice=nil
    elseif y>=566 and y<=624 and x>=682 and x<=894 then buy(v,args)
    end
    return true
end
local function text(g,value,x,y,width,align)
    g.printf(value,x,y,width,align or 'left')
end
local function button(g,x,y,w,h,label,active)
    g.setColor(active and .25 or .12,active and .39 or .20,active and .29 or .18,1)
    g.rectangle('fill',x,y,w,h,5,5)
    g.setColor(.99,.94,.78,1);g.printf(label,x+5,y+h*.5-7,w-10,'center')
end
function Station.draw(v,args,width,height)
    local g=love.graphics
    g.push('all');g.scale(width/960,height/678)
    g.setColor(.035,.065,.06,1);g.rectangle('fill',36,38,888,600,10)
    local title=v.mode=='counter' and 'GAS STATION  /  SERVICE COUNTER'
        or v.mode=='truck' and 'FUEL PUMP  /  DELIVERY TRUCK' or 'FUEL PUMP  /  MOTORCYCLE'
    g.setColor(.96,.9,.7,1);g.print(title,70,70,0,1.6)
    local service=args.service
    if v.mode=='truck' then
        local fuel=args.companyTruck and args.companyTruck.fuelLiters or Truck.TANK_LITERS
        text(g,('Company funds $%.2f   ·   Tank %.2f / %.0f L'):format(args.companyCash or 0,fuel,CompanyTruck.TANK_LITERS),70,119,800)
    else
        text(g,('Household funds $%.2f   ·   Motorcycle tank %.2f / %.0f L'):format(
            (args.householdCents or 0)/100,service.fuel,Service.tank),70,119,800)
    end
    if v.mode=='counter' then
        g.setColor(.11,.23,.19,1);g.rectangle('fill',70,174,820,300,8,8)
        g.setColor(.83,.59,.27,1);g.rectangle('fill',108,220,180,110,6,6)
        g.setColor(.18,.30,.24,1);g.rectangle('fill',126,237,144,76,3,3)
        g.setColor(.94,.85,.62,1);g.rectangle('fill',144,257,18,11,2,2);g.rectangle('fill',180,257,18,11,2,2)
        text(g,'OIL CHANGE',330,214,450)
        g.setColor(.98,.94,.82,1);g.print('$8.50',330,252,0,1.45)
        g.setColor(.76,.80,.72,1);text(g,'Walk to the counter and leave your motorcycle parked on the forecourt.',330,297,500)
        text(g,('Oil interval: %.1f mi remaining'):format(math.max(0,Service.oilLife-service.oil)),330,339,500)
        text(g,Station.bikeAtForecourt(args.rider.bike,args.world)
            and 'Motorcycle is on the station forecourt.' or 'Your motorcycle must be parked on the forecourt.',330,379,500)
    else
        local PumpSprite=require('src.commute.gas_pump_sprite')
        local fuel=v.mode=='truck' and args.companyTruck.fuelLiters or service.fuel
        local capacity=v.mode=='truck' and CompanyTruck.TANK_LITERS or Service.tank
        local amount=selectedAmount(v,args)
        PumpSprite.draw(g,110,186,260,284,math.min(1,(fuel+amount/1000)/capacity),v.clock,v.animation>0)
        g.setColor(.11,.23,.19,1);g.rectangle('fill',405,182,485,312,8,8)
        g.setColor(.98,.94,.82,1);g.print('REGULAR GASOLINE',436,205,0,1.15)
        g.setColor(.76,.80,.72,1);text(g,'$1.60 per litre',436,238,410)
        text(g,('Current tank  %.2f / %.0f L'):format(fuel,capacity),436,270,410)
        button(g,440,296,60,58,'−',amount>0)
        g.push('all');g.setFont(require('src.screens.typography').get(14))
        g.setColor(.99,.94,.78,1);g.printf(('%d.%03d L'):format(math.floor(amount/1000),amount%1000),505,316,70,'center')
        g.pop()
        button(g,575,296,60,58,'+',amount<amountLimit(v.mode,args))
        button(g,440,367,195,44,'FILL TO FULL',true)
        g.setColor(.95,.86,.64,1);g.print(('TOTAL  $%.2f'):format(cost(v.mode,amount)/100),440,434,0,1.35)
        text(g,v.mode=='truck' and 'The truck must be parked in its marked bay.'
            or 'The motorcycle must be in a marked pump bay.',675,290,190)
        text(g,amount>0 and ('Selected amount: %.3f L'):format(amount/1000) or 'Tank is full.',675,370,190)
    end
    g.setColor(1,.89,.67,1)
    text(g,v.notice or (v.mode=='counter' and 'Only oil changes are available at the counter.'
        or 'Choose a fuel amount, review the total, then pay.'),70,526,820,'center')
    button(g,65,566,180,58,'LEAVE',true)
    local enabled=canBuy(v,args)
    button(g,682,566,212,58,v.quote and 'CONFIRM / PAY' or 'REVIEW / PAY',enabled)
    g.pop();return true
end
return Station
