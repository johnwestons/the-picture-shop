-- Fleet component inspection and persistent-state validation.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.Fleet.weakestComponent(item)
        local model = item and Runtime.definition(item.modelId)
        if not model then return nil end
        local weakest
        for componentId, component in pairs(model.components) do
            local value = item.variables[componentId]
            if not weakest or value < weakest.value then
                weakest = { id = componentId, label = component.label, value = value }
            end
        end
        return weakest
    end

    function Runtime.Fleet.validState(value)
        if type(value) ~= "table" or type(value.nextId) ~= "number" or value.nextId < 1
            or value.nextId ~= math.floor(value.nextId)
            or type(value.nextDeliveryId) ~= "number" or value.nextDeliveryId < 1
            or value.nextDeliveryId ~= math.floor(value.nextDeliveryId)
            or type(value.nextServiceNoticeId) ~= "number" or value.nextServiceNoticeId < 1
            or value.nextServiceNoticeId ~= math.floor(value.nextServiceNoticeId)
            or type(value.items) ~= "table" or type(value.deliveries) ~= "table"
            or type(value.serviceNotices) ~= "table"
        then return false end

        local function denseArray(items)
            local count, highestIndex = 0, 0
            for key in pairs(items) do
                if type(key) ~= "number" or key < 1 or key ~= math.floor(key) then return false end
                count, highestIndex = count + 1, math.max(highestIndex, key)
            end
            return count == highestIndex
        end

        local function validMachineRecord(item)
            local model = type(item) == "table" and Runtime.definition(item.modelId)
            local machineNumber = type(item) == "table" and type(item.id) == "string"
                and tonumber(item.id:match("^MCH%-(%d+)$")) or nil
            if not model or not machineNumber
                or type(item.serial) ~= "string" or type(item.name) ~= "string"
                or type(item.source) ~= "string" or (item.status ~= "installed" and item.status ~= "stored")
                or type(item.purchasePrice) ~= "number" or item.purchasePrice < 0
                or type(item.acquiredAt) ~= "number" or type(item.cycles) ~= "number" or item.cycles < 0
                or type(item.operatingMinutes) ~= "number" or item.operatingMinutes < 0
                or type(item.condition) ~= "number" or item.condition < 0 or item.condition > 100
                or type(item.variables) ~= "table" or type(item.maintenance) ~= "table"
                or type(item.maintenance.serviceCount) ~= "number" or item.maintenance.serviceCount < 0
                or (item.maintenance.lastServiceAt ~= nil and type(item.maintenance.lastServiceAt) ~= "number")
                or (item.maintenance.lastServiceQuality ~= nil
                    and (type(item.maintenance.lastServiceQuality) ~= "number"
                        or item.maintenance.lastServiceQuality < 0 or item.maintenance.lastServiceQuality > 1))
                or machineNumber >= value.nextId
            then return false end
            if item.modelId == "polar_115" then
                local cutter = item.maintenance.cutter
                if type(cutter) ~= "table" or type(cutter.oilServices) ~= "number" or cutter.oilServices < 0
                    or (cutter.lubricationServices ~= nil and type(cutter.lubricationServices) ~= "number")
                    or (cutter.lastLubricationScore ~= nil and type(cutter.lastLubricationScore) ~= "number")
                    or (cutter.backgaugeLubrication ~= nil and type(cutter.backgaugeLubrication) ~= "number")
                    or (cutter.guideLubrication ~= nil and type(cutter.guideLubrication) ~= "number")
                    or (cutter.crankLubrication ~= nil and type(cutter.crankLubrication) ~= "number")
                    or (cutter.gearOilLevel ~= nil and (type(cutter.gearOilLevel) ~= "number"
                        or cutter.gearOilLevel < 0 or cutter.gearOilLevel > 1))
                    or (cutter.centralLubricationInstalled ~= nil
                        and type(cutter.centralLubricationInstalled) ~= "boolean")
                    or type(cutter.bladeRemoved) ~= "boolean" or type(cutter.bladeInSleeve) ~= "boolean"
                    or type(cutter.weeklyTechnician) ~= "boolean"
                    or (cutter.nextTechnicianDay ~= nil and type(cutter.nextTechnicianDay) ~= "number")
                    or (cutter.appointmentType ~= nil and cutter.appointmentType ~= "weekly"
                        and cutter.appointmentType ~= "requested")
                    or type(cutter.technicianSequence) ~= "number" or cutter.technicianSequence < 0
                then return false end
            end
            if item.modelId == "heidelberg_10x15" then
                local press = item.maintenance.windmill
                if type(press) ~= "table" or type(press.serviceCount) ~= "number"
                    or press.serviceCount < 0
                    or (press.lastDailyOilHours ~= nil and type(press.lastDailyOilHours) ~= "number")
                    or type(press.lastRollerStripe) ~= "number" or press.lastRollerStripe < 0
                    or press.lastRollerStripe > 1
                    or (press.technicianDueDay ~= nil and type(press.technicianDueDay) ~= "number")
                then return false end
            end
            for componentId in pairs(model.components) do
                local componentValue = item.variables[componentId]
                if type(componentValue) ~= "number" or componentValue < 0 or componentValue > 100 then return false end
            end
            for componentId in pairs(item.variables) do
                if not model.components[componentId] then return false end
            end
            return math.abs(Runtime.calculateCondition(item) - item.condition) <= 0.11
        end

        local ids = {}
        if not denseArray(value.items) or not denseArray(value.deliveries)
            or not denseArray(value.serviceNotices)
        then return false end
        for index, item in ipairs(value.items) do
            if not validMachineRecord(item) or ids[item.id] then return false end
            ids[item.id] = true
            if value.items[index] ~= item then return false end
        end

        local orderIds = {}
        for index, order in ipairs(value.deliveries) do
            local orderNumber = type(order) == "table" and type(order.id) == "string"
                and tonumber(order.id:match("^MDO%-(%d+)$")) or nil
            local machineNumber = type(order) == "table" and type(order.machineId) == "string"
                and tonumber(order.machineId:match("^MCH%-(%d+)$")) or nil
            local delivery = type(order) == "table" and order.delivery or nil
            if not orderNumber or orderNumber >= value.nextDeliveryId or orderIds[order.id]
                or not machineNumber or machineNumber >= value.nextId
                or not Runtime.definition(order.modelId) or type(order.machineName) ~= "string"
                or type(order.company) ~= "string" or type(order.price) ~= "number" or order.price < 0
                or type(order.condition) ~= "number" or order.condition < 0 or order.condition > 100
                or type(delivery) ~= "table" or not Runtime.deliveryStatuses[delivery.status]
                or type(delivery.orderedAt) ~= "number"
                or (delivery.scheduledAt ~= nil and type(delivery.scheduledAt) ~= "number")
                or (delivery.arrivedAt ~= nil and type(delivery.arrivedAt) ~= "number")
                or (delivery.receivedAt ~= nil and type(delivery.receivedAt) ~= "number")
                or (delivery.expectedAtHours ~= nil and type(delivery.expectedAtHours) ~= "number")
                or (delivery.receivedAtHours ~= nil and type(delivery.receivedAtHours) ~= "number")
                or value.deliveries[index] ~= order
            then return false end
            if delivery.status == "received" then
                if order.item ~= nil or delivery.receivedAt == nil then return false end
            else
                if not validMachineRecord(order.item) or order.item.status ~= "stored"
                    or order.item.id ~= order.machineId or order.item.modelId ~= order.modelId
                    or ids[order.item.id] or math.abs(order.item.condition - order.condition) > 0.11
                then return false end
                ids[order.item.id] = true
            end
            orderIds[order.id] = true
        end
        local noticeIds = {}
        for _, notice in ipairs(value.serviceNotices) do
            local noticeNumber = type(notice) == "table" and type(notice.id) == "string"
                and tonumber(notice.id:match("^SERVICE%-(%d+)$")) or nil
            if not noticeNumber or noticeNumber >= value.nextServiceNoticeId or noticeIds[notice.id]
                or type(notice.sender) ~= "string" or type(notice.subject) ~= "string"
                or type(notice.body) ~= "string" or type(notice.receivedAtHours) ~= "number"
                or (notice.unread ~= nil and type(notice.unread) ~= "boolean")
            then return false end
            noticeIds[notice.id] = true
        end
        return true
    end

    Runtime.Fleet.copy = Runtime.copy
end

return Component
