local Config = require("src.config")
local PaperWork = require("src.paper_work")
local BusinessCalendar = require("src.business_calendar")
local MachineFleet = require("src.machine_fleet")
local Reputation = require("src.reputation")
local PalletState = require("src.pallet_state")
local WarehouseUpgrades = require("src.warehouse_upgrades")
local PalletStorage = require("src.pallet_storage")
local Forklift = require("src.forklift")
local WarehouseConstruction = require("src.warehouse_construction")

local Schema = { VERSION = 15, SLOT_COUNT = 3 }
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
local function nonnegativeInteger(value) return integer(value) and value >= 0 end
local function positiveInteger(value) return integer(value) and value >= 1 end
local function text(value) return type(value) == "string" and value ~= "" end
local function optionalNumber(value) return value == nil or number(value) end
local function optionalText(value) return value == nil or text(value) end
local function optionalNonnegative(value) return value == nil or nonnegative(value) end
local function optionalNonnegativeInteger(value) return value == nil or nonnegativeInteger(value) end
local function optionalPositiveInteger(value) return value == nil or positiveInteger(value) end
local function optionalBoolean(value) return value == nil or type(value) == "boolean" end

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

-- Raw local loads and legacy normalization can precede the full schema check.
-- Reject malformed physical containers before traversing them, and reject a
-- shared vehicle operator before snapshot normalization removes active flags.
function Schema.validPhysicalSource(value)
    if type(value) ~= "table" then return false end
    for _, field in ipairs({"jobs", "procurement", "palletJack", "forklift", "constructionWorker"}) do
        if value[field] ~= nil and type(value[field]) ~= "table" then return false end
    end
    local function group(record)
        return type(record) == "table" and (record.pallets == nil
            or array(record.pallets, function(pallet) return type(pallet) == "table" end))
    end
    for _, field in ipairs({"active", "completed", "declined"}) do
        local collection = value.jobs and value.jobs[field]
        if collection ~= nil and not array(collection, group) then return false end
    end
    if value.procurement and value.procurement.orders ~= nil
        and not array(value.procurement.orders, group) then return false end
    local jack, lift = value.palletJack, value.forklift
    if jack and lift and jack.operating == true and lift.operating == true
        and jack.operatorPlayerId ~= nil and jack.operatorPlayerId == lift.operatorPlayerId then return false end
    return true
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

local function storedPlacement(value)
    local _, reason = PalletStorage.normalizePlacement(value)
    return reason == nil
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

local function artwork(value)
    return value == nil or (type(value) == "table"
        and text(value.key)
        and text(value.displayName)
        and text(value.fileName)
        and value.suppliedBy == "client"
        and (value.orientation == "portrait" or value.orientation == "landscape"))
end

local function stockSpec(value)
    return value == nil or (type(value) == "table"
        and value.suppliedBy == "client"
        and text(value.grade)
        and nonnegative(value.weight)
        and text(value.finish)
        and text(value.color)
        and text(value.grain)
        and text(value.description))
end

local function passHistoryEntry(value)
    if type(value) ~= "table" then return false end
    if not optionalPositiveInteger(value.colorIndex)
        or not optionalPositiveInteger(value.passNumber)
        or not optionalText(value.inkColor)
        or not optionalText(value.plateId)
        or not optionalText(value.status)
        or not optionalNonnegativeInteger(value.requiredGoodSheets)
        or not optionalNonnegativeInteger(value.availableSheets)
        or not optionalNonnegativeInteger(value.impressions)
        or not optionalNonnegativeInteger(value.goodSheets)
        or not optionalNonnegativeInteger(value.spoilage)
        or not optionalNonnegativeInteger(value.targetSheets)
        or not optionalNonnegativeInteger(value.feedSheets)
        or not optionalNonnegativeInteger(value.remainingSheets)
        or not optionalNumber(value.startedAtHours)
        or not optionalNumber(value.completedAtHours)
        or not optionalNonnegative(value.pressHours)
        or not optionalBoolean(value.artworkVerified)
    then
        return false
    end
    if value.proofQuality ~= nil
        and (not number(value.proofQuality) or value.proofQuality < 0 or value.proofQuality > 1)
    then
        return false
    end
    return value.quality == nil or (number(value.quality) and value.quality >= 0 and value.quality <= 1)
end

local function palletPress(value)
    return value == nil or (type(value) == "table"
        and text(value.status)
        and positiveInteger(value.requiredGoodSheets)
        and nonnegativeInteger(value.availableSheets)
        and nonnegativeInteger(value.completedColors)
        and nonnegativeInteger(value.goodSheets)
        and nonnegativeInteger(value.spoilage)
        and optionalNumber(value.dryUntilHours)
        and array(value.passHistory, passHistoryEntry))
end

local function pressPlate(value)
    if type(value) ~= "table"
        or not text(value.id)
        or not text(value.jobId)
        or not positiveInteger(value.colorIndex)
        or not text(value.inkColor)
        or not text(value.artworkKey)
        or not dimensions(value.artworkSize)
        or not text(value.status)
        or not optionalText(value.source)
        or not number(value.quality) or value.quality < 0 or value.quality > 1
        or not number(value.life) or value.life < 0 or value.life > 1
        or not positiveInteger(value.processStep)
        or type(value.processScores) ~= "table"
        or type(value.mounted) ~= "boolean"
        or not optionalNumber(value.orderedAtHours)
        or not optionalNumber(value.readyAtHours)
        or not optionalNonnegative(value.actualCost)
    then
        return false
    end
    return array(value.processScores, function(score)
        return number(score) and score >= 0 and score <= 1
    end)
end

local function pressActual(value)
    if type(value) ~= "table" then return false end
    for _, field in ipairs({
        "plateCost", "inHousePlates", "inkUnits", "tympanSheets", "washUnits",
        "proofs", "impressions", "spoilage", "pressHours", "supplyCost",
    }) do
        if not nonnegative(value[field]) then return false end
    end
    return true
end

local function jobPress(value)
    return value == nil or (type(value) == "table"
        and positiveInteger(value.colors) and value.colors <= 4
        and number(value.coverage) and value.coverage >= 0 and value.coverage <= 1
        and dimensions(value.artworkSize)
        and array(value.colorSequence, text)
        and #value.colorSequence == value.colors
        and array(value.requestedCopies, positiveInteger)
        and #value.requestedCopies >= 1
        and positiveInteger(value.orderedQuantity)
        and positiveInteger(value.suppliedSheets)
        and nonnegativeInteger(value.spoilageAllowance)
        and array(value.plates, pressPlate)
        and #value.plates == value.colors
        and pressActual(value.actual))
end

local function quotePallet(value)
    return type(value) == "table"
        and positiveInteger(value.number)
        and positiveInteger(value.sheetCount)
        and positiveInteger(value.requiredLifts)
        and nonnegative(value.price)
        and optionalPositiveInteger(value.requestedCopies)
        and optionalNonnegativeInteger(value.spoilageAllowance)
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
        and optionalPositiveInteger(value.orderedCopies)
        and optionalPositiveInteger(value.suppliedSheets)
        and optionalNonnegativeInteger(value.spoilageAllowance)
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
        and (value.kind == nil or value.kind == "replacement")
        and (value.palletIds == nil or array(value.palletIds, text))
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
        and optionalText(value.replacementFor)
        and (value.replacementSequence == nil or positiveInteger(value.replacementSequence))
        and optionalBoolean(value.discardAfterSpoil)
        and optionalPositiveInteger(value.requestedCopies)
        and optionalNonnegativeInteger(value.spoilageAllowance)
        and text(value.status)
        and text(value.location)
        and (value.packaging == "flat" or value.packaging == "boxed")
        and type(value.wrapped) == "boolean"
        and (value.packagedAs == nil or value.packagedAs == "flat" or value.packagedAs == "boxed")
        and optionalNumber(value.pickedUpAt)
        and worldPosition(value.world)
        and storedPlacement(value)
        and paper(value.paper)
        and palletPress(value.press)
end

local function printQuantities(value)
    if value.press == nil then return artwork(value.artwork) and stockSpec(value.stockSpec) end
    if not artwork(value.artwork) or value.artwork == nil
        or not stockSpec(value.stockSpec) or value.stockSpec == nil
        or not jobPress(value.press)
        or #value.press.requestedCopies ~= #value.quote.pallets
    then
        return false
    end
    local originals, replacements = {}, {}
    for _, pallet in ipairs(value.pallets) do
        if pallet.replacementFor then
            replacements[pallet.replacementFor] = replacements[pallet.replacementFor] or {}
            replacements[pallet.replacementFor][#replacements[pallet.replacementFor] + 1] = pallet
        else
            if originals[pallet.number] then return false end
            originals[pallet.number] = pallet
        end
    end
    local ordered, supplied, allowance = 0, 0, 0
    for index = 1, #value.quote.pallets do
        local pallet = originals[index]
        local requested = value.press.requestedCopies[index]
        local quoted = value.quote.pallets[index]
        if not pallet or not quoted
            or quoted.sheetCount ~= pallet.initialSheets
            or quoted.requestedCopies ~= requested
        then
            return false
        end
        local groupRequested, groupSupplied, groupAllowance = 0, 0, 0
        local group = { pallet }
        for _, replacement in ipairs(replacements[pallet.id] or {}) do
            group[#group + 1] = replacement
        end
        replacements[pallet.id] = nil
        for _, member in ipairs(group) do
            local effectiveSheets = math.max(0,
                member.initialSheets - (member.damagedSheets or 0))
            local memberRequested = math.max(0, member.requestedCopies or 0)
            if member.spoilageAllowance == nil
                or member.spoilageAllowance ~= effectiveSheets - memberRequested
                or memberRequested > effectiveSheets
            then
                return false
            end
            if member.status == "spoiled_discarded" then
                if memberRequested ~= 0 or member.press ~= nil then return false end
            elseif type(member.press) ~= "table"
                or memberRequested <= 0
                or member.press.requiredGoodSheets ~= memberRequested
                or member.press.availableSheets > effectiveSheets
                or member.press.completedColors > value.press.colors
            then
                return false
            end
            groupRequested = groupRequested + memberRequested
            groupSupplied = groupSupplied + effectiveSheets
            groupAllowance = groupAllowance + member.spoilageAllowance
        end
        if groupRequested ~= requested or groupSupplied ~= quoted.sheetCount
            or groupAllowance ~= quoted.spoilageAllowance
        then
            return false
        end
        ordered = ordered + groupRequested
        supplied = supplied + groupSupplied
        allowance = allowance + groupAllowance
    end
    if next(replacements) ~= nil then return false end
    for colorIndex, plate in ipairs(value.press.plates) do
        local artworkSize = plate.artworkSize
        if plate.jobId ~= value.id
            or plate.colorIndex ~= colorIndex
            or plate.inkColor ~= value.press.colorSequence[colorIndex]
            or plate.artworkKey ~= value.artwork.key
            or artworkSize.width ~= value.press.artworkSize.width
            or artworkSize.height ~= value.press.artworkSize.height
        then
            return false
        end
    end
    return value.press.orderedQuantity == ordered
        and value.press.suppliedSheets == supplied
        and value.press.spoilageAllowance == allowance
        and value.quote.totalSheets == supplied
        and value.quote.orderedCopies == ordered
        and value.quote.suppliedSheets == supplied
        and value.quote.spoilageAllowance == allowance
end

local function job(value)
    return type(value) == "table"
        and text(value.id)
        and text(value.company)
        and dimensions(value.sourceSize)
        and dimensions(value.finishedSize)
        and (value.artworkKey == nil or text(value.artworkKey))
        and artwork(value.artwork)
        and (value.artwork == nil or value.artworkKey == value.artwork.key)
        and stockSpec(value.stockSpec)
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
        and optionalBoolean(value.promotionSent)
        and optionalNumber(value.pickupRequestedAtHours)
        and optionalNumber(value.completedAtHours)
        and optionalNonnegativeInteger(value.replacementSkids)
        and optionalNonnegativeInteger(value.replacementSheets)
        and quote(value.quote)
        and array(value.pallets, customerPallet)
        and delivery(value.delivery)
        and pickup(value.pickup)
        and printQuantities(value)
end

local function clientEmails(value)
    if type(value) ~= "table" or not positiveInteger(value.nextEmailId)
        or not positiveInteger(value.nextPromotionId)
        or type(value.pending) ~= "table" or type(value.inbox) ~= "table" or type(value.archive) ~= "table"
        or type(value.sentPromotions) ~= "table"
    then return false end
    local function email(item, received)
        if type(item) ~= "table" or not text(item.id) or not text(item.sender)
            or not text(item.subject) or not text(item.body)
            or not nonnegative(item.readyAtHours)
            or (received and not nonnegative(item.receivedAtHours))
        then return false end
        if item.job ~= nil then
            return text(item.sourceJobId) and job(item.job)
                and optionalNonnegative(item.standardPrice)
                and optionalNonnegative(item.discountAmount)
                and optionalNonnegative(item.discountedTotal)
        end
        return text(item.noticeKind)
            and optionalText(item.sourceJobId)
            and optionalText(item.orderId)
            and optionalNonnegative(item.total)
    end
    if not array(value.pending, function(item) return email(item, false) end)
        or not array(value.inbox, function(item) return email(item, true) end)
    then return false end
    return array(value.archive, function(item)
        if type(item) ~= "table" or not text(item.id) or not text(item.sender)
            or not text(item.subject) or not optionalNumber(item.respondedAtHours)
        then return false end
        if item.response == "archived" then
            return text(item.noticeKind) and optionalText(item.orderId) and optionalNonnegative(item.total)
        end
        return text(item.jobId)
            and (item.response == "accepted" or item.response == "declined"
                or item.response == "quote_accepted" or item.response == "quote_rejected"
                or item.response == "estimate_sent")
            and optionalNumber(item.quotedPrice) and optionalNumber(item.acceptanceChance)
    end) and array(value.sentPromotions, function(item)
        return type(item) == "table" and text(item.id) and text(item.recipient)
            and item.discountPercent == 10 and type(item.customMessage) == "string"
            and nonnegative(item.sentAtHours)
            and optionalText(item.sourceJobId)
            and (item.responseOutcome == nil or item.responseOutcome == "new_job"
                or item.responseOutcome == "thank_you" or item.responseOutcome == "no_response")
    end)
end

local WORK_PHONE_KINDS = {
    customer_order = true,
    customer_status = true,
    supplier_status = true,
    service_order = true,
    construction_notice = true,
}

local function phoneCall(value)
    return type(value) == "table"
        and text(value.id)
        and WORK_PHONE_KINDS[value.kind] == true
        and text(value.caller)
        and text(value.role)
        and text(value.subject)
        and text(value.message)
        and nonnegative(value.receivedAtHours)
        and type(value.answered) == "boolean"
        and optionalText(value.jobId)
        and optionalText(value.orderId)
        and optionalText(value.projectId)
        and optionalText(value.bayId)
        and optionalText(value.optionId)
        and (value.kind ~= "construction_notice" or (text(value.projectId)
            and value.projectId:match("^WUP%-%d+$") ~= nil and #value.projectId <= 64
            and (value.bayId == "front_left" or value.bayId == "front_right")
            and (value.optionId == "floor" or value.optionId == "storage" or value.optionId == "breakroom")))
        and optionalPositiveInteger(value.categoryIndex)
        and optionalPositiveInteger(value.itemIndex)
        and optionalText(value.outcome)
        and optionalText(value.response)
        and optionalNonnegative(value.endedAtHours)
end

local function workPhone(value)
    return type(value) == "table"
        and positiveInteger(value.nextCallId)
        and nonnegative(value.nextCallAtHours)
        and (value.incoming == nil or phoneCall(value.incoming))
        and array(value.history, phoneCall)
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
        and storedPlacement(value)
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

local function setupScores(value)
    if type(value) ~= "table" then return false end
    for key, score in pairs(value) do
        if not text(key) or not number(score) or score < 0 or score > 1 then return false end
    end
    return true
end

local function copyQuantity(value)
    if value == nil then return true end
    if nonnegativeInteger(value) then return true end
    return array(value, positiveInteger)
end

local function proofRecord(value)
    return value == nil or (type(value) == "table"
        and (value.quality == nil or (number(value.quality) and value.quality >= 0 and value.quality <= 1))
        and optionalBoolean(value.approved)
        and optionalNonnegativeInteger(value.sheets)
        and optionalNonnegativeInteger(value.spoilage)
        and optionalNumber(value.createdAtHours))
end

local function windmillProcess(value)
    if value == nil then return true end
    if type(value) ~= "table"
        or not text(value.status)
        or not number(value.speed) or value.speed <= 0
        or type(value.motor) ~= "boolean"
        or type(value.feeder) ~= "boolean"
        or type(value.impression) ~= "boolean"
        or type(value.emergency) ~= "boolean"
        or not setupScores(value.setup)
        or not nonnegative(value.counter)
        or not nonnegative(value.goodSheets)
        or not nonnegative(value.spoilage)
        or not nonnegative(value.sheetAccumulator)
        or not nonnegative(value.animationClock)
        or not optionalText(value.jobId)
        or not optionalText(value.palletId)
        or not optionalPositiveInteger(value.colorIndex)
        or not optionalBoolean(value.proofApproved)
        or not optionalBoolean(value.artworkVerified)
        or not optionalText(value.warning)
        or not proofRecord(value.proof)
        or not copyQuantity(value.requestedCopies)
    then
        return false
    end
    if value.proofQuality ~= nil
        and (not number(value.proofQuality) or value.proofQuality < 0 or value.proofQuality > 1)
    then
        return false
    end
    for _, field in ipairs({
        "orderedQuantity", "suppliedSheets", "spoilageAllowance", "requiredGoodSheets",
        "availableSheets", "targetGoodSheets", "targetSheets", "remainingSheets", "proofSheets",
        "feedStart", "feedRemaining",
    }) do
        if not optionalNonnegativeInteger(value[field]) then return false end
    end
    return value.passHistory == nil or array(value.passHistory, passHistoryEntry)
end

local function physicalOwnership(value)
    local valid = PalletState.validate(value)
    if not valid then return false end
    local process = value.windmill and value.windmill.process
    local atPress, matchedJob, matchedPallet = 0, nil, nil
    for _, savedJob in ipairs(value.jobs and value.jobs.active or {}) do
        for _, pallet in ipairs(savedJob.pallets or {}) do
            if pallet.location == "at_press" then atPress = atPress + 1 end
            if process and pallet.id == process.palletId then
                matchedJob, matchedPallet = savedJob, pallet
            end
        end
    end
    if not process or process.palletId == nil then
        return atPress == 0 and (not process or process.jobId == nil)
    end
    return atPress == 1
        and matchedJob ~= nil and matchedPallet ~= nil
        and process.jobId == matchedJob.id
        and matchedPallet.location == "at_press"
        and type(matchedJob.press) == "table"
        and type(matchedPallet.press) == "table"
        and positiveInteger(process.colorIndex)
        and process.colorIndex <= matchedJob.press.colors
end

local function palletJack(value)
    return placement(value)
        and type(value.operating) == "boolean"
        and optionalNumber(value.animationClock)
        and (value.carriedPalletId == nil or text(value.carriedPalletId))
end

local function persistentState(value)
    return type(value) == "table"
        and Schema.validPhysicalSource(value)
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
        and Reputation.valid(value.reputation)
        and cutterMemory(value.cutterMemory)
        and type(value.procurement) == "table"
        and positiveInteger(value.procurement.nextOrderId)
        and array(value.procurement.orders, purchaseOrder)
        and positiveInteger(value.vendorCategory)
        and BusinessCalendar.valid(value.calendar, value.bills)
        and clientEmails(value.clientEmails)
        and workPhone(value.workPhone)
        and MachineFleet.validState(value.machines)
        and WarehouseUpgrades.validate(value.warehouse)
        and WarehouseConstruction.valid(value.constructionWorker, value.warehouse)
        and type(value.storage) == "table" and PalletStorage.normalize(value.storage) ~= nil
        and Forklift.validState(value.forklift, Config.forklift)
        and (not value.forklift.owned or value.warehouse.forkliftOwned)
        and placement(value.cutter)
        and palletJack(value.palletJack)
        and placement(value.wrapper)
        and placement(value.windmill)
        and optionalBoolean(value.windmill.tutorialComplete)
        and windmillProcess(value.windmill.process)
        and physicalOwnership(value)
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
        reputation = Reputation.defaultState(),
        cutterMemory = {},
        procurement = { orders = {}, nextOrderId = 1, shipments = {}, nextShipmentId = 1 },
        vendorCategory = 1,
        calendar = BusinessCalendar.defaultCalendar(),
        bills = BusinessCalendar.defaultBills(),
        clientEmails = { nextEmailId = 1, nextPromotionId = 1,
            pending = {}, inbox = {}, archive = {}, sentPromotions = {} },
        workPhone = { nextCallId = 1, nextCallAtHours = 6, incoming = nil, history = {} },
        machines = MachineFleet.defaultState(),
        cutter = defaultPlacement(Config.cutterPlacement),
        palletJack = jack,
        warehouse = WarehouseUpgrades.defaultState(),
        storage = PalletStorage.defaultState(),
        forklift = Forklift.defaultState(Config.forklift),
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

local function titleForKey(key)
    local result = tostring(key or "client-artwork"):gsub("[_%-]+", " ")
    return (result:gsub("(%a)([%w']*)", function(first, rest)
        return string.upper(first) .. string.lower(rest)
    end))
end

local function artworkOrientation(job)
    local size = job.press and job.press.artworkSize or job.finishedSize
    return dimensions(size) and size.width > size.height and "landscape" or "portrait"
end

local function normalizeArtwork(job, required)
    if job.artwork == nil and not required then return end
    if job.artwork == nil then job.artwork = {} end
    if type(job.artwork) ~= "table" then return end
    local key = text(job.artwork.key) and job.artwork.key
        or text(job.artworkKey) and job.artworkKey or "client-artwork"
    if job.artwork.key == nil then job.artwork.key = key end
    if job.artwork.displayName == nil then job.artwork.displayName = titleForKey(key) end
    if job.artwork.fileName == nil then job.artwork.fileName = key .. ".png" end
    if job.artwork.suppliedBy == nil then job.artwork.suppliedBy = "client" end
    if job.artwork.orientation == nil then job.artwork.orientation = artworkOrientation(job) end
    if job.artworkKey == nil then job.artworkKey = key end
end

local function legacyStockDescription(job)
    local details = type(job.details) == "table" and job.details or {}
    return text(details.stockDescription) and details.stockDescription or "Customer supplied paper"
end

local function normalizeStockSpec(job, required)
    if job.stockSpec == nil and not required then return end
    if job.stockSpec == nil then job.stockSpec = {} end
    if type(job.stockSpec) ~= "table" then return end
    local description = legacyStockDescription(job)
    local lower = string.lower(description)
    if job.stockSpec.suppliedBy == nil then job.stockSpec.suppliedBy = "client" end
    if job.stockSpec.grade == nil then
        job.stockSpec.grade = lower:find("cover", 1, true) and "cover"
            or lower:find("text", 1, true) and "text" or "unspecified"
    end
    if job.stockSpec.weight == nil then
        job.stockSpec.weight = tonumber(lower:match("(%d+)%s*lb")) or 0
    end
    if job.stockSpec.finish == nil then
        job.stockSpec.finish = lower:find("gloss", 1, true) and "gloss"
            or lower:find("uncoated", 1, true) and "uncoated" or "unspecified"
    end
    if job.stockSpec.color == nil then job.stockSpec.color = "unspecified" end
    if job.stockSpec.grain == nil then
        local details = type(job.details) == "table" and job.details or {}
        job.stockSpec.grain = text(details.grainDirection) and details.grainDirection or "unspecified"
    end
    if job.stockSpec.description == nil then job.stockSpec.description = description end
end

local actualFields = {
    "plateCost", "inHousePlates", "inkUnits", "tympanSheets", "washUnits",
    "proofs", "impressions", "spoilage", "pressHours", "supplyCost",
}

local function normalizePlate(job, press, colorIndex)
    if type(press.plates) ~= "table" then return end
    local plate = press.plates[colorIndex]
    if plate == nil then
        plate = {}
        press.plates[colorIndex] = plate
    end
    if type(plate) ~= "table" then return end
    local artworkKey = job.artwork and job.artwork.key or job.artworkKey or "client-artwork"
    if plate.id == nil then plate.id = string.format("%s-PLATE-%02d", job.id or "JOB", colorIndex) end
    if plate.jobId == nil then plate.jobId = job.id end
    if plate.colorIndex == nil then plate.colorIndex = colorIndex end
    if plate.inkColor == nil then
        plate.inkColor = type(press.colorSequence) == "table" and press.colorSequence[colorIndex]
            or (colorIndex == 1 and "Black" or "Spot " .. colorIndex)
    end
    if plate.artworkKey == nil then plate.artworkKey = artworkKey end
    if plate.artworkSize == nil then plate.artworkSize = copy(press.artworkSize or job.finishedSize) end
    if plate.status == nil then plate.status = "unprepared" end
    if plate.quality == nil then plate.quality = 0 end
    if plate.life == nil then plate.life = 1 end
    if plate.processStep == nil then plate.processStep = 1 end
    if plate.processScores == nil then plate.processScores = {} end
    if plate.mounted == nil then plate.mounted = false end
end

local function normalizePrintJob(job)
    local press = job.press
    if type(press) ~= "table" then return end
    normalizeArtwork(job, true)
    normalizeStockSpec(job, true)
    if press.colors == nil then press.colors = 1 end
    if press.coverage == nil then press.coverage = 0.4 end
    if press.artworkSize == nil then press.artworkSize = copy(job.finishedSize) end
    if press.colorSequence == nil then press.colorSequence = {} end
    if type(press.colorSequence) == "table" and positiveInteger(press.colors) then
        for colorIndex = 1, press.colors do
            if press.colorSequence[colorIndex] == nil then
                press.colorSequence[colorIndex] = colorIndex == 1 and "Black" or "Spot " .. colorIndex
            end
        end
    end
    if press.requestedCopies == nil then press.requestedCopies = {} end

    local ordered, supplied, allowance = 0, 0, 0
    if type(job.pallets) == "table" then
        for index, pallet in ipairs(job.pallets) do
            if type(pallet) == "table" then
                local replacement = type(pallet.replacementFor) == "string"
                local quoted = type(job.quote) == "table" and type(job.quote.pallets) == "table"
                    and not replacement and job.quote.pallets[pallet.number or index] or nil
                local requested = pallet.requestedCopies
                    or (not replacement and type(press.requestedCopies) == "table"
                        and press.requestedCopies[pallet.number or index])
                    or (type(quoted) == "table" and quoted.requestedCopies)
                    or (pallet.status == "spoiled_discarded" and 0 or pallet.initialSheets)
                if pallet.requestedCopies == nil and requested > 0 then
                    pallet.requestedCopies = requested
                end
                if not replacement and type(press.requestedCopies) == "table"
                    and press.requestedCopies[pallet.number or index] == nil
                then
                    press.requestedCopies[pallet.number or index] = requested
                end
                local palletAllowance = pallet.spoilageAllowance
                if palletAllowance == nil and number(pallet.initialSheets) and number(requested) then
                    palletAllowance = math.max(0, pallet.initialSheets - requested)
                    pallet.spoilageAllowance = palletAllowance
                end
                if type(quoted) == "table" then
                    if quoted.requestedCopies == nil then quoted.requestedCopies = requested end
                    if quoted.spoilageAllowance == nil then quoted.spoilageAllowance = palletAllowance or 0 end
                end
                if pallet.press == nil and pallet.status ~= "spoiled_discarded" then pallet.press = {} end
                if type(pallet.press) == "table" then
                    if pallet.press.status == nil then pallet.press.status = "awaiting_cut" end
                    if pallet.press.requiredGoodSheets == nil then pallet.press.requiredGoodSheets = requested end
                    if pallet.press.completedColors == nil then pallet.press.completedColors = 0 end
                    if pallet.press.goodSheets == nil then pallet.press.goodSheets = 0 end
                    if pallet.press.availableSheets == nil then
                        local priorPassSheets = number(pallet.finishedSheets)
                            and pallet.finishedSheets > 0 and pallet.finishedSheets
                            or pallet.press.goodSheets
                        pallet.press.availableSheets = pallet.press.completedColors > 0
                            and priorPassSheets or pallet.initialSheets
                    end
                    if pallet.press.spoilage == nil then pallet.press.spoilage = 0 end
                    if pallet.press.passHistory == nil then pallet.press.passHistory = {} end
                end
                if number(requested) then ordered = ordered + requested end
                if number(pallet.initialSheets) then
                    supplied = supplied + math.max(0,
                        pallet.initialSheets - (tonumber(pallet.damagedSheets) or 0))
                end
                if number(palletAllowance) then allowance = allowance + palletAllowance end
            end
        end
    end
    if press.orderedQuantity == nil then press.orderedQuantity = ordered end
    if press.suppliedSheets == nil then press.suppliedSheets = supplied end
    if press.spoilageAllowance == nil then press.spoilageAllowance = allowance end
    if type(job.quote) == "table" then
        if job.quote.orderedCopies == nil then job.quote.orderedCopies = ordered end
        if job.quote.suppliedSheets == nil then job.quote.suppliedSheets = supplied end
        if job.quote.spoilageAllowance == nil then job.quote.spoilageAllowance = allowance end
    end
    if press.plates == nil then press.plates = {} end
    if type(press.plates) == "table" and positiveInteger(press.colors) then
        for colorIndex = 1, press.colors do normalizePlate(job, press, colorIndex) end
    end
    if press.actual == nil then press.actual = {} end
    if type(press.actual) == "table" then
        for _, field in ipairs(actualFields) do
            if press.actual[field] == nil then press.actual[field] = 0 end
        end
    end
end

local function normalizeJob(savedJob)
    if type(savedJob) ~= "table" then return end
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
                    pallet.activeLift = math.min(pallet.requiredLifts or 1, (pallet.completedLifts or 0) + 1)
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
    normalizeArtwork(savedJob, false)
    normalizeStockSpec(savedJob, false)
    normalizePrintJob(savedJob)
end

local function normalizeJobs(jobs)
    for _, collectionName in ipairs({ "active", "completed", "declined" }) do
        local collection = type(jobs[collectionName]) == "table" and jobs[collectionName] or {}
        jobs[collectionName] = collection
        for _, savedJob in ipairs(collection) do normalizeJob(savedJob) end
    end
end

local function normalizeEmailJobs(emails)
    if type(emails) ~= "table" then return end
    for _, collectionName in ipairs({ "pending", "inbox" }) do
        if type(emails[collectionName]) == "table" then
            for _, email in ipairs(emails[collectionName]) do
                if type(email) == "table" then normalizeJob(email.job) end
            end
        end
    end
end

local function normalizeWindmillProcess(value, state)
    if type(value) ~= "table" then return value end
    if value.status == nil then value.status = "idle" end
    if value.speed == nil then value.speed = 3000 end
    if value.motor == nil then value.motor = false end
    if value.feeder == nil then value.feeder = false end
    if value.impression == nil then value.impression = false end
    if value.emergency == nil then value.emergency = false end
    if value.setup == nil then value.setup = {} end
    if value.counter == nil then value.counter = 0 end
    if value.goodSheets == nil then value.goodSheets = 0 end
    if value.spoilage == nil then value.spoilage = 0 end
    if value.sheetAccumulator == nil then value.sheetAccumulator = 0 end
    if value.animationClock == nil then value.animationClock = 0 end
    local activeJob, activePallet
    for _, savedJob in ipairs(state and state.jobs and state.jobs.active or {}) do
        if savedJob.id == value.jobId then
            activeJob = savedJob
            for _, pallet in ipairs(savedJob.pallets or {}) do
                if pallet.id == value.palletId then activePallet = pallet; break end
            end
            break
        end
    end
    if activeJob and activePallet and type(activeJob.press) == "table"
        and type(activePallet.press) == "table"
    then
        local required = activePallet.press.requiredGoodSheets or activePallet.requestedCopies
            or activePallet.initialSheets
        local available = activePallet.press.availableSheets or activePallet.initialSheets
        if value.targetSheets == nil then
            local colors = math.max(1, math.floor(tonumber(activeJob.press.colors) or 1))
            local color = math.max(1, math.min(colors, math.floor(tonumber(value.colorIndex)
                or (activePallet.press.completedColors or 0) + 1)))
            local supplied = math.max(required, math.floor(tonumber(activePallet.initialSheets) or required))
            local allowance = math.max(0, math.floor(tonumber(activePallet.spoilageAllowance)
                or (supplied - required)))
            local reservePerPass = math.floor(allowance / colors)
            value.targetSheets = required + reservePerPass * (colors - color)
        end
        if value.feedStart == nil then value.feedStart = available end
        if value.feedRemaining == nil and number(available) and number(value.counter) then
            value.feedRemaining = math.max(0, available - value.counter)
        end
        if value.artworkVerified == nil and value.proofApproved ~= nil then
            value.artworkVerified = value.proofApproved == true
        end
    end
    return value
end

local function repairLegacyPhysicalOwnership(state)
    -- Legacy machine repair predates racks/stacks/forklifts. Never let it move
    -- newly-owned stock to a machine or floor based on a stale old claim.
    if state.forklift and state.forklift.carriedPalletId then return end
    for _, item in ipairs(PalletState.items(state)) do
        if item.pallet.location == "rack" or item.pallet.location == "stacked"
            or item.pallet.location == "on_forklift" or item.pallet.storage ~= nil then return end
    end
    local process = state.windmill and state.windmill.process
    local selected = process and process.palletId and PalletState.find(state, process.palletId) or nil
    if selected and (selected.vendor or selected.job.id ~= process.jobId
        or type(selected.job.press) ~= "table" or type(selected.pallet.press) ~= "table")
    then
        selected = nil
    end
    local selectedWasAtPress = selected and selected.pallet.location == "at_press"
    local offset = 0
    for _, item in ipairs(PalletState.items(state)) do
        local pallet = item.pallet
        if pallet.location == "at_press" and (not selected or pallet ~= selected.pallet) then
            pallet.location = "warehouse"
        end
        local physical = pallet.location == "warehouse" or pallet.location == "cutter_output"
            or pallet.location == "on_pallet_jack" or pallet.location == "at_cutter"
            or pallet.location == "at_press" or pallet.location == "press_output"
        if physical and type(pallet.world) ~= "table" then
            offset = offset + 1
            local anchor = (pallet.location == "at_cutter" or pallet.location == "cutter_output")
                and state.cutter or (pallet.location == "at_press" or pallet.location == "press_output")
                and state.windmill or state.palletJack
            pallet.world = { x = anchor.x + offset * 8, y = anchor.y + offset * 5,
                direction = anchor.direction or "northwest", spawnProgress = 1 }
        end
    end
    if selected then
        selected.pallet.location = "at_press"
        if state.palletJack.carriedPalletId == selected.pallet.id then
            state.palletJack.carriedPalletId = nil
        end
        if not selectedWasAtPress or type(selected.pallet.world) ~= "table" then
            selected.pallet.world = { x = state.windmill.x, y = state.windmill.y,
                direction = state.windmill.direction, spawnProgress = 1 }
        end
    elseif process and process.palletId then
        state.windmill.process = nil
    end
    PalletState.reconcile(state)
end

local function normalizeState(source, repairPhysical)
    source = type(source) == "table" and source or {}
    if not Schema.validPhysicalSource(source) then return nil, "Invalid physical stock or vehicle ownership." end
    local result = Schema.defaultState()
    local warehouse, warehouseError = WarehouseUpgrades.normalize(source.warehouse)
    if not warehouse then return nil, warehouseError end
    local storage, storageError = PalletStorage.normalize(source.storage)
    if not storage then return nil, storageError end
    if source.forklift ~= nil and not Forklift.validState(source.forklift, Config.forklift) then
        return nil, "Invalid saved forklift state."
    end
    result.warehouse, result.storage = warehouse, storage
    if not WarehouseConstruction.valid(source.constructionWorker, warehouse) then
        return nil, "Invalid saved construction worker state."
    end
    result.constructionWorker = WarehouseConstruction.normalize(source.constructionWorker, warehouse)
    result.forklift = source.forklift == nil and Forklift.defaultState(Config.forklift)
        or Forklift.normalize(source.forklift, Config.forklift)
    if result.forklift.owned and not warehouse.forkliftOwned then
        return nil, "Forklift ownership has no purchase entitlement."
    end
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
    result.reputation = type(source.reputation) == "table"
        and copy(source.reputation) or result.reputation
    Reputation.ensure(result)
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
    normalizeEmailJobs(result.clientEmails)
    result.workPhone = type(source.workPhone) == "table"
        and copy(source.workPhone) or result.workPhone
    result.workPhone.nextCallId = math.max(1,
        math.floor(tonumber(result.workPhone.nextCallId) or 1))
    result.workPhone.nextCallAtHours = math.max(0,
        tonumber(result.workPhone.nextCallAtHours) or 6)
    result.workPhone.incoming = type(result.workPhone.incoming) == "table"
        and result.workPhone.incoming or nil
    result.workPhone.history = type(result.workPhone.history) == "table"
        and result.workPhone.history or {}
    result.machines = type(source.machines) == "table"
        and copy(source.machines) or result.machines
    MachineFleet.ensure(result)
    BusinessCalendar.ensure(result)
    result.cutter = mergePlacement(result.cutter, source.cutter)
    result.wrapper = mergePlacement(result.wrapper, source.wrapper)
    result.windmill = mergePlacement(result.windmill, source.windmill)
    if type(source.windmill) == "table" and source.windmill.tutorialComplete ~= nil then
        result.windmill.tutorialComplete = source.windmill.tutorialComplete == true
    end
    if type(source.windmill) == "table" and type(source.windmill.process) == "table" then
        result.windmill.process = normalizeWindmillProcess(copy(source.windmill.process), result)
    end
    result.technicianVisit = type(source.technicianVisit) == "table"
        and copy(source.technicianVisit) or nil
    result.palletJack = mergePlacement(result.palletJack, source.palletJack)
    if type(source.palletJack) == "table" then
        result.palletJack.operating = source.palletJack.operating == true
        result.palletJack.animationClock = source.palletJack.animationClock or 0
        result.palletJack.carriedPalletId = source.palletJack.carriedPalletId
    end
    if repairPhysical then repairLegacyPhysicalOwnership(result) end
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
                or pallet.location == "at_press" or pallet.location == "press_output"
                or pallet.location == "rack" or pallet.location == "stacked" or pallet.location == "on_forklift"
            then
                local needsPrinting = type(savedJob.press) == "table"
                local printingComplete = not needsPrinting
                    or (type(pallet.press) == "table" and pallet.press.status == "complete")
                local cuttingComplete = pallet.status == "cut" or pallet.status == "printed"
                    or pallet.status == "finished" or pallet.status == "wrapped"
                    or (pallet.paper and pallet.paper.status == "complete"
                        and (pallet.remainingSheets or 0) == 0)
                if pallet.location == "at_press"
                    or (needsPrinting and not printingComplete and cuttingComplete)
                    or pallet.status == "in_process" or pallet.status == "press_setup"
                then
                    inProcess = inProcess + 1
                elseif pallet.status == "cut" or pallet.status == "printed"
                    or pallet.status == "finished" or pallet.status == "wrapped"
                    or (cuttingComplete and printingComplete)
                then
                    finished = finished + 1
                elseif pallet.location == "at_cutter" then
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
    local committedPlacements = {}
    for _, kind in ipairs({ "cutter", "wrapper", "windmill" }) do
        local item = type(state) == "table" and state[kind] or nil
        local origin = type(item) == "table" and item.moving == true
            and item._relocationOrigin or nil
        if type(origin) == "table" and number(origin.x) and number(origin.y)
            and directions[origin.direction]
        then
            committedPlacements[kind] = {
                x = origin.x,
                y = origin.y,
                direction = origin.direction,
            }
        end
    end
    local result, reason = normalizeState(state)
    if not result then return nil, reason end
    for kind, origin in pairs(committedPlacements) do
        result[kind].x, result[kind].y = origin.x, origin.y
        result[kind].direction = origin.direction
    end
    result.cutter.moving, result.cutter.inMotion = false, false
    result.wrapper.moving, result.wrapper.inMotion = false, false
    result.windmill.moving, result.windmill.inMotion = false, false
    result.palletJack.operating = false
    result.palletJack.moving, result.palletJack.inMotion = false, false
    result.palletJack.operatorPlayerId = nil
    Forklift.forceRelease(result, Config.forklift)
    Schema.reconcile(result)
    return result
end

function Schema.validState(state)
    return persistentState(state)
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
        or payload.version == 11 or payload.version == 12 or payload.version == 13 or payload.version == 14
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
        state = normalizeState(payload.state, true),
        player = { x = payload.player.x, y = payload.player.y },
    }
    Schema.reconcile(migrated.state)
    return Schema.validPayload(migrated) and migrated or nil
end

Schema.copy = copy
Schema.validSlot = validSlot
return Schema
