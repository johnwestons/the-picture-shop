local Station={}
local Service=require('src.commute.bike_service')
local CompanyTruck=require('src.company_delivery_driver')
local Truck=require('src.commute.delivery_truck')
local function near(point,other,radius)
    return point and other and (point.x-other.x)^2+(point.z-other.z)^2<=radius^2
end
function Station.atCounter(rider,world)
    local sites=world and (world.sites or world.roads and world.roads.sites)
    local site=sites and sites.byId['gas-station']
    return site and not rider.gear.mounted and not rider.gear.transition and not rider.ped.crash
        and near(rider.ped,site.door,2)
end
function Station.nearCounter(rider,world)
    local sites=world and (world.sites or world.roads and world.roads.sites)
    local site=sites and sites.byId['gas-station']
    return site and near(rider.ped,site.door,3.5)
end
function Station.truckAtPump(truck,world)
    local sites=world and (world.sites or world.roads and world.roads.sites)
    local site=sites and sites.byId['gas-station']
    return truck and site and near(truck,site.parking,14)
end
function Station.buy(rider,world,wallet,id,revision,companyTruck,truck,state)
    if not Station.atCounter(rider,world) then return false,'Walk to the gas station counter first.' end
    if id=='truckfuel' then
        if not companyTruck or not truck then return false,'The delivery truck is unavailable.' end
        if not Station.truckAtPump(truck,world) then
            return false,'Park the delivery truck on the gas station forecourt first.'
        end
        if revision~=companyTruck.revision then return false,'The truck fuel order changed. Review the current price.' end
        local liters=math.max(0,CompanyTruck.TANK_LITERS-companyTruck.fuelLiters)
        local cents=math.ceil(liters*CompanyTruck.FUEL_PRICE_CENTS_PER_LITER)
        if cents<=0 then return false,'The delivery truck tank is already full.' end
        local paid=require('src.business_calendar').recordPaidExpenseCents(state,
            'Delivery truck fuel',cents,'truck-fuel')
        if not paid then return false,'Not enough company funds to refuel the delivery truck.' end
        companyTruck.fuelLiters=CompanyTruck.TANK_LITERS
        companyTruck.revision=companyTruck.revision+1
        truck.fuel=companyTruck.fuelLiters
        return true,('Delivery truck refueled. Company expense: $%.2f.'):format(cents/100)
    end
    if id~='fuel' and id~='oil' and id~='chain' then
        return false,'Tire purchases are available at the mechanic shop.'
    end
    local bike=rider.bike
    local s=bike.service
    if revision~=s.revision then return false,'The order has changed. Review the current price.' end
    local label,price,available=Service.offer(s,id)
    if not available then return false,'This service is already up to date.' end
    if id~='fuel' and not near(bike,world.sites.byId['gas-station'].parking,8) then
        return false,'Park your motorcycle on the station forecourt for installation.'
    end
    if wallet.balanceCents<price then return false,'Not enough household funds.' end
    wallet.balanceCents=wallet.balanceCents-price
    if id=='fuel' then s.fuel=Service.tank
    elseif id=='oil' then s.oil=0
    elseif id=='chain' then s.chain=0 end
    s.revision=s.revision+1
    return true,('%s paid. $%.2f'):format(label,price/100)
end

function Station.open(mode)
    return {page='station',selected=1,mode=mode=='truck' and 'truck' or 'bike'}
end

local function item(v)
    if v.mode=='truck' then return 'truckfuel' end
    return Service.orders[v.selected]
end
local function revision(v,args)
    return v.mode=='truck' and args.companyTruck and args.companyTruck.revision
        or args.service and args.service.revision or 0
end
local function buy(v,args)
    local id=item(v);local rev=revision(v,args)
    local available
    if v.mode=='truck' then
        available=args.companyTruck and args.companyTruck.fuelLiters<CompanyTruck.TANK_LITERS
            and Station.truckAtPump(args.truck,args.world)
    else
        local _,_,can=Service.offer(args.service,id);available=can
    end
    if not available then
        v.quote=nil
        v.notice=v.mode=='truck' and 'Park the truck on the forecourt and check its fuel.' or 'Already up to date.'
        return true
    end
    if v.quote~=rev then
        v.quote=rev
        if v.mode=='truck' then
            local cost=math.ceil((CompanyTruck.TANK_LITERS-args.companyTruck.fuelLiters)
                *CompanyTruck.FUEL_PRICE_CENTS_PER_LITER)
            v.notice=('Refuel the delivery truck for $%.2f from company funds? Review / Buy again.'):format(cost/100)
        else
            local name,cost=Service.offer(args.service,id)
            v.notice=('Buy %s for $%.2f? Press Buy again.'):format(name,cost/100)
        end
    else
        v.quote=nil
        local okay,message=args.buy(id,rev)
        v.notice=message or (okay and 'Order submitted.' or 'Order declined.')
    end
    return true
end

function Station.key(v,key,args)
    if key=='escape' or key=='back' then args.close()
    elseif key=='tab' or key=='m' then
        v.mode=v.mode=='truck' and 'bike' or 'truck';v.selected=1;v.quote=nil;v.notice=nil
    elseif key=='up' or key=='down' then
        if v.mode=='bike' then
            v.selected=(v.selected-1+(key=='up' and -1 or 1))%#Service.orders+1
            v.quote=nil;v.notice=nil
        end
    elseif key=='return' or key=='kpenter' or key=='e' then buy(v,args) end
    return true
end

function Station.pointer(v,x,y,args)
    if y>=566 and y<=624 and x>=65 and x<=245 then args.close()
    elseif y>=566 and y<=624 and x>=682 and x<=894 then buy(v,args)
    elseif y>=140 and y<=176 and x>=65 and x<=315 then
        if v.mode~='bike' then v.mode='bike';v.selected=1;v.quote=nil;v.notice=nil end
    elseif y>=140 and y<=176 and x>=320 and x<=575 then
        if v.mode~='truck' then v.mode='truck';v.selected=1;v.quote=nil;v.notice=nil end
    elseif v.mode=='bike' and x>=65 and x<=575 and y>=190 and y<325 then
        v.selected=math.max(1,math.min(#Service.orders,math.floor((y-190)/42)+1))
        v.quote=nil;v.notice=nil
    elseif v.mode=='truck' and x>=65 and x<=575 and y>=190 and y<245 then
        v.selected=1;v.quote=nil;v.notice=nil
    end
    return true
end

function Station.draw(v,args,width,height)
    local g=love.graphics
    g.push('all');g.scale(width/960,height/678)
    g.setColor(.035,.065,.06,1);g.rectangle('fill',36,38,888,600,10)
    g.setColor(.96,.9,.7);g.print('GAS STATION   /   SERVICE COUNTER',70,70,0,1.6)
    if v.mode=='truck' then
        local fuel=args.companyTruck and args.companyTruck.fuelLiters or Truck.TANK_LITERS
        g.print(('Company $%.2f   |   Delivery truck fuel %.1f / %.0f L'):format(
            (args.companyCash or 0),fuel,CompanyTruck.TANK_LITERS),70,119)
    else
        local service=args.service
        g.print(('Household $%.2f    |    Tank %.2f / %.0f L    |    Odometer %.2f mi'):format(
            (args.householdCents or 0)/100,service.fuel,Service.tank,service.miles),70,119)
    end
    local function tab(x,label,selected)
        g.setColor(selected and .21 or .09,selected and .31 or .16,selected and .23 or .15,1)
        g.rectangle('fill',x,140,250,34,4)
        g.setColor(.98,.95,.82);g.printf(label,x+5,150,240,'center')
    end
    tab(65,'MOTORCYCLE',v.mode=='bike');tab(320,'DELIVERY TRUCK',v.mode=='truck')
    if v.mode=='truck' then
        local fuel=args.companyTruck and args.companyTruck.fuelLiters or 0
        local cost=math.ceil((CompanyTruck.TANK_LITERS-fuel)*CompanyTruck.FUEL_PRICE_CENTS_PER_LITER)
        g.setColor(.09,.27,.21);g.rectangle('fill',65,190,510,48,4)
        g.setColor(.98,.95,.82);g.print('Refill delivery truck to full',81,202)
        g.printf(('$%.2f'):format(cost/100),445,202,105,'right')
        g.setColor(.94,.9,.77)
        g.printf(('Fuel: %.1f / %.0f L\nPrice: $%.2f / L\n%s'):format(fuel,CompanyTruck.TANK_LITERS,
            CompanyTruck.FUEL_PRICE_CENTS_PER_LITER/100,
            Station.truckAtPump(args.truck,args.world) and 'Truck is parked on the forecourt.'
                or 'Park the truck on the station forecourt to refuel.'),598,190,285)
    else
        local service=args.service
        for i,id in ipairs(Service.orders) do
            local name,price=Service.offer(service,id)
            local y=190+(i-1)*42
            g.setColor(i==v.selected and .24 or .09,.27,.21);g.rectangle('fill',65,y,510,39,4)
            g.setColor(.98,.95,.82);g.print(name,81,y+11);g.printf(('$%.2f'):format(price/100),445,y+11,105,'right')
        end
        local remaining=function(life,used)return math.max(0,life-used) end
        g.setColor(.94,.9,.77)
        g.printf(('Oil: %.1f mi left\nChain & sprockets: %.1f mi left'):format(
            remaining(Service.oilLife,service.oil),remaining(Service.chainLife,service.chain)),598,190,285)
        local selected=Service.orders[v.selected]
        local details=({fuel='Fuel is $1.60/L. Walk here for a refill if stranded.',
            oil='Fresh oil lasts 18 miles.',chain='Replace the chain and sprockets together. Rated for 42 miles.'})[selected]
        g.printf(details,598,317,275)
    end
    g.printf(v.notice or 'Choose a vehicle, select a service, then review the price.',70,535,810)
    g.setColor(.22,.33,.26);g.rectangle('fill',65,566,180,58,4);g.rectangle('fill',682,566,212,58,4)
    g.setColor(1,.92,.72);g.print('Leave station',95,586);g.print(v.quote and 'Confirm purchase' or 'Review / Buy',711,586)
    g.pop();return true
end
return Station
