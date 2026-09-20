-- One first-person rack presenter for local and remote players. It emits
-- intents; only the host's storage boundary may change physical stock.
local Ui = require("src.screens.ui")
local Storage = require("src.pallet_storage")
local Screen = {}
Screen.__index = Screen
Screen.RACK_IMAGE = "assets/source/warehouse-expansion-v1/rack-front-2x5-approved.png"
Screen.PALLET_IMAGE = "assets/source/warehouse-expansion-v1/pallet-front-variants-v1.png"

local sessionNumber = 0
local images, imageError
local SOURCE = { width=1536, height=740 }
local COLUMNS = { {110,240}, {382,234}, {650,245}, {929,227}, {1190,240} }
local ROWS = { [1]={y=483,height=185}, [2]={y=240,height=186} }
local REASONS = {
    no_vehicle="Operate a nearby pallet jack or forklift to move stock.",
    not_operator="Only the worker operating this vehicle can transfer its load.",
    out_of_range="Move the vehicle to this rack's loading position.",
    not_aligned="Align the forks with the selected shelf.",
    blocked="The shelf approach is blocked.",
    moving="Stop the vehicle before transferring a pallet.",
    lifting="Wait until the forks finish raising or lowering.",
    wrong_height="Lower forks for the bottom row; raise them fully for the top row.",
    forklift_required="Upper row: buy and operate a forklift to use these five spaces.",
    forklift_not_owned="Purchase the forklift before using it for rack transfers.",
    rack_unavailable="This storage bay is not yet complete.",
    no_load="The vehicle must physically carry the pallet you want to store.",
    empty="This shelf is empty. Bring a pallet on your vehicle to store it.",
    loaded="Unload the vehicle before retrieving another pallet.",
    occupied="Choose an empty shelf to store the loaded pallet.",
    waiting="Waiting for the host to confirm this transfer.",
    readonly="Rack viewing is available; transfer controls are not connected.",
    two_vehicles="Park the other vehicle before using this one.",
    stale_revision="The rack changed. Review its current contents and try again.",
    wrong_fork_height="Move the forks to this shelf's height before transferring.",
    slot_occupied="Another pallet is already on that shelf.",
}
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end
local function finite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end
local function label(value, maximum)
    local text = tostring(value or ""):gsub("[\r\n\t]", " ")
    maximum = maximum or 80
    return #text > maximum and text:sub(1,maximum-3).."..." or text
end
local function rackReady(state, rackId)
    local rack = state.storage and state.storage.racks and state.storage.racks[rackId]
    local bay = rack and state.warehouse and state.warehouse.bays and state.warehouse.bays[rack.bayId]
    return bay and bay.status == "complete" and bay.optionId == "storage" or false
end
local function fontFor(fonts, name)
    return type(fonts) == "table" and (fonts[name] or fonts.body or fonts.normal) or nil
end
local function setFont(fonts, name)
    local font = fontFor(fonts,name)
    if font then love.graphics.setFont(font) end
end
local function centerText(text, rect)
    local font = love.graphics.getFont()
    local height = font and font.getHeight and font:getHeight() or 14
    love.graphics.printf(text,rect.x,rect.y+(rect.height-height)/2,rect.width,"center")
end

local function loadImages()
    if images or imageError then return images, imageError end
    if not love or not love.graphics or not love.graphics.newImage then return nil, "Rack images unavailable." end
    local okay, result = pcall(function()
        local rack = love.graphics.newImage(Screen.RACK_IMAGE)
        local pallet = love.graphics.newImage(Screen.PALLET_IMAGE)
        local rw,rh = rack:getDimensions()
        local pw,ph = pallet:getDimensions()
        if rw ~= 1536 or rh ~= 1024 or pw ~= 2172 or ph ~= 724 then
            error("Rack art dimensions changed; source anchors need registration.")
        end
        rack:setFilter("linear","linear")
        pallet:setFilter("linear","linear")
        local result = {rack=rack,pallet=pallet,quads={},rackQuad=love.graphics.newQuad(0,0,1536,740,rw,rh)}
        for index=1,3 do result.quads[index] = love.graphics.newQuad((index-1)*724,0,724,724,pw,ph) end
        return result
    end)
    if okay then images = result else imageError = tostring(result) end
    return images, imageError
end

function Screen.clearImageCache()
    images,imageError=nil,nil
end

function Screen.new(rackId, options)
    options = options or {}
    sessionNumber = sessionNumber + 1
    return setmetatable({rackId=rackId,selected={row=1,column=1},onIntent=options.onIntent,
        context=options.context,onClose=options.onClose,requestPrefix=options.requestPrefix,
        sessionNumber=sessionNumber,requestNumber=0,width=options.width or 960,height=options.height or 678,
        closed=false,pending=nil,message=nil,pointer=nil},Screen)
end

function Screen:layout(width,height)
    width, height = width or self.width, height or self.height
    local margin = width < 700 and 12 or 24
    local panel = {x=margin,y=margin,width=width-margin*2,height=height-margin*2}
    local headerHeight, footerHeight = height < 500 and 40 or 50, height < 500 and 108 or 122
    local area = {x=panel.x+8,y=panel.y+headerHeight,width=panel.width-16,
        height=math.max(1,panel.height-headerHeight-footerHeight)}
    local scale = math.min(area.width/SOURCE.width,area.height/SOURCE.height)
    local art = {x=area.x+(area.width-SOURCE.width*scale)/2,y=area.y,
        width=SOURCE.width*scale,height=SOURCE.height*scale,scale=scale}
    local bottom = panel.y+panel.height
    local actionWidth = (panel.width-40)/2
    local result = {panel=panel,art=art,slots={{},{}},
        close={x=panel.x+panel.width-112,y=panel.y+4,width=100,height=44},
        title={x=panel.x+16,y=panel.y+12,width=panel.width-136,height=28},
        details={x=panel.x+16,y=bottom-footerHeight+5,width=panel.width-32,height=38},
        warning={x=panel.x+16,y=bottom-76,width=panel.width-32,height=26},
        store={x=panel.x+16,y=bottom-54,width=actionWidth,height=44},
        retrieve={x=panel.x+24+actionWidth,y=bottom-54,width=actionWidth,height=44}}
    for row=1,2 do
        for column=1,5 do
            local source = {x=COLUMNS[column][1],y=ROWS[row].y,width=COLUMNS[column][2],height=ROWS[row].height}
            result.slots[row][column] = {x=art.x+source.x*scale,y=art.y+source.y*scale,
                width=source.width*scale,height=source.height*scale,source=source}
        end
    end
    return result
end

function Screen:resize(width,height)
    if not finite(width) or not finite(height) or width < 480 or height < 320 then return false end
    self.width,self.height = width,height
    return true
end

function Screen:getSelected() return copy(self.selected) end

function Screen:setContext(context) self.context = context end

function Screen:select(row,column)
    if row ~= 1 and row ~= 2 then return false end
    if not finite(column) or column ~= math.floor(column) or column < 1 or column > 5 then return false end
    self.selected, self.message = {row=row,column=column},nil
    return true
end

function Screen.appearance(pallet)
    if not pallet then return nil end
    if pallet.wrapped == true or pallet.wrapProgress == 1 then return 3 end
    if pallet.kind == "vendor_product" then return 2 end
    local paper = pallet.paper
    if pallet.status == "complete" or pallet.status == "finished" or pallet.status == "cut"
        or (paper and paper.status == "complete") or (pallet.finishedSheets or 0) > 0 then return 2 end
    return 1
end

local function palletDescription(item)
    if not item then return "Empty shelf", "Select a physical shelf, then store or retrieve using the vehicle." end
    local pallet = item.pallet
    local title = label(pallet.id,40) .. "  |  " .. label(item.job and (item.job.company or item.job.vendor),40)
    local detail
    if pallet.kind == "vendor_product" then
        detail = label(pallet.productName or pallet.productId,46).."  |  "..Ui.commaNumber(pallet.remainingQuantity or pallet.quantity or 0).." "..label(pallet.unit,12)
    else
        detail = Ui.commaNumber(pallet.remainingSheets or pallet.initialSheets or 0).." sheets"
        if (pallet.finishedSheets or 0) > 0 then detail=detail.."  |  "..Ui.commaNumber(pallet.finishedSheets).." finished" end
        if (pallet.damagedSheets or 0) > 0 then detail=detail.."  |  "..Ui.commaNumber(pallet.damagedSheets).." spoiled" end
        if pallet.press then detail=detail.."  |  "..tostring(pallet.press.completedColors or 0).." colors printed" end
    end
    return title, detail..(pallet.wrapped and "  |  Wrapped" or "  |  Unwrapped")
end

function Screen:view(state)
    local row,column = self.selected.row,self.selected.column
    local ids = Storage.slots(state,self.rackId)
    local selectedId = ids[row][column]
    local selectedItem = selectedId and Storage.find(state,selectedId)
    local context = type(self.context) == "function" and self.context(state,self.rackId,row,column) or self.context
    context = type(context) == "table" and context or {}
    local kind = context.vehicle
    local field = kind == "forklift" and "forklift" or kind == "pallet_jack" and "palletJack" or nil
    local vehicle = field and state[field]
    local common
    if not rackReady(state,self.rackId) then common="rack_unavailable"
    elseif self.pending then common="waiting"
    elseif type(self.onIntent) ~= "function" then common="readonly"
    elseif not vehicle then common="no_vehicle"
    elseif not vehicle.operating or vehicle.operatorPlayerId ~= context.playerId then common="not_operator"
    elseif context.near ~= true then common="out_of_range"
    elseif context.aligned ~= true then common="not_aligned"
    elseif context.clear ~= true then common="blocked"
    elseif vehicle.moving then common="moving"
    elseif kind == "pallet_jack" and row == 2 then common="forklift_required"
    elseif kind == "forklift" then
        if vehicle.owned ~= true or not (state.warehouse and state.warehouse.forkliftOwned) then common="forklift_not_owned"
        elseif vehicle.lifting then common="lifting"
        elseif not finite(vehicle.forkHeight) or math.abs(vehicle.forkHeight-(row==2 and 1 or 0))>0.001
            or (vehicle.targetForkHeight ~= nil and (not finite(vehicle.targetForkHeight)
                or math.abs(vehicle.targetForkHeight-vehicle.forkHeight)>0.001)) then common="wrong_height" end
    end
    local other = field and state[field=="forklift" and "palletJack" or "forklift"]
    if not common and other and other.operating and other.operatorPlayerId==context.playerId then common="two_vehicles" end
    local carriedItem = vehicle and vehicle.carriedPalletId and Storage.find(state,vehicle.carriedPalletId)
    local expectedLocation = kind=="forklift" and "on_forklift" or "on_pallet_jack"
    local carrying = carriedItem and carriedItem.pallet.location==expectedLocation
    local storeReason = common or (selectedId and "occupied") or (not carrying and "no_load") or nil
    local retrieveReason = common or (not selectedId and "empty") or (vehicle and vehicle.carriedPalletId and "loaded") or nil
    local title,detail = palletDescription(selectedItem)
    local warning = common and REASONS[common]
        or (selectedId and retrieveReason and REASONS[retrieveReason])
        or (not selectedId and storeReason and REASONS[storeReason])
        or (row==2 and "Forklift at upper height. This transfer moves the actual loaded pallet."
            or "Lower row accepts a pallet jack or forklift. Upper row requires a forklift.")
    local slots = {{},{}}
    for r=1,2 do for c=1,5 do
        local id=ids[r][c]
        local item=id and Storage.find(state,id)
        slots[r][c]={palletId=id,variant=item and Screen.appearance(item.pallet),
            wrapped=item and item.pallet.wrapped==true or false,
            label=(r==2 and "U" or "L")..c,selected=r==row and c==column}
    end end
    return {rackId=self.rackId,selected=copy(self.selected),selectedId=selectedId,slots=slots,
        title=title,detail=detail,warning=self.message or warning,vehicle=kind,playerId=context.playerId,
        carriedPalletId=carrying and carriedItem.pallet.id or nil,
        canStore=storeReason==nil,canRetrieve=retrieveReason==nil,storeReason=storeReason,retrieveReason=retrieveReason,
        upperLocked=not (state.warehouse and state.warehouse.forkliftOwned==true),
        revision=state.storage and state.storage.revision or 0,closed=self.closed}
end

function Screen:resolve(requestId,okay,message)
    if not self.pending or self.pending.requestId~=requestId then return false end
    self.pending=nil
    self.message=message or (okay and "Pallet transfer confirmed." or "The host could not complete this transfer.")
    return true
end

function Screen:activate(state,action)
    if self.closed or (action~="store" and action~="retrieve") then return nil end
    local view=self:view(state)
    if not (action=="store" and view.canStore or action=="retrieve" and view.canRetrieve) then
        local reason=action=="store" and view.storeReason or view.retrieveReason
        self.message=REASONS[reason] or "That transfer is unavailable."
        return {action="blocked",reason=reason}
    end
    self.requestNumber=self.requestNumber+1
    local prefix=tostring(self.requestPrefix or ("RACK-"..tostring(view.playerId).."-"..self.sessionNumber)):gsub("[^%w_.%-]","-"):sub(1,72)
    local request={requestId=prefix.."-"..view.revision.."-"..self.requestNumber,expectedRevision=view.revision,
        action=action,vehicle=view.vehicle,palletId=action=="store" and view.carriedPalletId or view.selectedId,
        rackId=self.rackId,row=self.selected.row,column=self.selected.column}
    self.pending=copy(request)
    self.message=nil
    local okay,accepted,response=pcall(self.onIntent,copy(request))
    if not okay then self:resolve(request.requestId,false,"Transfer could not be sent. Please try again.")
    elseif accepted~=nil then
        self:resolve(request.requestId,accepted==true,accepted==true and "Pallet transfer confirmed."
            or label(REASONS[response] or response or "Transfer rejected.",100))
    end
    return {action="intent",request=copy(request),pending=self.pending~=nil}
end

function Screen:close()
    if self.closed then return {action="close"} end
    self.closed=true
    -- Closing a view never cancels an already-sent physical transfer.
    if type(self.onClose)=="function" then self.onClose() end
    return {action="close"}
end

function Screen:mousepressed(state,x,y,button)
    if self.closed or button~=1 then return nil end
    local layout=self:layout()
    if Ui.contains(layout.close,x,y) then return self:close() end
    for row=1,2 do for column=1,5 do
        local rect=layout.slots[row][column]
        local hitWidth,hitHeight=math.max(44,rect.width),math.max(44,rect.height)
        local hit={x=rect.x+(rect.width-hitWidth)/2,y=rect.y+(rect.height-hitHeight)/2,width=hitWidth,height=hitHeight}
        if Ui.contains(hit,x,y) then
            self:select(row,column)
            return {action="selected",row=row,column=column}
        end
    end end
    if Ui.contains(layout.store,x,y) then return self:activate(state,"store") end
    if Ui.contains(layout.retrieve,x,y) then return self:activate(state,"retrieve") end
end

function Screen:touchpressed(state,x,y) return self:mousepressed(state,x,y,1) end
function Screen:mousemoved(x,y) self.pointer={x=x,y=y} end

function Screen:keypressed(state,key,isRepeat)
    if self.closed then return nil end
    if key=="escape" then return self:close() end
    local row,column=self.selected.row,self.selected.column
    if key=="left" then column=math.max(1,column-1)
    elseif key=="right" then column=math.min(5,column+1)
    elseif key=="up" then row=2
    elseif key=="down" then row=1
    elseif not isRepeat and (key=="return" or key=="kpenter" or key=="space") then
        return self:activate(state,self:view(state).selectedId and "retrieve" or "store")
    elseif not isRepeat and key=="s" then return self:activate(state,"store")
    elseif not isRepeat and key=="r" then return self:activate(state,"retrieve")
    else return nil end
    self:select(row,column)
    return {action="selected",row=row,column=column}
end

local function button(rect,text,enabled,hovered)
    Ui.panel(rect,enabled and (hovered and {0.19,0.42,0.35,1} or {0.10,0.29,0.25,1}) or {0.12,0.13,0.13,1},
        enabled and {0.45,0.69,0.54,1} or {0.26,0.29,0.28,1},3,1)
    love.graphics.setColor(enabled and {0.95,0.96,0.91,1} or {0.48,0.51,0.49,1})
    centerText(text,rect)
end

function Screen:draw(state,fonts,assets)
    if self.closed then return end
    local view,layout=self:view(state),self:layout()
    local art,errorMessage=loadImages()
    local g=love.graphics
    g.push("all")
    Ui.panel(layout.panel,{0.035,0.045,0.042,0.99},{0.37,0.45,0.39,1},5,2)
    setFont(fonts,"title")
    g.setColor(0.97,0.79,0.34,1)
    g.printf(self.rackId=="front_left-rack" and "LEFT BAY / PALLET SHELVES" or "RIGHT BAY / PALLET SHELVES",
        layout.title.x,layout.title.y,layout.title.width,"left")
    setFont(fonts,"body")
    button(layout.close,"BACK",true,self.pointer and Ui.contains(layout.close,self.pointer.x,self.pointer.y))
    if art then
        g.setColor(1,1,1,1)
        g.draw(art.rack,art.rackQuad,layout.art.x,layout.art.y,0,layout.art.scale,layout.art.scale)
    else
        g.setColor(0.92,0.67,0.33,1)
        g.printf("Shelf artwork unavailable. "..label(errorMessage,110),layout.art.x,layout.art.y+20,layout.art.width,"center")
    end
    setFont(fonts,"small")
    if view.upperLocked then
        local warning={x=layout.art.x+layout.art.width*0.24,y=layout.art.y+layout.art.scale*120,
            width=layout.art.width*0.52,height=math.max(16,layout.art.scale*30)}
        g.setColor(0.05,0.05,0.035,0.92); g.rectangle("fill",warning.x,warning.y,warning.width,warning.height,2,2)
        g.setColor(0.97,0.76,0.36,1); centerText("TOP ROW: FORKLIFT REQUIRED",warning)
    end
    for row=1,2 do for column=1,5 do
        local slot,rect=view.slots[row][column],layout.slots[row][column]
        if slot.variant and art then
            -- All three source pallets share baseline y=648. A single scale
            -- preserves the smaller height of the cut-paper load.
            local scale=math.min(rect.width/670,rect.height/565)
            local sourceCenter=slot.variant==1 and 374 or slot.variant==2 and 361 or 352
            g.setColor(1,1,1,1)
            g.draw(art.pallet,art.quads[slot.variant],rect.x+rect.width/2-sourceCenter*scale,
                rect.y+rect.height-648*scale,0,scale,scale)
        end
        local hovered=self.pointer and Ui.contains(rect,self.pointer.x,self.pointer.y)
        if slot.selected or hovered then
            g.setColor(slot.selected and {0.98,0.79,0.28,0.95} or {0.76,0.83,0.76,0.7})
            g.setLineWidth(slot.selected and 2 or 1)
            g.rectangle("line",rect.x+2,rect.y+2,math.max(0,rect.width-4),math.max(0,rect.height-4),2,2)
        end
        if row==2 and view.upperLocked then
            g.setColor(0.06,0.05,0.03,0.28)
            g.rectangle("fill",rect.x,rect.y,rect.width,rect.height)
        end
        local plaque={x=rect.x+rect.width*0.30,y=rect.y+rect.height+3*layout.art.scale,
            width=rect.width*0.40,height=math.max(12,22*layout.art.scale)}
        g.setColor(0.12,0.13,0.10,0.9); g.rectangle("fill",plaque.x,plaque.y,plaque.width,plaque.height,2,2)
        g.setColor(0.95,0.91,0.68,1); centerText(slot.label,plaque)
    end end
    setFont(fonts,"body")
    g.setColor(0.91,0.94,0.89,1)
    g.printf(label(view.title,100),layout.details.x,layout.details.y,layout.details.width,"left")
    setFont(fonts,"small")
    g.setColor(0.70,0.77,0.72,1)
    g.printf(label(view.detail,120),layout.details.x,layout.details.y+18,layout.details.width,"left")
    g.setColor(view.upperLocked and {0.94,0.68,0.29,1} or {0.81,0.82,0.67,1})
    g.printf(label(view.warning,132),layout.warning.x,layout.warning.y,layout.warning.width,"left")
    setFont(fonts,"body")
    button(layout.store,"STORE LOADED PALLET",view.canStore,self.pointer and Ui.contains(layout.store,self.pointer.x,self.pointer.y))
    button(layout.retrieve,"RETRIEVE SELECTED PALLET",view.canRetrieve,self.pointer and Ui.contains(layout.retrieve,self.pointer.x,self.pointer.y))
    g.pop()
end

return Screen
