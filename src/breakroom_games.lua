-- Durable fixture ownership. Live matches are deliberately kept outside saves.
local Games = {}
Games.IDS = { air_hockey = true, basketball = true, critter_kombat = true }
Games.BAYS = { front_left = true, front_right = true }
Games.ORDER = { "air_hockey", "basketball", "critter_kombat" }
Games.CATALOG = {
    air_hockey = { name = "Air hockey table", price = 1800, x = 465, y = 417,
        width = 162, depth = 90, interactionX = 506, interactionY = 408 },
    basketball = { name = "Portable basketball goal and ball", price = 950,
        x = 126, y = 450, width = 150, depth = 40,
        rimX = 172, rimY = 280, interactionX = 40, interactionY = 385 },
    critter_kombat = { name = "Critter Kombat arcade", price = 2500, x = 887, y = 430,
        width = 60, depth = 40, interactionX = 860, interactionY = 436 },
}

local function token(value)
    return type(value) == "string" and #value >= 1 and #value <= 64
        and value:match("^[%w_.%-]+$") ~= nil
end
local function exact(value, allowed)
    if type(value) ~= "table" then return false end
    for key in pairs(value) do if not allowed[key] then return false end end
    return true
end
local function bay()
    return { air_hockey = false, basketball = false, critter_kombat = false,
        ball = nil }
end
function Games.defaultState()
    return { version = 1, bays = { front_left = bay(), front_right = bay() }, receipts = {} }
end
local function validBall(ball, bayId)
    if ball == nil then return true end
    return exact(ball, { id=true, sceneId=true, x=true, y=true, mode=true,
        holderPlayerId=true, lastX=true, lastY=true, lastSceneId=true })
        and ball.id == bayId .. "-basketball"
        and (ball.sceneId=="warehouse" or Games.BAYS[ball.sceneId])
        and (ball.lastSceneId=="warehouse" or Games.BAYS[ball.lastSceneId])
        and type(ball.x) == "number" and ball.x >= 0 and ball.x <= 960
        and type(ball.y) == "number" and ball.y >= 0 and ball.y <= 678
        and type(ball.lastX) == "number" and ball.lastX >= 0 and ball.lastX <= 960
        and type(ball.lastY) == "number" and ball.lastY >= 0 and ball.lastY <= 678
        and (ball.mode == "placed" or ball.mode == "held" or ball.mode == "flight")
        and (ball.holderPlayerId == nil or type(ball.holderPlayerId) == "number"
            and ball.holderPlayerId == math.floor(ball.holderPlayerId)
            and ball.holderPlayerId >= 1 and ball.holderPlayerId <= 4)
end
function Games.validate(value)
    if not exact(value, { version=true, bays=true, receipts=true }) or value.version ~= 1
        or not exact(value.bays, Games.BAYS) or type(value.receipts) ~= "table" then return false end
    local receiptOwners, requestIds = {}, {}
    for index, receipt in ipairs(value.receipts) do
        if not exact(receipt, { requestId=true, bayId=true, fixtureId=true, pricePaid=true })
            or not token(receipt.requestId) or requestIds[receipt.requestId]
            or not Games.BAYS[receipt.bayId] or not Games.IDS[receipt.fixtureId]
            or receipt.pricePaid ~= Games.CATALOG[receipt.fixtureId].price then return false end
        local key = receipt.bayId .. ":" .. receipt.fixtureId
        if receiptOwners[key] then return false end
        receiptOwners[key], requestIds[receipt.requestId] = true, true
    end
    for key in pairs(value.receipts) do
        if type(key) ~= "number" or key ~= math.floor(key)
            or key < 1 or key > #value.receipts then return false end
    end
    for bayId in pairs(Games.BAYS) do
        local record = value.bays[bayId]
        if not exact(record, { air_hockey=true, basketball=true, critter_kombat=true, ball=true })
            or not validBall(record.ball, bayId) then return false end
        for fixtureId in pairs(Games.IDS) do
            if type(record[fixtureId]) ~= "boolean"
                or record[fixtureId] ~= (receiptOwners[bayId .. ":" .. fixtureId] == true) then return false end
        end
        if record.ball ~= nil and not record.basketball then return false end
    end
    return true
end
function Games.normalize(value)
    if value == nil then return Games.defaultState() end
    if not Games.validate(value) then return nil end
    -- Do not restore transient possession or a projectile from a disk save.
    local copy = Games.defaultState()
    for bayId in pairs(Games.BAYS) do
        for id in pairs(Games.IDS) do copy.bays[bayId][id] = value.bays[bayId][id] end
        local ball = value.bays[bayId].ball
        if ball then copy.bays[bayId].ball = {
            id = ball.id, sceneId = ball.lastSceneId, x = ball.lastX, y = ball.lastY,
            lastX = ball.lastX, lastY = ball.lastY, lastSceneId=ball.lastSceneId,
            mode = "placed" }
        end
    end
    for i, receipt in ipairs(value.receipts) do
        copy.receipts[i] = { requestId=receipt.requestId, bayId=receipt.bayId,
            fixtureId=receipt.fixtureId, pricePaid=receipt.pricePaid }
    end
    return copy
end
function Games.owns(state, bayId, fixtureId)
    local record = state and state.breakroomGames and state.breakroomGames.bays
        and state.breakroomGames.bays[bayId]
    return record and record[fixtureId] == true or false
end
local function footprintBlocked(state, bayId, fixtureId, players)
    local fixture = Games.CATALOG[fixtureId]
    local function overlaps(x,y,sceneId,margin)
        return sceneId == bayId and type(x) == "number" and type(y) == "number"
            and math.abs(x-fixture.x) < fixture.width/2+(margin or 0)
            and math.abs(y-fixture.y) < fixture.depth/2+(margin or 0)
    end
    for _, player in ipairs(players or {}) do
        if overlaps(player.x,player.y,player.sceneId,12) then return true end
    end
    local jack=state.palletJack
    if jack and overlaps(jack.x,jack.y,jack.sceneId,28) then return true end
    for _,item in ipairs(require("src.pallet_logistics").physicalPallets(state)) do
        local world=item.pallet and item.pallet.world
        if world and overlaps(world.x,world.y,world.sceneId or "warehouse",22) then return true end
    end
    return false
end
function Games.purchase(state, bayId, fixtureId, requestId, players)
    if not Games.BAYS[bayId] or not Games.IDS[fixtureId] or not token(requestId)
        then return false, "Unknown break room purchase." end
    local current = state.breakroomGames or Games.defaultState()
    if not Games.validate(current) then return false, "Break room purchase records are invalid." end
    for _, receipt in ipairs(current.receipts) do
        if receipt.requestId == requestId then
            if receipt.bayId == bayId and receipt.fixtureId == fixtureId then
                return true, "Purchase already recorded.", "replayed"
            end
            return false, "This request ID belongs to another purchase."
        end
    end
    local bay = state.warehouse and state.warehouse.bays and state.warehouse.bays[bayId]
    if not bay or bay.status ~= "complete" or bay.optionId ~= "breakroom" then
        return false, "Complete this break room before buying games."
    end
    if current.bays[bayId][fixtureId] then return false, "This game is already owned in this room." end
    if footprintBlocked(state,bayId,fixtureId,players) then
        return false,"Move the person or equipment clear of this fixture's floor space."
    end
    local price = Games.CATALOG[fixtureId].price
    if type(state.money) ~= "number" or state.money < price then return false, "Not enough shop cash." end
    state.money = state.money - price
    current.bays[bayId][fixtureId] = true
    if fixtureId == "basketball" then
        current.bays[bayId].ball = { id=bayId.."-basketball", sceneId=bayId,
            x=240, y=315, lastX=240, lastY=315, lastSceneId=bayId, mode="placed" }
    end
    current.receipts[#current.receipts+1] = {
        requestId=requestId, bayId=bayId, fixtureId=fixtureId, pricePaid=price }
    state.breakroomGames = current
    return true, Games.CATALOG[fixtureId].name .. " installed in the break room.", "purchased"
end
return Games
