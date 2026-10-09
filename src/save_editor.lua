local SaveEditor = {}
local Upgrades = require("src.warehouse_upgrades")
local Games = require("src.breakroom_games")
local Fleet = require("src.machine_fleet")
local Storage = require("src.pallet_storage")
local Calendar = require("src.business_calendar")
local Schema = require("src.save_schema")

local FIELDS = {
    { id = "money", label = "Cash", path = { "money" }, step = 1000, maximum = 999999999, money = true },
    { id = "accounts_receivable", label = "Accounts receivable", path = { "accountsReceivable" }, step = 500, maximum = 999999999, money = true },
    { id = "paper", label = "Loose paper sheets", path = { "inventory", "paper" }, step = 100, maximum = 999999999 },
    { id = "prints", label = "Finished prints", path = { "inventory", "prints" }, step = 100, maximum = 999999999 },
    { id = "shipping_cartons", label = "Shipping cartons", path = { "inventory", "stock", "shipping_cartons" }, step = 10, maximum = 999999999 },
    { id = "plastic_wrap_rolls", label = "Plastic wrap rolls", path = { "inventory", "plasticWrapRolls" }, step = 1, maximum = 999999999 },
    { id = "completed_cuts", label = "Completed cuts", path = { "shopProgress", "completedCuts" }, step = 10, maximum = 999999999 },
}
local SUPPLY_FIELDS = {
    { id="house_sheets",label="House stock sheets",path={"inventory","stock","house_sheets"},step=100,maximum=999999999 },
    { id="cover_stock",label="Cover stock sheets",path={"inventory","stock","cover_stock"},step=100,maximum=999999999 },
    { id="maintenance_kit",label="Maintenance kits",path={"inventory","stock","maintenance_kit"},step=1,maximum=999999999 },
    { id="black_ink",label="Black ink",path={"inventory","stock","black_ink"},step=10,maximum=999999999 },
    { id="color_ink",label="Spot-color ink",path={"inventory","stock","color_ink"},step=10,maximum=999999999 },
    { id="press_wash",label="Press wash",path={"inventory","stock","press_wash"},step=5,maximum=999999999 },
    { id="tympan_sheets",label="Tympan sheets",path={"inventory","stock","tympan_sheets"},step=5,maximum=999999999 },
    { id="raw_press_plates",label="Raw press plates",path={"inventory","stock","raw_press_plates"},step=5,maximum=999999999 },
}

local BY_ID = {}
for _, field in ipairs(FIELDS) do BY_ID[field.id] = field end
for _, field in ipairs(SUPPLY_FIELDS) do BY_ID[field.id] = field end

local ACTIONS = {
    rooms = {
        { id="front_left:floor", label="Room A: utility room", bay="front_left", option="floor" },
        { id="front_left:storage", label="Room A: storage room", bay="front_left", option="storage" },
        { id="front_left:breakroom", label="Room A: break room", bay="front_left", option="breakroom" },
        { id="front_right:floor", label="Room B: utility room", bay="front_right", option="floor" },
        { id="front_right:storage", label="Room B: storage room", bay="front_right", option="storage" },
        { id="front_right:breakroom", label="Room B: break room", bay="front_right", option="breakroom" },
        { id="forklift", label="Warehouse forklift", forklift=true },
    },
    machines = {
        { id="polar_115", label="Polar 115 cutter", machine=true, offer=1 },
        { id="skid_wrapper", label="Skid wrapper", machine=true, offer=2 },
        { id="heidelberg_10x15", label="Heidelberg Windmill", machine=true, offer=3 },
    },
    games = {
        { id="front_left:air_hockey", label="Room A: air hockey", bay="front_left", fixture="air_hockey" },
        { id="front_left:basketball", label="Room A: basketball", bay="front_left", fixture="basketball" },
        { id="front_left:critter_kombat", label="Room A: Critter Kombat", bay="front_left", fixture="critter_kombat" },
        { id="front_right:air_hockey", label="Room B: air hockey", bay="front_right", fixture="air_hockey" },
        { id="front_right:basketball", label="Room B: basketball", bay="front_right", fixture="basketball" },
        { id="front_right:critter_kombat", label="Room B: Critter Kombat", bay="front_right", fixture="critter_kombat" },
    },
}
local ACTION_BY_ID = {}
for _, group in pairs(ACTIONS) do
    for _, action in ipairs(group) do ACTION_BY_ID[action.id] = action end
end

local function copy(value)
    if type(value)~="table" then return value end
    local result={}
    for key,item in pairs(value) do result[key]=copy(item) end
    return result
end

local function requestId(receipts, prefix)
    local existing={}
    for _,receipt in ipairs(receipts) do existing[receipt.requestId]=true end
    local suffix=1
    while existing[prefix..suffix] do suffix=suffix+1 end
    return prefix..suffix
end

local function grantRoom(state, bayId, optionId)
    local warehouse,reason=Upgrades.ensure(state)
    if not warehouse then return false,reason end
    local bay=warehouse.bays[bayId]
    if bay.status~="locked" and bay.optionId~=optionId then
        return false,"That bay already contains a different room."
    end
    if bay.status=="complete" then return false,"That room is already complete." end
    local now=Calendar.absoluteHours(state)
    local project
    if bay.status=="locked" then
        local catalog=Upgrades.catalog(optionId)
        local id=string.format("WUP-%04d",warehouse.nextProjectId)
        local token=requestId(warehouse.receipts,"CHEAT-ROOM-")
        project={id=id,requestId=token,bayId=bayId,optionId=optionId,
            pricePaid=catalog.price,purchasedAtHours=now}
        warehouse.nextProjectId=warehouse.nextProjectId+1
        warehouse.projects[#warehouse.projects+1]=project
        warehouse.receipts[#warehouse.receipts+1]={requestId=token,kind="upgrade",bayId=bayId,
            optionId=optionId,targetId=id,pricePaid=catalog.price,purchasedAtHours=now}
        bay.optionId,bay.projectId=optionId,id
    else
        for _,candidate in ipairs(warehouse.projects) do
            if candidate.id==bay.projectId then project=candidate;break end
        end
        if not project then return false,"The room project is missing." end
    end
    -- Complete a valid four-stage project instantly without changing the shop clock.
    local start=math.max(now,project.purchasedAtHours)
    project.phase,project.stage="complete",4
    project.noticeCallId="CHEAT-NOTICE-"..project.id
    project.noticeDeliveredAtHours=start
    project.arrivalDueAtHours=start+Upgrades.ARRIVAL_LEAD_HOURS
    project.workerArrivedAtHours=project.arrivalDueAtHours
    project.stageStartedAtHours=project.workerArrivedAtHours+3*Upgrades.STAGE_HOURS
    project.stageDueAtHours=project.stageStartedAtHours+Upgrades.STAGE_HOURS
    project.completedAtHours=project.stageDueAtHours
    project.workerReleasedAtHours=project.completedAtHours
    project.pausedAtHours=nil
    bay.status="complete"
    if warehouse.activeProjectId==project.id then warehouse.activeProjectId=nil end
    if state.constructionWorker and state.constructionWorker.projectId==project.id then
        state.constructionWorker=nil
    end
    if optionId=="storage" then
        state.storage=state.storage or Storage.defaultState()
        local rack=Storage.rackDefinition(bayId)
        state.storage.racks[rack.id]=state.storage.racks[rack.id] or rack
    end
    return true,"Room completed and unlocked."
end

local function grantForklift(state)
    local warehouse,reason=Upgrades.ensure(state)
    if not warehouse then return false,reason end
    if warehouse.forkliftOwned then return false,"The forklift is already owned." end
    warehouse.receipts[#warehouse.receipts+1]={requestId=requestId(warehouse.receipts,"CHEAT-FORKLIFT-"),
        kind="forklift",optionId="forklift",targetId="forklift",
        pricePaid=Upgrades.catalog("forklift").price,purchasedAtHours=Calendar.absoluteHours(state)}
    warehouse.forkliftOwned=true
    -- The normal warehouse update places the physical lift when its spawn is clear.
    return true,"Forklift granted. It will appear when its parking space is clear."
end

local function grantMachine(state,action)
    local offer=Fleet.offers("dealer")[action.offer]
    if not offer or offer.modelId~=action.id then return false,"Machine offer is unavailable." end
    -- Reuse the normal installation/placement path; its debit consumes this
    -- temporary credit, leaving the player's cash unchanged.
    state.money=state.money+offer.price
    local ok,item=Fleet.buy(state,"dealer",action.offer)
    if not ok then return false,item end
    for componentId in pairs(Fleet.definitions[action.id].components) do
        item.variables[componentId]=100
    end
    item.condition=100
    return true,"New machine installed at 100% condition."
end

local function grantGame(state,action)
    local bay=state.warehouse and state.warehouse.bays[action.bay]
    if bay and bay.status~="complete"
        and (bay.status=="locked" or bay.optionId=="breakroom") then
        local ok,reason=grantRoom(state,action.bay,"breakroom")
        if not ok then return false,reason end
        bay=state.warehouse.bays[action.bay]
    end
    if not bay or bay.status~="complete" or bay.optionId~="breakroom" then
        return false,"Complete a break room in this bay first."
    end
    state.breakroomGames=state.breakroomGames or Games.defaultState()
    if not Games.validate(state.breakroomGames) then return false,"Break room purchase records are invalid." end
    local record=state.breakroomGames.bays[action.bay]
    if record[action.fixture] then return false,"That game is already owned." end
    record[action.fixture]=true
    if action.fixture=="basketball" then
        record.ball={id=action.bay.."-basketball",sceneId=action.bay,
            x=240,y=315,lastX=240,lastY=315,lastSceneId=action.bay,mode="placed"}
    end
    state.breakroomGames.receipts[#state.breakroomGames.receipts+1]={
        requestId=requestId(state.breakroomGames.receipts,"CHEAT-GAME-"),bayId=action.bay,
        fixtureId=action.fixture,pricePaid=Games.CATALOG[action.fixture].price}
    return true,"Break room game installed."
end

function SaveEditor.actions(group) return ACTIONS[group] or {} end

function SaveEditor.actionStatus(state,id)
    local action=ACTION_BY_ID[id]
    if not action or not state then return "UNAVAILABLE" end
    if action.machine then
        local count=0
        for _,item in ipairs(state.machines and state.machines.items or {}) do
            if item.modelId==id and item.status=="installed" then count=count+1 end
        end
        return tostring(count).." INSTALLED"
    end
    if action.forklift then return state.warehouse and state.warehouse.forkliftOwned and "OWNED" or "GRANT" end
    local bay=state.warehouse and state.warehouse.bays and state.warehouse.bays[action.bay]
    if action.fixture then
        if Games.owns(state,action.bay,action.fixture) then return "OWNED" end
        if bay and bay.status~="locked" and bay.optionId~="breakroom" then return "OTHER ROOM" end
        return bay and bay.status~="complete" and "GRANT + ROOM" or "GRANT"
    end
    if not bay or bay.status=="locked" then return "GRANT" end
    if bay.optionId~=action.option then return "OTHER ROOM" end
    return bay.status=="complete" and "OWNED" or "FINISH"
end

local function getPath(root, path)
    local value = root
    for _, key in ipairs(path) do
        if type(value) ~= "table" then return nil end
        value = value[key]
    end
    return value
end

local function setPath(root, path, value)
    local target = root
    for index = 1, #path - 1 do
        local key = path[index]
        if type(target[key]) ~= "table" then target[key] = {} end
        target = target[key]
    end
    target[path[#path]] = value
end

function SaveEditor.fields(group)
    return group=="supplies" and SUPPLY_FIELDS or FIELDS
end

function SaveEditor.field(id)
    return BY_ID[id]
end

function SaveEditor.value(state, id)
    local field = BY_ID[id]
    return field and getPath(state, field.path) or nil
end

function SaveEditor.setValue(state, id, value)
    local field = BY_ID[id]
    if type(state) ~= "table" or not field then return false, "Unknown save field." end
    value = tonumber(value)
    if not value or value ~= value or value == math.huge or value == -math.huge then
        return false, "Enter a whole number."
    end
    value = math.max(0, math.min(field.maximum, math.floor(value + 0.5)))
    local previous = getPath(state, field.path)
    setPath(state, field.path, value)
    return true, value, previous
end

function SaveEditor.editSlot(context, slot, id, value)
    if type(context) ~= "table" or not context.save then
        return false, "Save editor is unavailable."
    end
    if context.isNetworkClient and context.isNetworkClient() then
        return false, "Only the host can change shop saves."
    end
    slot = math.floor(tonumber(slot) or 0)
    if slot < 1 or slot > (context.save.SLOT_COUNT or 3) then
        return false, "Choose a valid save slot."
    end

    local live = context.useActiveState == true and context.state
        and context.state.activeSlot == slot
    if live then
        local ok, applied, previous = SaveEditor.setValue(context.state, id, value)
        if not ok then return false, applied end
        if not context.saveCurrent or not context.saveCurrent() then
            setPath(context.state, BY_ID[id].path, previous)
            return false, "The live shop could not be saved; the change was rolled back."
        end
        return true, applied, "Live slot " .. slot .. " saved."
    end

    local payload, status = context.save.load(slot)
    if not payload then
        return false, status == "corrupted"
            and "That slot is damaged and has no valid recovery copy."
            or "That slot is empty. Create a shop before editing it."
    end
    local ok, applied = SaveEditor.setValue(payload.state, id, value)
    if not ok then return false, applied end
    if not context.save.save(slot, payload.state, payload.player) then
        return false, "That save file could not be updated safely."
    end
    return true, applied, "Slot " .. slot .. " saved."
end

local MUTABLE_FIELDS={"money","warehouse","breakroomGames","storage","forklift",
    "machines","constructionWorker"}
local function restore(state,backup)
    for _,key in ipairs(MUTABLE_FIELDS) do state[key]=backup[key] end
end

function SaveEditor.grantSlot(context,slot,id)
    local action=ACTION_BY_ID[id]
    if not action then return false,"Unknown cheat item." end
    if type(context)~="table" or not context.save then
        return false,"Save editor is unavailable."
    end
    if context.isNetworkClient and context.isNetworkClient() then
        return false,"Only the host can change shop saves."
    end
    slot=math.floor(tonumber(slot) or 0)
    if slot<1 or slot>(context.save.SLOT_COUNT or 3) then
        return false,"Choose a valid save slot."
    end
    local live=context.useActiveState==true and context.state
        and context.state.activeSlot==slot
    local payload,status
    if not live then
        payload,status=context.save.load(slot)
        if not payload then return false,status=="corrupted"
            and "That slot is damaged and has no valid recovery copy."
            or "That slot is empty. Create a shop before editing it." end
    end
    local state=live and context.state or payload.state
    local backup={}
    for _,key in ipairs(MUTABLE_FIELDS) do backup[key]=copy(state[key]) end
    local executed,ok,message=pcall(function()
        if action.option then return grantRoom(state,action.bay,action.option) end
        if action.forklift then return grantForklift(state) end
        if action.machine then return grantMachine(state,action) end
        return grantGame(state,action)
    end)
    if not executed then
        restore(state,backup)
        return false,"The grant failed before saving: "..tostring(ok)
    end
    if not ok then restore(state,backup);return false,message end
    local valid,accepted=pcall(Schema.validState,state)
    if not valid or not accepted then
        restore(state,backup)
        return false,"The grant would make this save invalid; nothing was changed."
    end
    local writeOk,saved=pcall(function()
        if live then return context.saveCurrent and context.saveCurrent() end
        return context.save.save(slot,state,payload.player)
    end)
    if not writeOk or not saved then
        restore(state,backup)
        return false,"The shop could not be saved; the grant was rolled back."
    end
    return true,message.." Slot "..slot.." saved."
end

function SaveEditor.inspectSlot(context, slot)
    if context.useActiveState == true and context.state
        and context.state.activeSlot == slot
    then
        return context.state, "live"
    end
    local payload, status = context.save.load(slot)
    return payload and payload.state or nil, status
end

return SaveEditor
