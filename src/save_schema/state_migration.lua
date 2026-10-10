-- Legacy physical ownership repair and state normalization.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.repairLegacyPhysicalOwnership(state)
        -- Legacy machine repair predates racks/stacks/forklifts. Never let it move
        -- newly-owned stock to a machine or floor based on a stale old claim.
        if state.forklift and state.forklift.carriedPalletId then return end
        for _, item in ipairs(Runtime.PalletState.items(state)) do
            if item.pallet.location == "rack" or item.pallet.location == "stacked"
                or item.pallet.location == "on_forklift" or item.pallet.storage ~= nil then return end
        end
        local process = state.windmill and state.windmill.process
        local selected = process and process.palletId and Runtime.PalletState.find(state, process.palletId) or nil
        if selected and (selected.vendor or selected.job.id ~= process.jobId
            or type(selected.job.press) ~= "table" or type(selected.pallet.press) ~= "table")
        then
            selected = nil
        end
        local selectedWasAtPress = selected and selected.pallet.location == "at_press"
        local offset = 0
        for _, item in ipairs(Runtime.PalletState.items(state)) do
            local pallet = item.pallet
            if pallet.location == "at_press" and (not selected or pallet ~= selected.pallet) then
                pallet.location = "warehouse"
            end
            local physical = pallet.location == "warehouse" or pallet.location == "cutter_output"
                or pallet.location == "on_pallet_jack" or pallet.location == "at_cutter"
                or pallet.location == "at_press" or pallet.location == "press_output"
                or pallet.location == "on_employee"
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
        Runtime.PalletState.reconcile(state)
    end

    function Runtime.normalizeState(source, repairPhysical)
        source = type(source) == "table" and source or {}
        if not Runtime.Schema.validPhysicalSource(source) then return nil, "Invalid physical stock or vehicle ownership." end
        if type(source.calendar)=="table" and source.calendar.secondsPerDay~=nil
            and not Runtime.BusinessCalendar.validDayLength(source.calendar.secondsPerDay) then return nil,"Invalid shop day length." end
        local function validLaborRecord(record)
            return record==nil or type(record)=="table" and Runtime.Labor.validJob(record.labor)
                and (type(record.quote)~="table" or Runtime.Labor.validBudget(record.quote.employeeBudget)
                    and (record.quote.servicePrice==nil or Runtime.nonnegative(record.quote.servicePrice)))
        end
        for _,name in ipairs({"active","completed","declined"}) do
            for _,record in ipairs(source.jobs and source.jobs[name] or {}) do
                if not validLaborRecord(record) then return nil,"Invalid job labor accounting." end
            end
        end
        for _,name in ipairs({"pending","inbox"}) do
            local emails=type(source.clientEmails)=="table" and source.clientEmails[name]
            if type(emails)=="table" then for _,email in pairs(emails) do
                if type(email)=="table" and not validLaborRecord(email.job) then return nil,"Invalid estimate labor allowance." end
            end end
        end
        if source.credit ~= nil and not Runtime.Credit.validState(source.credit) then
            return nil, "Invalid saved credit account."
        end
        local result = Runtime.Schema.defaultState()
        local warehouse, warehouseError = Runtime.WarehouseUpgrades.normalize(source.warehouse)
        if not warehouse then return nil, warehouseError end
        local stagingAreas, stagingError = Runtime.StagingAreas.normalize(source.stagingAreas)
        if not stagingAreas then return nil, stagingError end
        local storage, storageError = Runtime.PalletStorage.normalize(source.storage)
        if not storage then return nil, storageError end
        if source.forklift ~= nil and not Runtime.Forklift.validState(source.forklift, Runtime.Config.forklift) then
            return nil, "Invalid saved forklift state."
        end
        result.warehouse, result.stagingAreas, result.storage = warehouse, stagingAreas, storage
        result.breakroomGames = Runtime.BreakroomGames.normalize(source.breakroomGames)
        if not result.breakroomGames then return nil, "Invalid saved break room games." end
        for bayId, fixtures in pairs(result.breakroomGames.bays) do
            local bay = warehouse.bays[bayId]
            if (fixtures.air_hockey or fixtures.basketball or fixtures.critter_kombat)
                and (not bay or bay.optionId ~= "breakroom" or bay.status ~= "complete") then
                return nil, "Break room fixture has no completed room."
            end
        end
        if not Runtime.WarehouseConstruction.valid(source.constructionWorker, warehouse) then
            return nil, "Invalid saved construction worker state."
        end
        result.constructionWorker = Runtime.WarehouseConstruction.normalize(source.constructionWorker, warehouse)
        result.forklift = source.forklift == nil and Runtime.Forklift.defaultState(Runtime.Config.forklift)
            or Runtime.Forklift.normalize(source.forklift, Runtime.Config.forklift)
        if result.forklift.owned and not warehouse.forkliftOwned then
            return nil, "Forklift ownership has no purchase entitlement."
        end
        if Runtime.nonnegative(source.money) then result.money = source.money end

        if type(source.inventory) == "table" then
            result.inventory = Runtime.copy(source.inventory)
            local defaults = Runtime.Schema.defaultState().inventory
            for key, value in pairs(defaults) do
                if result.inventory[key] == nil then result.inventory[key] = Runtime.copy(value) end
            end
        end
        result.shopProgress = type(source.shopProgress) == "table"
            and Runtime.copy(source.shopProgress) or result.shopProgress
        result.jobs = type(source.jobs) == "table" and Runtime.copy(source.jobs) or result.jobs
        result.jobs.active = type(result.jobs.active) == "table" and result.jobs.active or {}
        result.jobs.completed = type(result.jobs.completed) == "table" and result.jobs.completed or {}
        result.jobs.declined = type(result.jobs.declined) == "table" and result.jobs.declined or {}
        Runtime.normalizeJobs(result.jobs)
        result.nextJobId = source.nextJobId ~= nil and source.nextJobId or result.nextJobId
        result.accountsReceivable = source.accountsReceivable ~= nil
            and source.accountsReceivable or result.accountsReceivable
        result.reputation = type(source.reputation) == "table"
            and Runtime.copy(source.reputation) or result.reputation
        Runtime.Reputation.ensure(result)
        result.cutterMemory = type(source.cutterMemory) == "table"
            and Runtime.copy(source.cutterMemory) or result.cutterMemory
        result.procurement = type(source.procurement) == "table"
            and Runtime.copy(source.procurement) or result.procurement
        result.procurement.orders = type(result.procurement.orders) == "table" and result.procurement.orders or {}
        result.procurement.nextOrderId = result.procurement.nextOrderId or 1
        result.procurement.shipments = type(result.procurement.shipments) == "table" and result.procurement.shipments or {}
        result.procurement.nextShipmentId = result.procurement.nextShipmentId or 1
        result.vendorCategory = source.vendorCategory ~= nil and source.vendorCategory or result.vendorCategory
        result.calendar = type(source.calendar) == "table" and Runtime.copy(source.calendar) or result.calendar
        result.bills = type(source.bills) == "table" and Runtime.copy(source.bills) or result.bills
        result.credit = Runtime.Credit.normalize(source.credit) or Runtime.Credit.defaultState()
        result.employment = Runtime.Employees.normalize(source.employment, Runtime.BusinessCalendar.absoluteHours(result))
        if not result.employment then return nil,"Invalid employee or payroll records." end
        result.clientEmails = type(source.clientEmails) == "table"
            and Runtime.copy(source.clientEmails) or result.clientEmails
        result.clientEmails.nextEmailId = math.max(1, math.floor(tonumber(result.clientEmails.nextEmailId) or 1))
        result.clientEmails.nextPromotionId = math.max(1, math.floor(tonumber(result.clientEmails.nextPromotionId) or 1))
        result.clientEmails.pending = type(result.clientEmails.pending) == "table" and result.clientEmails.pending or {}
        result.clientEmails.inbox = type(result.clientEmails.inbox) == "table" and result.clientEmails.inbox or {}
        result.clientEmails.archive = type(result.clientEmails.archive) == "table" and result.clientEmails.archive or {}
        result.clientEmails.sentPromotions = type(result.clientEmails.sentPromotions) == "table"
            and result.clientEmails.sentPromotions or {}
        Runtime.normalizeEmailJobs(result.clientEmails)
        result.workPhone = type(source.workPhone) == "table"
            and Runtime.copy(source.workPhone) or result.workPhone
        result.workPhone.nextCallId = math.max(1,
            math.floor(tonumber(result.workPhone.nextCallId) or 1))
        result.workPhone.nextCallAtHours = math.max(0,
            tonumber(result.workPhone.nextCallAtHours) or 6)
        result.workPhone.incoming = type(result.workPhone.incoming) == "table"
            and result.workPhone.incoming or nil
        result.workPhone.history = type(result.workPhone.history) == "table"
            and result.workPhone.history or {}
        result.machines = type(source.machines) == "table"
            and Runtime.copy(source.machines) or result.machines
        Runtime.MachineFleet.ensure(result)
        Runtime.BusinessCalendar.ensure(result)
        result.cutter = Runtime.mergePlacement(result.cutter, source.cutter)
        result.wrapper = Runtime.mergePlacement(result.wrapper, source.wrapper)
        result.windmill = Runtime.mergePlacement(result.windmill, source.windmill)
        if type(source.windmill) == "table" and source.windmill.tutorialComplete ~= nil then
            result.windmill.tutorialComplete = source.windmill.tutorialComplete == true
        end
        if type(source.windmill) == "table" and type(source.windmill.process) == "table" then
            result.windmill.process = Runtime.normalizeWindmillProcess(Runtime.copy(source.windmill.process), result)
        end
        result.technicianVisit = type(source.technicianVisit) == "table"
            and Runtime.copy(source.technicianVisit) or nil
        result.palletJack = Runtime.mergePlacement(result.palletJack, source.palletJack)
        if type(source.palletJack) == "table" then
            result.palletJack.operating = source.palletJack.operating == true
            result.palletJack.sceneId = source.palletJack.sceneId or "warehouse"
            result.palletJack.animationClock = source.palletJack.animationClock or 0
            result.palletJack.carriedPalletId = source.palletJack.carriedPalletId
        end
        if repairPhysical then Runtime.repairLegacyPhysicalOwnership(result) end
        return result
    end
end

return Component
