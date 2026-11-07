-- Physical ownership, machine placement, and state validation.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}
local MachineRotation = require("src.machine_rotation")

function Component.install(Runtime)
    function Runtime.physicalOwnership(value)
        local valid = Runtime.PalletState.validate(value)
        if not valid then return false end
        local presses = Runtime.MachineFleet.installedUnits(value, "heidelberg_10x15")
        if #presses == 0 then presses[1] = { id = "legacy-windmill" } end
        local owners, loaded = {}, {}
        for _, press in ipairs(presses) do
            local placement = press.world or value.windmill or {}
            local process = placement.process
            if process and process.palletId then
                if loaded[process.palletId] then return false end
                loaded[process.palletId] = { process = process, machineId = press.id }
            elseif process and process.jobId then
                return false
            end
        end
        for _, savedJob in ipairs(value.jobs and value.jobs.active or {}) do
            for _, pallet in ipairs(savedJob.pallets or {}) do
                if pallet.location == "at_press" then
                    local owner = pallet.pressMachineId or (presses[1] and presses[1].id)
                    if not owner or owners[owner] then return false end
                    owners[owner] = true
                    local entry = loaded[pallet.id]
                    if not entry or entry.machineId ~= owner
                        or entry.process.jobId ~= savedJob.id
                        or type(savedJob.press) ~= "table" or type(pallet.press) ~= "table"
                        or not Runtime.positiveInteger(entry.process.colorIndex)
                        or entry.process.colorIndex > savedJob.press.colors
                    then return false end
                    loaded[pallet.id] = nil
                end
            end
        end
        return next(loaded) == nil
    end

    function Runtime.machineUnitWorlds(value)
        for _, item in ipairs(value.machines and value.machines.items or {}) do
            local world = item.world
            if item.modelId == "polar_115" and item.memory ~= nil
                and not Runtime.cutterMemory(item.memory) then return false end
            if world then
                if type(world) ~= "table" or not Runtime.number(world.x) or not Runtime.number(world.y)
                    or world.x < 0 or world.x > Runtime.Config.baseWidth
                    or world.y < 0 or world.y > Runtime.Config.baseHeight
                    or not Runtime.directions[world.direction]
                    or (world.sceneId~=nil and world.sceneId~="warehouse"
                        and world.sceneId~="front_left" and world.sceneId~="front_right")
                    or (world.rotationIndex ~= nil and ((item.modelId ~= "polar_115"
                        and item.modelId ~= "skid_wrapper" and item.modelId ~= "heidelberg_10x15")
                        or not Runtime.integer(world.rotationIndex)
                        or world.rotationIndex < 1 or world.rotationIndex > 64))
                    or (world.rotationIndex ~= nil and ((item.modelId == "polar_115"
                        and MachineRotation.directionForFrame("cutter", world.rotationIndex) ~= world.direction)
                        or (item.modelId == "skid_wrapper"
                            and MachineRotation.directionForFrame("wrapper", world.rotationIndex) ~= world.direction)
                        or (item.modelId == "heidelberg_10x15"
                            and MachineRotation.directionForFrame("windmill", world.rotationIndex) ~= world.direction)))
                    or not Runtime.optionalBoolean(world.moving)
                    or not Runtime.optionalBoolean(world.inMotion)
                    or (item.modelId == "heidelberg_10x15"
                        and (not Runtime.windmillProcess(world.process)
                            or not Runtime.optionalBoolean(world.tutorialComplete)))
                then return false end
            end
        end
        return true
    end

    function Runtime.palletJack(value)
        return Runtime.placement(value)
            and type(value.operating) == "boolean"
            and (value.sceneId==nil or value.sceneId=="warehouse"
                or value.sceneId=="front_left" or value.sceneId=="front_right")
            and Runtime.optionalNumber(value.animationClock)
            and (value.carriedPalletId == nil or Runtime.text(value.carriedPalletId))
    end

    function Runtime.deliveryDriver(value)
        if value==nil then return true end
        if type(value)~="table" or value.version~=1
            or not ({idle=true,approaching=true,waiting=true,signed=true,missed=true,done=true})[value.status]
            or not Runtime.nonnegative(value.waitSeconds)
            or value.waitSeconds>120
            or type(value.driverReturned)~="boolean"
            or type(value.penaltyApplied)~="boolean"
            or not Runtime.optionalText(value.deliveryId)
            or not Runtime.optionalText(value.signedBy)
            or not Runtime.optionalNumber(value.signedAtHours)
            or not Runtime.optionalBoolean(value.penaltyApplied)
        then return false end
        if value.status=="idle" then return value.deliveryId==nil and value.mode==nil end
        return Runtime.text(value.deliveryId) and #value.deliveryId<=64
            and (value.mode=="delivery" or value.mode=="vendor_delivery" or value.mode=="machine_delivery")
    end

    function Runtime.persistentState(value)
        return type(value) == "table"
            and Runtime.Schema.validPhysicalSource(value)
            and Runtime.nonnegative(value.money)
            and Runtime.Home.valid(value.home)
            and Runtime.inventory(value.inventory)
            and type(value.shopProgress) == "table"
            and Runtime.nonnegative(value.shopProgress.completedCuts)
            and type(value.jobs) == "table"
            and Runtime.array(value.jobs.active, Runtime.job)
            and Runtime.array(value.jobs.completed, Runtime.job)
            and Runtime.array(value.jobs.declined, Runtime.job)
            and Runtime.positiveInteger(value.nextJobId)
            and Runtime.nonnegative(value.accountsReceivable)
            and Runtime.Reputation.valid(value.reputation)
            and Runtime.deliveryDriver(value.deliveryDriver)
            and Runtime.cutterMemory(value.cutterMemory)
            and (value.groceryStore==nil or require("src.commute.grocery_inventory").valid(value.groceryStore))
            and type(value.procurement) == "table"
            and Runtime.positiveInteger(value.procurement.nextOrderId)
            and Runtime.array(value.procurement.orders, Runtime.purchaseOrder)
            and Runtime.positiveInteger(value.vendorCategory)
            and Runtime.BusinessCalendar.valid(value.calendar, value.bills)
            and Runtime.clientEmails(value.clientEmails)
            and Runtime.workPhone(value.workPhone)
            and Runtime.MachineFleet.validState(value.machines)
            and Runtime.machineUnitWorlds(value)
            and Runtime.Credit.validState(value.credit)
            and Runtime.Employees.valid(value.employment)
            and Runtime.WarehouseUpgrades.validate(value.warehouse)
            and Runtime.StagingAreas.valid(value.stagingAreas)
            and Runtime.BreakroomGames.validate(value.breakroomGames)
            and Runtime.WarehouseConstruction.valid(value.constructionWorker, value.warehouse)
            and type(value.storage) == "table" and Runtime.PalletStorage.normalize(value.storage) ~= nil
            and Runtime.Forklift.validState(value.forklift, Runtime.Config.forklift)
            and (not value.forklift.owned or value.warehouse.forkliftOwned)
            and Runtime.placement(value.cutter, true)
            and (value.cutter.rotationIndex == nil or MachineRotation.directionForFrame(
                "cutter", value.cutter.rotationIndex) == value.cutter.direction)
            and Runtime.palletJack(value.palletJack)
            and (value.extraPalletJacks==nil or Runtime.array(value.extraPalletJacks,Runtime.palletJack))
            and Runtime.placement(value.wrapper, true)
            and (value.wrapper.rotationIndex == nil or MachineRotation.directionForFrame(
                "wrapper", value.wrapper.rotationIndex) == value.wrapper.direction)
            and Runtime.placement(value.windmill, true)
            and (value.windmill.rotationIndex == nil or MachineRotation.directionForFrame(
                "windmill", value.windmill.rotationIndex) == value.windmill.direction)
            and Runtime.optionalBoolean(value.windmill.tutorialComplete)
            and Runtime.windmillProcess(value.windmill.process)
            and Runtime.physicalOwnership(value)
    end
end

return Component
