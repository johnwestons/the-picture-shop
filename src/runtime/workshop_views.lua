-- Host-side workshop views and argument checks.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.exactArguments(arguments, required, optional)
        if type(arguments) ~= "table" then return false end
        local allowed = {}
        for _, name in ipairs(required or {}) do allowed[name] = true end
        for _, name in ipairs(optional or {}) do allowed[name] = true end
        for key in pairs(arguments) do
            if type(key) ~= "string" or not allowed[key] then return false end
        end
        for _, name in ipairs(required or {}) do
            if arguments[name] == nil then return false end
        end
        return true
    end

    function Runtime.machineRelocationActive()
        return Runtime.state.cutter and Runtime.state.cutter.moving
            or Runtime.state.wrapper and Runtime.state.wrapper.moving
            or Runtime.state.windmill and Runtime.state.windmill.moving
    end

    function Runtime.customerView(offer)
        local rows = {}
        for _, row in ipairs((offer.quote and offer.quote.pallets) or {}) do
            local projected = {
                number = math.floor(tonumber(row.number) or (#rows + 1)),
                sheetCount = math.floor(tonumber(row.sheetCount) or 0),
                requiredLifts = math.floor(tonumber(row.requiredLifts) or 0),
            }
            if offer.press then
                projected.requestedCopies = math.floor(tonumber(row.requestedCopies) or 0)
                projected.spoilageAllowance = math.floor(tonumber(row.spoilageAllowance)
                    or math.max(0, projected.sheetCount - projected.requestedCopies))
            else
                projected.price = math.floor(tonumber(row.price) or 0)
            end
            rows[#rows + 1] = projected
        end
        local stock = offer.stockSpec and offer.stockSpec.description
            or offer.details and offer.details.stockDescription or "Customer-supplied paper"
        local artwork = offer.artwork or {}
        return {
            jobId = tostring(offer.id),
            company = tostring(offer.company),
            difficulty = offer.difficulty,
            sourceSize = { width = offer.sourceSize.width, height = offer.sourceSize.height },
            finishedSize = { width = offer.finishedSize.width, height = offer.finishedSize.height },
            stock = tostring(stock),
            packaging = offer.packaging == "boxed" and "boxed" or "flat",
            delivery = tostring(Runtime.JobService.deliverySummary(offer)),
            artworkKey = tostring(artwork.key or offer.artworkKey or "flower"),
            artworkName = tostring(artwork.displayName or artwork.fileName
                or offer.artworkKey or "Client artwork"),
            printJob = offer.press ~= nil,
            colorCount = offer.press and offer.press.colors or nil,
            colorSequence = offer.press and table.concat(offer.press.colorSequence or {}, " then ") or nil,
            quoteRows = rows,
            recommendedTotal = math.floor(tonumber(offer.quote and
                (offer.quote.recommendedPrice or offer.quote.totalPrice)) or 0),
        }
    end

    function Runtime.wrapperPalletView()
        local pallets = {}
        for _, item in ipairs(Runtime.Wrapper.nearbyPallets(Runtime.state)) do
            pallets[#pallets + 1] = {
                palletId = tostring(item.pallet.id),
                jobLabel = tostring((item.job.company or "Client") .. " · " .. item.job.id),
                packaging = item.pallet.packaging == "boxed" and "boxed" or "flat",
                distance = math.sqrt(math.max(0, tonumber(item.distance) or 0)),
            }
            if #pallets >= 5 then break end
        end
        return pallets
    end

    function Runtime.wrapperView(detailed)
        local runtime = Runtime.Wrapper.snapshot()
        local view = {
            step = runtime.step,
            progress = runtime.progress,
            cycleTime = runtime.cycleTime,
            pallets = Runtime.wrapperPalletView(),
            selectedPalletId = runtime.selectedPalletId,
            palletId = runtime.palletId,
        }
        if detailed ~= false then
            view.plasticWrapRolls = math.max(0,
                math.floor(tonumber(Runtime.state.inventory.plasticWrapRolls) or 0))
            view.plasticWrapUses = math.max(0,
                math.floor(tonumber(Runtime.state.inventory.plasticWrapUses) or 0))
        end
        return view
    end

    function Runtime.wrapperSnapshotView()
        if Runtime.wrapperMaintenanceAuthority then
            return Runtime.wrapperMaintenanceAuthority.view(Runtime.activeWrapperRemote, false)
        end
        return Runtime.wrapperView(false)
    end

    function Runtime.cutterView(includeCandidates)
        return Runtime.Machine.networkView(Runtime.state, includeCandidates == true)
    end

    function Runtime.cutterNoArguments(arguments)
        if not Runtime.exactArguments(arguments, {}) then
            return nil, "invalid_arguments", "That cutter action takes no additional data."
        end
        return {}
    end

    function Runtime.performCutterAction(player, operation, durable)
        local allowed, code, accessMessage = Runtime.World.validateNetworkWorkshopAccess(
            player, Runtime.state, Runtime.state._activeWorkshopResourceId or "cutter")
        if not allowed then
            return false, code, accessMessage, Runtime.cutterView(true)
        end
        local previousMessage = Runtime.state.message
        local accepted = operation() == true
        local resultMessage = Runtime.state.message
        if resultMessage == nil or resultMessage == previousMessage then
            resultMessage = accepted and "Cutter action completed."
                or "The cutter is not ready for that action."
        end
        if accepted and durable then Runtime.saveCurrent() end
        return accepted, accepted and "completed" or "machine_blocked",
            tostring(resultMessage or (accepted and "Cutter action completed."
                or "The cutter rejected that action.")), Runtime.cutterView(true)
    end

    function Runtime.findActiveJob(jobId)
        for _, job in ipairs((Runtime.state.jobs and Runtime.state.jobs.active) or {}) do
            if job.id == jobId then return job end
        end
    end

    Runtime.UINT32_MAX = 4294967295

    function Runtime.uint32(value)
        return math.max(0, math.min(Runtime.UINT32_MAX, math.floor(tonumber(value) or 0)))
    end

    function Runtime.windmillRuntimeClock()
        if love and love.timer and love.timer.getTime then return love.timer.getTime() end
        return os.clock()
    end

    function Runtime.windmillPlateMarkerPermille()
        return math.max(0, math.min(1000,
            math.floor(((math.sin(Runtime.windmillRuntimeClock() * 2.2) + 1) * 500) + 0.5)))
    end

    function Runtime.findPlateById(plateId)
        for _, job in ipairs((Runtime.state.jobs and Runtime.state.jobs.active) or {}) do
            if job.press then
                for colorIndex, plate in ipairs(Runtime.PlateService.ensureJob(job)) do
                    if plate.id == plateId then return job, plate, colorIndex end
                end
            end
        end
    end

    function Runtime.windmillView(session)
        local process, job = Runtime.Windmill.current(Runtime.state)
        local setupPermille = {}
        for index, task in ipairs(Runtime.Windmill.setupTasks()) do
            setupPermille[index] = math.max(0, math.min(1000,
                math.floor((tonumber(process.setup[task]) or 0) * 1000 + 0.5)))
        end
        local candidates = {}
        for _, item in ipairs(Runtime.Windmill.candidates(Runtime.state)) do
            candidates[#candidates + 1] = {
                palletId = tostring(item.pallet.id),
                colorIndex = math.max(1, math.min(4, math.floor(tonumber(item.color) or 1))),
            }
            if #candidates >= 3 then break end
        end
        local view = {
            runtimeRevision = Runtime.uint32(Runtime.Windmill.networkRuntimeRevision()),
            status = tostring(process.status),
            speed = math.max(1000, math.min(5500, math.floor(tonumber(process.speed) or 3000))),
            motor = process.motor == true,
            feeder = process.feeder == true,
            impression = process.impression == true,
            emergency = process.emergency == true,
            counter = Runtime.uint32(process.counter),
            goodSheets = Runtime.uint32(process.goodSheets),
            spoilage = Runtime.uint32(process.spoilage),
            targetSheets = Runtime.uint32(process.targetSheets),
            feedStart = Runtime.uint32(process.feedStart),
            feedRemaining = Runtime.uint32(process.feedRemaining),
            proofApproved = process.proofApproved == true,
            artworkVerified = process.artworkVerified == true,
            setupPermille = setupPermille,
            candidates = candidates,
            serviceStep = "idle",
            servicePermille = 0,
            plateMarkerPermille = Runtime.windmillPlateMarkerPermille(),
        }
        if process.jobId then view.jobId = tostring(process.jobId) end
        if process.palletId then view.palletId = tostring(process.palletId) end
        if process.colorIndex then
            view.colorIndex = math.max(1, math.min(4, math.floor(process.colorIndex)))
        end
        if job and job.press then
            view.colorCount = math.max(1, math.min(4,
                math.floor(tonumber(job.press.colors) or 1)))
        end
        if process.proofQuality ~= nil then
            view.proofPermille = math.max(0, math.min(1000,
                math.floor((tonumber(process.proofQuality) or 0) * 1000 + 0.5)))
        end
        local warning = process.warning or Runtime.Windmill.failureSummary(Runtime.state)
        if warning then view.warning = tostring(warning) end
        if type(session) == "table" then
            if session.setupGame and session.setupTask then
                view.warning = nil
                view.setupTask = session.setupTask
                view.setupSummary = session.setupTask == "feeder" and Runtime.PressSetupGames.instruction(session.setupGame)
                    or Runtime.PressSetupGames.summary(session.setupGame)
                view.setupVisual = require("src.press_setup_view").encode(session.setupGame)
            end
            if session.maintenance then
                view.warning = nil
                local step = math.max(1, math.floor(tonumber(session.lockoutStep) or 1))
                if step == 1 then view.serviceStep = "lockout_disconnect"
                elseif step == 2 then view.serviceStep = "lockout_key"
                elseif step == 3 then view.serviceStep = "lockout_tag"
                else view.serviceStep = "task" end
                if step <= 3 then
                    view.servicePermille = (step - 1) * 80
                else
                    view.servicePermille = math.max(0, math.min(1000,
                        math.floor(250 + Runtime.MachineMaintenance.progress(session.maintenance) * 750 + 0.5)))
                    local task = Runtime.MachineMaintenance.activeTask(session.maintenance)
                    if task then view.serviceTask = tostring(task.label or task.id) end
                end
            end
        end
        return view
    end

    function Runtime.windmillNoArguments(arguments)
        if not Runtime.exactArguments(arguments, {}) then
            return nil, "invalid_arguments", "That Windmill action takes no additional data."
        end
        return {}
    end

    function Runtime.windmillTokenArguments(field, invalidCode, invalidMessage)
        return function(arguments)
            local value = type(arguments) == "table" and arguments[field]
            if not Runtime.exactArguments(arguments, { field }) or type(value) ~= "string"
                or #value < 1 or #value > 64
                or not value:match("^[A-Za-z0-9][A-Za-z0-9_.%-]*$")
            then
                return nil, invalidCode, invalidMessage
            end
            return { [field] = value }
        end
    end

    function Runtime.performWindmillAction(player, lease, operation, durable, allowDuringService)
        local allowed, code, accessMessage = Runtime.World.validateNetworkWorkshopAccess(
            player, Runtime.state, Runtime.state._activeWorkshopResourceId or "windmill")
        if not allowed then
            return false, code, accessMessage, Runtime.windmillView(lease and lease.private)
        end
        local session = lease and lease.private
        if session and session.maintenance and not allowDuringService then
            return false, "service_active",
                "Finish or release the active Windmill service lockout before operating the press.",
                Runtime.windmillView(session)
        end
        local previousMessage = Runtime.state.message
        local accepted, detail = operation()
        accepted = accepted == true
        local resultMessage
        if type(detail) == "string" then resultMessage = detail end
        if not resultMessage and Runtime.state.message ~= nil and Runtime.state.message ~= previousMessage then
            resultMessage = tostring(Runtime.state.message)
        end
        if not resultMessage then
            resultMessage = accepted and "Windmill action completed."
                or "The Windmill is not ready for that action."
        end
        Runtime.state.message = resultMessage
        if accepted and durable then Runtime.saveCurrent() end
        return accepted, accepted and "completed" or "machine_blocked",
            resultMessage, Runtime.windmillView(lease and lease.private)
    end

    function Runtime.windmillSimpleCommand(operation, durable, allowDuringService)
        return {
            normalize = Runtime.windmillNoArguments,
            perform = function(lease, player)
                return Runtime.performWindmillAction(player, lease,
                    function() return operation(Runtime.state) end, durable ~= false,
                    allowDuringService == true)
            end,
        }
    end
end

return Component
