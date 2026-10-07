-- Phone calls, purchasing, inventory, and machine process validation.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    Runtime.WORK_PHONE_KINDS = {
        customer_order = true,
        customer_status = true,
        supplier_status = true,
        service_order = true,
        construction_notice = true,
    }

    function Runtime.phoneCall(value)
        return type(value) == "table"
            and Runtime.text(value.id)
            and Runtime.WORK_PHONE_KINDS[value.kind] == true
            and Runtime.text(value.caller)
            and Runtime.text(value.role)
            and Runtime.text(value.subject)
            and Runtime.text(value.message)
            and Runtime.nonnegative(value.receivedAtHours)
            and type(value.answered) == "boolean"
            and Runtime.optionalText(value.jobId)
            and Runtime.optionalText(value.orderId)
            and Runtime.optionalText(value.projectId)
            and Runtime.optionalText(value.bayId)
            and Runtime.optionalText(value.optionId)
            and (value.kind ~= "construction_notice" or (Runtime.text(value.projectId)
                and value.projectId:match("^WUP%-%d+$") ~= nil and #value.projectId <= 64
                and (value.bayId == "front_left" or value.bayId == "front_right")
                and (value.optionId == "floor" or value.optionId == "storage" or value.optionId == "breakroom")))
            and Runtime.optionalPositiveInteger(value.categoryIndex)
            and Runtime.optionalPositiveInteger(value.itemIndex)
            and Runtime.optionalText(value.outcome)
            and Runtime.optionalText(value.response)
            and Runtime.optionalNonnegative(value.endedAtHours)
    end

    function Runtime.workPhone(value)
        return type(value) == "table"
            and Runtime.positiveInteger(value.nextCallId)
            and Runtime.nonnegative(value.nextCallAtHours)
            and (value.incoming == nil or Runtime.phoneCall(value.incoming))
            and Runtime.array(value.history, Runtime.phoneCall)
    end

    function Runtime.vendorPallet(value)
        return type(value) == "table"
            and Runtime.text(value.id)
            and Runtime.positiveInteger(value.number)
            and value.kind == "vendor_product"
            and Runtime.text(value.category)
            and Runtime.text(value.categoryName)
            and Runtime.positiveInteger(value.assetRow)
            and Runtime.text(value.productId)
            and Runtime.text(value.productName)
            and Runtime.nonnegative(value.quantity)
            and Runtime.text(value.unit)
            and Runtime.text(value.location)
            and Runtime.text(value.status)
            and Runtime.worldPosition(value.world)
            and Runtime.storedPlacement(value)
    end

    function Runtime.purchaseOrder(value)
        return type(value) == "table"
            and Runtime.text(value.id)
            and Runtime.text(value.vendor)
            and Runtime.text(value.company)
            and Runtime.text(value.category)
            and Runtime.text(value.item)
            and Runtime.text(value.productName)
            and Runtime.nonnegative(value.price)
            and Runtime.text(value.status)
            and Runtime.optionalNumber(value.orderedAt)
            and Runtime.delivery(value.delivery)
            and Runtime.array(value.pallets, Runtime.vendorPallet)
    end

    function Runtime.stock(value)
        if type(value) ~= "table" then return false end
        for key, quantity in pairs(value) do
            if not Runtime.text(key) or not Runtime.nonnegative(quantity) then return false end
        end
        return true
    end

    function Runtime.cutterMemory(value)
        if type(value) ~= "table" then return false end
        for key, measurements in pairs(value) do
            local cutNumber = tonumber(key)
            if not Runtime.integer(cutNumber) or cutNumber < 1 or cutNumber > 4
                or not Runtime.array(measurements, function(measurement)
                    return Runtime.nonnegative(measurement) and measurement <= 25
                end)
                or #measurements > 3
            then
                return false
            end
        end
        return true
    end

    function Runtime.inventory(value)
        return type(value) == "table"
            and Runtime.nonnegative(value.paper)
            and Runtime.nonnegative(value.prints)
            and Runtime.nonnegative(value.rawPallets)
            and Runtime.nonnegative(value.inProcessPallets)
            and Runtime.nonnegative(value.finishedPallets)
            and Runtime.nonnegative(value.plasticWrapRolls)
            and Runtime.integer(value.plasticWrapRolls)
            and Runtime.nonnegative(value.plasticWrapUses)
            and Runtime.integer(value.plasticWrapUses)
            and value.plasticWrapUses <= 11
            and Runtime.stock(value.stock)
    end

    function Runtime.placement(value)
        return type(value) == "table"
            and Runtime.number(value.x) and Runtime.number(value.y)
            and Runtime.directions[value.direction] == true
            and type(value.moving) == "boolean"
            and type(value.inMotion) == "boolean"
    end

    function Runtime.setupScores(value)
        if type(value) ~= "table" then return false end
        for key, score in pairs(value) do
            if not Runtime.text(key) or not Runtime.number(score) or score < 0 or score > 1 then return false end
        end
        return true
    end

    function Runtime.copyQuantity(value)
        if value == nil then return true end
        if Runtime.nonnegativeInteger(value) then return true end
        return Runtime.array(value, Runtime.positiveInteger)
    end

    function Runtime.proofRecord(value)
        return value == nil or (type(value) == "table"
            and (value.quality == nil or (Runtime.number(value.quality) and value.quality >= 0 and value.quality <= 1))
            and Runtime.optionalBoolean(value.approved)
            and Runtime.optionalNonnegativeInteger(value.sheets)
            and Runtime.optionalNonnegativeInteger(value.spoilage)
            and Runtime.optionalNumber(value.createdAtHours))
    end

    function Runtime.windmillProcess(value)
        if value == nil then return true end
        if type(value) ~= "table"
            or not Runtime.text(value.status)
            or not Runtime.number(value.speed) or value.speed <= 0
            or type(value.motor) ~= "boolean"
            or type(value.feeder) ~= "boolean"
            or type(value.impression) ~= "boolean"
            or type(value.emergency) ~= "boolean"
            or not Runtime.setupScores(value.setup)
            or not Runtime.nonnegative(value.counter)
            or not Runtime.nonnegative(value.goodSheets)
            or not Runtime.nonnegative(value.spoilage)
            or not Runtime.nonnegative(value.sheetAccumulator)
            or not Runtime.nonnegative(value.animationClock)
            or not Runtime.optionalText(value.jobId)
            or not Runtime.optionalText(value.palletId)
            or not Runtime.optionalPositiveInteger(value.colorIndex)
            or not Runtime.optionalBoolean(value.proofApproved)
            or not Runtime.optionalBoolean(value.artworkVerified)
            or not Runtime.optionalText(value.warning)
            or not Runtime.proofRecord(value.proof)
            or not Runtime.copyQuantity(value.requestedCopies)
        then
            return false
        end
        if value.proofQuality ~= nil
            and (not Runtime.number(value.proofQuality) or value.proofQuality < 0 or value.proofQuality > 1)
        then
            return false
        end
        for _, field in ipairs({
            "orderedQuantity", "suppliedSheets", "spoilageAllowance", "requiredGoodSheets",
            "availableSheets", "targetGoodSheets", "targetSheets", "remainingSheets", "proofSheets",
            "feedStart", "feedRemaining",
        }) do
            if not Runtime.optionalNonnegativeInteger(value[field]) then return false end
        end
        return value.passHistory == nil or Runtime.array(value.passHistory, Runtime.passHistoryEntry)
    end
end

return Component
