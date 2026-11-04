-- Customer service views remain local; only host-validated orders change a bike.
local Upgrades=require('src.commute.bike_upgrades')
local Paint=require('src.commute.bike_paint')
local Repairs=require('src.commute.bike_repairs')
local Residents=require('src.home_residents')
local Fonts=require('src.screens.title_fonts')
local Station=require('src.commute.gas_station')
local Shop={}
local shopName=require('src.commute.sites').MECHANIC_NAME:upper()
local function interior() return require('src.commute.mechanic_interior') end
local function view(R) return R._commute and R._commute.mechanicOffer end
local function stationArgs(R)
    local C=require('src.commute.runtime')
    return C.localPart(R).rider.bike.service,function(id,rev)
        local okay=C.request(R,('station:%d:%d:%s'):format(R.state.home.commute.token,rev,id))
        return R.state.message or (okay and 'Order submitted.' or 'Order declined.')
    end,function() Shop.close(R) end
end
local function current(R) return Residents.get(R.state,R.World.player) end
local function money(cents) return ('$%.2f'):format(cents/100) end
local function mph(speed) return ('%d mph'):format(math.floor(speed*2.236936+.5)) end
function Shop.quote(R,level) return Upgrades.quote(R.state,R.World.player,level) end
function Shop.paintQuote(R,id) return Paint.quote(R.state,R.World.player,id) end
function Shop.repairQuote(R) return Repairs.quote(R.state,R.World.player) end
local function quote(R,v)
    if v.service=='repair' then return Shop.repairQuote(R) end
    if v.service=='paint' then return Shop.paintQuote(R,v.selectedPaintId) end
    return Shop.quote(R,v.selected)
end
function Shop.close(R)
    local v=view(R)
    if v and v.interior then interior().release(v.interior) end
    if R._commute then R._commute.mechanicOffer=nil end
end
function Shop.open(R)
    local C=require('src.commute.runtime')
    local okay,reason=Upgrades.canVisit(R.state,R.World.player,R.state.home.commute,C.world(R))
    if not okay then R.state.message=reason;return false end
    Shop.close(R);C.cancelCameraDrag(R)
    local resident=current(R)
    R._commute.mechanicOffer={token=R.state.home.commute.token,page='lobby',service='performance',
        selected=math.min(Upgrades.MAX_LEVEL,(resident.ridingUpgradeLevel or 0)+1),
        selectedPaintId=resident.ridingPaintId or Paint.DEFAULT,previewFrame=5,
        interior=interior().new(R),elapsed=0}
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
function Shop.repair(R)
    local v=view(R);if not v or v.pending or v.page=='install' then return false end
    v.service='repair';v.page='catalog';v.notice=nil;v.review=nil;return true
end
local function browse(R)
    if (current(R).ridingDamage or 0)>0 then return Shop.repair(R) end
    return Shop.catalog(R)
end
function Shop.selectPaint(R,id)
    local v=view(R)
    if not v or v.pending or v.page=='install' or not Paint.valid(id) then return false end
    v.service='paint';v.page='catalog';v.selectedPaintId=id;v.notice=nil;v.review=nil;return true
end
function Shop.confirm(R)
    local v=view(R);if not v or v.pending or v.page=='install' then return false end
    local q=quote(R,v);if not q then return false end
    if q.status~='available' then
        v.notice=q.status=='healthy' and 'Your bike is in full working order.'
            or q.status=='current' and 'Your bike already has this finish.'
            or q.status=='installed' and 'This kit is already installed.'
            or q.status=='locked' and 'Install the earlier kit first.'
            or ('You need '..money(q.shortfallCents)..' more in household funds.')
        return false
    end
    if v.page~='confirm' or not v.review then
        v.review={service=v.service,revision=q.revision,paintId=v.selectedPaintId,level=q.level,damage=q.damage}
        v.page='confirm';v.notice=nil;return true
    end
    if v.review.service~=v.service or v.service=='paint'
        and (v.review.revision~=q.revision or v.review.paintId~=v.selectedPaintId)
        or v.service=='repair' and (v.review.revision~=q.revision or v.review.damage~=q.damage)
        or v.service=='performance' and v.review.level~=q.level then
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
    if v.page=='station' then return true end
    local trip=R.state.home.commute
    if not trip or trip.token~=v.token then Shop.close(R);return false end
    dt=math.max(0,math.min(.1,dt or 0));v.elapsed=v.elapsed+dt
    interior().update(v.interior,R,dt)
    if v.pending then
        local p=v.pending;local resident=current(R);p.elapsed=p.elapsed+dt
        local confirmed=resident and (p.kind=='paint'
            and (resident.ridingPaintRevision or 0)==p.previous+1 and resident.ridingPaintId==p.paintId
            or p.kind=='repair' and (resident.ridingRepairRevision or 0)==p.previous+1 and resident.ridingDamage==0
            or p.kind=='performance' and (resident.ridingUpgradeLevel or 0)>=p.level)
        if confirmed then
            v.receipt={kind=p.kind,name=p.name,costCents=p.costCents,level=p.level,paintId=p.paintId}
            v.pending=nil;v.page='install';v.installTime=0;v.notice=nil
        elseif p.kind=='paint' and resident and (resident.ridingPaintRevision or 0)>p.previous then
            v.pending=nil;v.page='catalog';v.notice='Your bike finish changed. Review the current finish before ordering again.'
        elseif p.kind=='repair' and resident and (resident.ridingRepairRevision or 0)>p.previous then
            v.pending=nil;v.page='catalog';v.notice='Your repair record changed. Check the bike condition before ordering again.'
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
    if key=='escape' or key=='back' then
        if v.page=='lobby' then Shop.close(R)
        elseif not v.pending and v.page~='install' then v.page='lobby';v.notice=nil end
        return true
    end
    if v.pending or v.page=='install' then return true end
    if v.page=='lobby' then
        local action=interior().keypressed(v.interior,R,key)
        if action=='catalog' then browse(R) elseif action=='exit' then Shop.close(R) end
    elseif v.page=='receipt' then
        if key=='return' or key=='e' or key=='kpenter' then
            v.page='lobby';v.selected=math.min(3,(current(R).ridingUpgradeLevel or 0)+1)
        end
    elseif key=='tab' and v.page=='catalog' then
        if v.service=='performance' then Shop.paint(R)
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
        if n and n>=1 and n<=3 then v.selected=n;v.notice=nil
        elseif key=='up' or key=='left' then v.selected=math.max(1,v.selected-1);v.notice=nil
        elseif key=='down' or key=='right' then v.selected=math.min(3,v.selected+1);v.notice=nil end
    end
    return true
end
local function contains(b,x,y) return x>=b.x and y>=b.y and x<=b.x+b.w and y<=b.y+b.h end
local buttons={back={x=96,y=574,w=205,h=44},buy={x=570,y=574,w=292,h=44},
    performance={x=470,y=114,w=130,h=44},paint={x=610,y=114,w=120,h=44},repair={x=740,y=114,w=122,h=44},
    previous={x=500,y=396,w=44,h=40},next={x=678,y=396,w=44,h=40}}
local function swatch(index)
    return {x=96+(index-1)%2*124,y=170+math.floor((index-1)/2)*92,w=114,h=80}
end
function Shop.layout()
    local layout={performance=buttons.performance,paint=buttons.paint,repair=buttons.repair,back=buttons.back,buy=buttons.buy,
        previous=buttons.previous,next=buttons.next,swatches={}}
    for i=1,#Paint.CATALOG do layout.swatches[i]=swatch(i) end
    return layout
end
function Shop.pointer(R,x,y)
    local v=view(R);if not v then return false end
    if v.page=='station' then return Station.pointer(v,x*960/R.Config.baseWidth,y*678/R.Config.baseHeight,stationArgs(R)) end
    if v.page=='lobby' then
        local action=interior().pointer(v.interior,R,x,y)
        if action=='catalog' then browse(R) elseif action=='exit' then Shop.close(R) end
        return true
    end
    x,y=x*960/R.Config.baseWidth,y*678/R.Config.baseHeight
    if v.pending or v.page=='install' then return true end
    if contains(buttons.back,x,y) then Shop.keypressed(R,'escape');return true end
    if contains(buttons.buy,x,y) then
        if v.page=='receipt' then Shop.keypressed(R,'return') else Shop.confirm(R) end
    elseif v.page=='catalog' then
        if contains(buttons.performance,x,y) then Shop.catalog(R)
        elseif contains(buttons.paint,x,y) then Shop.paint(R)
        elseif contains(buttons.repair,x,y) then Shop.repair(R)
        elseif v.service=='paint' then
            if contains(buttons.previous,x,y) then v.previewFrame=(v.previewFrame-2)%16+1
            elseif contains(buttons.next,x,y) then v.previewFrame=v.previewFrame%16+1
            else for n,finish in ipairs(Paint.CATALOG) do
                if contains(swatch(n),x,y) then Shop.selectPaint(R,finish.id);break end
            end end
        elseif v.service=='performance' then
            for n=1,3 do if contains({x=96,y=170+(n-1)*116,w=238,h=104},x,y) then
                v.selected=n;v.notice=nil;break
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
        for n,offer in ipairs(Upgrades.CATALOG) do
            local b={x=96,y=170+(n-1)*116,w=238,h=104};local row=Shop.quote(R,n)
            g.setColor(n==v.selected and .16 or .075,n==v.selected and .25 or .12,n==v.selected and .21 or .11,1)
            g.rectangle('fill',b.x,b.y,b.w,b.h,5,5)
            text(n..'  '..offer.name,b.x+12,b.y+13,b.w-24,20)
            text(money(offer.costCents),b.x+12,b.y+42,b.w-24,20,{1,.84,.45,1})
            text(row.status=='installed' and 'INSTALLED' or row.status=='locked' and 'PREVIOUS KIT REQUIRED'
                or row.status=='unaffordable' and 'SAVE UP FOR THIS KIT' or 'AVAILABLE',b.x+12,b.y+75,b.w-24,13)
        end
        text(v.page=='confirm' and 'CONFIRM WORK ORDER' or q.offer.name,366,172,468,27,{1,.85,.47,1})
        text(q.offer.description,366,215,468,19)
        text(q.offer.parts,366,276,468,16,{.66,.79,.76,1})
        text('YOUR BIKE',366,318,210,16);text('AFTER THIS KIT',606,318,235,16)
        local rows={{'Road',q.current.maxSpeed,q.offer.maxSpeed},{'Boost',q.current.boostMaxSpeed,q.offer.boostMaxSpeed},
            {'Dirt boost',q.current.boostMaxSpeed*.82,q.offer.boostMaxSpeed*.82}}
        for n,row in ipairs(rows) do
            text(row[1]..'  '..mph(row[2]),366,344+(n-1)*30,225,20)
            text(mph(row[3]),606,344+(n-1)*30,225,20,{.90,.88,.60,1})
        end
        text(('Acceleration %.0f%%  >  %.0f%%'):format(q.current.acceleration*100,q.offer.acceleration*100),366,444,468,18)
        local note=v.notice or (q.status=='locked' and 'Install '..Upgrades.profile(v.selected-1).name..' first.'
            or q.status=='installed' and 'This upgrade is already on your motorcycle.'
            or q.status=='unaffordable' and 'Need '..money(q.shortfallCents)..' more in household funds.'
            or v.page=='confirm' and 'Pay '..money(q.offer.costCents)..' now? Parts and labor are included.'
            or 'Choose a kit, review the quote, then approve the work.')
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
    text(working and (receipt.kind=='paint' and 'PAINT SERVICE IN PROGRESS' or 'FINISHING YOUR SERVICE') or 'READY TO RIDE',96,181,766,29,{1,.85,.47,1},'center')
    local description=receipt.kind=='repair' and 'Collision repairs' or receipt.name..(receipt.kind=='paint' and ' finish' or ' installed')
    text(description,96,228,766,24,nil,'center')
    g.setColor(.025,.06,.055,1);g.rectangle('fill',120,282,232,242,8)
    interior().drawMechanic(v.interior,R,236,449,.40)
    text(shopName..' MECHANIC',126,477,220,16,{1,.85,.47,1},'center')
    interior().drawBike(v.interior,R,621,397,.88,receipt.paintId or current(R).ridingPaintId,5)
    text('Paid '..money(receipt.costCents)..' from household funds',390,421,446,20,nil,'center')
    if receipt.kind=='repair' then
        text('Condition restored to 100%.',390,456,446,19,nil,'center')
    elseif receipt.kind=='performance' then
        local profile=Upgrades.profile(receipt.level)
        text('Road '..mph(profile.maxSpeed)..' / Boost '..mph(profile.boostMaxSpeed),390,456,446,19,nil,'center')
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
function Shop.draw(R)
    local v=view(R);if not v then return false end
    if v.page=='station' then return Station.draw(v,require('src.commute.runtime').localPart(R).rider.bike.service,R.state.home.balanceCents,R.Config.baseWidth,R.Config.baseHeight) end
    interior().draw(v.interior,R)
    if v.page=='lobby' then return true end
    local g=love.graphics;g.push('all');g.scale(R.Config.baseWidth/960,R.Config.baseHeight/678)
    g.setColor(0,0,0,.68);g.rectangle('fill',0,0,960,678)
    g.setColor(.035,.065,.065,.98);g.rectangle('fill',72,62,816,574,10,10)
    g.setColor(.44,.56,.45,1);g.rectangle('line',72,62,816,574,10,10)
    text(shopName..' / MOTORCYCLE SERVICE',96,82,766,27,{1,.85,.47,1})
    text('Household funds: '..money(R.state.home.balanceCents),96,121,368,18)
    if v.page=='install' or v.page=='receipt' then drawReceipt(R,v)
    else
        local q=quote(R,v)
        button(buttons.performance,'UPGRADES',v.page=='catalog' and not v.pending)
        button(buttons.paint,'PAINT',v.page=='catalog' and not v.pending)
        button(buttons.repair,'REPAIRS',v.page=='catalog' and not v.pending)
        local active=buttons[v.service]
        g.setColor(1,.85,.47,1);g.rectangle('fill',active.x+7,active.y+active.h-4,active.w-14,3)
        if q then
            if v.service=='repair' then drawRepair(R,v,q)
            elseif v.service=='paint' then drawPaint(R,v,q)
            else drawPerformance(R,v,q) end
            button(buttons.back,'SHOP FLOOR / ESC',not v.pending)
            local cost=q.priceCents or q.offer.costCents
            local action=v.service=='repair' and ' & REPAIR' or v.service=='paint' and ' & REPAINT' or ' & INSTALL'
            local label=v.pending and 'AWAITING CONFIRMATION' or v.page=='confirm'
                and ('PAY '..money(cost)..action) or q.status=='healthy' and 'NO REPAIRS NEEDED' or 'REVIEW QUOTE'
            button(buttons.buy,label,q.status=='available' and not v.pending)
        end
    end
    g.pop();return true
end
return Shop
