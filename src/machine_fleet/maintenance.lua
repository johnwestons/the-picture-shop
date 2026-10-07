-- Machine health, service notices, and lubrication outcomes.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.Fleet.definition(modelId) return Runtime.definition(modelId) end

    function Runtime.Fleet.condition(item)
        if item then item.condition = Runtime.calculateCondition(item) end
        return item and item.condition or 0
    end

    function Runtime.Fleet.conditionStatus(value)
        value = tonumber(value) or 0
        if value >= 90 then return "Excellent"
        elseif value >= 75 then return "Good"
        elseif value >= 55 then return "Fair"
        elseif value >= 30 then return "Poor"
        end
        return "Critical"
    end

    function Runtime.Fleet.owned(state)
        local result = {}
        for _, item in ipairs(Runtime.Fleet.ensure(state).items) do result[#result + 1] = item end
        return result
    end

    function Runtime.Fleet.addServiceNotice(state, subject, body, sender)
        local fleet = Runtime.Fleet.ensure(state)
        local notice = {
            id = string.format("SERVICE-%04d", fleet.nextServiceNoticeId),
            sender = sender or "Precision Blade Service",
            subject = tostring(subject),
            body = tostring(body),
            unread = true,
            receivedAtHours = Runtime.BusinessCalendar.absoluteHours(state),
            serviceNotice = true,
        }
        fleet.nextServiceNoticeId = fleet.nextServiceNoticeId + 1
        fleet.serviceNotices[#fleet.serviceNotices + 1] = notice
        return notice
    end

    function Runtime.Fleet.serviceInbox(state)
        return Runtime.Fleet.ensure(state).serviceNotices
    end

    function Runtime.Fleet.dismissServiceNotice(state, noticeId)
        local notices = Runtime.Fleet.ensure(state).serviceNotices
        for index, notice in ipairs(notices) do
            if notice.id == noticeId then return table.remove(notices, index) end
        end
    end

    function Runtime.Fleet.completeCutterOiling(state, machineId, score)
        return Runtime.Fleet.completeCutterLubrication(state, machineId, { score = score })
    end

    function Runtime.Fleet.completeCutterLubrication(state, machineId, result)
        local item = Runtime.Fleet.byId(state, machineId)
        if not item or item.modelId ~= "polar_115" then return false, "Cutter not found." end
        local stock = state.inventory and state.inventory.stock or {}
        if (stock.maintenance_kit or 0) < 1 then return false, "A machine maintenance kit is required." end
        result = type(result) == "table" and result or {}
        local score = Runtime.clamp(tonumber(result.score) or 0, 0, 1)
        local consumed, consumptionError = Runtime.Procurement.consumePhysicalProduct(state, "maintenance_kit", 1, {allowAbstract=true})
        if not consumed then return false, consumptionError end
        stock.maintenance_kit = stock.maintenance_kit - 1
        -- Hydraulic oil is deliberately excluded: it remains technician-only work.
        item.variables.hydraulicHealth = Runtime.clamp(item.variables.hydraulicHealth + 3 + score * 5, 0, 100)
        item.variables.backgaugeCalibration = Runtime.clamp(item.variables.backgaugeCalibration + 8 + score * 10, 0, 100)
        item.variables.safetyCircuit = Runtime.clamp(item.variables.safetyCircuit + 4 + score * 6, 0, 100)
        item.maintenance.serviceCount = item.maintenance.serviceCount + 1
        item.maintenance.lastServiceAt = os.time()
        item.maintenance.lastServiceQuality = score
        item.maintenance.cutter.oilServices = item.maintenance.cutter.oilServices + 1
        local cutter = item.maintenance.cutter
        cutter.lubricationServices = cutter.lubricationServices + 1
        cutter.lastLubricationScore = score
        cutter.backgaugeLubrication = 78 + score * 22
        cutter.guideLubrication = 78 + score * 22
        cutter.crankLubrication = 78 + score * 22
        cutter.gearOilLevel = Runtime.clamp(tonumber(result.gearOilLevel) or cutter.gearOilLevel, 0, 1)
        item.condition = Runtime.calculateCondition(item)
        return true, item
    end
end

return Component
