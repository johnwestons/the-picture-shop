-- Customer service views remain local; only host-validated orders change a bike.
local Upgrades=require('src.commute.bike_upgrades')
local Paint=require('src.commute.bike_paint')
local Repairs=require('src.commute.bike_repairs')
local Tires=require('src.commute.bike_tires')
local TruckService=require('src.commute.truck_service')
local TruckMechanic=require('src.commute.truck_mechanic')
local Residents=require('src.home_residents')
local Fonts=require('src.screens.title_fonts')
local Station=require('src.commute.gas_station')
local TownStore=require('src.commute.town_store')
local Shop={}
local shopName=require('src.commute.sites').MECHANIC_NAME:upper()
local function interior() return require('src.commute.mechanic_interior') end
local function gasInterior() return require('src.commute.gas_station_interior') end
local function view(R) return R._commute and R._commute.mechanicOffer end
local function syncGroceryGate(v)
    if not v or v.interiorKind~='grocery' then return end
    local Grocery=require('src.commute.grocery_interior')
    local interior=v.interior
    v.cartPushed=interior and interior.cartPose and interior.cartPose.pushed==true or false
    v.atGroceryRegister=interior and Grocery.atCheckout(interior.pose) or false
end
local function requestGroceryCart(R,v,action)
    local pushed=action=='cartpush_on'
    local okay=require('src.commute.runtime').request(R,('cartpush:%d:%d'):format(v.token,pushed and 1 or 0))
    if not okay and v.interior then
        v.interior.cartPose.pushed=not pushed
        v.interior.pose.cartPushing=not pushed
    end
    return okay
end
local function stationArgs(R)
    local C=require('src.commute.runtime')
    local part=C.localPart(R)
    local trip=R.state.home.commute
    local selectedTruck=part.rider.vehicle=='truck' and part.rider.truck
        or require('src.commute.trip').nearestTruck(trip,part.rider,5.5) or trip.truck
    return {rider=part.rider,service=part.rider.bike.service,truck=selectedTruck,
        companyTruck=require('src.company_delivery_driver').ensure(R.state),
        householdCents=R.state.home.balanceCents,companyCash=R.state.money or 0,world=C.world(R),
        buy=function(id,rev,amountMl)
        local command=(id=='fuel' or id=='truckfuel')
            and ('station:%d:%d:%s:%d'):format(R.state.home.commute.token,rev,id,amountMl or 0)
            or ('station:%d:%d:%s'):format(R.state.home.commute.token,rev,id)
        local okay=C.request(R,command)
        if R.multiplayer:isClient() and okay then return true,'Purchase sent to the host.' end
        return okay,R.state.message or (okay and 'Order submitted.' or 'Order declined.')
    end,close=function()
        local offer=view(R)
        if offer and offer.returnToInterior and offer.interior then
            offer.page='stationFloor';offer.mode=nil;offer.amountMl=nil;offer.quote=nil
            offer.notice=nil;offer.pending=nil;offer.returnToInterior=nil
        else Shop.close(R) end
    end}
end
local function current(R) return Residents.get(R.state,R.World.player) end
local function money(cents) return ('$%.2f'):format(cents/100) end
local function mph(speed) return ('%d mph'):format(math.floor(speed*2.236936+.5)) end
local function releaseInterior(v)
    if not v or not v.interior then return end
    if v.interiorKind=='grocery' then require('src.commute.grocery_interior').release(v.interior)
    elseif v.interiorKind=='station' then gasInterior().release(v.interior)
    else interior().release(v.interior) end
end
function Shop.quote(R,level) return Upgrades.quote(R.state,R.World.player,level) end
function Shop.paintQuote(R,id) return Paint.quote(R.state,R.World.player,id) end
function Shop.repairQuote(R) return Repairs.quote(R.state,R.World.player) end
function Shop.tireQuote(R,id)
    local part=require('src.commute.runtime').localPart(R)
    return part and Tires.quote(R.state,part.rider.bike.service,id)
end
local function quote(R,v)
    if v.vehicleKind=='truck' then
        local trip=R.state.home.commute
        local okay,_,_,truck=TruckMechanic.canVisit(R.state,R.World.player,trip,
            require('src.commute.runtime').world(R),v.truckModel)
        if not okay then return nil end
        if v.service=='truck_repair' then return TruckMechanic.quote(R.state,truck,'repair') end
        if v.service=='truck_maintenance' then
            return TruckMechanic.quote(R.state,truck,'maintenance',v.selectedTruckMaintenance)
        end
        return TruckMechanic.quote(R.state,truck,'upgrade',v.selectedTruckUpgrade)
    end
    if v.service=='repair' then return Shop.repairQuote(R) end
    if v.service=='paint' then return Shop.paintQuote(R,v.selectedPaintId) end
    if v.service=='tires' then return Shop.tireQuote(R,v.selectedTireId) end
    return Shop.quote(R,v.selectedCategory or v.selected)
end
function Shop.close(R,silent)
    local v=view(R)
    if not silent and v and v.interiorKind=='grocery' and R.state.home.commute and R.state.home.commute.independent then
        R._commute.groceryExiting=true
        require('src.commute.runtime').request(R,'exitgrocery:'..R.state.home.commute.token)
    end
    releaseInterior(v)
    if R._commute then R._commute.mechanicOffer=nil end
end
function Shop.open(R)
    local C=require('src.commute.runtime')
    local bikeOkay,bikeReason=Upgrades.canVisit(R.state,R.World.player,R.state.home.commute,C.world(R))
    local truckOkay,truckReason,_,truck=TruckMechanic.canVisit(R.state,R.World.player,
        R.state.home.commute,C.world(R))
    if not bikeOkay and not truckOkay then R.state.message=truckReason or bikeReason;return false end
    local part=C.localPart(R)
    local useTruck=truckOkay
    if truckOkay and bikeOkay and part then
        local ped=part.rider.ped;local bike=part.rider.bike
        local truckDistance=(ped.x-truck.x)^2+(ped.z-truck.z)^2
        local bikeDistance=(ped.x-bike.x)^2+(ped.z-bike.z)^2
        useTruck=truckDistance<=bikeDistance
    end
    Shop.close(R);C.cancelCameraDrag(R)
    local resident=current(R)
    R._commute.mechanicOffer={token=R.state.home.commute.token,page='lobby',service='performance',
        selectedCategory='engine',selected=math.min(Upgrades.MAX_LEVEL,(resident.ridingUpgradeLevel or 0)+1),
        selectedPaintId=resident.ridingPaintId or Paint.DEFAULT,
        selectedTireId=part.rider.bike.service.tire,previewFrame=5,
        vehicleKind=useTruck and 'truck' or 'bike',truckModel=useTruck and truck.model or nil,
        selectedTruckMaintenance='oil',selectedTruckUpgrade='engine',
        interior=interior().new(R),elapsed=0}
    return true
end
function Shop.openTownStore(R,storeId,confirmed)
    local C=require('src.commute.runtime')
    local part=C.localPart(R)
    if (storeId=='grocery' or storeId=='gas-station')
        and not require('src.commute.town_characters').isOpen(R.state.home,storeId,
            require('src.business_calendar').absoluteHours(R.state)) then
        R.state.message=TownStore.title(storeId)..' is closed for the night. It is open 08:00–18:00.'
        return false
    end
    if not part or not TownStore.counter(part.rider,C.world(R),storeId) then
        R.state.message='Walk up to the store counter on foot first.';return false
    end
    if storeId=='grocery' and R.state.home.commute.independent and not confirmed then
        return C.request(R,'grocery:'..R.state.home.commute.token)
    end
    Shop.close(R,true);C.cancelCameraDrag(R)
    if R._commute then R._commute.mapOpen=false end
    local offer=TownStore.open(storeId,R.state.home.commute.token)
    local resident=current(R)
    offer.bikeInventoryRevision=resident and resident.bikeInventory and resident.bikeInventory.revision or 0
    offer.cartCapacity=TownStore.cartRoom(resident and resident.bikeInventory)
    offer.storeStock=R.state.groceryStore
    offer.calendarDay=R.state.calendar.totalDays
    offer.calendarWeekday=R.state.calendar.weekday
    if storeId=='grocery' then
        offer.page='groceryFloor';offer.interiorKind='grocery';offer.elapsed=0
        offer.interior=require('src.commute.grocery_interior').new(R)
    end
    R._commute.mechanicOffer=offer
    return true
end
function Shop.openStationStore(R)
    local C=require('src.commute.runtime')
    local currentView=view(R);local part=C.localPart(R)
    if not require('src.commute.town_characters').isOpen(R.state.home,'gas-station',
        require('src.business_calendar').absoluteHours(R.state)) then
        R.state.message='The gas station is closed for the night. It is open 08:00–18:00.'
        return false
    end
    if not currentView or currentView.page~='stationFloor' or not part
        or not TownStore.counter(part.rider,C.world(R),'gas-station') then
        R.state.message='Walk up to the gas station counter before shopping.';return false
    end
    local offer=TownStore.open('gas-station',currentView.token)
    local resident=current(R)
    offer.bikeInventoryRevision=resident and resident.bikeInventory and resident.bikeInventory.revision or 0
    offer.cartCapacity=TownStore.cartRoom(resident and resident.bikeInventory)
    offer.storeStock=R.state.groceryStore
    offer.calendarDay=R.state.calendar.totalDays
    offer.calendarWeekday=R.state.calendar.weekday
    offer.interiorKind='station';offer.interior=currentView.interior
    offer.returnToInterior=true;offer.elapsed=currentView.elapsed or 0
    C.cancelCameraDrag(R)
    if R._commute then R._commute.mapOpen=false;R._commute.mechanicOffer=offer end
    return true
end
function Shop.openStationInterior(R)
    local C=require('src.commute.runtime')
    local part=C.localPart(R)
    if not require('src.commute.town_characters').isOpen(R.state.home,'gas-station',
        require('src.business_calendar').absoluteHours(R.state)) then
        R.state.message='The gas station is closed for the night. It is open 08:00–18:00.'
        return false
    end
    if not part or not Station.atCounter(part.rider,C.world(R)) then
        R.state.message='Walk to the gas station door before going inside.';return false
    end
    Shop.close(R,true);C.cancelCameraDrag(R)
    if R._commute then R._commute.mapOpen=false end
    R._commute.mechanicOffer={token=R.state.home.commute.token,page='stationFloor',
        interiorKind='station',interior=gasInterior().new(R),elapsed=0}
    return true
end
function Shop.catalog(R)
    local v=view(R);if not v or v.pending or v.page=='install' then return false end
    v.service='performance';v.page='catalog';v.notice=nil;v.review=nil;return true
end
function Shop.paint(R)
    local v=view(R);if not v or v.pending or v.page=='install' then return false end
    v.service='paint';v.page='catalog';v.notice=nil;v.review=nil;return true
end
function Shop.tires(R)
    local v=view(R);if not v or v.pending or v.page=='install' then return false end
    local part=require('src.commute.runtime').localPart(R)
    v.service='tires';v.page='catalog';v.selectedTireId=part.rider.bike.service.tire;v.notice=nil;v.review=nil
    return true
end
function Shop.repair(R)
    local v=view(R);if not v or v.pending or v.page=='install' then return false end
    v.service='repair';v.page='catalog';v.notice=nil;v.review=nil;return true
end
local function browse(R)
    local v=view(R)
    if v and v.vehicleKind=='truck' then
        local trip=R.state.home.commute
        local okay,_,_,truck=TruckMechanic.canVisit(R.state,R.World.player,trip,
            require('src.commute.runtime').world(R),v.truckModel)
        if not okay then v.notice='Park the truck in the mechanic area before ordering service.';return false end
        v.service=((truck.damage or 0)>0 or truck.service.mechanicalFailure)
            and 'truck_repair' or 'truck_maintenance'
        v.page='truck_catalog';v.notice=nil;v.review=nil;return true
    end
    if (current(R).ridingDamage or 0)>0 then return Shop.repair(R) end
    return Shop.catalog(R)
end
function Shop.selectPaint(R,id)
    local v=view(R)
    if not v or v.pending or v.page=='install' or not Paint.valid(id) then return false end
    v.service='paint';v.page='catalog';v.selectedPaintId=id;v.notice=nil;v.review=nil;return true
end
local function confirmTruck(R,v)
    local q=quote(R,v);if not q then return false end
    if q.status~='available' then
        v.notice=q.status=='healthy' and 'This truck service is not due.'
            or q.status=='maxed' and 'This component is already fully upgraded.'
            or ('You need '..money(q.shortfallCents or 0)..' more in household funds.')
        return false
    end
    if v.page~='truck_confirm' or not v.review then
        v.review={service=v.service,model=v.truckModel,revision=q.revision,
            item=v.selectedTruckMaintenance,category=v.selectedTruckUpgrade,
            level=q.level,damage=q.damage,failed=q.failed}
        v.page='truck_confirm';v.notice=nil;return true
    end
    local review=v.review
    if review.service~=v.service or review.model~=v.truckModel or review.revision~=q.revision
        or v.service=='truck_repair' and (review.damage~=q.damage or review.failed~=q.failed)
        or v.service=='truck_maintenance' and review.item~=v.selectedTruckMaintenance
        or v.service=='truck_upgrades' and (review.category~=v.selectedTruckUpgrade or review.level~=q.level) then
        v.page='truck_catalog';v.review=nil
        v.notice='The truck changed after this quote. Review the current service before paying.'
        return false
    end
    local command,pending
    if v.service=='truck_repair' then
        pending={kind='repair',previous=q.revision,damage=q.damage,failed=q.failed,
            name='Truck repairs',elapsed=0}
        command=('truckrepair:%d:%s:%d:%d:%d'):format(v.token,v.truckModel,q.revision,q.damage,q.failed and 1 or 0)
    elseif v.service=='truck_maintenance' then
        pending={kind='maintenance',previous=q.revision,item=v.selectedTruckMaintenance,
            name=q.item.name,elapsed=0}
        command=('truckservice:%d:%s:%d:%s'):format(v.token,v.truckModel,q.revision,v.selectedTruckMaintenance)
    else
        pending={kind='upgrade',previous=q.revision,category=v.selectedTruckUpgrade,level=q.level,
            name=q.offer.name,elapsed=0}
        command=('truckupgrade:%d:%s:%s:%d:%d:%d'):format(v.token,v.truckModel,v.selectedTruckUpgrade,
            q.revision,q.currentLevel,q.level)
    end
    v.pending=pending
    local okay=require('src.commute.runtime').request(R,command)
    if not okay then v.pending=nil;v.notice=R.state.message;v.page='truck_catalog';return false end
    v.notice='Waiting for the mechanic to confirm your order...'
    return true
end
function Shop.confirm(R)
    local v=view(R);if not v or v.pending or v.page=='install' then return false end
    if v.vehicleKind=='truck' then return confirmTruck(R,v) end
    local q=quote(R,v);if not q then return false end
    if q.status~='available' then
        v.notice=q.status=='healthy' and 'Your bike is in full working order.'
            or q.status=='current' and v.service=='tires' and 'These tires are installed and in good condition.'
            or q.status=='current' and 'Your bike already has this finish.'
            or q.status=='installed' and 'This kit is already installed.'
            or q.status=='locked' and 'Install the earlier kit first.'
            or q.status=='maxed' and 'This component is already at its highest level.'
            or ('You need '..money(q.shortfallCents)..' more in household funds.')
        return false
    end
    if v.page~='confirm' or not v.review then
        v.review={service=v.service,revision=q.revision,paintId=v.selectedPaintId,tireId=v.selectedTireId,
            level=q.level,damage=q.damage,category=v.selectedCategory}
        v.page='confirm';v.notice=nil;return true
    end
    if v.review.service~=v.service or v.service=='paint'
        and (v.review.revision~=q.revision or v.review.paintId~=v.selectedPaintId)
        or v.service=='repair' and (v.review.revision~=q.revision or v.review.damage~=q.damage)
        or v.service=='tires' and (v.review.revision~=q.revision or v.review.tireId~=v.selectedTireId)
        or v.service=='performance' and (v.review.category~=v.selectedCategory or v.review.level~=q.level) then
        v.page='catalog';v.review=nil
        v.notice='Your bike changed after this quote. Review the current service before paying.'
        return false
    end
    local command
    if v.service=='repair' then
        v.pending={kind='repair',previous=q.revision,costCents=q.priceCents,name='Collision repairs',elapsed=0}
        command=('bikerepair:%d:%d:%d'):format(v.token,q.revision,q.damage)
    elseif v.service=='paint' then
        v.pending={kind='paint',paintId=v.selectedPaintId,previous=q.revision,
            costCents=q.priceCents,name=q.offer.name,elapsed=0}
        command=('bikepaint:%d:%d:%s'):format(v.token,q.revision,v.selectedPaintId)
    elseif v.service=='tires' then
        v.pending={kind='tire',tireId=v.selectedTireId,previous=q.revision,
            costCents=q.priceCents,name=q.offer.name,elapsed=0}
        command=('biketire:%d:%d:%s'):format(v.token,q.revision,v.selectedTireId)
    elseif v.service=='performance' then
        v.pending={kind='performance',category=v.selectedCategory,level=q.offer.level,previous=q.currentLevel,
            costCents=q.offer.costCents,name=q.offer.name,elapsed=0}
        command=('bikepart:%d:%s:%d:%d'):format(v.token,v.selectedCategory,q.currentLevel,q.offer.level)
    else
        v.pending={kind='performance',level=v.selected,previous=q.level,
            costCents=q.offer.costCents,name=q.offer.name,elapsed=0}
        command=('bikeupgrade:%d:%d:%d'):format(v.token,q.level,v.selected)
    end
    local okay=require('src.commute.runtime').request(R,command)
    if not okay then v.pending=nil;v.notice=R.state.message;v.page='catalog';return false end
    v.notice='Waiting for the mechanic to confirm your order...'
    return true
end
function Shop.update(R,dt)
    local v=view(R);if not v then return false end
    if v.page=='station' then return Station.update(v,dt,stationArgs(R)) end
    if v.page=='stationFloor' then
        local trip=R.state.home and R.state.home.commute
        if not trip or trip.token~=v.token then Shop.close(R);return false end
        local action=gasInterior().update(v.interior,R,dt)
        if action=='shop' then Shop.openStationStore(R)
        elseif action=='counter' then
            local panel=Station.open('counter')
            panel.token=v.token;panel.interior=v.interior;panel.interiorKind='station'
            panel.elapsed=v.elapsed or 0;panel.returnToInterior=true
            v.interior=nil;R._commute.mechanicOffer=panel
        elseif action=='exit' then Shop.close(R) end
        return true
    end
    local trip=R.state.home.commute
    if not trip or trip.token~=v.token then Shop.close(R);return false end
    if v.page=='store' then
        syncGroceryGate(v)
        local resident=current(R)
        TownStore.update(v,R.state,dt,resident and resident.bikeInventory)
        return true
    end
    dt=math.max(0,math.min(.1,dt or 0));v.elapsed=v.elapsed+dt
    if v.interiorKind=='grocery' then
        local Grocery=require('src.commute.grocery_interior')
        v.interior.cartCount=TownStore.cartCount(v.cart)
        v.interior.cartTotalCents=TownStore.cartTotal(v.cart) or 0
        v.interior.cartItems=v.cart
        syncGroceryGate(v)
        local action=Grocery.update(v.interior,R,dt)
        if action then
            syncGroceryGate(v)
            if TownStore.category(v,action) then v.notice=nil;v.review=nil end
        end
        return true
    end
    interior().update(v.interior,R,dt)
    if v.vehicleKind=='truck' then
        local pending=v.pending
        if pending then
            pending.elapsed=pending.elapsed+dt
            local okay,_,_,truck=TruckMechanic.canVisit(R.state,R.World.player,trip,
                require('src.commute.runtime').world(R),v.truckModel)
            local done=false
            if okay and pending.kind=='repair' then
                done=truck.repairRevision==pending.previous+1 and truck.damage==0
                    and not truck.service.mechanicalFailure
            elseif okay and pending.kind=='maintenance' then
                local field=({oil='oilMiles',oil_filter='oilFilterMiles',air_filter='airFilterMiles',
                    spark_plugs='sparkPlugMiles',coolant='coolantMiles',tires='tireMiles',brakes='brakeMiles'})[pending.item]
                done=field and truck.service.revision>pending.previous and truck.service[field]==0
            elseif okay and pending.kind=='upgrade' then
                done=truck.service.upgrades[pending.category]>=pending.level
            end
            if done then
                v.notice=pending.name..' completed.';v.pending=nil;v.page='truck_catalog';v.review=nil
            elseif pending.elapsed>=5 then
                v.pending=nil;v.page='truck_catalog'
                v.notice='No service confirmation received. Review your balance and try again.'
            end
        end
        return true
    end
    if v.pending then
        local p=v.pending;local resident=current(R);p.elapsed=p.elapsed+dt
        local confirmed=resident and (p.kind=='paint'
            and (resident.ridingPaintRevision or 0)==p.previous+1 and resident.ridingPaintId==p.paintId
            or p.kind=='repair' and (resident.ridingRepairRevision or 0)==p.previous+1 and resident.ridingDamage==0
            or p.kind=='tire' and resident.ridingService and (resident.ridingService.revision or 0)==p.previous+1
                and resident.ridingService.tire==p.tireId
            or p.kind=='performance' and p.category and resident.ridingUpgradeParts
                and (resident.ridingUpgradeParts[p.category] or 0)>=p.level
            or p.kind=='performance' and not p.category and (resident.ridingUpgradeLevel or 0)>=p.level)
        if confirmed then
            v.receipt={kind=p.kind,name=p.name,costCents=p.costCents,level=p.level,category=p.category,paintId=p.paintId}
            v.pending=nil;v.page='install';v.installTime=0;v.notice=nil
        elseif p.kind=='paint' and resident and (resident.ridingPaintRevision or 0)>p.previous then
            v.pending=nil;v.page='catalog';v.notice='Your bike finish changed. Review the current finish before ordering again.'
        elseif p.kind=='repair' and resident and (resident.ridingRepairRevision or 0)>p.previous then
            v.pending=nil;v.page='catalog';v.notice='Your repair record changed. Check the bike condition before ordering again.'
        elseif p.kind=='tire' and resident and resident.ridingService
            and (resident.ridingService.revision or 0)>p.previous then
            v.pending=nil;v.page='catalog';v.notice='Your tire record changed. Review the current tires before ordering again.'
        elseif p.elapsed>=5 then
            v.pending=nil;v.page='catalog'
            v.notice='No installation confirmed. Review your balance and retry; completed orders are never charged twice.'
        end
    elseif v.page=='install' then
        v.installTime=v.installTime+dt
        if v.installTime>=2 then v.page='receipt' end
    end
    return true
end
local function paintIndex(id)
    for i,finish in ipairs(Paint.CATALOG) do if finish.id==id then return i end end
    return 1
end
function Shop.keypressed(R,key)
    local v=view(R);if not v then return false end
    if v.page=='station' then return Station.key(v,key,stationArgs(R)) end
    if v.page=='stationFloor' then
        local action=gasInterior().keypressed(v.interior,key)
        if action=='shop' then Shop.openStationStore(R)
        elseif action=='counter' then
            local panel=Station.open('counter')
            panel.token=v.token;panel.interior=v.interior;panel.interiorKind='station'
            panel.elapsed=v.elapsed or 0;panel.returnToInterior=true
            v.interior=nil;R._commute.mechanicOffer=panel
        elseif action=='exit' then Shop.close(R) end
        return true
    end
    if v.page=='store' then
        syncGroceryGate(v)
        local C=require('src.commute.runtime')
        local resident=current(R)
        v.bikeInventoryRevision=resident and resident.bikeInventory and resident.bikeInventory.revision or 0
        v.cartCapacity=TownStore.cartRoom(resident and resident.bikeInventory)
        v.storeStock=R.state.groceryStore
        v.calendarDay=R.state.calendar.totalDays
        v.calendarWeekday=R.state.calendar.weekday
        local function buy(storeId,productId,quantity,revision)
            local okay=C.request(R,('storebuy:%d:%d:%s:%s:%d'):format(v.token,revision,storeId,productId,quantity))
            if R.multiplayer:isClient() and okay then return 'Purchase sent to the host.',true end
            return R.state.message or (okay and 'Purchase complete.' or 'Purchase declined.'),okay
        end
        local function buyCart(_,cart,revision,payload)
            payload=payload or TownStore.encodeCart(cart)
            if not payload then return 'Your cart is empty.',false end
            local okay=C.request(R,('storecart:%d:%d:%s'):format(v.token,revision,payload))
            if R.multiplayer:isClient() and okay then return 'Checkout sent to the host.',true end
            return R.state.message or (okay and 'Checkout complete.' or 'Checkout declined.'),okay
        end
        local function closeStore()
            if v.interiorKind=='grocery' or v.interiorKind=='station' and v.returnToInterior then
                v.page=v.interiorKind=='grocery' and 'groceryFloor' or 'stationFloor'
                v.notice=nil;v.review=nil;v.returnToInterior=nil
            else Shop.close(R) end
        end
        return TownStore.key(v,key,R.state.home.revision,buy,closeStore,buyCart)
    end
    if v.interiorKind=='grocery' and v.page=='groceryFloor' then
        local action=require('src.commute.grocery_interior').keypressed(v.interior,key)
        if action=='cartpush_on' or action=='cartpush_off' then requestGroceryCart(R,v,action)
        elseif action and action~='exit' then
            syncGroceryGate(v)
            if TownStore.category(v,action) then v.notice=nil;v.review=nil end
        elseif action=='exit' then Shop.close(R) end
        return true
    end
    if v.vehicleKind=='truck' and (key=='escape' or key=='back') then
        if v.page=='lobby' then Shop.close(R)
        elseif not v.pending then
            if v.page=='truck_confirm' then v.page='truck_catalog';v.review=nil
            else v.page='lobby' end
            v.notice=nil
        end
        return true
    end
    if key=='escape' or key=='back' then
        if v.page=='lobby' then Shop.close(R)
        elseif not v.pending and v.page~='install' then v.page='lobby';v.notice=nil end
        return true
    end
    if v.pending or v.page=='install' then return true end
    if v.page=='lobby' then
        local action=interior().keypressed(v.interior,R,key)
        if action=='catalog' then browse(R) elseif action=='exit' then Shop.close(R) end
    elseif v.vehicleKind=='truck' and v.page=='truck_catalog' then
        if key=='tab' then
            v.service=v.service=='truck_repair' and 'truck_maintenance'
                or v.service=='truck_maintenance' and 'truck_upgrades' or 'truck_repair'
            v.notice=nil;v.review=nil
        elseif key=='return' or key=='e' or key=='kpenter' then Shop.confirm(R)
        elseif v.service=='truck_maintenance' then
            local items=TruckService.MAINTENANCE;local index=1
            for i,item in ipairs(items) do if item.id==v.selectedTruckMaintenance then index=i;break end end
            local n=tonumber(key)
            if n and n>=1 and n<=#items then v.selectedTruckMaintenance=items[n].id;v.notice=nil;v.review=nil
            elseif key=='up' or key=='left' then v.selectedTruckMaintenance=items[math.max(1,index-1)].id;v.notice=nil;v.review=nil
            elseif key=='down' or key=='right' then v.selectedTruckMaintenance=items[math.min(#items,index+1)].id;v.notice=nil;v.review=nil end
        elseif v.service=='truck_upgrades' then
            local order={'engine','tires','brakes','suspension','durability'};local index=1
            for i,id in ipairs(order) do if id==v.selectedTruckUpgrade then index=i;break end end
            local n=tonumber(key)
            if n and n>=1 and n<=#order then v.selectedTruckUpgrade=order[n];v.notice=nil;v.review=nil
            elseif key=='up' or key=='left' then v.selectedTruckUpgrade=order[math.max(1,index-1)];v.notice=nil;v.review=nil
            elseif key=='down' or key=='right' then v.selectedTruckUpgrade=order[math.min(#order,index+1)];v.notice=nil;v.review=nil end
        end
    elseif v.page=='receipt' then
        if key=='return' or key=='e' or key=='kpenter' then
            v.page='lobby';v.selected=math.min(3,(current(R).ridingUpgradeLevel or 0)+1)
        end
    elseif key=='tab' and v.page=='catalog' then
        if v.service=='performance' then Shop.tires(R)
        elseif v.service=='tires' then Shop.paint(R)
        elseif v.service=='paint' then Shop.repair(R)
        else Shop.catalog(R) end
    elseif key=='return' or key=='e' or key=='kpenter' then Shop.confirm(R)
    elseif v.page=='catalog' and v.service=='paint' then
        local n=tonumber(key);local index=paintIndex(v.selectedPaintId)
        if n and n>=1 and n<=#Paint.CATALOG then Shop.selectPaint(R,Paint.CATALOG[n].id)
        elseif key=='left' then Shop.selectPaint(R,Paint.CATALOG[math.max(1,index-1)].id)
        elseif key=='right' then Shop.selectPaint(R,Paint.CATALOG[math.min(#Paint.CATALOG,index+1)].id)
        elseif key=='up' then Shop.selectPaint(R,Paint.CATALOG[math.max(1,index-2)].id)
        elseif key=='down' then Shop.selectPaint(R,Paint.CATALOG[math.min(#Paint.CATALOG,index+2)].id)
        elseif key=='q' then v.previewFrame=(v.previewFrame-2)%16+1
        elseif key=='r' then v.previewFrame=v.previewFrame%16+1 end
    elseif v.page=='catalog' and v.service=='performance' then
        local n=tonumber(key)
        local index=1;for i,category in ipairs(Upgrades.CATEGORIES) do if category.id==v.selectedCategory then index=i;break end end
        if n and n>=1 and n<=#Upgrades.CATEGORIES then v.selectedCategory=Upgrades.CATEGORIES[n].id;v.notice=nil;v.review=nil
        elseif key=='up' or key=='left' then v.selectedCategory=Upgrades.CATEGORIES[math.max(1,index-1)].id;v.notice=nil;v.review=nil
        elseif key=='down' or key=='right' then v.selectedCategory=Upgrades.CATEGORIES[math.min(#Upgrades.CATEGORIES,index+1)].id;v.notice=nil;v.review=nil end
    elseif v.page=='catalog' and v.service=='tires' then
        local n=tonumber(key);local index=1
        for i,id in ipairs(require('src.commute.bike_service').tireOrder) do
            if id==v.selectedTireId then index=i;break end
        end
        if n and n>=1 and n<=#require('src.commute.bike_service').tireOrder then
            v.selectedTireId=require('src.commute.bike_service').tireOrder[n];v.notice=nil;v.review=nil
        elseif key=='up' or key=='left' then
            v.selectedTireId=require('src.commute.bike_service').tireOrder[math.max(1,index-1)];v.notice=nil;v.review=nil
        elseif key=='down' or key=='right' then
            v.selectedTireId=require('src.commute.bike_service').tireOrder[math.min(#require('src.commute.bike_service').tireOrder,index+1)];v.notice=nil;v.review=nil
        end
    end
    return true
end
local function contains(b,x,y) return x>=b.x and y>=b.y and x<=b.x+b.w and y<=b.y+b.h end
local buttons={back={x=96,y=574,w=205,h=44},buy={x=570,y=574,w=292,h=44},
    performance={x=430,y=114,w=130,h=44},tires={x=568,y=114,w=88,h=44},
    paint={x=664,y=114,w=88,h=44},repair={x=760,y=114,w=102,h=44},
    previous={x=500,y=396,w=44,h=40},next={x=678,y=396,w=44,h=40}}
local truckTabs={repair={x=96,y=130,w=150,h=42},maintenance={x=254,y=130,w=190,h=42},
    upgrades={x=452,y=130,w=160,h=42}}
local truckUpgradeOrder={'engine','tires','brakes','suspension','durability'}
local function truckRow(index) return {x=96,y=187+(index-1)*54,w=250,h=48} end
local function categoryRow(index) return {x=96,y=170+(index-1)*49,w=238,h=45} end
local function swatch(index)
    return {x=96+(index-1)%2*124,y=170+math.floor((index-1)/2)*92,w=114,h=80}
end
function Shop.layout()
    local layout={performance=buttons.performance,tires=buttons.tires,paint=buttons.paint,repair=buttons.repair,back=buttons.back,buy=buttons.buy,
        previous=buttons.previous,next=buttons.next,swatches={},categories={}}
    for i=1,#Paint.CATALOG do layout.swatches[i]=swatch(i) end
    for i=1,#Upgrades.CATEGORIES do layout.categories[i]=categoryRow(i) end
    return layout
end
function Shop.pointer(R,x,y)
    local v=view(R);if not v then return false end
    if v.page=='station' then return Station.pointer(v,x*960/R.Config.baseWidth,y*678/R.Config.baseHeight,stationArgs(R)) end
    if v.page=='stationFloor' then
        local action=gasInterior().pointer(v.interior,R,x,y)
        if action=='shop' then Shop.openStationStore(R)
        elseif action=='counter' then
            local panel=Station.open('counter')
            panel.token=v.token;panel.interior=v.interior;panel.interiorKind='station'
            panel.elapsed=v.elapsed or 0;panel.returnToInterior=true
            v.interior=nil;R._commute.mechanicOffer=panel
        elseif action=='exit' then Shop.close(R) end
        return true
    end
    if v.page=='store' then
        syncGroceryGate(v)
        local C=require('src.commute.runtime')
        local resident=current(R)
        v.bikeInventoryRevision=resident and resident.bikeInventory and resident.bikeInventory.revision or 0
        v.cartCapacity=TownStore.cartRoom(resident and resident.bikeInventory)
        v.storeStock=R.state.groceryStore
        v.calendarDay=R.state.calendar.totalDays
        v.calendarWeekday=R.state.calendar.weekday
        local function buy(storeId,productId,quantity,revision)
            local okay=C.request(R,('storebuy:%d:%d:%s:%s:%d'):format(v.token,revision,storeId,productId,quantity))
            if R.multiplayer:isClient() and okay then return 'Purchase sent to the host.',true end
            return R.state.message or (okay and 'Purchase complete.' or 'Purchase declined.'),okay
        end
        local function buyCart(_,cart,revision,payload)
            payload=payload or TownStore.encodeCart(cart)
            if not payload then return 'Your cart is empty.',false end
            local okay=C.request(R,('storecart:%d:%d:%s'):format(v.token,revision,payload))
            if R.multiplayer:isClient() and okay then return 'Checkout sent to the host.',true end
            return R.state.message or (okay and 'Checkout complete.' or 'Checkout declined.'),okay
        end
        local function closeStore()
            if v.interiorKind=='grocery' or v.interiorKind=='station' and v.returnToInterior then
                v.page=v.interiorKind=='grocery' and 'groceryFloor' or 'stationFloor'
                v.notice=nil;v.review=nil;v.returnToInterior=nil
            else Shop.close(R) end
        end
        return TownStore.pointer(v,x*960/R.Config.baseWidth,y*678/R.Config.baseHeight,
            R.state.home.revision,buy,closeStore,buyCart)
    end
    if v.interiorKind=='grocery' and v.page=='groceryFloor' then
        local action=require('src.commute.grocery_interior').pointer(v.interior,R,x,y)
        if action=='cartpush_on' or action=='cartpush_off' then requestGroceryCart(R,v,action)
        elseif action and action~='exit' then
            syncGroceryGate(v)
            if TownStore.category(v,action) then v.notice=nil;v.review=nil end
        elseif action=='exit' then Shop.close(R) end
        return true
    end
    if v.page=='lobby' then
        local action=interior().pointer(v.interior,R,x,y)
        if action=='catalog' then browse(R) elseif action=='exit' then Shop.close(R) end
        return true
    end
    x,y=x*960/R.Config.baseWidth,y*678/R.Config.baseHeight
    if v.pending or v.page=='install' then return true end
    if v.vehicleKind=='truck' then
        if contains(buttons.back,x,y) then Shop.keypressed(R,'escape');return true end
        if v.page=='truck_catalog' then
            if contains(buttons.buy,x,y) then Shop.confirm(R);return true end
            if contains(truckTabs.repair,x,y) then v.service='truck_repair';v.notice=nil;v.review=nil
            elseif contains(truckTabs.maintenance,x,y) then v.service='truck_maintenance';v.notice=nil;v.review=nil
            elseif contains(truckTabs.upgrades,x,y) then v.service='truck_upgrades';v.notice=nil;v.review=nil
            elseif v.service=='truck_maintenance' then
                for n,item in ipairs(TruckService.MAINTENANCE) do if contains(truckRow(n),x,y) then
                    v.selectedTruckMaintenance=item.id;v.notice=nil;v.review=nil;break end end
            elseif v.service=='truck_upgrades' then
                for n,id in ipairs(truckUpgradeOrder) do if contains(truckRow(n),x,y) then
                    v.selectedTruckUpgrade=id;v.notice=nil;v.review=nil;break end end
            end
        end
        return true
    end
    if contains(buttons.back,x,y) then Shop.keypressed(R,'escape');return true end
    if contains(buttons.buy,x,y) then
        if v.page=='receipt' then Shop.keypressed(R,'return') else Shop.confirm(R) end
    elseif v.page=='catalog' then
        if contains(buttons.performance,x,y) then Shop.catalog(R)
        elseif contains(buttons.tires,x,y) then Shop.tires(R)
        elseif contains(buttons.paint,x,y) then Shop.paint(R)
        elseif contains(buttons.repair,x,y) then Shop.repair(R)
        elseif v.service=='paint' then
            if contains(buttons.previous,x,y) then v.previewFrame=(v.previewFrame-2)%16+1
            elseif contains(buttons.next,x,y) then v.previewFrame=v.previewFrame%16+1
            else for n,finish in ipairs(Paint.CATALOG) do
                if contains(swatch(n),x,y) then Shop.selectPaint(R,finish.id);break end
            end end
        elseif v.service=='performance' then
            for n,category in ipairs(Upgrades.CATEGORIES) do if contains(categoryRow(n),x,y) then
                v.selectedCategory=category.id;v.notice=nil;v.review=nil;break
            end end
        elseif v.service=='tires' then
            local Service=require('src.commute.bike_service')
            for n,id in ipairs(Service.tireOrder) do if contains({x=96,y=170+(n-1)*52,w=238,h=46},x,y) then
                v.selectedTireId=id;v.notice=nil;v.review=nil;break
            end end
        end
    end
    return true
end
local function text(value,x,y,w,size,color,align)
    local g=love.graphics;g.setFont(Fonts.get('metal',size or 18))
    g.setColor(unpack(color or {.87,.92,.88,1}));g.printf(value,x,y,w,align or 'left')
end
local function button(b,label,enabled)
    local g=love.graphics;g.setColor(enabled and .16 or .09,enabled and .30 or .13,enabled and .25 or .12,1)
    g.rectangle('fill',b.x,b.y,b.w,b.h,5,5)
    g.setColor(enabled and .73 or .35,enabled and .79 or .39,enabled and .62 or .35,1)
    g.rectangle('line',b.x,b.y,b.w,b.h,5,5)
    text(label,b.x+8,b.y+(b.h-20)/2,b.w-16,17,enabled and {1,.93,.71,1} or {.48,.53,.48,1},'center')
end
local function drawPaint(R,v,q)
    local g=love.graphics
    for n,finish in ipairs(Paint.CATALOG) do
        local b=swatch(n);local selected=v.selectedPaintId==finish.id
        g.setColor(.075,.12,.11,1);g.rectangle('fill',b.x,b.y,b.w,b.h,5)
        g.setColor(unpack(finish.color));g.rectangle('fill',b.x+9,b.y+8,b.w-18,34,4)
        if q.paintId==finish.id then text('CURRENT',b.x+9,b.y+17,b.w-18,12,{.04,.06,.05,1},'center') end
        text(finish.name:gsub('Original ',''),b.x+5,b.y+50,b.w-10,16,nil,'center')
        g.setColor(selected and 1 or .30,selected and .85 or .40,selected and .47 or .34,1)
        g.setLineWidth(selected and 2 or 1);g.rectangle('line',b.x,b.y,b.w,b.h,5);g.setLineWidth(1)
    end
    text('REPAINT '..money(Paint.COST_CENTS),96,540,238,17,{1,.85,.47,1},'center')
    text(v.page=='confirm' and 'CONFIRM PAINT WORK' or q.offer.name,366,172,468,27,{1,.85,.47,1})
    text('Live preview / paint finish',366,214,468,17,{.66,.79,.76,1})
    g.setColor(.02,.045,.043,1);g.rectangle('fill',366,245,496,145,8)
    interior().drawBike(v.interior,R,614,382,.95,v.selectedPaintId,v.previewFrame)
    button(buttons.previous,'<',v.page=='catalog');button(buttons.next,'>',v.page=='catalog')
    text(('VIEW %d / 16'):format(v.previewFrame),550,408,122,14,nil,'center')
    text('Current: '..q.current.name,366,451,468,18)
    local note=v.notice or (q.status=='current' and 'This is already your bike finish. No payment needed.'
        or q.status=='unaffordable' and 'Need '..money(q.shortfallCents)..' more in household funds.'
        or v.page=='confirm' and 'Pay '..money(q.priceCents)..' to repaint your bike? Preparation and labor are included.'
        or 'Choose a color, review the quote, then approve the repaint.')
    text(note,366,490,468,18,{1,.85,.47,1})
end
local function drawPerformance(R,v,q)
    local g=love.graphics
    for n,category in ipairs(Upgrades.CATEGORIES) do
        local b=categoryRow(n);local row=Shop.quote(R,category.id);local selected=category.id==v.selectedCategory
        g.setColor(selected and .16 or .075,selected and .25 or .12,selected and .21 or .11,1)
        g.rectangle('fill',b.x,b.y,b.w,b.h,5,5)
        text(category.name,b.x+10,b.y+5,b.w-20,17)
        local detail=row.status=='maxed' and 'LEVEL 3 / 3   MAXED'
            or ('LEVEL %d / 3   NEXT %s'):format(row.currentLevel,money(row.offer.costCents))
        text(detail,b.x+10,b.y+27,b.w-20,12,row.status=='unaffordable' and {1,.66,.52,1} or {.68,.79,.72,1})
    end
    local compare=q.after or q.current
    local heading=q.status=='maxed' and 'FULLY UPGRADED' or q.offer.name
    text(v.page=='confirm' and 'CONFIRM COMPONENT UPGRADE' or heading,366,172,468,25,{1,.85,.47,1})
    text(q.category.part..(' · %d → %d'):format(q.currentLevel,q.offer and q.offer.level or q.currentLevel),366,208,496,14,{.76,.85,.82,1})
    if q.offer then text(q.offer.description,366,234,496,16) end
    text('STAT',366,284,130,14,{.76,.85,.82,1})
    text('NOW',499,284,72,14,{.76,.85,.82,1},'right')
    text('WITH',579,284,72,14,{1,.85,.47,1},'right')
    text('OUTPUT',660,284,92,14,{.76,.85,.82,1},'center')
    text('CHANGE',762,284,94,14,{.76,.85,.82,1},'right')
    local rows={
        {name='Power',a=q.current.powerHp,b=compare.powerHp,limit=25,format=function(x)return ('%.1f hp'):format(x)end},
        {name='Torque',a=q.current.torqueNm,b=compare.torqueNm,limit=30,format=function(x)return ('%.1f Nm'):format(x)end},
        {name='Top speed',a=q.current.maxSpeed*2.236936,b=compare.maxSpeed*2.236936,limit=80,format=function(x)return ('%.0f mph'):format(x)end},
        {name='Boost speed',a=q.current.boostMaxSpeed*2.236936,b=compare.boostMaxSpeed*2.236936,limit=80,format=function(x)return ('%.0f mph'):format(x)end},
        {name='Acceleration',a=q.current.acceleration/1.15*100,b=compare.acceleration/1.15*100,limit=250,format=function(x)return ('%.0f%%'):format(x)end},
        {name='Hill pull',a=q.current.hillPull*100,b=compare.hillPull*100,limit=250,format=function(x)return ('%.0f%%'):format(x)end},
        {name='Braking',a=q.current.brakeMultiplier*100,b=compare.brakeMultiplier*100,limit=200,format=function(x)return ('%.0f%%'):format(x)end},
        {name='Handling',a=(q.current.gripMultiplier+q.current.responseMultiplier+q.current.turnMultiplier)/3*100,
            b=(compare.gripMultiplier+compare.responseMultiplier+compare.turnMultiplier)/3*100,limit=200,format=function(x)return ('%.0f%%'):format(x)end},
        {name='Durability',a=(1-q.current.damageMultiplier)*100,b=(1-compare.damageMultiplier)*100,limit=50,format=function(x)return ('%.0f%% less'):format(x)end},
    }
    for n,row in ipairs(rows) do
        local y=304+(n-1)*23
        text(row.name,366,y,130,14)
        text(row.format(row.a),499,y,72,14,nil,'right')
        text(row.format(row.b),579,y,72,14,{1,.88,.56,1},'right')
        local x,width=660,92
        g.setColor(.10,.16,.145,1);g.rectangle('fill',x,y+2,width,5,2);g.rectangle('fill',x,y+10,width,5,2)
        g.setColor(.28,.57,.48,1);g.rectangle('fill',x,y+2,width*math.min(1,row.a/row.limit),5,2)
        g.setColor(.94,.72,.32,1);g.rectangle('fill',x,y+10,width*math.min(1,row.b/row.limit),5,2)
        local delta=row.b-row.a
        local change=row.name=='Power' and ('%+.1f hp'):format(delta)
            or row.name=='Torque' and ('%+.1f Nm'):format(delta)
            or (row.name=='Top speed' or row.name=='Boost speed') and ('%+.0f mph'):format(delta) or ('%+.0f%%'):format(delta)
        text(change,738,y,118,13,delta>0 and {1,.85,.47,1} or {.69,.77,.72,1},'right')
    end
    local note=v.notice or (q.status=='maxed' and 'This component is already at its highest level.'
        or q.status=='unaffordable' and 'Need '..money(q.shortfallCents)..' more in household funds.'
        or v.page=='confirm' and 'Pay '..money(q.offer.costCents)..' for parts and installation?'
        or 'Select a component to compare its current and upgraded performance.')
    text(note,366,520,496,16,{1,.85,.47,1})

end
local function drawTires(R,v,q)
    local Service=require('src.commute.bike_service')
    local g=love.graphics
    for n,id in ipairs(Service.tireOrder) do
        local tire=Service.tires[id];local b={x=96,y=170+(n-1)*52,w=238,h=46}
        local selected=id==v.selectedTireId
        g.setColor(selected and .16 or .075,selected and .25 or .12,selected and .21 or .11,1)
        g.rectangle('fill',b.x,b.y,b.w,b.h,5,5)
        text(n..'  '..tire.name,b.x+10,b.y+5,b.w-20,17)
        text(('Road %d%%   Dirt %d%%'):format(math.floor(tire.road*100+.5),math.floor(tire.dirt*100+.5)),
            b.x+10,b.y+26,b.w-20,13,{.68,.78,.72,1})
        if id==q.tireId then text('FITTED',b.x+157,b.y+7,70,11,{1,.85,.47,1},'right') end
    end
    text(v.page=='confirm' and 'CONFIRM TIRE ORDER' or q.offer.name,366,172,468,27,{1,.85,.47,1})
    text(q.offer.description,366,215,468,17,nil)
    text('CURRENTLY FITTED',366,282,220,16,{.66,.79,.76,1})
    text(q.current.name,366,309,468,20)
    text(('Tread remaining  %.1f / %.0f mi'):format(math.max(0,q.current.life-q.tread),q.current.life),366,340,468,18)
    text(('Grip  Concrete %.0f%%  /  Dirt %.0f%%'):format(q.offer.road*100,q.offer.dirt*100),366,382,468,18)
    text(('Acceleration  Concrete %+.0f%%  /  Dirt %+.0f%%'):format(
        (q.offer.roadAcceleration-1)*100,(q.offer.dirtAcceleration-1)*100),366,414,468,18)
    text('Parts, balancing and installation',366,453,468,18,{.66,.79,.76,1})
    local note=v.notice or (q.status=='current' and 'These tires are fitted and have tread remaining.'
        or q.status=='unaffordable' and 'Need '..money(q.shortfallCents)..' more in household funds.'
        or v.page=='confirm' and 'Approve the quote to fit this tire set.'
        or 'Choose a compound for your usual terrain, review the quote, then approve installation.')
    text(note,366,490,468,18,{1,.85,.47,1})
end
local function drawRepair(R,v,q)
    local g=love.graphics
    g.setColor(.025,.06,.055,1);g.rectangle('fill',96,176,256,280,7)
    text('YOUR MOTORCYCLE',108,190,232,19,nil,'center')
    interior().drawBike(v.interior,R,224,351,.80,current(R).ridingPaintId,5)
    text(('CONDITION  %d%%'):format(q.condition),108,370,232,20,nil,'center')
    g.setColor(.16,.21,.19,1);g.rectangle('fill',122,411,204,10,4)
    if q.condition>0 then
        local fill=204*q.condition/100
        g.setColor(.85,.72,.39,1);g.rectangle('fill',122,411,fill,10,math.min(4,fill/2))
    end
    text(v.page=='confirm' and 'CONFIRM REPAIR ORDER' or 'COLLISION REPAIRS',378,181,466,27,{1,.85,.47,1})
    text(q.damage==0 and 'Inspection complete. Your bike is in full working order.'
        or 'The mechanic can fix the collision damage and restore your bike to full speed.',
        378,232,466,19)
    text(('Damage   %d%%'):format(q.damage),378,318,466,20)
    text('Parts and labor   '..money(q.priceCents),378,355,466,20,{1,.85,.47,1})
    text('After repair   100% condition',378,397,466,18)
    local note=v.notice
    if not note and q.status=='unaffordable' then note='Need '..money(q.shortfallCents)..' more in household funds.' end
    if not note and v.page=='confirm' then note='Pay '..money(q.priceCents)..' to fix the bike?' end
    if not note and q.damage>0 then note='Review the estimate to authorize the repair.' end
    if note then text(note,378,483,466,18,{1,.85,.47,1}) end
end
local function drawReceipt(R,v)
    local g=love.graphics;local receipt=v.receipt;local working=v.page=='install'
    text(working and (receipt.kind=='paint' and 'PAINT SERVICE IN PROGRESS' or receipt.kind=='tire'
        and 'FITTING NEW TIRES' or 'FINISHING YOUR SERVICE') or 'READY TO RIDE',96,181,766,29,{1,.85,.47,1},'center')
    local description=receipt.kind=='repair' and 'Collision repairs' or receipt.name..(receipt.kind=='paint' and ' finish'
        or receipt.kind=='tire' and ' tires' or ' installed')
    text(description,96,228,766,24,nil,'center')
    g.setColor(.025,.06,.055,1);g.rectangle('fill',120,282,232,242,8)
    interior().drawMechanic(v.interior,R,236,449,.40)
    text(shopName..' MECHANIC',126,477,220,16,{1,.85,.47,1},'center')
    interior().drawBike(v.interior,R,621,397,.88,receipt.paintId or current(R).ridingPaintId,5)
    text('Paid '..money(receipt.costCents)..' from household funds',390,421,446,20,nil,'center')
    if receipt.kind=='repair' then
        text('Condition restored to 100%.',390,456,446,19,nil,'center')
    elseif receipt.kind=='performance' then
        local resident=current(R)
        local profile=Upgrades.profile(resident and resident.ridingUpgradeParts,resident and resident.ridingUpgradeLevel)
        text(('Power %.1f hp  /  Road %s  /  Hill pull %.0f%%'):format(
            profile.powerHp,mph(profile.maxSpeed),profile.hillPull*100),390,456,446,19,nil,'center')
    elseif receipt.kind=='tire' then text('Your new tire compound is saved with your motorcycle.',390,456,446,18,nil,'center')
    else text('Your new color is saved with your motorcycle.',390,456,446,18,nil,'center') end
    if working then
        g.setColor(.14,.22,.19,1);g.rectangle('fill',408,505,410,12,4,4)
        local fill=410*math.min(1,v.installTime/2)
        if fill>0 then
            g.setColor(.9,.74,.37,1);g.rectangle('fill',408,505,fill,12,math.min(4,fill/2))
        end
    else text('The same bike is waiting outside.',390,501,446,18,nil,'center') end
    button(buttons.back,'SHOP FLOOR',not working);button(buttons.buy,'BACK TO THE SHOP',not working)
end
local function drawTruckCatalog(R,v)
    local g=love.graphics
    text(shopName..' / TRUCK SERVICE',96,82,766,27,{1,.85,.47,1})
    text('Household funds: '..money(R.state.home.balanceCents),96,105,330,18)
    button(truckTabs.repair,'REPAIRS',v.service=='truck_repair')
    button(truckTabs.maintenance,'MAINTENANCE',v.service=='truck_maintenance')
    button(truckTabs.upgrades,'UPGRADES',v.service=='truck_upgrades')
    local trip=R.state.home.commute
    local _,_,_,truck=TruckMechanic.canVisit(R.state,R.World.player,trip,
        require('src.commute.runtime').world(R),v.truckModel)
    if not truck then
        text('Bring the truck back to the mechanic parking area to continue.',96,208,760,22,{1,.85,.47,1})
        button(buttons.back,'SHOP FLOOR / ESC',true)
        return
    end
    local q=quote(R,v)
    g.setColor(.025,.06,.055,1);g.rectangle('fill',96,184,260,360,7)
    text(v.truckModel=='kei' and 'KEI TRUCK' or 'BOX TRUCK',108,190,236,20,{1,.85,.47,1})
    local failureName=({oil_pressure='Oil pressure',overheating='Cooling system',
        ignition_misfire='Ignition misfire'})[truck.service.failureType] or 'None'
    if v.service=='truck_repair' then
        local repair=TruckMechanic.quote(R.state,truck,'repair')
        text(('Condition  %d%%'):format(100-(truck.damage or 0)),108,226,236,18)
        g.setColor(.16,.21,.19,1);g.rectangle('fill',118,260,216,12,4)
        local fill=216*(100-(truck.damage or 0))/100
        if fill>0 then g.setColor(.66,.83,.56,1);g.rectangle('fill',118,260,fill,12,math.min(4,fill/2)) end
        text(('Collision damage  %d%%'):format(truck.damage or 0),108,292,236,18)
        text('Engine condition  '..failureName,108,322,236,18)
        text('Repairs restore safe running condition.',108,370,236,18,{.68,.78,.72,1})
        if repair.status=='healthy' then text('No repairs are needed.',108,410,236,18,{.68,.78,.72,1}) end
    elseif v.service=='truck_maintenance' then
        for n,item in ipairs(TruckService.MAINTENANCE) do
            local b=truckRow(n);local selected=item.id==v.selectedTruckMaintenance
            local itemQuote=TruckMechanic.quote(R.state,truck,'maintenance',item.id)
            g.setColor(selected and .16 or .075,selected and .25 or .12,selected and .21 or .11,1)
            g.rectangle('fill',b.x,b.y,b.w,b.h,5,5)
            text(item.name,b.x+9,b.y+5,b.w-18,15)
            local status=itemQuote.status=='healthy'
                and ('%d%% TO INTERVAL'):format(math.min(100,math.floor(100*itemQuote.usedMiles/itemQuote.interval+.5)))
                or itemQuote.status=='unaffordable' and 'DUE'
                or 'SERVICE DUE'
            text(status,b.x+9,b.y+28,b.w-18,12,{.68,.78,.72,1})
        end
    else
        for n,id in ipairs(truckUpgradeOrder) do
            local b=truckRow(n);local selected=id==v.selectedTruckUpgrade
            local entry=TruckService.UPGRADES[id];local level=truck.service.upgrades[id]
            g.setColor(selected and .16 or .075,selected and .25 or .12,selected and .21 or .11,1)
            g.rectangle('fill',b.x,b.y,b.w,b.h,5,5)
            text(entry.name,b.x+9,b.y+5,b.w-18,16)
            text(('LEVEL %d / 3'):format(level),b.x+9,b.y+28,b.w-18,12,{.68,.78,.72,1})
        end
    end
    text(v.page=='truck_confirm' and 'CONFIRM TRUCK SERVICE' or 'SERVICE ESTIMATE',390,194,450,25,{1,.85,.47,1})
    if q then
        if v.service=='truck_repair' then
            text(('Collision damage   %d%%'):format(q.damage),390,256,442,19)
            text('Mechanical fault   '..(q.failed and failureName or 'None'),390,294,442,19)
            text('Parts and labor   '..money(q.priceCents),390,340,442,20,{1,.85,.47,1})
        elseif v.service=='truck_maintenance' then
            text(q.item.name,390,250,442,22)
            text(('Current use  %.1f / %.0f mi'):format(q.usedMiles,q.interval),390,290,442,19)
            text('Parts and labor   '..money(q.priceCents),390,330,442,20,{1,.85,.47,1})
        elseif q.status=='maxed' then
            text(q.category.name..' is fully upgraded.',390,250,442,22)
        else
            text(q.offer.name,390,250,442,22)
            text(('Installed level  %d / 3'):format(q.currentLevel),390,290,442,19)
            text('Parts and labor   '..money(q.priceCents),390,330,442,20,{1,.85,.47,1})
        end
    end
    local note=v.notice or (v.page=='truck_confirm' and 'Approve the quote to authorize this service.'
        or q and q.status=='unaffordable' and ('Need '..money(q.shortfallCents)..' more in household funds.')
        or q and q.status=='healthy' and 'This maintenance item is not due yet.'
        or q and q.status=='maxed' and 'This component is already at its highest level.'
        or 'Select a service, review the estimate, then approve the order.')
    text(note,390,440,440,42,{1,.85,.47,1})
    button(buttons.back,'SHOP FLOOR / ESC',not v.pending)
    local label=v.pending and 'AWAITING CONFIRMATION' or v.page=='truck_confirm'
        and ('PAY '..money(q and q.priceCents or 0)) or q and q.status=='available'
        and ('REVIEW '..money(q.priceCents)) or 'NO SERVICE NEEDED'
    button(buttons.buy,label,q and q.status=='available' and not v.pending)
end
function Shop.draw(R)
    local v=view(R);if not v then return false end
    if v.page=='station' then
        local drawn=Station.draw(v,stationArgs(R),R.Config.baseWidth,R.Config.baseHeight)
        return drawn
    end
    if v.page=='stationFloor' then
        local drawn=gasInterior().draw(v.interior,R)
        if R.mobileControls and R.mobileControls:isEnabled() then R.mobileControls:draw() end
        return drawn
    end
    if v.page=='store' then
        local resident=Residents.get(R.state,R.World.player)
        return TownStore.draw(v,R.state.home.balanceCents,resident and resident.bikeInventory,
            R.state.home.revision,R.Config.baseWidth,R.Config.baseHeight,
            (v.interiorKind=='grocery' or v.interiorKind=='station' and v.returnToInterior)
                and 'Back to floor' or nil,R.state.groceryStore,
            R.state.calendar.totalDays,R.state.calendar.weekday)
    end
    if v.interiorKind=='grocery' and v.page=='groceryFloor' then
        v.interior.cartCount=TownStore.cartCount(v.cart)
        v.interior.cartTotalCents=TownStore.cartTotal(v.cart) or 0
        v.interior.cartItems=v.cart
        local drawn=require('src.commute.grocery_interior').draw(v.interior,R)
        if R.mobileControls and R.mobileControls:isEnabled() then R.mobileControls:draw() end
        return drawn
    end
    interior().draw(v.interior,R)
    if v.page=='lobby' then return true end
    local g=love.graphics;g.push('all');g.scale(R.Config.baseWidth/960,R.Config.baseHeight/678)
    if v.vehicleKind=='truck' then
        g.setColor(0,0,0,.68);g.rectangle('fill',0,0,960,678)
        g.setColor(.035,.065,.065,.98);g.rectangle('fill',72,62,816,574,10,10)
        g.setColor(.44,.56,.45,1);g.rectangle('line',72,62,816,574,10,10)
        drawTruckCatalog(R,v);g.pop();return true
    end
    g.setColor(0,0,0,.68);g.rectangle('fill',0,0,960,678)
    g.setColor(.035,.065,.065,.98);g.rectangle('fill',72,62,816,574,10,10)
    g.setColor(.44,.56,.45,1);g.rectangle('line',72,62,816,574,10,10)
    text(shopName..' / MOTORCYCLE SERVICE',96,82,766,27,{1,.85,.47,1})
    text('Household funds: '..money(R.state.home.balanceCents),96,121,368,18)
    if v.page=='install' or v.page=='receipt' then drawReceipt(R,v)
    else
        local q=quote(R,v)
        button(buttons.performance,'UPGRADES',v.page=='catalog' and not v.pending)
        button(buttons.tires,'TIRES',v.page=='catalog' and not v.pending)
        button(buttons.paint,'PAINT',v.page=='catalog' and not v.pending)
        button(buttons.repair,'REPAIRS',v.page=='catalog' and not v.pending)
        local active=buttons[v.service]
        g.setColor(1,.85,.47,1);g.rectangle('fill',active.x+7,active.y+active.h-4,active.w-14,3)
        if q then
            if v.service=='repair' then drawRepair(R,v,q)
            elseif v.service=='paint' then drawPaint(R,v,q)
            elseif v.service=='tires' then drawTires(R,v,q)
            else drawPerformance(R,v,q) end
            button(buttons.back,'SHOP FLOOR / ESC',not v.pending)
            local cost=q.priceCents or q.offer.costCents
            local action=v.service=='repair' and ' & REPAIR' or v.service=='paint' and ' & REPAINT'
                or v.service=='tires' and ' & FIT TIRES' or ' & INSTALL'
            local label=v.pending and 'AWAITING CONFIRMATION' or v.page=='confirm'
                and ('PAY '..money(cost)..action) or q.status=='healthy' and 'NO REPAIRS NEEDED'
                or q.status=='maxed' and 'COMPONENT MAXED'
                or q.status=='current' and v.service=='tires' and 'TIRES IN GOOD CONDITION' or 'REVIEW QUOTE'
            button(buttons.buy,label,q.status=='available' and not v.pending)
        end
    end
    g.pop();return true
end
return Shop
