-- Compact, touch-friendly item exchange panel for player cargo and staff offers.
local Trade=require('src.item_trade')
local Residents=require('src.home_residents')
local Catalog=require('src.home_shop_catalog')
local Food=require('src.home_food_catalog')
local Art=require('src.commute.grocery_ui_art')
local FoodArt=require('src.home_food_art')
local Screen={}
local session
local fonts={}

local function font(size)
    fonts[size]=fonts[size] or love.graphics.newFont(size)
    return fonts[size]
end
local function contains(x,y,rect)
    return x>=rect.x and x<=rect.x+rect.w and y>=rect.y and y<=rect.y+rect.h
end
local function localPlayer(Runtime) return Runtime.World and Runtime.World.player end
local function remotePlayer(Runtime,id)
    for _,player in ipairs(Runtime.multiplayer:remotePlayers()) do
        if tonumber(player.id)==tonumber(id) then return player end
    end
end
local function product(id) return id and Catalog.PRODUCTS[id] end
local function displayName(id,source)
    local row=source=='pocket' and Food.ITEMS[id] or product(id)
    return row and row.name or 'Unknown item'
end
local function drawItemIcon(id,source,x,y,size)
    if source=='pocket' and Food.ITEMS[id] then
        FoodArt.draw(Food.ITEMS[id].sprite,x,y,size)
        return true
    end
    return Art.drawProduct(id,x,y,size)
end
function Screen.open(Runtime,target)
    if not Runtime or not target then return false end
    if target.employeeId then
        session={kind='employee',employeeId=target.employeeId,employeeName=target.employeeName,
            selectedGive=nil,ownSource='pocket'}
    elseif tonumber(target.playerId) then
        session={kind='player',playerId=tonumber(target.playerId),playerName=target.playerName,
            selectedGive=nil,selectedWant=nil,selectedOffer=nil,ownSource='pocket',wantSource='pocket'}
    else return false end
    Runtime.state.screen='trade'
    return true
end
function Screen.close(Runtime)
    session=nil
    Runtime.state.screen='world'
end

local function box(x,y,w,h,fill,stroke,radius)
    local g=love.graphics
    g.setColor(unpack(fill));g.rectangle('fill',x,y,w,h,radius or 5,radius or 5)
    if stroke then g.setColor(unpack(stroke));g.setLineWidth(1.5);g.rectangle('line',x,y,w,h,radius or 5,radius or 5) end
end
local function button(label,rect,enabled,highlight)
    local g=love.graphics
    local fill=enabled and (highlight and {.04,.39,.40,.98} or {.18,.25,.28,.98}) or {.13,.16,.17,.85}
    local stroke=enabled and (highlight and {.35,.91,.84,1} or {.57,.68,.68,1}) or {.31,.37,.38,.9}
    box(rect.x,rect.y,rect.w,rect.h,fill,stroke,5)
    g.setFont(font(14));g.setColor(enabled and {.92,.96,.92,1} or {.56,.62,.61,1})
    g.printf(label,rect.x+5,rect.y+math.floor((rect.h-17)/2),rect.w-10,'center')
end
local function drawItemRow(x,y,w,item,selected,locked)
    local g=love.graphics
    box(x,y,w,17,selected and {.13,.36,.36,.98} or {.035,.065,.078,.93},
        selected and {.30,.86,.78,1} or {.14,.30,.33,.98},3)
    if not drawItemIcon(item.id,item.source,x+13,y+8.5,15) then
        g.setColor(.94,.72,.28,1);g.circle('fill',x+13,y+8.5,6.5)
        g.setColor(.04,.10,.11,1);g.setFont(font(7));g.printf(string.upper(item.id:sub(1,2)),x+6,y+6,14,'center')
    end
    g.setFont(font(10));g.setColor(locked and {.51,.58,.58,1} or {.88,.92,.90,1})
    g.print(item.name,x+27,y+2)
    g.setColor(.83,.85,.63,1);g.printf('×'..tostring(item.quantity),x+w-42,y+2,34,'right')
end
local function inventoryRows(state,player,source)
    return source=='pocket' and Trade.pocketRows(state,player) or Trade.inventoryRows(state,player)
end
local function inventoryPanel(x,y,w,title,rows,source,sourceSetter,selected,selectedSetter)
    local g=love.graphics
    box(x,y,w,245,{.035,.075,.09,.98},{.20,.43,.47,1},7)
    g.setFont(font(14));g.setColor(.96,.80,.35,1);g.print(title,x+13,y+11)
    local tabY=y+31;local tabWidth=(w-26)/2
    button('POCKETS',{x=x+9,y=tabY,w=tabWidth,h=22},true,source=='pocket')
    button('BIKE CARGO',{x=x+17+tabWidth,y=tabY,w=tabWidth,h=22},true,source=='cargo')
    if #rows==0 then
        g.setFont(font(12));g.setColor(.65,.74,.72,1)
        g.printf(source=='pocket' and 'No food or drinks in your pockets.' or 'No tradeable items in bike cargo.',x+12,y+82,w-24,'center')
    else
        for i,row in ipairs(rows) do
            drawItemRow(x+9,y+57+(i-1)*18,w-18,row,
                selected and selected.source==source and selected.id==row.id,false)
        end
    end
    return function(mx,my)
        if contains(mx,my,{x=x+9,y=tabY,w=tabWidth,h=22}) then
            if source~='pocket' then sourceSetter('pocket') end
            return true
        elseif contains(mx,my,{x=x+17+tabWidth,y=tabY,w=tabWidth,h=22}) then
            if source~='cargo' then sourceSetter('cargo') end
            return true
        end
        local index=math.floor((my-(y+57))/18)+1
        if mx>=x+9 and mx<=x+w-9 and index>=1 and index<=#rows
            and my>=y+57 and my<y+57+#rows*18 then
            selectedSetter({id=rows[index].id,source=source});return true
        end
        return false
    end
end
local function playerData(Runtime)
    local actor=localPlayer(Runtime);local target=remotePlayer(Runtime,session.playerId)
    if not actor or not target then return actor,target,{},{},{},{} end
    local residents=Residents.ensure(Runtime.state)
    local ownResident=Residents.get(Runtime.state,actor)
    local targetResident=Residents.get(Runtime.state,target)
    local own=Trade.inventoryRows(Runtime.state,actor)
    local theirs=Trade.inventoryRows(Runtime.state,target)
    local pending=Trade.pendingFor(Runtime.state,actor,Residents.key(target))
    local sent=Trade.sentFor(Runtime.state,actor,Residents.key(target))
    return actor,target,own,theirs,pending,sent,ownResident,targetResident
end
local function drawHeader(title,subtitle)
    local g=love.graphics
    g.setFont(font(20));g.setColor(.97,.79,.31,1);g.printf(title,110,72,740,'center')
    g.setFont(font(12));g.setColor(.65,.82,.82,1);g.printf(subtitle,125,104,710,'center')
end
function Screen.draw(Runtime)
    local g=love.graphics
    if not session then Screen.close(Runtime);return end
    g.push('all')
    g.setColor(.01,.025,.035,.82);g.rectangle('fill',0,0,960,678)
    box(88,48,784,582,{.035,.065,.082,.99},{.52,.72,.69,1},10)
    if session.kind=='employee' then
        local worker=require('src.employees').worker(Runtime.state,session.employeeId)
        if not worker then
            drawHeader('STAFF TRADE','This employee is no longer on staff.')
            button('CLOSE',{x=410,y=550,w=140,h=46},true,false)
            g.pop();return
        end
        local offer=Trade.employeeOffer(Runtime.state,worker,localPlayer(Runtime))
        local canAccept=offer~=nil and (not offer.wantId
            or Trade.availableCount(Runtime.state,localPlayer(Runtime),offer.wantId,offer.wantSource)>0)
        session.employeeName=worker.name
        drawHeader('STAFF TRADE  /  '..string.upper(worker.name),
            'Compare carried items with staff. Home deliveries cannot be traded.')
        box(130,139,700,155,{.045,.10,.12,.98},{.22,.52,.53,1},7)
        g.setFont(font(13));g.setColor(.72,.85,.84,1);g.print('EMPLOYEE OFFER',151,155)
        if offer then
            box(152,185,255,82,{.06,.15,.16,1},{.35,.71,.67,1},6)
            drawItemIcon(offer.giveId,offer.giveSource,185,226,48)
            g.setFont(font(14));g.setColor(.98,.94,.80,1);g.printf(offer.giveName,220,203,174,'left')
            g.setFont(font(11));g.setColor(.68,.81,.79,1)
            g.printf((offer.giveSource=='pocket' and 'From '..worker.name..'’s pockets' or 'From bike cargo'),220,225,174,'left')
            g.setFont(font(23));g.setColor(.97,.79,.34,1);g.printf(offer.gift and '→' or '↔',426,211,72,'center')
            box(518,185,285,82,{.06,.15,.16,1},{.35,.71,.67,1},6)
            if offer.wantId then
                drawItemIcon(offer.wantId,offer.wantSource,551,226,48)
                g.setFont(font(14));g.setColor(.98,.94,.80,1);g.printf(offer.wantName,586,203,198,'left')
                g.setFont(font(11));g.setColor(.68,.81,.79,1)
                g.printf('Wants 1 from your '..(offer.wantSource=='pocket' and 'pockets' or 'bike cargo'),586,225,198,'left')
            else
                g.setFont(font(17));g.setColor(.99,.84,.42,1);g.printf('A small gift for you',530,210,260,'center')
            end
        else
            g.setFont(font(14));g.setColor(.70,.76,.74,1);g.printf(worker.name..' has no items to trade right now.',150,214,660,'center')
        end
        local own=inventoryRows(Runtime.state,localPlayer(Runtime),session.ownSource)
        local selectOwn=inventoryPanel(130,298,700,'YOUR ITEMS  /  choose one to give',own,
            session.ownSource,function(source) session.ownSource=source;session.selectedGive=nil end,
            session.selectedGive,function(item)session.selectedGive=item end)
        g.setFont(font(11));g.setColor(.60,.71,.70,1)
        g.printf(offer and (offer.gift and 'Accept the gift or give the employee one of your items.'
            or 'Accept only if you have the requested item; you can also give a separate gift.')
            or 'Choose an item from your pockets or bike cargo to give them.',135,548,690,'center')
        button(offer and (offer.gift and 'ACCEPT GIFT' or 'ACCEPT TRADE'),{x=121,y=575,w=210,h=42},canAccept,true)
        local giveLabel=session.selectedGive and displayName(session.selectedGive.id,session.selectedGive.source)
            or 'GIVE SELECTED'
        button(session.selectedGive and ('GIVE '..string.upper(giveLabel)) or giveLabel,
            {x=347,y=575,w=300,h=42},session.selectedGive~=nil,false)
        button('CLOSE',{x=730,y=575,w=110,h=42},true,false)
        session._selectOwn=selectOwn
    else
        local actor,target,own,theirs,pending,sent=playerData(Runtime)
        local name=target and (target.name or session.playerName or ('Player '..session.playerId)) or 'Player offline'
        session.playerName=name
        drawHeader('PLAYER EXCHANGE  /  '..string.upper(name),
            'Choose pockets or bike cargo on either side. The other player accepts to complete the exchange.')
        local ownRows=inventoryRows(Runtime.state,actor,session.ownSource)
        local targetRows=inventoryRows(Runtime.state,target,session.wantSource)
        local selectOwn=inventoryPanel(110,130,350,'YOUR OFFER',ownRows,session.ownSource,
            function(source) session.ownSource=source;session.selectedGive=nil end,
            session.selectedGive,function(item)session.selectedGive=item end)
        local selectTarget=inventoryPanel(500,130,350,string.upper(name)..' REQUESTED ITEM',targetRows,
            session.wantSource,function(source) session.wantSource=source;session.selectedWant=nil end,
            session.selectedWant,function(item)session.selectedWant=item end)
        box(110,385,740,94,{.045,.09,.105,.98},{.20,.42,.46,1},7)
        g.setFont(font(13));g.setColor(.97,.80,.35,1);g.print('OPEN OFFER FROM '..string.upper(name),128,397)
        local activeOffer=pending[1]
        local activeSent=sent[1]
        session.selectedOffer=activeOffer and activeOffer.id or nil
        if activeOffer then
            g.setFont(font(14));g.setColor(.90,.94,.90,1)
            local request=activeOffer.wantId and (' for '..displayName(activeOffer.wantId,activeOffer.wantSource or 'cargo')) or ' as a gift'
            g.printf(displayName(activeOffer.giveId,activeOffer.giveSource or 'cargo')..request..'  •  offer # '..activeOffer.id,130,426,700,'left')
        elseif activeSent then
            g.setFont(font(14));g.setColor(.90,.94,.90,1)
            local request=activeSent.wantId and (' for '..displayName(activeSent.wantId,activeSent.wantSource or 'cargo')) or ' as a gift'
            g.printf('You offered '..displayName(activeSent.giveId,activeSent.giveSource or 'cargo')..request..'  •  awaiting response',130,426,700,'left')
        else
            g.setFont(font(12));g.setColor(.64,.73,.72,1);g.print('No open offer from this player.',130,426)
        end
        local giveLabel=session.selectedGive and displayName(session.selectedGive.id,session.selectedGive.source) or 'select an item'
        local wantLabel=session.selectedWant and displayName(session.selectedWant.id,session.selectedWant.source) or 'select an item'
        g.setFont(font(12));g.setColor(.66,.83,.81,1)
        g.printf('YOU OFFER: '..giveLabel..'     YOU REQUEST: '..wantLabel,115,488,730,'center')
        button('PROPOSE TRADE',{x=120,y=513,w=195,h=38},session.selectedGive~=nil and session.selectedWant~=nil,true)
        button('SEND AS GIFT',{x=330,y=513,w=175,h=38},session.selectedGive~=nil,false)
        button('ACCEPT OFFER',{x=120,y=565,w=195,h=38},activeOffer~=nil,true)
        button(activeOffer and 'DECLINE OFFER' or 'CANCEL SENT OFFER',{x=330,y=565,w=175,h=38},activeOffer~=nil or activeSent~=nil,false)
        button('CLOSE',{x=730,y=539,w=110,h=44},true,false)
        session._selectOwn,session._selectTarget=selectOwn,selectTarget
    end
    g.pop()
end

local function send(Runtime,command)
    if Runtime.multiplayer:isClient() then
        local requested,message=Runtime.multiplayer:requestInteraction('itemTrade',command)
        Runtime.state.message=requested and 'Trade request sent to the host…' or tostring(message or 'Trade request could not be sent.')
        return requested
    end
    local ok,_,message=Runtime.World.performNetworkInteraction(Runtime.World.player,Runtime.state,'itemTrade',command)
    Runtime.state.message=message or Runtime.state.message
    if ok then Runtime.saveCurrent() end
    return ok
end
function Screen.mousepressed(Runtime,x,y,buttonId)
    if not session or buttonId~=1 then return true end
    if session.kind=='employee' then
        local worker=require('src.employees').worker(Runtime.state,session.employeeId)
        local offer=worker and Trade.employeeOffer(Runtime.state,worker,localPlayer(Runtime))
        local own=inventoryRows(Runtime.state,localPlayer(Runtime),session.ownSource)
        local listClick=inventoryPanel(130,298,700,'',own,session.ownSource,
            function(source) session.ownSource=source;session.selectedGive=nil end,
            session.selectedGive,function(item)session.selectedGive=item end)
        if listClick(x,y) then return true end
        local canAccept=offer~=nil and (not offer.wantId
            or Trade.availableCount(Runtime.state,localPlayer(Runtime),offer.wantId,offer.wantSource)>0)
        if contains(x,y,{x=121,y=575,w=210,h=42}) and canAccept then send(Runtime,'employee:'..worker.id..':accept');return true end
        if contains(x,y,{x=347,y=575,w=300,h=42}) and session.selectedGive then
            send(Runtime,'employee:'..session.employeeId..':gift:'..session.selectedGive.source..':'..session.selectedGive.id);return true
        end
        if contains(x,y,{x=730,y=575,w=110,h=42}) then Screen.close(Runtime);return true end
        if contains(x,y,{x=410,y=550,w=140,h=46}) then Screen.close(Runtime);return true end
        return true
    end
    local actor,target,own,theirs,pending,sent=playerData(Runtime)
    if session._selectOwn and session._selectOwn(x,y) then return true end
    if session._selectTarget and session._selectTarget(x,y) then return true end
    if contains(x,y,{x=120,y=513,w=195,h=38}) and session.selectedGive and session.selectedWant then
        send(Runtime,('offer:%d:%s:%s:%s:%s'):format(session.playerId,
            session.selectedGive.source,session.selectedGive.id,
            session.selectedWant.source,session.selectedWant.id));return true
    end
    if contains(x,y,{x=330,y=513,w=175,h=38}) and session.selectedGive then
        send(Runtime,('offer:%d:%s:%s:gift'):format(session.playerId,
            session.selectedGive.source,session.selectedGive.id));return true
    end
    local offer=pending[1]
    if contains(x,y,{x=120,y=565,w=195,h=38}) and offer then send(Runtime,'accept:'..offer.id);return true end
    local cancel=offer or sent[1]
    if contains(x,y,{x=330,y=565,w=175,h=38}) and cancel then send(Runtime,'decline:'..cancel.id);return true end
    if contains(x,y,{x=730,y=539,w=110,h=44}) then Screen.close(Runtime);return true end
    return true
end
function Screen.keypressed(Runtime,key)
    if key=='escape' or key=='back' then Screen.close(Runtime);return true end
    return true
end
return Screen
