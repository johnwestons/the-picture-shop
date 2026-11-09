-- Print quantities, jobs, and email validation.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.printQuantities(value)
        if value.press == nil then
            return Runtime.artwork(value.artwork) and Runtime.stockSpec(value.stockSpec)
                and (value.stockSpec == nil or value.stockSpec.suppliedBy == "client")
        end
        if not Runtime.artwork(value.artwork) or value.artwork == nil
            or not Runtime.stockSpec(value.stockSpec, true) or value.stockSpec == nil
            or not Runtime.jobPress(value.press)
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
                        + math.max(0, math.floor(tonumber(member.press.housePaperSheets) or 0))
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

    local skillAwardStages = { cutter = true, press = true, wrapping = true }
    function Runtime.employeeSkillAwards(value)
        if value == nil then return true end
        if type(value) ~= "table" then return false end
        local stages = 0
        for stage, employeeIds in pairs(value) do
            if not skillAwardStages[stage] or type(employeeIds) ~= "table"
                or #employeeIds > 24
                or not Runtime.array(employeeIds, function(employeeId)
                    return Runtime.text(employeeId) and #employeeId <= 64
                        and employeeId:match("^[%w_.%-]+$") ~= nil
                end)
            then
                return false
            end
            local seen = {}
            for _, employeeId in ipairs(employeeIds) do
                if seen[employeeId] then return false end
                seen[employeeId] = true
            end
            stages = stages + 1
        end
        return stages <= 3
    end

    local function jobFeedback(value)
        if value == nil then return true end
        if type(value) ~= "table" or not Runtime.array(value.events, function(event)
            return type(event) == "table" and Runtime.text(event.stage)
                and #event.stage <= 40 and Runtime.nonnegative(event.atHours)
                and type(event.detail) == "string" and #event.detail <= 220
        end) or #value.events > 32 then return false end
        return Runtime.optionalText(value.stage)
            and Runtime.optionalText(value.stageDetail)
            and Runtime.optionalNumber(value.stageAtHours)
            and Runtime.optionalNumber(value.shippedAtHours)
            and Runtime.optionalText(value.lastDetail)
            and Runtime.optionalText(value.blocker)
            and Runtime.optionalText(value.lastAlert)
            and Runtime.optionalNonnegativeInteger(value.caughtDefects)
            and Runtime.optionalNonnegativeInteger(value.reworkSheets)
            and Runtime.optionalNonnegativeInteger(value.reworkCost)
            and Runtime.optionalNonnegativeInteger(value.scrapSheets)
            and Runtime.optionalNonnegativeInteger(value.deliveredSheets)
    end

    local function driverDelivery(value)
        if value == nil then return true end
        return type(value) == "table" and value.version == 1
            and Runtime.text(value.driverEmployeeId) and #value.driverEmployeeId <= 64
            and value.driverEmployeeId:match("^[%w_.%-]+$") ~= nil
            and Runtime.integer(value.driverSkill) and value.driverSkill >= 0 and value.driverSkill <= 100
            and Runtime.nonnegative(value.standardArrivalAtHours)
            and Runtime.nonnegative(value.arrivedAtHours)
            and Runtime.nonnegative(value.lateHours)
            and Runtime.integer(value.serviceRating) and value.serviceRating >= 1 and value.serviceRating <= 5
    end

    local function jobInspection(value)
        if value == nil then return true end
        return type(value) == "table"
            and (value.status == "passed" or value.status == "held" or value.status == "rework_in_progress")
            and Runtime.nonnegative(value.inspectedAtHours)
            and Runtime.array(value.findings, function(item) return Runtime.text(item) and #item <= 180 end)
            and #value.findings <= 24
            and Runtime.array(value.palletIds, function(item) return Runtime.text(item) and #item <= 64 end)
            and #value.palletIds <= 24
            and Runtime.optionalBoolean(value.firstPass)
    end

    local function customerCase(value)
        if value == nil then return true end
        return type(value) == "table"
            and (value.status == "open" or value.status == "resolved")
            and (value.reason == "quality" or value.reason == "late")
            and Runtime.nonnegative(value.openedAtHours)
            and Runtime.optionalNonnegative(value.lateHours)
            and (value.resolution == nil or value.resolution == "credit"
                or value.resolution == "apology" or value.resolution == "decline")
            and Runtime.optionalNumber(value.resolvedAtHours)
            and Runtime.optionalNonnegative(value.creditAmount)
            and Runtime.optionalText(value.responseText)
    end

    local function outboundDelivery(value)
        if value == nil then return true end
        return type(value) == "table"
            and Runtime.optionalBoolean(value.requested)
            and Runtime.optionalBoolean(value.offered)
            and (value.transport == "customer" or value.transport == "shop" or value.transport == "pending")
            and Runtime.optionalNonnegative(value.quotedPrice)
    end

    function Runtime.job(value)
        return type(value) == "table"
            and Runtime.text(value.id)
            and Runtime.text(value.company)
            and (value.customerDestination == nil or Runtime.text(value.customerDestination))
            and Runtime.dimensions(value.sourceSize)
            and Runtime.dimensions(value.finishedSize)
            and (value.artworkKey == nil or Runtime.text(value.artworkKey))
            and Runtime.artwork(value.artwork)
            and (value.artwork == nil or value.artworkKey == value.artwork.key)
            and Runtime.stockSpec(value.stockSpec, value.press ~= nil)
            and Runtime.deliveryService(value.deliveryService)
            and outboundDelivery(value.outboundDelivery)
            and (value.requestChannel == nil or value.requestChannel == "reception" or value.requestChannel == "email")
            and type(value.details) == "table"
            and Runtime.text(value.difficulty)
            and (value.packaging == "flat" or value.packaging == "boxed")
            and Runtime.text(value.status)
            and Runtime.Labor.validJob(value.labor)
            and Runtime.optionalNumber(value.createdAt)
            and Runtime.optionalNumber(value.acceptedAt)
            and Runtime.optionalNumber(value.declinedAt)
            and Runtime.optionalNumber(value.completedAt)
            and Runtime.optionalNumber(value.paidAt)
            and Runtime.optionalNumber(value.paymentAmount)
            and Runtime.optionalBoolean(value.promotionSent)
            and Runtime.optionalNumber(value.pickupRequestedAtHours)
            and Runtime.optionalNumber(value.completedAtHours)
            and Runtime.optionalNumber(value.acceptedGameHours)
            and require("src.business_deadlines").valid(value.deadline)
            and Runtime.optionalNonnegativeInteger(value.replacementSkids)
            and Runtime.optionalNonnegativeInteger(value.replacementSheets)
            and Runtime.optionalBoolean(value.housePaperReserved)
            and Runtime.optionalNonnegativeInteger(value.housePaperReservedSheets)
            and jobFeedback(value.feedback)
            and driverDelivery(value.driverDelivery)
            and jobInspection(value.inspection)
            and customerCase(value.customerCase)
            and Runtime.employeeSkillAwards(value.employeeSkillAwards)
            and Runtime.quote(value.quote)
            and Runtime.array(value.pallets, Runtime.customerPallet)
            and Runtime.delivery(value.delivery)
            and Runtime.pickup(value.pickup)
            and Runtime.printQuantities(value)
    end

    function Runtime.clientEmails(value)
        if type(value) ~= "table" or not Runtime.positiveInteger(value.nextEmailId)
            or not Runtime.positiveInteger(value.nextPromotionId)
            or type(value.pending) ~= "table" or type(value.inbox) ~= "table" or type(value.archive) ~= "table"
            or type(value.sentPromotions) ~= "table"
        then return false end
        local function email(item, received)
            if type(item) ~= "table" or not Runtime.text(item.id) or not Runtime.text(item.sender)
                or not Runtime.text(item.subject) or not Runtime.text(item.body)
                or not Runtime.optionalBoolean(item.unread)
                or not Runtime.nonnegative(item.readyAtHours)
                or (received and not Runtime.nonnegative(item.receivedAtHours))
            then return false end
            if item.job ~= nil then
                return Runtime.text(item.sourceJobId) and Runtime.job(item.job)
                    and Runtime.optionalNonnegative(item.standardPrice)
                    and Runtime.optionalNonnegative(item.discountAmount)
                    and Runtime.optionalNonnegative(item.discountedTotal)
            end
            return Runtime.text(item.noticeKind)
                and Runtime.optionalText(item.sourceJobId)
                and Runtime.optionalText(item.orderId)
                and Runtime.optionalText(item.applicationId)
                and (item.attachmentKind == nil or item.attachmentKind == "resume")
                and Runtime.optionalNonnegative(item.total)
        end
        if not Runtime.array(value.pending, function(item) return email(item, false) end)
            or not Runtime.array(value.inbox, function(item) return email(item, true) end)
        then return false end
        return Runtime.array(value.archive, function(item)
            if type(item) ~= "table" or not Runtime.text(item.id) or not Runtime.text(item.sender)
                or not Runtime.text(item.subject) or not Runtime.optionalText(item.body)
                or not Runtime.optionalNumber(item.respondedAtHours)
            then return false end
            if item.response == "archived" then
                return Runtime.text(item.noticeKind) and Runtime.optionalText(item.orderId) and Runtime.optionalNonnegative(item.total)
            end
            return Runtime.text(item.jobId)
                and (item.response == "accepted" or item.response == "declined"
                    or item.response == "quote_accepted" or item.response == "quote_rejected"
                    or item.response == "estimate_sent")
                and Runtime.optionalNumber(item.quotedPrice) and Runtime.optionalNumber(item.acceptanceChance)
        end) and Runtime.array(value.sentPromotions, function(item)
            return type(item) == "table" and Runtime.text(item.id) and Runtime.text(item.recipient)
                and item.discountPercent == 10 and type(item.customMessage) == "string"
                and Runtime.nonnegative(item.sentAtHours)
                and Runtime.optionalText(item.sourceJobId)
                and Runtime.optionalNumber(item.couponUsedAtHours)
                and (item.responseOutcome == nil or item.responseOutcome == "new_job"
                    or item.responseOutcome == "thank_you" or item.responseOutcome == "no_response")
        end)
    end
end

return Component
