-- Remote console entry, result application, and snapshots.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.Screen.enter(grant, state)
        Runtime.Screen.leaseResourceId = grant and grant.resourceId or nil
        Runtime.Screen.resourceId = Runtime.MachineResource.parse(Runtime.Screen.leaseResourceId)
            or Runtime.Screen.leaseResourceId
        Runtime.Screen.leaseId = grant and grant.leaseId or nil
        Runtime.Screen.revision = tonumber(grant and grant.revision) or 0
        Runtime.Screen.workshopTick = 0
        local incomingView = grant and (grant.view or grant.data) or nil
        Runtime.Screen.view = nil
        if Runtime.Screen.resourceId == "windmill" then
            Runtime.mergeWindmillView(incomingView)
        elseif Runtime.Screen.resourceId == "skid_wrapper" then
            Runtime.mergeWrapperView(incomingView)
        else
            Runtime.Screen.view = incomingView
        end
        Runtime.Screen.quoteText = tostring(Runtime.Screen.view and Runtime.Screen.view.recommendedTotal or "")
        Runtime.Screen.quoteFocused = false
        Runtime.Screen.quoteReplaceOnType = true
        Runtime.Screen.selectedJobId = nil
        Runtime.Screen.selectedPalletId = Runtime.Screen.view and Runtime.Screen.view.selectedPalletId or nil
        Runtime.Screen.waiting = false
        Runtime.Screen.safetyWaiting = false
        Runtime.Screen.status = tostring(grant and grant.message or "Remote console ready.")
        Runtime.Screen.gaugeFocused = false
        Runtime.Screen.gaugeReplaceOnType = true
        Runtime.Screen.cutterTab = "production"
        Runtime.Screen.cutterPresentation = Runtime.CutterPresentation.new()
        if Runtime.Screen.resourceId == "cutter" then Runtime.Screen.cutterPresentation:accept(Runtime.Screen.view) end
        Runtime.Screen.wrapperTab = "production"
        Runtime.Screen.wrapperClock = 0
        Runtime.Screen.windmillTab = "run"
        Runtime.Screen.windmillJobId, Runtime.Screen.windmillPlateId = nil, nil
        Runtime.syncCutterGauge(true)
        if Runtime.Screen.resourceId == "work_phone" then Runtime.WorkPhoneScreen.enter(Runtime.Projection.copy(state)) end
        Runtime.Screen.hostLayout = grant and grant.useHostLayout == true
        Runtime.Screen.sharedMachine = nil
        if Runtime.Screen.hostLayout and (Runtime.Screen.resourceId == "cutter" or Runtime.Screen.resourceId == "skid_wrapper") then
            Runtime.Screen.sharedMachine = Runtime.SharedMachineGui.new(Runtime.Screen.resourceId, function() return Runtime.Screen.view end,
                Runtime.Screen.cutterPresentation, function(action,args) return Runtime.request(Runtime.Screen.sendCommand,action,args) end)
            Runtime.Screen.sharedMachine.sync(state)
        end
        Runtime.Screen.sharedComputer, Runtime.Screen.officePending = nil, nil
        Runtime.Screen.sharedPress = nil
        if Runtime.Screen.hostLayout and Runtime.Screen.resourceId == "windmill" then
            Runtime.Screen.sharedPress=Runtime.SharedPressGui.new(function() return Runtime.Screen.view end,
                function(action,args) return Runtime.request(Runtime.Screen.sendCommand,action,args) end)
        end
        if Runtime.Screen.resourceId == "office_computer" then
            Runtime.Screen.guiState = Runtime.Projection.copy(state)
            Runtime.Screen.sharedComputer = Runtime.ComputerScreen.new({
                warehouseEnabled = Runtime.Config.warehouse and Runtime.Config.warehouse.enabled == true,
                warehouseFirstStorageOnly = Runtime.Config.warehouse and Runtime.Config.warehouse.firstStorageOnly == true,
                warehouseRequestPrefix = "WH-" .. tostring(Runtime.Screen.leaseId or "guest"),
                remoteCommand = function(intent)
                if Runtime.Screen.waiting then return false end
                local normalized, errorMessage = Runtime.OfficeIntent.normalize(intent)
                if not normalized then Runtime.Screen.status = errorMessage; return false end
                Runtime.Screen.officePending = intent.kind
                return Runtime.request(Runtime.Screen.sendCommand, "office_action", { officeIntent = normalized })
            end })
            Runtime.Screen.sharedComputer.enter(Runtime.Screen.guiState)
        end
        if state then state.screen = "workshop_remote" end
        return Runtime.Screen.resourceId ~= nil and Runtime.Screen.leaseId ~= nil
    end

    function Runtime.Screen.clear()
        Runtime.Screen.sharedPress = nil
        Runtime.Screen.sharedMachine = nil
        Runtime.Screen.sharedComputer, Runtime.Screen.guiState, Runtime.Screen.sendCommand, Runtime.Screen.officePending = nil, nil, nil, nil
        Runtime.Screen.cutterPresentation = Runtime.CutterPresentation.new()
        Runtime.Screen.resourceId, Runtime.Screen.leaseResourceId, Runtime.Screen.leaseId, Runtime.Screen.view = nil, nil, nil, nil
        Runtime.Screen.quoteFocused, Runtime.Screen.waiting, Runtime.Screen.safetyWaiting = false, false, false
        Runtime.Screen.selectedJobId, Runtime.Screen.selectedPalletId = nil, nil
        Runtime.Screen.gaugeFocused, Runtime.Screen.gaugeReplaceOnType = false, true
        Runtime.Screen.cutterTab = "production"
        Runtime.Screen.wrapperTab = "production"
        Runtime.Screen.wrapperClock = 0
        Runtime.Screen.windmillTab = "run"
        Runtime.Screen.windmillJobId, Runtime.Screen.windmillPlateId = nil, nil
        Runtime.Screen.workshopTick = 0
    end

    function Runtime.Screen.isOpen() return Runtime.Screen.resourceId ~= nil and Runtime.Screen.leaseId ~= nil end
    function Runtime.Screen.canClose()
        return not Runtime.Screen.waiting and not Runtime.Screen.safetyWaiting
            and (Runtime.Screen.resourceId ~= "skid_wrapper" or (Runtime.Screen.view and Runtime.Screen.view.step or Runtime.Wrapper.step) ~= "wrapping")
            and (Runtime.Screen.resourceId ~= "windmill"
                or not Runtime.Screen.view or Runtime.Screen.view.status ~= "production")
    end
    function Runtime.Screen.hasMachineModal()
        return Runtime.Screen.sharedMachine and Runtime.Screen.sharedMachine.screen.hasModal() or false
    end
    function Runtime.Screen.wantsTextInput()
        if Runtime.Screen.sharedMachine then return Runtime.Screen.sharedMachine.screen.wantsTextInput() end
        if Runtime.Screen.sharedComputer then return Runtime.Screen.sharedComputer.wantsTextInput() end
        return Runtime.Screen.resourceId == "cutter" and Runtime.Screen.gaugeFocused
    end

    function Runtime.Screen.wrapperStartEnabled(state)
        return Runtime.Screen.resourceId == "skid_wrapper"
            and not Runtime.Screen.waiting
            and tostring(Runtime.Screen.view and Runtime.Screen.view.serviceStep or "idle") == "idle"
            and Runtime.Wrapper.step ~= "wrapping"
            and Runtime.selectedWrapperPallet(Runtime.wrapperRows(state)) ~= nil
    end

    function Runtime.wrapperServiceBeginEnabled(state)
        local stock = state and state.inventory and state.inventory.stock or {}
        local view = Runtime.Screen.view or {}
        return Runtime.Screen.resourceId == "skid_wrapper" and not Runtime.Screen.waiting
            and tostring(view.serviceStep or "idle") == "idle"
            and view.step ~= "wrapping" and #Runtime.wrapperRows(state) == 0
            and (tonumber(stock.maintenance_kit) or 0) > 0
    end

    function Runtime.Screen.applyResult(result)
        if type(result) ~= "table" or result.resourceId ~= Runtime.Screen.leaseResourceId then return false end
        if result.urgentSafety == true then
            Runtime.Screen.safetyWaiting = false
        else
            Runtime.Screen.waiting = false
        end
        local priorRevision = Runtime.Screen.revision
        local resultRevision = tonumber(result.revision)
        local resourceCurrent = resultRevision ~= nil and resultRevision >= priorRevision
        Runtime.Screen.revision = math.max(priorRevision, resultRevision or priorRevision)
        Runtime.Screen.status = tostring(result.message or (result.accepted and "Action completed." or "Action rejected."))
        if Runtime.Screen.sharedComputer and result.action == "office_action" then
            if Runtime.Screen.officePending == "buy_upgrade" or Runtime.Screen.officePending == "buy_forklift" then
                Runtime.Screen.sharedComputer.resolveWarehouse(result.accepted == true, Runtime.Screen.status)
            end
            if result.accepted then
                local computer = Runtime.Screen.sharedComputer
                if Runtime.Screen.officePending == "checkout" then computer.cart, computer.cartOpen = {}, false
                elseif Runtime.Screen.officePending == "promotion" then computer.promoJobId, computer.promoText = nil, ""
                elseif Runtime.Screen.officePending == "estimate" or Runtime.Screen.officePending == "decline"
                    or Runtime.Screen.officePending == "archive" or Runtime.Screen.officePending == "archive_service" then
                    computer.selectedEmailId, computer.emailSelectionRequired = nil, true
                end
            end
            Runtime.Screen.officePending = nil
        end
        if Runtime.Screen.resourceId == "cutter" then
            if resourceCurrent then Runtime.mergeCutterView(result.view or result.data) end
            if result.accepted and result.action == "cancel_service" then
                Runtime.Screen.cutterTab = "production"
            end
        elseif Runtime.Screen.resourceId == "windmill" then
            if resourceCurrent then Runtime.mergeWindmillView(result.view or result.data) end
        elseif Runtime.Screen.resourceId == "skid_wrapper" then
            Runtime.mergeWrapperView(result.view or result.data)
        elseif result.view or result.data then
            Runtime.Screen.view = result.view or result.data
        end
        if result.accepted and result.action == "select_pallet" then
            Runtime.Screen.selectedPalletId = result.palletId
                or (Runtime.Screen.view and Runtime.Screen.view.selectedPalletId) or Runtime.Screen.selectedPalletId
        end
        return true
    end

    function Runtime.Screen.applySnapshot(snapshot)
        if type(snapshot) ~= "table" then return false end
        Runtime.Screen.workshopTick = tonumber(snapshot.revision) or Runtime.Screen.workshopTick
        local wrapper = snapshot.wrapper
        if Runtime.Screen.leaseResourceId == "skid_wrapper" and type(wrapper) == "table" then
            Runtime.mergeWrapperView(wrapper)
        elseif Runtime.Screen.resourceId == "windmill" then
            local resourceRevision = Runtime.windmillResourceRevision(snapshot)
            if resourceRevision and resourceRevision >= Runtime.Screen.revision then
                local windmill = snapshot.windmill
                if windmill == nil or Runtime.mergeWindmillView(windmill) then
                    Runtime.Screen.revision = resourceRevision
                end
            end
        end
        return true
    end

    function Runtime.Screen.applyCutterSnapshot(snapshot)
        if Runtime.Screen.resourceId ~= "cutter" or type(snapshot) ~= "table" then return false end
        if (snapshot.resourceId or "cutter") ~= Runtime.Screen.leaseResourceId then return false end
        local resourceRevision = Runtime.cutterResourceRevision(snapshot)
        if resourceRevision == nil or resourceRevision < Runtime.Screen.revision then return false end
        local cutter = snapshot.view or snapshot.cutter or snapshot.data
        if type(cutter) ~= "table" or not Runtime.mergeCutterView(cutter) then return false end
        Runtime.Screen.revision = resourceRevision
        return true
    end

    function Runtime.Screen.applyWrapperSnapshot(snapshot)
        if Runtime.Screen.resourceId ~= "skid_wrapper" or type(snapshot) ~= "table"
            or snapshot.resourceId ~= Runtime.Screen.leaseResourceId then return false end
        local resourceRevision = tonumber(snapshot.resourceRevision)
        if resourceRevision == nil or resourceRevision < Runtime.Screen.revision then return false end
        if not Runtime.mergeWrapperView(snapshot.view) then return false end
        Runtime.Screen.revision = resourceRevision
        return true
    end

    function Runtime.Screen.applyWindmillSnapshot(snapshot)
        if Runtime.Screen.resourceId ~= "windmill" or type(snapshot) ~= "table" then return false end
        if (snapshot.resourceId or "windmill") ~= Runtime.Screen.leaseResourceId then return false end
        local resourceRevision = Runtime.windmillResourceRevision(snapshot)
        if resourceRevision == nil or resourceRevision < Runtime.Screen.revision then return false end
        local windmill = snapshot.view or snapshot.windmill or snapshot.data
        if type(windmill) ~= "table" or not Runtime.mergeWindmillView(windmill) then return false end
        Runtime.Screen.revision = resourceRevision
        return true
    end
end

return Component
