-- Owned machines, placements, deliveries, and fleet normalization.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.normalizeItem(item)
        if type(item) ~= "table" or not Runtime.definition(item.modelId) or type(item.id) ~= "string" then return nil end
        local model = Runtime.definition(item.modelId)
        item.serial = type(item.serial) == "string" and item.serial or ("PS-" .. item.id)
        item.name = model.name
        item.source = type(item.source) == "string" and item.source or "unknown"
        item.status = item.status == "installed" and "installed" or "stored"
        item.purchasePrice = math.max(0, Runtime.rounded(tonumber(item.purchasePrice) or 0))
        item.acquiredAt = tonumber(item.acquiredAt) or os.time()
        item.cycles = math.max(0, tonumber(item.cycles) or 0)
        item.operatingMinutes = math.max(0, tonumber(item.operatingMinutes) or 0)
        item.variables = type(item.variables) == "table" and item.variables or {}
        for componentId in pairs(model.components) do
            item.variables[componentId] = Runtime.clamp(tonumber(item.variables[componentId]) or 100, 0, 100)
        end
        for componentId in pairs(item.variables) do
            if not model.components[componentId] then item.variables[componentId] = nil end
        end
        item.maintenance = type(item.maintenance) == "table" and item.maintenance or {}
        item.maintenance.serviceCount = math.max(0, math.floor(tonumber(item.maintenance.serviceCount) or 0))
        if type(item.maintenance.lastServiceAt) ~= "number" then item.maintenance.lastServiceAt = nil end
        if type(item.maintenance.lastServiceQuality) ~= "number" then item.maintenance.lastServiceQuality = nil end
        if item.modelId == "polar_115" then
            item.maintenance.cutter = type(item.maintenance.cutter) == "table" and item.maintenance.cutter or {}
            local cutter = item.maintenance.cutter
            cutter.oilServices = math.max(0, math.floor(tonumber(cutter.oilServices) or 0))
            cutter.lubricationServices = math.max(0, math.floor(tonumber(cutter.lubricationServices)
                or cutter.oilServices))
            cutter.lastLubricationScore = Runtime.clamp(tonumber(cutter.lastLubricationScore) or 0, 0, 1)
            cutter.backgaugeLubrication = Runtime.clamp(tonumber(cutter.backgaugeLubrication) or 100, 0, 100)
            cutter.guideLubrication = Runtime.clamp(tonumber(cutter.guideLubrication) or 100, 0, 100)
            cutter.crankLubrication = Runtime.clamp(tonumber(cutter.crankLubrication) or 100, 0, 100)
            cutter.gearOilLevel = Runtime.clamp(tonumber(cutter.gearOilLevel) or 0.48, 0, 1)
            cutter.centralLubricationInstalled = cutter.centralLubricationInstalled == true
                or item.source == "online"
            cutter.bladeRemoved = cutter.bladeRemoved == true
            cutter.bladeInSleeve = cutter.bladeInSleeve == true
            cutter.weeklyTechnician = cutter.weeklyTechnician == true
            cutter.nextTechnicianDay = tonumber(cutter.nextTechnicianDay)
            cutter.appointmentType = cutter.appointmentType == "weekly" and "weekly"
                or cutter.appointmentType == "requested" and "requested" or nil
            cutter.technicianSequence = math.max(0, math.floor(tonumber(cutter.technicianSequence) or 0))
        else
            item.maintenance.cutter = nil
        end
        if item.modelId == "heidelberg_10x15" then
            item.maintenance.windmill = type(item.maintenance.windmill) == "table"
                and item.maintenance.windmill or {}
            local press = item.maintenance.windmill
            press.serviceCount = math.max(0, math.floor(tonumber(press.serviceCount) or 0))
            press.lastDailyOilHours = tonumber(press.lastDailyOilHours)
            press.lastRollerStripe = math.max(0, math.min(1, tonumber(press.lastRollerStripe) or 0.8))
            press.technicianDueDay = tonumber(press.technicianDueDay)
        else
            item.maintenance.windmill = nil
        end
        if type(item.world) == "table" and type(item.world.x) == "number" and type(item.world.y) == "number" then
            item.world.direction = type(item.world.direction) == "string" and item.world.direction or "northwest"
        else
            item.world = nil
        end
        item.condition = Runtime.calculateCondition(item)
        return item
    end

    Runtime.floorSlots = {
        { 470, 420 }, { 350, 525 }, { 540, 540 },
        { 530, 335 }, { 760, 540 }, { 740, 335 },
        { 390, 355 }, { 605, 550 },
    }

    function Runtime.placementFor(state, item)
        local model = Runtime.definition(item.modelId)
        local key = model and model.placementKey
        if not key then return nil end
        local first = state[key]
        if type(first) == "table" and type(first.x) == "number" and type(first.y) == "number" then
            return first
        end
        local config = Runtime.Config[key .. "Placement"]
        return config and { x = config.spawnX, y = config.spawnY }
    end

    function Runtime.assignFloorPosition(state, fleet, item)
        if item.world then return true end
        local occupied = {}
        local itemConfig = Runtime.Config[Runtime.definition(item.modelId).placementKey .. "Placement"]
        for _, other in ipairs(fleet.items) do
            if other ~= item and other.status == "installed" then
                local point = other.world or Runtime.placementFor(state, other)
                if point then
                    local config = Runtime.Config[Runtime.definition(other.modelId).placementKey .. "Placement"]
                    occupied[#occupied + 1] = { x = point.x, y = point.y,
                        halfWidth = config.collisionHalfWidth,
                        halfHeight = config.collisionHalfHeight }
                end
            end
        end
        if state.forklift then
            occupied[#occupied + 1] = { x = state.forklift.x, y = state.forklift.y,
                halfWidth = Runtime.Config.forklift.collisionHalfWidth,
                halfHeight = Runtime.Config.forklift.collisionHalfHeight }
        end
        if state.palletJack then
            occupied[#occupied + 1] = { x = state.palletJack.x, y = state.palletJack.y,
                halfWidth = Runtime.Config.palletJack.collisionHalfWidth,
                halfHeight = Runtime.Config.palletJack.collisionHalfHeight }
        end
        for _, obstacle in ipairs(Runtime.WarehouseLayout.obstacles(state)) do
            occupied[#occupied + 1] = { x = obstacle.x, y = obstacle.y,
                halfWidth = obstacle.halfWidth or 26,
                halfHeight = obstacle.halfHeight or 18 }
        end
        for _, job in ipairs(state.jobs and state.jobs.active or {}) do
            for _, pallet in ipairs(job.pallets or {}) do
                local world = pallet.world
                if world and pallet.location ~= "at_cutter" and pallet.location ~= "at_press" then
                    occupied[#occupied + 1] = { x = world.x, y = world.y,
                        halfWidth = 33, halfHeight = 11 }
                end
            end
        end
        local function clearSlot(slot)
            local clear = not Runtime.WarehouseLayout.isReserved(state, slot[1], slot[2])
                and slot[1] + itemConfig.operatorDistanceX < Runtime.Config.baseWidth - 15
                and slot[2] + itemConfig.operatorDistanceY < Runtime.Config.baseHeight - 20
                and Runtime.Navigation.isAreaWalkable(Runtime.Assets, slot[1], slot[2],
                    itemConfig.collisionHalfWidth, itemConfig.collisionHalfHeight)
            for _, dx in ipairs({ -itemConfig.collisionHalfWidth, itemConfig.collisionHalfWidth }) do
                for _, dy in ipairs({ -itemConfig.collisionHalfHeight, itemConfig.collisionHalfHeight }) do
                    if Runtime.WarehouseLayout.isReserved(state, slot[1] + dx, slot[2] + dy) then
                        clear = false
                    end
                end
            end
            for _, point in ipairs(occupied) do
                if math.abs(slot[1] - point.x)
                        < itemConfig.collisionHalfWidth + point.halfWidth + 8
                    and math.abs(slot[2] - point.y)
                        < itemConfig.collisionHalfHeight + point.halfHeight + 18 then
                    clear = false
                    break
                end
            end
            return clear
        end
        for _, slot in ipairs(Runtime.floorSlots) do
            if clearSlot(slot) then
                item.world = { x = slot[1], y = slot[2], direction = "northwest" }
                return true
            end
        end
        for y = 330, 550, 44 do
            for x = 345, 775, 55 do
                if clearSlot({ x, y }) then
                    item.world = { x = x, y = y, direction = "northwest" }
                    return true
                end
            end
        end
        return false
    end

    function Runtime.normalizeDeliveryOrder(order)
        if type(order) ~= "table" or type(order.id) ~= "string"
            or not order.id:match("^MDO%-%d+$")
        then return nil end
        order.delivery = type(order.delivery) == "table" and order.delivery or {}
        local status = Runtime.deliveryStatuses[order.delivery.status]
            and order.delivery.status or "awaiting_delivery"
        order.delivery.status = status
        order.delivery.orderedAt = tonumber(order.delivery.orderedAt) or os.time()
        for _, key in ipairs({ "scheduledAt", "arrivedAt", "receivedAt" }) do
            if type(order.delivery[key]) ~= "number" then order.delivery[key] = nil end
        end
        order.item = status ~= "received" and Runtime.normalizeItem(order.item) or nil
        if status ~= "received" and not order.item then return nil end
        local modelId = order.item and order.item.modelId or order.modelId
        local model = Runtime.definition(modelId)
        local machineId = order.item and order.item.id or order.machineId
        if not model or type(machineId) ~= "string" or not machineId:match("^MCH%-%d+$") then return nil end
        if order.item then order.item.status = "stored" end
        order.machineId = machineId
        order.modelId = modelId
        order.machineName = model.name
        order.condition = order.item and Runtime.calculateCondition(order.item)
            or Runtime.clamp(tonumber(order.condition) or 0, 0, 100)
        order.price = math.max(0, Runtime.rounded(tonumber(order.price) or 0))
        order.company = type(order.company) == "string" and order.company or "Picture Shop Online Equipment"
        return order
    end

    function Runtime.Fleet.ensure(state)
        assert(type(state) == "table", "machine fleet requires game state")
        if type(state.machines) ~= "table" then state.machines = Runtime.Fleet.defaultState() end
        local fleet = state.machines
        fleet.items = type(fleet.items) == "table" and fleet.items or {}
        local normalized, machineIds = {}, {}
        local highestId = 0
        for _, source in ipairs(fleet.items) do
            local item = Runtime.normalizeItem(source)
            if item and not machineIds[item.id] then
                local number = tonumber(item.id:match("^MCH%-(%d+)$"))
                highestId = math.max(highestId, number or 0)
                machineIds[item.id] = true
                normalized[#normalized + 1] = item
            end
        end
        fleet.items = normalized
        local seenOnFloor = {}
        for _, item in ipairs(fleet.items) do
            -- Older saves kept spare purchases in storage. Bring those units onto
            -- the floor when the save is opened under the multi-machine rules.
            if item.status == "stored" then
                item.status = "installed"
                item.world = nil
            end
            if not seenOnFloor[item.modelId] or Runtime.assignFloorPosition(state, fleet, item) then
                seenOnFloor[item.modelId] = true
            else
                item.status = "stored"
            end
        end
        fleet.deliveries = type(fleet.deliveries) == "table" and fleet.deliveries or {}
        local deliveries, deliveryIds = {}, {}
        local highestDeliveryId = 0
        for _, source in ipairs(fleet.deliveries) do
            local order = Runtime.normalizeDeliveryOrder(source)
            local orderNumber = order and tonumber(order.id:match("^MDO%-(%d+)$")) or nil
            local machineNumber = order and tonumber(order.machineId:match("^MCH%-(%d+)$")) or nil
            local pendingDuplicate = order and order.item and machineIds[order.machineId]
            if order and orderNumber and machineNumber and not deliveryIds[order.id] and not pendingDuplicate then
                highestDeliveryId = math.max(highestDeliveryId, orderNumber)
                highestId = math.max(highestId, machineNumber)
                deliveryIds[order.id] = true
                if order.item then machineIds[order.machineId] = true end
                deliveries[#deliveries + 1] = order
            end
        end
        fleet.deliveries = deliveries
        fleet.nextServiceNoticeId = math.max(1, math.floor(tonumber(fleet.nextServiceNoticeId) or 1))
        fleet.serviceNotices = type(fleet.serviceNotices) == "table" and fleet.serviceNotices or {}
        local notices, highestNotice = {}, 0
        for _, notice in ipairs(fleet.serviceNotices) do
            if type(notice) == "table" and type(notice.id) == "string"
                and type(notice.subject) == "string" and type(notice.body) == "string"
            then
                notice.sender = type(notice.sender) == "string" and notice.sender or "Precision Blade Service"
                notice.receivedAtHours = math.max(0, tonumber(notice.receivedAtHours) or 0)
                highestNotice = math.max(highestNotice, tonumber(notice.id:match("^SERVICE%-(%d+)$")) or 0)
                notices[#notices + 1] = notice
            end
        end
        fleet.serviceNotices = notices
        fleet.nextServiceNoticeId = math.max(fleet.nextServiceNoticeId, highestNotice + 1)
        fleet.nextId = math.max(highestId + 1, math.floor(tonumber(fleet.nextId) or 1), 1)
        fleet.nextDeliveryId = math.max(highestDeliveryId + 1,
            math.floor(tonumber(fleet.nextDeliveryId) or 1), 1)
        return fleet
    end
end

return Component
