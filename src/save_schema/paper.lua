-- Paper, artwork, press, quote, and pallet validation.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.dimensions(value)
        return type(value) == "table"
            and Runtime.number(value.width) and value.width > 0
            and Runtime.number(value.height) and value.height > 0
    end

    function Runtime.worldPosition(value)
        if value == nil then return true end
        if type(value) ~= "table" or not Runtime.number(value.x) or not Runtime.number(value.y) then return false end
        if value.direction ~= nil and not Runtime.directions[value.direction] then return false end
        if value.sceneId ~= nil and value.sceneId~="warehouse"
            and value.sceneId~="front_left" and value.sceneId~="front_right" then return false end
        if value.rotation ~= nil and (not Runtime.integer(value.rotation) or value.rotation < 1 or value.rotation > 4) then return false end
        if not Runtime.optionalNumber(value.fromX) or not Runtime.optionalNumber(value.fromY) then return false end
        if value.spawnProgress ~= nil and (not Runtime.nonnegative(value.spawnProgress) or value.spawnProgress > 1) then return false end
        return true
    end

    function Runtime.storedPlacement(value)
        local _, reason = Runtime.PalletStorage.normalizePlacement(value)
        return reason == nil
    end

    function Runtime.cut(value)
        return type(value) == "table"
            and Runtime.positiveInteger(value.number)
            and Runtime.text(value.edge)
            and Runtime.nonnegative(value.margin)
            and Runtime.nonnegative(value.gauge)
            and Runtime.number(value.orientation)
    end

    function Runtime.historyEntry(value)
        return type(value) == "table"
            and Runtime.positiveInteger(value.number)
            and Runtime.text(value.edge)
            and Runtime.nonnegative(value.margin)
            and Runtime.nonnegative(value.gauge)
            and Runtime.dimensions(value.resultingSize)
    end

    function Runtime.paper(value)
        if value == nil then return true end
        return type(value) == "table"
            and Runtime.text(value.id)
            and Runtime.text(value.jobId)
            and Runtime.text(value.palletId)
            and Runtime.text(value.artworkId)
            and (value.artworkKey == nil or Runtime.text(value.artworkKey))
            and Runtime.text(value.difficulty)
            and Runtime.dimensions(value.sourceSize)
            and Runtime.dimensions(value.finishedSize)
            and Runtime.dimensions(value.currentSize)
            and type(value.margins) == "table"
            and Runtime.nonnegative(value.margins.left)
            and Runtime.nonnegative(value.margins.right)
            and Runtime.nonnegative(value.margins.top)
            and Runtime.nonnegative(value.margins.bottom)
            and Runtime.number(value.orientation)
            and Runtime.positiveInteger(value.activeCut)
            and Runtime.array(value.cuts, Runtime.cut)
            and Runtime.text(value.status)
            and Runtime.array(value.history, Runtime.historyEntry)
    end

    function Runtime.artwork(value)
        return value == nil or (type(value) == "table"
            and Runtime.text(value.key)
            and Runtime.text(value.displayName)
            and Runtime.text(value.fileName)
            and value.suppliedBy == "client"
            and (value.orientation == "portrait" or value.orientation == "landscape"))
    end

    function Runtime.stockSpec(value)
        return value == nil or (type(value) == "table"
            and value.suppliedBy == "client"
            and Runtime.text(value.grade)
            and Runtime.nonnegative(value.weight)
            and Runtime.text(value.finish)
            and Runtime.text(value.color)
            and Runtime.text(value.grain)
            and Runtime.text(value.description))
    end

    function Runtime.passHistoryEntry(value)
        if type(value) ~= "table" then return false end
        if not Runtime.optionalPositiveInteger(value.colorIndex)
            or not Runtime.optionalPositiveInteger(value.passNumber)
            or not Runtime.optionalText(value.inkColor)
            or not Runtime.optionalText(value.plateId)
            or not Runtime.optionalText(value.status)
            or not Runtime.optionalNonnegativeInteger(value.requiredGoodSheets)
            or not Runtime.optionalNonnegativeInteger(value.availableSheets)
            or not Runtime.optionalNonnegativeInteger(value.impressions)
            or not Runtime.optionalNonnegativeInteger(value.goodSheets)
            or not Runtime.optionalNonnegativeInteger(value.spoilage)
            or not Runtime.optionalNonnegativeInteger(value.targetSheets)
            or not Runtime.optionalNonnegativeInteger(value.feedSheets)
            or not Runtime.optionalNonnegativeInteger(value.remainingSheets)
            or not Runtime.optionalNumber(value.startedAtHours)
            or not Runtime.optionalNumber(value.completedAtHours)
            or not Runtime.optionalNonnegative(value.pressHours)
            or not Runtime.optionalBoolean(value.artworkVerified)
        then
            return false
        end
        if value.proofQuality ~= nil
            and (not Runtime.number(value.proofQuality) or value.proofQuality < 0 or value.proofQuality > 1)
        then
            return false
        end
        return value.quality == nil or (Runtime.number(value.quality) and value.quality >= 0 and value.quality <= 1)
    end

    function Runtime.palletPress(value)
        return value == nil or (type(value) == "table"
            and Runtime.text(value.status)
            and Runtime.positiveInteger(value.requiredGoodSheets)
            and Runtime.nonnegativeInteger(value.availableSheets)
            and Runtime.nonnegativeInteger(value.completedColors)
            and Runtime.nonnegativeInteger(value.goodSheets)
            and Runtime.nonnegativeInteger(value.spoilage)
            and Runtime.optionalNumber(value.dryUntilHours)
            and Runtime.array(value.passHistory, Runtime.passHistoryEntry))
    end

    function Runtime.pressPlate(value)
        if type(value) ~= "table"
            or not Runtime.text(value.id)
            or not Runtime.text(value.jobId)
            or not Runtime.positiveInteger(value.colorIndex)
            or not Runtime.text(value.inkColor)
            or not Runtime.text(value.artworkKey)
            or not Runtime.dimensions(value.artworkSize)
            or not Runtime.text(value.status)
            or not Runtime.optionalText(value.source)
            or not Runtime.number(value.quality) or value.quality < 0 or value.quality > 1
            or not Runtime.number(value.life) or value.life < 0 or value.life > 1
            or not Runtime.positiveInteger(value.processStep)
            or type(value.processScores) ~= "table"
            or type(value.mounted) ~= "boolean"
            or not Runtime.optionalNumber(value.orderedAtHours)
            or not Runtime.optionalNumber(value.readyAtHours)
            or not Runtime.optionalNonnegative(value.actualCost)
        then
            return false
        end
        return Runtime.array(value.processScores, function(score)
            return Runtime.number(score) and score >= 0 and score <= 1
        end)
    end

    function Runtime.pressActual(value)
        if type(value) ~= "table" then return false end
        for _, field in ipairs({
            "plateCost", "inHousePlates", "inkUnits", "tympanSheets", "washUnits",
            "proofs", "impressions", "spoilage", "pressHours", "supplyCost",
        }) do
            if not Runtime.nonnegative(value[field]) then return false end
        end
        return true
    end

    function Runtime.jobPress(value)
        return value == nil or (type(value) == "table"
            and Runtime.positiveInteger(value.colors) and value.colors <= 4
            and Runtime.number(value.coverage) and value.coverage >= 0 and value.coverage <= 1
            and Runtime.dimensions(value.artworkSize)
            and Runtime.array(value.colorSequence, Runtime.text)
            and #value.colorSequence == value.colors
            and Runtime.array(value.requestedCopies, Runtime.positiveInteger)
            and #value.requestedCopies >= 1
            and Runtime.positiveInteger(value.orderedQuantity)
            and Runtime.positiveInteger(value.suppliedSheets)
            and Runtime.nonnegativeInteger(value.spoilageAllowance)
            and Runtime.array(value.plates, Runtime.pressPlate)
            and #value.plates == value.colors
            and Runtime.pressActual(value.actual))
    end

    function Runtime.quotePallet(value)
        return type(value) == "table"
            and Runtime.positiveInteger(value.number)
            and Runtime.positiveInteger(value.sheetCount)
            and Runtime.positiveInteger(value.requiredLifts)
            and Runtime.nonnegative(value.price)
            and Runtime.optionalPositiveInteger(value.requestedCopies)
            and Runtime.optionalNonnegativeInteger(value.spoilageAllowance)
    end

    function Runtime.quote(value)
        return type(value) == "table"
            and Runtime.positiveInteger(value.palletCount)
            and Runtime.positiveInteger(value.totalSheets)
            and Runtime.positiveInteger(value.totalLifts)
            and Runtime.nonnegative(value.totalPrice)
            and Runtime.optionalNumber(value.recommendedPrice)
            and Runtime.optionalNumber(value.playerPrice)
            and Runtime.optionalNumber(value.standardPrice)
            and (value.servicePrice==nil or Runtime.nonnegative(value.servicePrice))
            and Runtime.Labor.validBudget(value.employeeBudget)
            and Runtime.optionalPositiveInteger(value.orderedCopies)
            and Runtime.optionalPositiveInteger(value.suppliedSheets)
            and Runtime.optionalNonnegativeInteger(value.spoilageAllowance)
            and Runtime.array(value.pallets, Runtime.quotePallet)
            and #value.pallets == value.palletCount
    end

    function Runtime.deliveryService(value)
        return value == nil or (type(value) == "table"
            and Runtime.text(value.id)
            and Runtime.text(value.label)
            and Runtime.text(value.description)
            and Runtime.nonnegative(value.delayHours))
    end

    function Runtime.delivery(value)
        return value == nil or (type(value) == "table"
            and Runtime.text(value.status)
            and (value.kind == nil or value.kind == "replacement")
            and (value.palletIds == nil or Runtime.array(value.palletIds, Runtime.text))
            and Runtime.optionalNumber(value.receivedAt)
            and Runtime.optionalNumber(value.acceptedGameHours)
            and Runtime.optionalNumber(value.readyAtHours)
            and Runtime.optionalNumber(value.expectedAtHours)
            and Runtime.optionalNumber(value.receivedAtHours)
            and Runtime.deliveryService(value.service))
    end

    function Runtime.pickup(value)
        return value == nil or (type(value) == "table"
            and Runtime.text(value.status)
            and Runtime.optionalNumber(value.requestedAt)
            and Runtime.optionalNumber(value.scheduledAt)
            and Runtime.optionalNumber(value.arrivedAt)
            and Runtime.optionalNumber(value.loadedAt)
            and Runtime.optionalNumber(value.completedAt))
    end

    function Runtime.customerPallet(value)
        return type(value) == "table"
            and Runtime.text(value.id)
            and Runtime.positiveInteger(value.number)
            and Runtime.positiveInteger(value.initialSheets)
            and Runtime.nonnegative(value.remainingSheets)
            and Runtime.nonnegative(value.finishedSheets)
            and Runtime.nonnegative(value.damagedSheets)
            and Runtime.positiveInteger(value.requiredLifts)
            and Runtime.nonnegative(value.completedLifts)
            and (value.activeLift == nil or Runtime.positiveInteger(value.activeLift))
            and (value.lastLiftSheets == nil or Runtime.nonnegative(value.lastLiftSheets))
            and (value.programVerified == nil or type(value.programVerified) == "boolean")
            and (value.awaitingPalletReturn == nil or type(value.awaitingPalletReturn) == "boolean")
            and Runtime.optionalText(value.replacementFor)
            and (value.replacementSequence == nil or Runtime.positiveInteger(value.replacementSequence))
            and Runtime.optionalBoolean(value.discardAfterSpoil)
            and Runtime.optionalPositiveInteger(value.requestedCopies)
            and Runtime.optionalNonnegativeInteger(value.spoilageAllowance)
            and Runtime.text(value.status)
            and Runtime.text(value.location)
            and (value.packaging == "flat" or value.packaging == "boxed")
            and type(value.wrapped) == "boolean"
            and (value.packagedAs == nil or value.packagedAs == "flat" or value.packagedAs == "boxed")
            and Runtime.optionalNumber(value.pickedUpAt)
            and Runtime.worldPosition(value.world)
            and Runtime.storedPlacement(value)
            and Runtime.paper(value.paper)
            and Runtime.palletPress(value.press)
    end
end

return Component
