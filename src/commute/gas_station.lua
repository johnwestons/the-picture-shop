local Service=require('src.commute.bike_service')
local Station={}
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
function Station.buy(rider,world,wallet,id,revision)
    if not Station.atCounter(rider,world) then return false,'Walk to the gas station counter first.' end
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
    elseif id=='chain' then s.chain=0
    else s.tire=id;s.tread=0 end
    s.revision=s.revision+1
    return true,('%s paid. $%.2f'):format(label,price/100)
end
-- One panel geometry for drawing and touch. Coordinates use a 960 x 678 canvas.
function Station.open()
    return {page='station',selected=1}
end
function Station.key(v,key,s,buy,close)
    if key=='escape' or key=='back' then close()
    elseif key=='up' or key=='down' then
        v.selected=(v.selected-1+(key=='up' and -1 or 1))%#Service.orders+1
        v.quote=nil;v.notice=nil
    elseif key=='return' or key=='kpenter' or key=='e' then
        local id=Service.orders[v.selected]
        local name,cost,available=Service.offer(s,id)
        if not available then v.notice='Already up to date.';return true end
        if v.quote~=s.revision then
            v.quote=s.revision;v.notice=('Buy %s for $%.2f? Press Buy again.'):format(name,cost/100)
        else
            v.quote=nil;v.notice=buy(id,s.revision)
        end
    end
    return true
end
function Station.pointer(v,x,y,s,buy,close)
    if y>=566 and y<=624 and x>=65 and x<=245 then close()
    elseif y>=566 and y<=624 and x>=682 and x<=894 then Station.key(v,'return',s,buy,close)
    elseif x>=65 and x<=575 and y>=165 and y<525 then
        v.selected=math.floor((y-165)/40)+1;v.quote=nil;v.notice=nil
    end
    return true
end
function Station.draw(v,s,cents,width,height)
    local g=love.graphics
    g.push('all');g.scale(width/960,height/678)
    g.setColor(.035,.065,.06,1);g.rectangle('fill',36,38,888,600,10)
    g.setColor(.96,.9,.7);g.print('GAS & TIRE   /   SERVICE COUNTER',70,70,0,1.6)
    g.print(('Household $%.2f    |    Tank %.2f / %.0f L    |    Odometer %.2f mi'):format(cents/100,s.fuel,Service.tank,s.miles),70,119)
    for i,id in ipairs(Service.orders) do
        local name,price=Service.offer(s,id)
        local y=165+(i-1)*40
        g.setColor(i==v.selected and .24 or .09,.27,.21);g.rectangle('fill',65,y,510,37,4)
        g.setColor(.98,.95,.82);g.print(name,81,y+10);g.printf(('$%.2f'):format(price/100),445,y+10,105,'right')
    end
    local tire=Service.tires[s.tire]
    local remaining=function(life,used)return math.max(0,life-used) end
    g.setColor(.94,.9,.77)
    g.printf(('Installed: %s\nTread: %.1f mi left\nOil: %.1f mi left\nChain & sprockets: %.1f mi left'):format(tire.name,
        remaining(tire.life,s.tread),remaining(Service.oilLife,s.oil),remaining(Service.chainLife,s.chain)),598,175,285)
    local choice=Service.tires[Service.orders[v.selected]]
    local details=choice and ('Road grip %.0f%%   Dirt grip %.0f%%\nRated life %.0f mi. Skids wear tread faster.'):format(choice.road*100,choice.dirt*100,choice.life)
        or ({fuel='Fuel is $1.60/L. Walk here for a refill if stranded.',oil='Fresh oil lasts 18 miles.',chain='Replace the chain and sprockets together. Rated for 42 miles.'})[Service.orders[v.selected]]
    g.printf(details,598,317,275)
    g.printf(v.notice or 'Select a service, then review the price.',70,535,810)
    g.setColor(.22,.33,.26);g.rectangle('fill',65,566,180,58,4);g.rectangle('fill',682,566,212,58,4)
    g.setColor(1,.92,.72);g.print('Leave station',95,586);g.print(v.quote and 'Confirm purchase' or 'Review / Buy',711,586)
    g.pop();return true
end
return Station
