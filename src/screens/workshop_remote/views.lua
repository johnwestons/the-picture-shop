-- Merging host views and selecting work candidates.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.activeJobs(state)
        local rows = {}
        for _, job in ipairs((state.jobs and state.jobs.active) or {}) do
            rows[#rows + 1] = job
            if #rows >= 6 then break end
        end
        return rows
    end

    function Runtime.wrapperRows(state)
        local rows = {}
        if Runtime.Screen.view and type(Runtime.Screen.view.pallets) == "table" then
            for _, item in ipairs(Runtime.Screen.view.pallets) do rows[#rows + 1] = item end
            return rows
        end
        for _, item in ipairs(Runtime.Wrapper.nearbyPallets(state)) do
            rows[#rows + 1] = {
                palletId = item.pallet.id,
                jobLabel = item.job and ((item.job.company or "Client") .. " · " .. item.job.id)
                    or "Client pallet",
                packaging = item.pallet.packaging or "flat",
            }
            if #rows >= 6 then break end
        end
        return rows
    end

    function Runtime.selectedWrapperPallet(rows)
        if Runtime.Screen.selectedPalletId == nil then return nil end
        for _, item in ipairs(rows) do
            if item.palletId == Runtime.Screen.selectedPalletId then return item end
        end
        return nil
    end

    Runtime.WRAPPER_SERVICE_COPY = {
        turntableBearing = {
            component = "TURNTABLE BEARING",
            instruction = "Grease the three bearing fittings around the turntable in order.",
            points = { { 300, 346 }, { 420, 408 }, { 538, 344 } },
        },
        filmCarriage = {
            component = "FILM CARRIAGE",
            instruction = "Follow the carriage service points from the upper roller to the lower guide.",
            points = { { 404, 224 }, { 404, 316 }, { 404, 408 } },
        },
        driveBelt = {
            component = "DRIVE BELT",
            instruction = "Tap the moving tension marker as it crosses the service bay.",
        },
        controlBoard = {
            component = "CONTROL BOARD",
            instruction = "Test the cabinet points in order: power, safety loop, then reset.",
            points = { { 470, 234 }, { 520, 322 }, { 556, 410 } },
        },
    }

    function Runtime.wrapperServiceTarget(view)
        local task = Runtime.WRAPPER_SERVICE_COPY[tostring(view and view.serviceTaskId or "")]
        local phase = math.max(1, math.floor(tonumber(view and view.servicePhase) or 1))
        if not task then return nil end
        local x, y
        if view.serviceTaskId == "driveBelt" then
            x = 380 + math.sin((Runtime.Screen.wrapperClock or 0) * 1.8) * 150
            y = 376
        else
            local point = task.points and task.points[phase]
            if point then x, y = point[1], point[2] end
        end
        if not x or not y then return nil end
        return { x = x - 30, y = y - 30, width = 60, height = 60 }, task
    end

    function Runtime.mergeWrapperView(incoming)
        if type(incoming) ~= "table" then return false end
        local merged = Runtime.Screen.view or {}
        for key, value in pairs(incoming) do merged[key] = value end
        if incoming.serviceStep == nil then
            for _, field in ipairs({
                "serviceStep", "serviceTaskId", "serviceTaskIndex", "serviceTaskCount",
                "servicePhase", "serviceTargetCount", "serviceAttempts", "serviceMisses",
                "servicePermille",
            }) do
                merged[field] = nil
            end
        end
        Runtime.Screen.view = merged
        Runtime.Screen.selectedPalletId = incoming.selectedPalletId
        return true
    end

    function Runtime.cutterPalletLabel(state, palletId)
        for _, job in ipairs((state and state.jobs and state.jobs.active) or {}) do
            for _, pallet in ipairs(job.pallets or {}) do
                if pallet.id == palletId then
                    return string.format("%s · %s", tostring(job.company or "Client"),
                        tostring(job.id or palletId))
                end
            end
        end
        return tostring(palletId or "Pallet")
    end

    function Runtime.cutterRuntimeRevision(view)
        return type(view) == "table" and tonumber(view.runtimeRevision) or nil
    end

    function Runtime.syncCutterGauge(force)
        if Runtime.Screen.resourceId ~= "cutter" or (Runtime.Screen.gaugeFocused and not force) then return end
        local centi = math.max(0, math.floor(tonumber(Runtime.Screen.view and Runtime.Screen.view.gaugeCentiInch) or 0))
        Runtime.Screen.gaugeText = string.format("%.2f", centi / 100)
        Runtime.Screen.gaugeReplaceOnType = true
    end

    function Runtime.mergeCutterView(incoming)
        if type(incoming) ~= "table" then return false end
        local incomingRevision = Runtime.cutterRuntimeRevision(incoming)
        local currentRevision = Runtime.cutterRuntimeRevision(Runtime.Screen.view) or -1
        if incomingRevision == nil or incomingRevision < currentRevision then return false end
        local merged = Runtime.Screen.view or {}
        for key, value in pairs(incoming) do merged[key] = value end
        if incoming.serviceStep == nil then
            for _, field in ipairs({
                "serviceStep", "servicePermille", "serviceView", "serviceTool",
                "serviceItems", "centralInstalled", "gearInspected", "gearLevelPermille",
                "bladeBoltsDone", "bladeBoltMask",
            }) do
                merged[field] = nil
            end
        end
        if incoming.paper ~= nil then
            merged.candidates, merged.genericSheets = nil, nil
        elseif incoming.loaded == false then
            merged.paper = nil
            if incoming.candidates ~= nil and incoming.genericSheets == nil then
                merged.genericSheets = nil
            end
        end
        Runtime.Screen.view = merged
        Runtime.Screen.cutterPresentation:accept(merged)
        Runtime.syncCutterGauge(false)
        return true
    end

    function Runtime.cutterResourceRevision(snapshot)
        local direct = tonumber(snapshot.resourceRevision)
        if direct then return direct end
        local cutter = snapshot.cutter or snapshot.view or snapshot.data
        direct = type(cutter) == "table" and tonumber(cutter.resourceRevision) or nil
        if direct then return direct end
        for _, record in ipairs(snapshot.resources or {}) do
            if record.resourceId == (Runtime.Screen.leaseResourceId or "cutter") then
                return tonumber(record.revision)
            end
        end
        return nil
    end

    function Runtime.windmillRuntimeRevision(view)
        return type(view) == "table" and tonumber(view.runtimeRevision) or nil
    end

    function Runtime.mergeWindmillView(incoming)
        if type(incoming) ~= "table" then return false end
        local incomingRevision = Runtime.windmillRuntimeRevision(incoming)
        local currentRevision = Runtime.windmillRuntimeRevision(Runtime.Screen.view) or -1
        if incomingRevision == nil or incomingRevision < currentRevision then return false end
        local merged = {}
        for key, value in pairs(incoming) do merged[key] = value end
        Runtime.Screen.view = merged
        return true
    end

    function Runtime.windmillResourceRevision(snapshot)
        local direct = tonumber(snapshot.resourceRevision)
        if direct then return direct end
        local windmill = snapshot.windmill or snapshot.view or snapshot.data
        direct = type(windmill) == "table" and tonumber(windmill.resourceRevision) or nil
        if direct then return direct end
        for _, record in ipairs(snapshot.resources or {}) do
            if record.resourceId == (Runtime.Screen.leaseResourceId or "windmill") then
                return tonumber(record.revision)
            end
        end
        return nil
    end

    function Runtime.windmillCandidates()
        local rows = {}
        for _, candidate in ipairs((Runtime.Screen.view and Runtime.Screen.view.candidates) or {}) do
            rows[#rows + 1] = candidate
            if #rows >= 3 then break end
        end
        return rows
    end

    function Runtime.windmillPressJobs(state)
        local rows = {}
        for _, job in ipairs((state and state.jobs and state.jobs.active) or {}) do
            if type(job.press) == "table" then
                rows[#rows + 1] = job
                if #rows >= 5 then break end
            end
        end
        return rows
    end

    function Runtime.windmillSelectedJob(state)
        local jobs = Runtime.windmillPressJobs(state)
        local selected
        for _, job in ipairs(jobs) do
            if job.id == Runtime.Screen.windmillJobId then selected = job; break end
        end
        selected = selected or jobs[1]
        Runtime.Screen.windmillJobId = selected and selected.id or nil
        return selected, jobs
    end

    function Runtime.windmillSelectedPlate(state)
        local job, jobs = Runtime.windmillSelectedJob(state)
        local plates = job and job.press and job.press.plates or {}
        local selected
        for _, plate in ipairs(plates) do
            if plate.id == Runtime.Screen.windmillPlateId then selected = plate; break end
        end
        selected = selected or plates[1]
        Runtime.Screen.windmillPlateId = selected and selected.id or nil
        return selected, plates, job, jobs
    end

    function Runtime.windmillSetupComplete(view)
        for _, score in ipairs((view and view.setupPermille) or {}) do
            if (tonumber(score) or 0) <= 0 then return false end
        end
        return type(view and view.setupPermille) == "table" and #view.setupPermille == 6
    end

    function Runtime.windmillActivePlateReady(state, view)
        if not view or not view.jobId or not view.colorIndex then return false end
        for _, job in ipairs((state and state.jobs and state.jobs.active) or {}) do
            if job.id == view.jobId then
                local plate = job.press and job.press.plates and job.press.plates[view.colorIndex]
                return type(plate) == "table" and plate.status == "ready"
                    and plate.mounted == true and (tonumber(plate.life) or 0) > 0
            end
        end
        return false
    end

    function Runtime.cutterCandidates()
        local rows = {}
        for _, candidate in ipairs((Runtime.Screen.view and Runtime.Screen.view.candidates) or {}) do
            rows[#rows + 1] = candidate
            if #rows >= 3 then break end
        end
        return rows
    end

    function Runtime.rowRect(index)
        return { x = Runtime.ROW_X, y = Runtime.ROW_Y + (index - 1) * (Runtime.ROW_H + Runtime.ROW_GAP), width = Runtime.ROW_W, height = Runtime.ROW_H }
    end

    function Runtime.wrapperRowRect(index)
        return { x = Runtime.ROW_X, y = 214 + (index - 1) * (Runtime.ROW_H + 4), width = Runtime.ROW_W, height = Runtime.ROW_H }
    end

    function Runtime.vendorBuyRect(index)
        local itemRow = Runtime.rowRect(index)
        return {
            x = itemRow.x + itemRow.width - 146,
            y = itemRow.y + 5,
            width = 132,
            height = itemRow.height - 10,
        }
    end

    function Runtime.vendorRows()
        local rows = {}
        for _, item in ipairs((Runtime.Screen.view and Runtime.Screen.view.items) or {}) do
            rows[#rows + 1] = item
            if #rows >= 5 then break end
        end
        return rows
    end
end

return Component
