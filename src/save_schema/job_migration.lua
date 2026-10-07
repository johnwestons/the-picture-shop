-- Legacy print jobs, plates, and Windmill state migration.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    Runtime.actualFields = {
        "plateCost", "inHousePlates", "inkUnits", "tympanSheets", "washUnits",
        "proofs", "impressions", "spoilage", "pressHours", "supplyCost",
    }

    function Runtime.normalizePlate(job, press, colorIndex)
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
        if plate.artworkSize == nil then plate.artworkSize = Runtime.copy(press.artworkSize or job.finishedSize) end
        if plate.status == nil then plate.status = "unprepared" end
        if plate.quality == nil then plate.quality = 0 end
        if plate.life == nil then plate.life = 1 end
        if plate.processStep == nil then plate.processStep = 1 end
        if plate.processScores == nil then plate.processScores = {} end
        if plate.mounted == nil then plate.mounted = false end
    end

    function Runtime.normalizePrintJob(job)
        local press = job.press
        if type(press) ~= "table" then return end
        Runtime.normalizeArtwork(job, true)
        Runtime.normalizeStockSpec(job, true)
        if press.colors == nil then press.colors = 1 end
        if press.coverage == nil then press.coverage = 0.4 end
        if press.artworkSize == nil then press.artworkSize = Runtime.copy(job.finishedSize) end
        if press.colorSequence == nil then press.colorSequence = {} end
        if type(press.colorSequence) == "table" and Runtime.positiveInteger(press.colors) then
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
                    if palletAllowance == nil and Runtime.number(pallet.initialSheets) and Runtime.number(requested) then
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
                            local priorPassSheets = Runtime.number(pallet.finishedSheets)
                                and pallet.finishedSheets > 0 and pallet.finishedSheets
                                or pallet.press.goodSheets
                            pallet.press.availableSheets = pallet.press.completedColors > 0
                                and priorPassSheets or pallet.initialSheets
                        end
                        if pallet.press.spoilage == nil then pallet.press.spoilage = 0 end
                        if pallet.press.passHistory == nil then pallet.press.passHistory = {} end
                    end
                    if Runtime.number(requested) then ordered = ordered + requested end
                    if Runtime.number(pallet.initialSheets) then
                        supplied = supplied + math.max(0,
                            pallet.initialSheets - (tonumber(pallet.damagedSheets) or 0))
                    end
                    if Runtime.number(palletAllowance) then allowance = allowance + palletAllowance end
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
        if type(press.plates) == "table" and Runtime.positiveInteger(press.colors) then
            for colorIndex = 1, press.colors do Runtime.normalizePlate(job, press, colorIndex) end
        end
        if press.actual == nil then press.actual = {} end
        if type(press.actual) == "table" then
            for _, field in ipairs(Runtime.actualFields) do
                if press.actual[field] == nil then press.actual[field] = 0 end
            end
        end
    end

    function Runtime.normalizeJob(savedJob)
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
                    if pallet.paper == nil and Runtime.text(pallet.id)
                        and Runtime.dimensions(savedJob.sourceSize) and Runtime.dimensions(savedJob.finishedSize)
                    then
                        pallet.paper = Runtime.PaperWork.create(savedJob, pallet, savedJob.difficulty, index)
                    end
                end
            end
        end
        Runtime.normalizeArtwork(savedJob, false)
        Runtime.normalizeStockSpec(savedJob, false)
        Runtime.normalizePrintJob(savedJob)
    end

    function Runtime.normalizeJobs(jobs)
        for _, collectionName in ipairs({ "active", "completed", "declined" }) do
            local collection = type(jobs[collectionName]) == "table" and jobs[collectionName] or {}
            jobs[collectionName] = collection
            for _, savedJob in ipairs(collection) do Runtime.normalizeJob(savedJob) end
        end
    end

    function Runtime.normalizeEmailJobs(emails)
        if type(emails) ~= "table" then return end
        for _, collectionName in ipairs({ "pending", "inbox" }) do
            if type(emails[collectionName]) == "table" then
                for _, email in ipairs(emails[collectionName]) do
                    if type(email) == "table" then Runtime.normalizeJob(email.job) end
                end
            end
        end
    end

    function Runtime.normalizeWindmillProcess(value, state)
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
            if value.feedRemaining == nil and Runtime.number(available) and Runtime.number(value.counter) then
                value.feedRemaining = math.max(0, available - value.counter)
            end
            if value.artworkVerified == nil and value.proofApproved ~= nil then
                value.artworkVerified = value.proofApproved == true
            end
        end
        return value
    end
end

return Component
