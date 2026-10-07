-- Reception resource, quote, and job view validation.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.workshopResource(value, label)
        local base = Runtime.WORKSHOP_RESOURCES[value] and value or Runtime.MachineResource.parse(value)
        if not base then
            return nil, label .. " is not allowed"
        end
        return value
    end

    function Runtime.workshopAction(value, resourceId, label)
        local actions = Runtime.WORKSHOP_ACTION_ARGUMENTS[
            Runtime.WORKSHOP_RESOURCES[resourceId] and resourceId or Runtime.MachineResource.parse(resourceId)]
        if type(value) ~= "string" or not actions or actions[value] == nil then
            return nil, label .. " is not allowed for " .. tostring(resourceId)
        end
        return value, actions[value]
    end

    function Runtime.workshopPackaging(value, label)
        if type(value) ~= "string" or not Runtime.WORKSHOP_PACKAGING[value] then
            return nil, label .. " is invalid"
        end
        return value
    end

    function Runtime.normalizeWorkshopSize(value, label)
        local valid, shapeError = Runtime.shape(value, label, { "width", "height" })
        if not valid then return nil, shapeError end
        local width, fieldError = Runtime.numberInRange(value.width, 0.01, 1000, label .. ".width")
        if not width then return nil, fieldError end
        local height
        height, fieldError = Runtime.numberInRange(value.height, 0.01, 1000, label .. ".height")
        if not height then return nil, fieldError end
        return { width = width, height = height }
    end

    function Runtime.normalizeWorkshopQuoteRows(value, printJob, label)
        if not Runtime.Codec.isArray(value) then return nil, label .. " must be an array" end
        if #value < 1 or #value > 5 then
            return nil, label .. " must contain between 1 and 5 rows"
        end
        local rows, seen = {}, {}
        for index = 1, #value do
            local rowLabel = label .. "[" .. index .. "]"
            local required = printJob
                and { "number", "sheetCount", "requiredLifts", "requestedCopies", "spoilageAllowance" }
                or { "number", "sheetCount", "requiredLifts", "price" }
            local valid, shapeError = Runtime.shape(value[index], rowLabel, required)
            if not valid then return nil, shapeError end
            local number, fieldError = Runtime.integerInRange(value[index].number, 1, 5, rowLabel .. ".number")
            if not number then return nil, fieldError end
            if seen[number] then return nil, label .. " contains a duplicate row number" end
            seen[number] = true
            local sheetCount
            sheetCount, fieldError = Runtime.integerInRange(
                value[index].sheetCount, 1, 3000, rowLabel .. ".sheetCount")
            if not sheetCount then return nil, fieldError end
            local requiredLifts
            requiredLifts, fieldError = Runtime.integerInRange(
                value[index].requiredLifts, 1, 1000, rowLabel .. ".requiredLifts")
            if not requiredLifts then return nil, fieldError end
            local row = {
                number = number,
                sheetCount = sheetCount,
                requiredLifts = requiredLifts,
            }
            if printJob then
                row.requestedCopies, fieldError = Runtime.integerInRange(
                    value[index].requestedCopies, 1, 3000, rowLabel .. ".requestedCopies")
                if not row.requestedCopies then return nil, fieldError end
                row.spoilageAllowance, fieldError = Runtime.integerInRange(
                    value[index].spoilageAllowance, 0, 3000, rowLabel .. ".spoilageAllowance")
                if row.spoilageAllowance == nil then return nil, fieldError end
                if row.requestedCopies + row.spoilageAllowance ~= sheetCount then
                    return nil, rowLabel .. " copy counts do not match sheetCount"
                end
            else
                row.price, fieldError = Runtime.numberInRange(
                    value[index].price, 0, Runtime.MAX_WORKSHOP_AMOUNT, rowLabel .. ".price")
                if row.price == nil then return nil, fieldError end
            end
            rows[#rows + 1] = row
        end
        table.sort(rows, function(a, b) return a.number < b.number end)
        for index, row in ipairs(rows) do
            if row.number ~= index then return nil, label .. " row numbers must be contiguous" end
        end
        return Runtime.Codec.array(rows)
    end

    function Runtime.normalizeReceptionWorkshopView(value, label)
        local valid, shapeError = Runtime.shape(value, label, {
            "jobId", "company", "sourceSize", "finishedSize", "stock", "packaging",
            "delivery", "artworkKey", "artworkName", "printJob", "quoteRows",
            "recommendedTotal",
        }, { "colorCount", "colorSequence", "difficulty" })
        if not valid then return nil, shapeError end
        local jobId, fieldError = Runtime.token(value.jobId, Runtime.MAX_TOKEN_BYTES, label .. ".jobId")
        if not jobId then return nil, fieldError end
        local company
        company, fieldError = Runtime.printableString(
            value.company, 1, Runtime.MAX_WORKSHOP_VIEW_TEXT_BYTES, label .. ".company")
        if not company then return nil, fieldError end
        local sourceSize
        sourceSize, fieldError = Runtime.normalizeWorkshopSize(value.sourceSize, label .. ".sourceSize")
        if not sourceSize then return nil, fieldError end
        local finishedSize
        finishedSize, fieldError = Runtime.normalizeWorkshopSize(value.finishedSize, label .. ".finishedSize")
        if not finishedSize then return nil, fieldError end
        local stock
        stock, fieldError = Runtime.printableString(
            value.stock, 1, Runtime.MAX_WORKSHOP_VIEW_TEXT_BYTES, label .. ".stock")
        if not stock then return nil, fieldError end
        local packaging
        packaging, fieldError = Runtime.workshopPackaging(value.packaging, label .. ".packaging")
        if not packaging then return nil, fieldError end
        local delivery
        delivery, fieldError = Runtime.printableString(
            value.delivery, 1, Runtime.MAX_WORKSHOP_VIEW_TEXT_BYTES, label .. ".delivery")
        if not delivery then return nil, fieldError end
        local artworkKey
        artworkKey, fieldError = Runtime.token(value.artworkKey, Runtime.MAX_TOKEN_BYTES, label .. ".artworkKey")
        if not artworkKey then return nil, fieldError end
        local artworkName
        artworkName, fieldError = Runtime.printableString(
            value.artworkName, 1, Runtime.MAX_WORKSHOP_VIEW_TEXT_BYTES, label .. ".artworkName")
        if not artworkName then return nil, fieldError end
        if type(value.printJob) ~= "boolean" then return nil, label .. ".printJob must be boolean" end
        if value.difficulty~=nil and value.difficulty~="easy"
            and value.difficulty~="medium" and value.difficulty~="hard" then
            return nil,label .. ".difficulty must be easy, medium, or hard"
        end
        local colorCount,colorSequence
        if value.colorCount~=nil then
            colorCount,fieldError=Runtime.integerInRange(value.colorCount,1,4,label..".colorCount")
            if not colorCount or not value.printJob then return nil,fieldError or "Unexpected press colors." end
        end
        if value.colorSequence~=nil then
            colorSequence,fieldError=Runtime.printableString(value.colorSequence,1,96,label..".colorSequence")
            if not colorSequence or not value.printJob then return nil,fieldError or "Unexpected press colors." end
        end
        local quoteRows
        quoteRows, fieldError = Runtime.normalizeWorkshopQuoteRows(
            value.quoteRows, value.printJob, label .. ".quoteRows")
        if not quoteRows then return nil, fieldError end
        local recommendedTotal
        recommendedTotal, fieldError = Runtime.numberInRange(
            value.recommendedTotal, 0, Runtime.MAX_WORKSHOP_AMOUNT, label .. ".recommendedTotal")
        if recommendedTotal == nil then return nil, fieldError end
        return {
            jobId = jobId,
            company = company,
            difficulty = value.difficulty,
            sourceSize = sourceSize,
            finishedSize = finishedSize,
            stock = stock,
            packaging = packaging,
            delivery = delivery,
            artworkKey = artworkKey,
            artworkName = artworkName,
            printJob = value.printJob,
            colorCount = colorCount,
            colorSequence = colorSequence,
            quoteRows = quoteRows,
            recommendedTotal = recommendedTotal,
        }
    end
end

return Component
