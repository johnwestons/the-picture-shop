local Config = require("src.config")
local PaperWork = require("src.paper_work")
local BusinessCalendar = require("src.business_calendar")
local MachineFleet = require("src.machine_fleet")

local Schema = { VERSION = 12, SLOT_COUNT = 3 }
local directions = {
    northwest = true, north = true, northeast = true, east = true,
    southeast = true, south = true, southwest = true, west = true,
}

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end

local function number(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function nonnegative(value) return number(value) and value >= 0 end
local function integer(value) return number(value) and value == math.floor(value) end
local function positiveInteger(value) return integer(value) and value >= 1 end
local function text(value) return type(value) == "string" and value ~= "" end
local function optionalNumber(value) return value == nil or number(value) end

local function validSlot(slot)
    return integer(slot) and slot >= 1 and slot <= Schema.SLOT_COUNT
end

local function array(value, validator)
    if type(value) ~= "table" then return false end
    local count, highest = 0, 0
    for key, item in pairs(value) do
        if not positiveInteger(key) then return false end
        count = count + 1
        highest = math.max(highest, key)
        if validator and not validator(item) then return false end
    end
    return count == highest
end

local function dimensions(value)
    return type(value) == "table"
        and number(value.width) and value.width > 0
        and number(value.height) and value.height > 0
end

local function worldPosition(value)
    if value == nil then return true end
    if type(value) ~= "table" or not number(value.x) or not number(value.y) then return false end
    if value.direction ~= nil and not directions[value.direction] then return false end
    if value.rotation ~= nil and (not integer(value.rotation) or value.rotation < 1 or value.rotation > 4) then return false end
    if not optionalNumber(value.fromX) or not optionalNumber(value.fromY) then return false end
    if value.spawnProgress ~= nil and (not nonnegative(value.spawnProgress) or value.spawnProgress > 1) then return false end
    return true
end

local function cut(value)
    return type(value) == "table"
        and positiveInteger(value.number)
        and text(value.edge)
        and nonnegative(value.margin)
        and nonnegative(value.gauge)
        and number(value.orientation)
end

local function historyEntry(value)
    return type(value) == "table"
        and positiveInteger(value.number)
        and text(value.edge)
        and nonnegative(value.margin)
        and nonnegative(value.gauge)
        and dimensions(value.resultingSize)
end

local function paper(value)
    if value == nil then return true end
    return type(value) == "table"
        and text(value.id)
        and text(value.jobId)
        and text(value.palletId)
        and text(value.artworkId)
        and (value.artworkKey == nil or text(value.artworkKey))
        and text(value.difficulty)
        and dimensions(value.sourceSize)
        and dimensions(value.finishedSize)
        and dimensions(value.currentSize)
        and type(value.margins) == "table"
        and nonnegative(value.margins.left)
        and nonnegative(value.margins.right)
        and nonnegative(value.margins.top)
        and nonnegative(value.margins.bottom)
        and number(value.orientation)
        and positiveInteger(value.activeCut)
        and array(value.cuts, cut)
        and text(value.status)
        and array(value.history, historyEntry)
end

local function quotePallet(value)
    return type(value) == "table"
        and positiveInteger(value.number)
        and positiveInteger(value.sheetCount)
        and positiveInteger(value.requiredLifts)
        and nonnegative(value.price)
end

local function quote(value)
    return type(value) == "table"
        and positiveInteger(value.palletCount)
        and positiveInteger(value.totalSheets)
        and positiveInteger(value.totalLifts)
        and nonnegative(value.totalPrice)
        and optionalNumber(value.recommendedPrice)
        and optionalNumber(value.playerPrice)
        and optionalNumber(value.standardPrice)
        and array(value.pallets, quotePallet)
        and #value.pallets == value.palletCount
end

local function deliveryService(value)
    return value == nil or (type(value) == "table"
        and text(value.id)
        and text(value.label)
        and text(value.description)
        and nonnegative(value.delayHours))
end

local function delivery(value)
    return value == nil or (type(value) == "table"
        and text(value.status)
        and optionalNumber(value.receivedAt)
        and optionalNumber(value.acceptedGameHours)
        and optionalNumber(value.readyAtHours)
        and optionalNumber(value.expectedAtHours)
        and optionalNumber(value.receivedAtHours)
        and deliveryService(value.service))
end

local function pickup(value)
    return value == nil or (type(value) == "table"
        and text(value.status)
        and optionalNumber(value.requestedAt)
        and optionalNumber(value.scheduledAt)
        and optionalNumber(value.arrivedAt)
        and optionalNumber(value.loadedAt)
        and optionalNumber(value.completedAt))
end

local function customerPallet(value)
    return type(value) == "table"
        and text(value.id)
        and positiveInteger(value.number)
        and positiveInteger(value.initialSheets)
        and nonnegative(value.remainingSheets)
        and nonnegative(value.finishedSheets)
        and nonnegative(value.damagedSheets)
        and positiveInteger(value.requiredLifts)
        and nonnegative(value.completedLifts)
        and (value.activeLift == nil or positiveInteger(value.activeLift))
        and (value.lastLiftSheets == nil or nonnegative(value.lastLiftSheets))
        and (value.programVerified == nil or type(value.programVerified) == "boolean")
        and (value.awaitingPalletReturn == nil or type(value.awaitingPalletReturn) == "boolean")
        and text(value.status)
        and text(value.location)
        and (value.packaging == "flat" or value.packaging == "boxed")
        and type(value.wrapped) == "boolean"
        and (value.packagedAs == nil or value.packagedAs == "flat" or value.packagedAs == "boxed")
        and optionalNumber(value.pickedUpAt)
        and worldPosition(value.world)
        and paper(value.paper)
end

local function job(value)
    return type(value) == "table"
        and text(value.id)
        and text(value.company)
        and dimensions(value.sourceSize)
        and dimensions(value.finishedSize)
        and (value.artworkKey == nil or text(value.artworkKey))
        and deliveryService(value.deliveryService)
        and (value.requestChannel == nil or value.requestChannel == "reception" or value.requestChannel == "email")
        and type(value.details) == "table"
        and text(value.difficulty)
        and (value.packaging == "flat" or value.packaging == "boxed")
        and text(value.status)
        and optionalNumber(value.createdAt)
        and optionalNumber(value.acceptedAt)
        and optionalNumber(value.declinedAt)
        and optionalNumber(value.completedAt)
        and optionalNumber(value.paidAt)
        and optionalNumber(value.paymentAmount)
        and optionalNumber(value.pickupRequestedAtHours)
        and optionalNumber(value.completedAtHours)
        and quote(value.quote)
        and array(value.pallets, customerPallet)
        and delivery(value.delivery)
        and pickup(value.pickup)
end

local function clientEmails(value)
    if type(value) ~= "table" or not positiveInteger(value.nextEmailId)
        or not positiveInteger(value.nextPromotionId)
        or type(value.pending) ~= "table" or type(value.inbox) ~= "table" or type(value.archive) ~= "table"
        or type(value.sentPromotions) ~= "table"
    then return false end
    local function email(item, received)
        return type(item) == "table" and text(item.id) and text(item.sender)
            and text(item.subject) and text(item.body) and text(item.sourceJobId)
            and nonnegative(item.readyAtHours) and (not received or nonnegative(item.receivedAtHours))
            and job(item.job)
    end
    if not array(value.pending, function(item) return email(item, false) end)
        or not array(value.inbox, function(item) return email(item, true) end)
    then return false end
    return array(value.archive, function(item)
        return type(item) == "table" and text(item.id) and text(item.sender)
            and text(item.subject) and text(item.jobId)
            and (item.response == "accepted" or item.response == "declined"
                or item.response == "quote_accepted" or item.response == "quote_rejected")
            and optionalNumber(item.quotedPrice) and optionalNumber(item.acceptanceChance)
            and optionalNumber(item.respondedAtHours)
    end) and array(value.sentPromotions, function(item)
        return type(item) == "table" and text(item.id) and text(item.recipient)
            and item.discountPercent == 10 and type(item.customMessage) == "string"
            and nonnegative(item.sentAtHours)
    end)
end

local function vendorPallet(value)
    return type(value) == "table"
        and text(value.id)
        and positiveInteger(value.number)
        and value.kind == "vendor_product"
        and text(value.category)
        and text(value.categoryName)
        and positiveInteger(value.assetRow)
        and text(value.productId)
        and text(value.productName)
        and nonnegative(value.quantity)
        and text(value.unit)
        and text(value.location)
        and text(value.status)
        and worldPosition(value.world)
end

local function purchaseOrder(value)
    return type(value) == "table"
        and text(value.id)
        and text(value.vendor)
        and text(value.company)
        and text(value.category)
        and text(value.item)
        and text(value.productName)
        and nonnegative(value.price)
        and text(value.status)
        and optionalNumber(value.orderedAt)
        and delivery(value.delivery)
        and array(value.pallets, vendorPallet)
end

local function stock(value)
    if type(value) ~= "table" then return false end
    for key, quantity in pairs(value) do
        if not text(key) or not nonnegative(quantity) then return false end
    end
    return true
end

local function cutterMemory(value)
    if type(value) ~= "table" then return false end
    for key, measurements in pairs(value) do
        local cutNumber = tonumber(key)
        if not integer(cutNumber) or cutNumber < 1 or cutNumber > 4
            or not array(measurements, function(measurement)
                return nonnegative(measurement) and measurement <= 25
            end)
            or #measurements > 3
        then
            return false
        end
    end
    return true
end

local function inventory(value)
    return type(value) == "table"
        and nonnegative(value.paper)
        and nonnegative(value.prints)
        and nonnegative(value.rawPallets)
        and nonnegative(value.inProcessPallets)
        and nonnegative(value.finishedPallets)
        and nonnegative(value.plasticWrapRolls)
        and integer(value.plasticWrapRolls)
        and nonnegative(value.plasticWrapUses)
        and integer(value.plasticWrapUses)
        and value.plasticWrapUses <= 11
        and stock(value.stock)
end

local function placement(value)
    return type(value) == "table"
        and number(value.x) and number(value.y)
        and directions[value.direction] == true
        and type(value.moving) == "boolean"
        and type(value.inMotion) == "boolean"
end

local function palletJack(value)
    return placement(value)
        and type(value.operating) == "boolean"
        and optionalNumber(value.animationClock)
        and (value.carriedPalletId == nil or text(value.carriedPalletId))
end

local function persistentState(value)
    return type(value) == "table"
        and nonnegative(value.money)
        and inventory(value.inventory)
        and type(value.shopProgress) == "table"
        and nonnegative(value.shopProgress.completedCuts)
        and type(value.jobs) == "table"
        and array(value.jobs.active, job)
        and array(value.jobs.completed, job)
        and array(value.jobs.declined, job)
        and positiveInteger(value.nextJobId)
        and nonnegative(value.accountsReceivable)
        and cutterMemory(value.cutterMemory)
        and type(value.procurement) == "table"
        and positiveInteger(value.procurement.nextOrderId)
        and array(value.procurement.orders, purchaseOrder)
        and positiveInteger(value.vendorCategory)
        and BusinessCalendar.valid(value.calendar, value.bills)
        and clientEmails(value.clientEmails)
        and MachineFleet.validState(value.machines)
        and placement(value.cutter)
        and palletJack(value.palletJack)
        and placement(value.wrapper)
        and placement(value.windmill)
end

local function defaultPlacement(config)
    return {
        x = config.spawnX,
        y = config.spawnY,
        direction = config.defaultDirection or "northwest",
        moving = false,
        inMotion = false,
    }
end

function Schema.defaultState()
    local jack = defaultPlacement(Config.palletJack)
    jack.operating = false
    jack.animationClock = 0
    return {
        money = 180,
        inventory = {
            paper = 40,
            prints = 0,
            rawPallets = 0,
            inProcessPallets = 0,
            finishedPallets = 0,
            plasticWrapRolls = 1,
            plasticWrapUses = 11,
            stock = { shipping_cartons = 20 },
        },
        shopProgress = { completedCuts = 0 },
        jobs = { active = {}, completed = {}, declined = {} },
        nextJobId = 1,
        accountsReceivable = 0,
        cutterMemory = {},
        procurement = { orders = {}, nextOrderId = 1, shipments = {}, nextShipmentId = 1 },
        vendorCategory = 1,
        calendar = BusinessCalendar.defaultCalendar(),
        bills = BusinessCalendar.defaultBills(),
        clientEmails = { nextEmailId = 1, nextPromotionId = 1,
            pending = {}, inbox = {}, archive = {}, sentPromotions = {} },
        machines = MachineFleet.defaultState(),
        cutter = defaultPlacement(Config.cutterPlacement),
        palletJack = jack,
        wrapper = defaultPlacement(Config.wrapperPlacement),
        windmill = defaultPlacement(Config.windmillPlacement),
    }
end

local function mergePlacement(fallback, source)
    local result = copy(fallback)
    if type(source) ~= "table" then return result end
    if number(source.x) then result.x = source.x end
    if number(source.y) then result.y = source.y end
    if directions[source.direction] then result.direction = source.direction end
    result.moving = source.moving == true
    result.inMotion = source.inMotion == true
    return result
end

local function normalizeJobs(jobs)
    for _, collectionName in ipairs({ "active", "completed", "declined" }) do
        local collection = type(jobs[collectionName]) == "table" and jobs[collectionName] or {}
        jobs[collectionName] = collection
        for _, savedJob in ipairs(collection) do
            if type(savedJob) == "table" then
                if savedJob.details == nil then savedJob.details = {} end
                if savedJob.difficulty == nil then savedJob.difficulty = "easy" end
                if savedJob.packaging == nil then savedJob.packaging = "flat" end
                if type(savedJob.pallets) == "table" then
                    for index, pallet in ipairs(savedJob.pallets) do
                        if type(pallet) == "table" then
                            if pallet.packaging == nil then pallet.packaging = savedJob.packaging end
                            if pallet.wrapped == nil then pallet.wrapped = pallet.status == "wrapped" end
                            if pallet.remainingSheets == nil then pallet.remainingSheets = pallet.initialSheets end
                            if pallet.finishedSheets == nil then pallet.finishedSheets = 0 end
                            if pallet.damagedSheets == nil then pallet.damagedSheets = 0 end
                            if pallet.completedLifts == nil then pallet.completedLifts = 0 end
                            if pallet.activeLift == nil then
                                pallet.activeLift = math.min(pallet.requiredLifts or 1,
                                    (pallet.completedLifts or 0) + 1)
                            end
                            if pallet.lastLiftSheets == nil then pallet.lastLiftSheets = 0 end
                            if pallet.programVerified == nil then
                                pallet.programVerified = (pallet.completedLifts or 0) > 0
                                    or (pallet.paper and pallet.paper.status == "complete")
                            end
                            if pallet.paper == nil and text(pallet.id)
                                and dimensions(savedJob.sourceSize) and dimensions(savedJob.finishedSize)
                            then
                                pallet.paper = PaperWork.create(savedJob, pallet, savedJob.difficulty, index)
                            end
                        end
                    end
                end
            end
        end
    end
end

local function normalizeState(source)
    source = type(source) == "table" and source or {}
    local result = Schema.defaultState()
    if nonnegative(source.money) then result.money = source.money end

    if type(source.inventory) == "table" then
        result.inventory = copy(source.inventory)
        local defaults = Schema.defaultState().inventory
        for key, value in pairs(defaults) do
            if result.inventory[key] == nil then result.inventory[key] = copy(value) end
        end
    end
    result.shopProgress = type(source.shopProgress) == "table"
        and copy(source.shopProgress) or result.shopProgress
    result.jobs = type(source.jobs) == "table" and copy(source.jobs) or result.jobs
    result.jobs.active = type(result.jobs.active) == "table" and result.jobs.active or {}
    result.jobs.completed = type(result.jobs.completed) == "table" and result.jobs.completed or {}
    result.jobs.declined = type(result.jobs.declined) == "table" and result.jobs.declined or {}
    normalizeJobs(result.jobs)
    result.nextJobId = source.nextJobId ~= nil and source.nextJobId or result.nextJobId
    result.accountsReceivable = source.accountsReceivable ~= nil
        and source.accountsReceivable or result.accountsReceivable
    result.cutterMemory = type(source.cutterMemory) == "table"
        and copy(source.cutterMemory) or result.cutterMemory
    result.procurement = type(source.procurement) == "table"
        and copy(source.procurement) or result.procurement
    result.procurement.orders = type(result.procurement.orders) == "table" and result.procurement.orders or {}
    result.procurement.nextOrderId = result.procurement.nextOrderId or 1
    result.procurement.shipments = type(result.procurement.shipments) == "table" and result.procurement.shipments or {}
    result.procurement.nextShipmentId = result.procurement.nextShipmentId or 1
    result.vendorCategory = source.vendorCategory ~= nil and source.vendorCategory or result.vendorCategory
    result.calendar = type(source.calendar) == "table" and copy(source.calendar) or result.calendar
    result.bills = type(source.bills) == "table" and copy(source.bills) or result.bills
    result.clientEmails = type(source.clientEmails) == "table"
        and copy(source.clientEmails) or result.clientEmails
    result.clientEmails.nextEmailId = math.max(1, math.floor(tonumber(result.clientEmails.nextEmailId) or 1))
    result.clientEmails.nextPromotionId = math.max(1, math.floor(tonumber(result.clientEmails.nextPromotionId) or 1))
    result.clientEmails.pending = type(result.clientEmails.pending) == "table" and result.clientEmails.pending or {}
    result.clientEmails.inbox = type(result.clientEmails.inbox) == "table" and result.clientEmails.inbox or {}
    result.clientEmails.archive = type(result.clientEmails.archive) == "table" and result.clientEmails.archive or {}
    result.clientEmails.sentPromotions = type(result.clientEmails.sentPromotions) == "table"
        and result.clientEmails.sentPromotions or {}
    result.machines = type(source.machines) == "table"
        and copy(source.machines) or result.machines
    MachineFleet.ensure(result)
    BusinessCalendar.ensure(result)
    result.cutter = mergePlacement(result.cutter, source.cutter)
    result.wrapper = mergePlacement(result.wrapper, source.wrapper)
    result.windmill = mergePlacement(result.windmill, source.windmill)
    if type(source.windmill) == "table" and type(source.windmill.process) == "table" then
        result.windmill.process = copy(source.windmill.process)
    end
    result.technicianVisit = type(source.technicianVisit) == "table"
        and copy(source.technicianVisit) or nil
    result.palletJack = mergePlacement(result.palletJack, source.palletJack)
    if type(source.palletJack) == "table" then
        result.palletJack.operating = source.palletJack.operating == true
        result.palletJack.animationClock = source.palletJack.animationClock or 0
        result.palletJack.carriedPalletId = source.palletJack.carriedPalletId
    end
    return result
end

function Schema.reconcile(state)
    if type(state) ~= "table" then return false end
    state.inventory = type(state.inventory) == "table" and state.inventory or {}
    local raw, inProcess, finished = 0, 0, 0
    local active = state.jobs and type(state.jobs.active) == "table" and state.jobs.active or {}
    for _, savedJob in ipairs(active) do
        local pallets = type(savedJob) == "table" and type(savedJob.pallets) == "table"
            and savedJob.pallets or {}
        for _, pallet in ipairs(pallets) do
            if pallet.activeLift == nil then
                pallet.activeLift = math.min(pallet.requiredLifts or 1, (pallet.completedLifts or 0) + 1)
            end
            if pallet.lastLiftSheets == nil then pallet.lastLiftSheets = 0 end
            if pallet.programVerified == nil then
                pallet.programVerified = (pallet.completedLifts or 0) > 0
                    or (pallet.paper and pallet.paper.status == "complete")
            end
            if pallet.location == "at_cutter"
                and pallet.paper and pallet.paper.status == "complete"
                and (pallet.completedLifts or 0) == 0 and (pallet.remainingSheets or 0) > 0
            then
                local migratedSheets = math.min(500, pallet.remainingSheets)
                pallet.completedLifts = 1
                pallet.lastLiftSheets = migratedSheets
                pallet.remainingSheets = pallet.remainingSheets - migratedSheets
                pallet.finishedSheets = (pallet.finishedSheets or 0) + migratedSheets
                pallet.activeLift = math.min(pallet.requiredLifts or 1, pallet.completedLifts + 1)
                pallet.programVerified = true
            end
            if pallet.location == "warehouse" or pallet.location == "cutter_output"
                or pallet.location == "on_pallet_jack" or pallet.location == "at_cutter"
            then
                if pallet.status == "cut" or pallet.status == "finished" or pallet.status == "wrapped"
                    or (pallet.paper and pallet.paper.status == "complete"
                        and (pallet.remainingSheets or 0) == 0)
                then
                    finished = finished + 1
                elseif pallet.status == "in_process" or pallet.location == "at_cutter" then
                    inProcess = inProcess + 1
                else
                    raw = raw + 1
                end
            end
        end
    end
    state.inventory.rawPallets = raw
    state.inventory.inProcessPallets = inProcess
    state.inventory.finishedPallets = finished
    state.inventory.stock = type(state.inventory.stock) == "table" and state.inventory.stock or {}
    state.cutterMemory = type(state.cutterMemory) == "table" and state.cutterMemory or {}
    MachineFleet.ensure(state)
    BusinessCalendar.ensure(state)
    return true
end

function Schema.snapshot(state)
    local result = normalizeState(state)
    result.cutter.moving, result.cutter.inMotion = false, false
    result.wrapper.moving, result.wrapper.inMotion = false, false
    result.palletJack.operating = false
    result.palletJack.moving, result.palletJack.inMotion = false, false
    Schema.reconcile(result)
    return result
end

function Schema.newPayload(slot, timestamp)
    assert(validSlot(slot), "save slot must be 1, 2, or 3")
    local now = timestamp or os.time()
    return {
        version = Schema.VERSION,
        slot = slot,
        createdAt = now,
        updatedAt = now,
        state = Schema.defaultState(),
        player = { x = Config.player.spawnX, y = Config.player.spawnY },
    }
end

function Schema.validPayload(payload)
    return type(payload) == "table"
        and payload.version == Schema.VERSION
        and validSlot(payload.slot)
        and number(payload.createdAt)
        and number(payload.updatedAt)
        and persistentState(payload.state)
        and type(payload.player) == "table"
        and number(payload.player.x)
        and number(payload.player.y)
end

local function legacyCore(payload)
    return type(payload) == "table"
        and validSlot(payload.slot)
        and type(payload.state) == "table"
        and nonnegative(payload.state.money)
        and type(payload.state.inventory) == "table"
        and type(payload.player) == "table"
        and number(payload.player.x)
        and number(payload.player.y)
end

local function validV2Core(payload)
    local state = payload and payload.state
    return legacyCore(payload)
        and type(state.jobs) == "table"
        and type(state.jobs.active) == "table"
        and type(state.jobs.completed) == "table"
        and type(state.jobs.declined) == "table"
        and positiveInteger(state.nextJobId)
        and nonnegative(state.accountsReceivable)
end

function Schema.migrate(payload)
    if type(payload) ~= "table" then return nil end
    if payload.version == Schema.VERSION then
        local current = copy(payload)
        return Schema.validPayload(current) and current or nil
    end
    if payload.version == 1 then
        if not legacyCore(payload) then return nil end
    elseif payload.version == 2 or payload.version == 3 or payload.version == 4
        or payload.version == 5 or payload.version == 6 or payload.version == 7
        or payload.version == 8 or payload.version == 9 or payload.version == 10
        or payload.version == 11
    then
        if not validV2Core(payload) then return nil end
    else
        return nil
    end

    local createdAt = number(payload.createdAt) and payload.createdAt or os.time()
    local migrated = {
        version = Schema.VERSION,
        slot = payload.slot,
        createdAt = createdAt,
        updatedAt = number(payload.updatedAt) and payload.updatedAt or createdAt,
        state = normalizeState(payload.state),
        player = { x = payload.player.x, y = payload.player.y },
    }
    Schema.reconcile(migrated.state)
    return Schema.validPayload(migrated) and migrated or nil
end

Schema.copy = copy
Schema.validSlot = validSlot
return Schema
