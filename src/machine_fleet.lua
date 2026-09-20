local Fleet = {}
local BusinessCalendar = require("src.business_calendar")
local Procurement = require("src.procurement")
local Config = require("src.config")
local Inbox = require("src.inbox")

local saleGuard = nil

local deliveryStatuses = {
    awaiting_delivery = true,
    scheduled = true,
    backing = true,
    at_bay = true,
    received = true,
}

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function rounded(value)
    return math.floor(value + 0.5)
end

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end

Fleet.order = { "polar_115", "skid_wrapper", "heidelberg_10x15" }
Fleet.definitions = {
    polar_115 = {
        id = "polar_115",
        name = "Polar 115 programmable cutter",
        shortName = "Polar 115 cutter",
        placementKey = "cutter",
        basePrice = 2400,
        onlineCondition = 96,
        dealerCondition = 62,
        components = {
            bladeSharpness = { label = "Blade sharpness", weight = 0.38, wear = 0.18,
                serviceTask = "Inspect and dress the knife edge" },
            hydraulicHealth = { label = "Hydraulic system", weight = 0.27, wear = 0.06,
                serviceTask = "Check pressure and hydraulic seals" },
            backgaugeCalibration = { label = "Backgauge calibration", weight = 0.22, wear = 0.10,
                serviceTask = "Calibrate the backgauge" },
            safetyCircuit = { label = "Safety circuit", weight = 0.13, wear = 0.025,
                serviceTask = "Clean and test the safety sensors" },
        },
    },
    skid_wrapper = {
        id = "skid_wrapper",
        name = "Automatic skid wrapper",
        shortName = "Skid wrapper",
        placementKey = "wrapper",
        basePrice = 1200,
        onlineCondition = 94,
        dealerCondition = 55,
        components = {
            turntableBearing = { label = "Turntable bearing", weight = 0.34, wear = 0.16,
                serviceTask = "Clean and grease the turntable bearing" },
            filmCarriage = { label = "Film carriage", weight = 0.30, wear = 0.20,
                serviceTask = "Align and lubricate the film carriage" },
            driveBelt = { label = "Drive belt", weight = 0.24, wear = 0.13,
                serviceTask = "Inspect and tension the drive belt" },
            controlBoard = { label = "Control board", weight = 0.12, wear = 0.035,
                serviceTask = "Clean and test the control cabinet" },
        },
    },
    heidelberg_10x15 = {
        id = "heidelberg_10x15",
        name = "Original Heidelberg 10x15 Windmill",
        shortName = "Heidelberg Windmill",
        placementKey = "windmill",
        basePrice = 5200,
        onlineCondition = 92,
        dealerCondition = 58,
        components = {
            formRollers = { label = "Form rollers", weight = 0.22, wear = 0.34,
                serviceTask = "Clean and set the roller stripe" },
            gripperTiming = { label = "Grippers and timing", weight = 0.20, wear = 0.19,
                serviceTask = "Inspect gripper pads and register timing" },
            suctionAir = { label = "Suction and air", weight = 0.17, wear = 0.24,
                serviceTask = "Clean suckers and air passages" },
            inkTrain = { label = "Ink distribution", weight = 0.15, wear = 0.27,
                serviceTask = "Deep-clean the ink distribution train" },
            driveLubrication = { label = "Drive lubrication", weight = 0.16, wear = 0.16,
                serviceTask = "Lock out and lubricate the drive points" },
            safetyCircuit = { label = "Safety circuit", weight = 0.10, wear = 0.06,
                serviceTask = "Test guards and emergency controls" },
        },
    },
}

local function definition(modelId)
    return Fleet.definitions[modelId]
end

local function componentValues(model, startingCondition)
    local values, index = {}, 0
    local offsets = { 2, -3, 1, -1 }
    for componentId in pairs(model.components) do
        index = index + 1
        values[componentId] = startingCondition >= 100 and 100
            or clamp(startingCondition + offsets[(index - 1) % #offsets + 1], 0, 100)
    end
    return values
end

local function calculateCondition(item)
    local model = item and definition(item.modelId)
    if not model then return 0 end
    local total, weight = 0, 0
    for componentId, component in pairs(model.components) do
        local value = clamp(tonumber(item.variables and item.variables[componentId]) or 0, 0, 100)
        total = total + value * component.weight
        weight = weight + component.weight
    end
    return weight > 0 and rounded(total / weight * 10) / 10 or 0
end

local function createItem(id, modelId, startingCondition, source, status, price)
    local model = assert(definition(modelId), "unknown machine model: " .. tostring(modelId))
    local item = {
        id = id,
        serial = "PS-" .. id,
        modelId = modelId,
        name = model.name,
        source = source or "starter",
        status = status or "stored",
        purchasePrice = math.max(0, rounded(price or 0)),
        acquiredAt = os.time(),
        cycles = 0,
        operatingMinutes = 0,
        variables = componentValues(model, startingCondition or 100),
        maintenance = {
            serviceCount = 0,
            lastServiceAt = nil,
            lastServiceQuality = nil,
            cutter = nil,
            windmill = nil,
        },
    }
    if modelId == "heidelberg_10x15" then
        item.maintenance.windmill = {
            serviceCount = 0, lastDailyOilHours = nil, lastRollerStripe = 0.8,
            technicianDueDay = nil,
        }
    end
    item.condition = calculateCondition(item)
    return item
end

function Fleet.defaultState()
    return {
        nextId = 3,
        nextDeliveryId = 1,
        items = {
            createItem("MCH-0001", "polar_115", 100, "starter", "installed", 0),
            createItem("MCH-0002", "skid_wrapper", 100, "starter", "installed", 0),
        },
        deliveries = {},
        nextServiceNoticeId = 1,
        serviceNotices = {},
    }
end

local function normalizeItem(item)
    if type(item) ~= "table" or not definition(item.modelId) or type(item.id) ~= "string" then return nil end
    local model = definition(item.modelId)
    item.serial = type(item.serial) == "string" and item.serial or ("PS-" .. item.id)
    item.name = model.name
    item.source = type(item.source) == "string" and item.source or "unknown"
    item.status = item.status == "installed" and "installed" or "stored"
    item.purchasePrice = math.max(0, rounded(tonumber(item.purchasePrice) or 0))
    item.acquiredAt = tonumber(item.acquiredAt) or os.time()
    item.cycles = math.max(0, tonumber(item.cycles) or 0)
    item.operatingMinutes = math.max(0, tonumber(item.operatingMinutes) or 0)
    item.variables = type(item.variables) == "table" and item.variables or {}
    for componentId in pairs(model.components) do
        item.variables[componentId] = clamp(tonumber(item.variables[componentId]) or 100, 0, 100)
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
        cutter.lastLubricationScore = clamp(tonumber(cutter.lastLubricationScore) or 0, 0, 1)
        cutter.backgaugeLubrication = clamp(tonumber(cutter.backgaugeLubrication) or 100, 0, 100)
        cutter.guideLubrication = clamp(tonumber(cutter.guideLubrication) or 100, 0, 100)
        cutter.crankLubrication = clamp(tonumber(cutter.crankLubrication) or 100, 0, 100)
        cutter.gearOilLevel = clamp(tonumber(cutter.gearOilLevel) or 0.48, 0, 1)
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
    item.condition = calculateCondition(item)
    return item
end

local function normalizeDeliveryOrder(order)
    if type(order) ~= "table" or type(order.id) ~= "string"
        or not order.id:match("^MDO%-%d+$")
    then return nil end
    order.delivery = type(order.delivery) == "table" and order.delivery or {}
    local status = deliveryStatuses[order.delivery.status]
        and order.delivery.status or "awaiting_delivery"
    order.delivery.status = status
    order.delivery.orderedAt = tonumber(order.delivery.orderedAt) or os.time()
    for _, key in ipairs({ "scheduledAt", "arrivedAt", "receivedAt" }) do
        if type(order.delivery[key]) ~= "number" then order.delivery[key] = nil end
    end
    order.item = status ~= "received" and normalizeItem(order.item) or nil
    if status ~= "received" and not order.item then return nil end
    local modelId = order.item and order.item.modelId or order.modelId
    local model = definition(modelId)
    local machineId = order.item and order.item.id or order.machineId
    if not model or type(machineId) ~= "string" or not machineId:match("^MCH%-%d+$") then return nil end
    if order.item then order.item.status = "stored" end
    order.machineId = machineId
    order.modelId = modelId
    order.machineName = model.name
    order.condition = order.item and calculateCondition(order.item)
        or clamp(tonumber(order.condition) or 0, 0, 100)
    order.price = math.max(0, rounded(tonumber(order.price) or 0))
    order.company = type(order.company) == "string" and order.company or "Picture Shop Online Equipment"
    return order
end

function Fleet.ensure(state)
    assert(type(state) == "table", "machine fleet requires game state")
    if type(state.machines) ~= "table" then state.machines = Fleet.defaultState() end
    local fleet = state.machines
    fleet.items = type(fleet.items) == "table" and fleet.items or {}
    local normalized, installed, machineIds = {}, {}, {}
    local highestId = 0
    for _, source in ipairs(fleet.items) do
        local item = normalizeItem(source)
        if item and not machineIds[item.id] then
            local number = tonumber(item.id:match("^MCH%-(%d+)$"))
            highestId = math.max(highestId, number or 0)
            if item.status == "installed" then
                if installed[item.modelId] then item.status = "stored" else installed[item.modelId] = true end
            end
            machineIds[item.id] = true
            normalized[#normalized + 1] = item
        end
    end
    fleet.items = normalized
    fleet.deliveries = type(fleet.deliveries) == "table" and fleet.deliveries or {}
    local deliveries, deliveryIds = {}, {}
    local highestDeliveryId = 0
    for _, source in ipairs(fleet.deliveries) do
        local order = normalizeDeliveryOrder(source)
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

function Fleet.definition(modelId) return definition(modelId) end

function Fleet.condition(item)
    if item then item.condition = calculateCondition(item) end
    return item and item.condition or 0
end

function Fleet.conditionStatus(value)
    value = tonumber(value) or 0
    if value >= 90 then return "Excellent"
    elseif value >= 75 then return "Good"
    elseif value >= 55 then return "Fair"
    elseif value >= 30 then return "Poor"
    end
    return "Critical"
end

function Fleet.owned(state)
    local result = {}
    for _, item in ipairs(Fleet.ensure(state).items) do result[#result + 1] = item end
    return result
end

function Fleet.addServiceNotice(state, subject, body, sender)
    local fleet = Fleet.ensure(state)
    local notice = {
        id = string.format("SERVICE-%04d", fleet.nextServiceNoticeId),
        sender = sender or "Precision Blade Service",
        subject = tostring(subject),
        body = tostring(body),
        receivedAtHours = BusinessCalendar.absoluteHours(state),
        serviceNotice = true,
    }
    fleet.nextServiceNoticeId = fleet.nextServiceNoticeId + 1
    fleet.serviceNotices[#fleet.serviceNotices + 1] = notice
    return notice
end

function Fleet.serviceInbox(state)
    return Fleet.ensure(state).serviceNotices
end

function Fleet.dismissServiceNotice(state, noticeId)
    local notices = Fleet.ensure(state).serviceNotices
    for index, notice in ipairs(notices) do
        if notice.id == noticeId then return table.remove(notices, index) end
    end
end

function Fleet.completeCutterOiling(state, machineId, score)
    return Fleet.completeCutterLubrication(state, machineId, { score = score })
end

function Fleet.completeCutterLubrication(state, machineId, result)
    local item = Fleet.byId(state, machineId)
    if not item or item.modelId ~= "polar_115" then return false, "Cutter not found." end
    local stock = state.inventory and state.inventory.stock or {}
    if (stock.maintenance_kit or 0) < 1 then return false, "A machine maintenance kit is required." end
    result = type(result) == "table" and result or {}
    local score = clamp(tonumber(result.score) or 0, 0, 1)
    local consumed, consumptionError = Procurement.consumePhysicalProduct(state, "maintenance_kit", 1, {allowAbstract=true})
    if not consumed then return false, consumptionError end
    stock.maintenance_kit = stock.maintenance_kit - 1
    -- Hydraulic oil is deliberately excluded: it remains technician-only work.
    item.variables.hydraulicHealth = clamp(item.variables.hydraulicHealth + 3 + score * 5, 0, 100)
    item.variables.backgaugeCalibration = clamp(item.variables.backgaugeCalibration + 8 + score * 10, 0, 100)
    item.variables.safetyCircuit = clamp(item.variables.safetyCircuit + 4 + score * 6, 0, 100)
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
    cutter.gearOilLevel = clamp(tonumber(result.gearOilLevel) or cutter.gearOilLevel, 0, 1)
    item.condition = calculateCondition(item)
    return true, item
end

function Fleet.byId(state, machineId)
    for _, item in ipairs(Fleet.ensure(state).items) do
        if item.id == machineId then return item end
    end
end

function Fleet.installed(state, modelId)
    for _, item in ipairs(Fleet.ensure(state).items) do
        if item.modelId == modelId and item.status == "installed" then return item end
    end
end

function Fleet.isInstalled(state, modelId)
    return Fleet.installed(state, modelId) ~= nil
end

function Fleet.canOperate(state, modelId)
    local item = Fleet.installed(state, modelId)
    if not item then return false, "This machine is not installed in the shop." end
    if modelId == "polar_115" and item.maintenance.cutter.bladeRemoved then
        return false, "The cutter blade is removed for sharpening. Reinstall it before production."
    end
    if modelId == "heidelberg_10x15" and item.variables.safetyCircuit < 20 then
        return false, "The Windmill safety circuit must be serviced before production."
    end
    local condition = Fleet.condition(item)
    if condition < 15 then
        return false, item.name .. " is in critical condition and must be maintained before it can run."
    end
    return true, item
end

function Fleet.recordUse(state, modelId, cycles)
    local item = Fleet.installed(state, modelId)
    local model = item and definition(item.modelId)
    if not item or not model then return false, "No installed machine can receive wear." end
    cycles = math.max(0, tonumber(cycles) or 1)
    for componentId, component in pairs(model.components) do
        item.variables[componentId] = clamp(item.variables[componentId] - component.wear * cycles, 0, 100)
    end
    item.cycles = item.cycles + cycles
    item.operatingMinutes = item.operatingMinutes + cycles * (modelId == "heidelberg_10x15" and 20 or 0.25)
    if modelId == "polar_115" and item.maintenance.cutter then
        local cutter = item.maintenance.cutter
        cutter.backgaugeLubrication = clamp(cutter.backgaugeLubrication - cycles * 0.30, 0, 100)
        cutter.guideLubrication = clamp(cutter.guideLubrication - cycles * 0.24, 0, 100)
        cutter.crankLubrication = clamp(cutter.crankLubrication - cycles * 0.20, 0, 100)
        cutter.gearOilLevel = clamp(cutter.gearOilLevel - cycles * 0.00035, 0, 1)
    end
    item.condition = calculateCondition(item)
    return true, item
end

function Fleet.maintenancePlan(state, machineId)
    local item = Fleet.byId(state, machineId)
    local model = item and definition(item.modelId)
    if not item or not model then return nil, "Machine not found." end
    local tasks = {}
    for componentId, component in pairs(model.components) do
        tasks[#tasks + 1] = {
            id = componentId,
            label = component.serviceTask,
            componentLabel = component.label,
            health = item.variables[componentId],
            -- Future sprite minigames can bind a moving/interactive scene to
            -- this stable component id without changing the save contract.
            sceneId = item.modelId .. ":" .. componentId,
        }
    end
    table.sort(tasks, function(a, b) return a.health < b.health end)
    return { machineId = item.id, modelId = item.modelId, tasks = tasks }
end

function Fleet.completeMaintenance(state, machineId, taskScores)
    local item = Fleet.byId(state, machineId)
    local model = item and definition(item.modelId)
    if not item or not model then return false, "Machine not found." end
    local stock = state.inventory and state.inventory.stock or {}
    if (stock.maintenance_kit or 0) < 1 then return false, "A machine maintenance kit is required." end
    local consumed, consumptionError = Procurement.consumePhysicalProduct(state, "maintenance_kit", 1, {allowAbstract=true})
    if not consumed then return false, consumptionError end
    local total, count = 0, 0
    for componentId in pairs(model.components) do
        local score = type(taskScores) == "table" and tonumber(taskScores[componentId]) or nil
        score = clamp(score or 0, 0, 1)
        total, count = total + score, count + 1
        item.variables[componentId] = clamp(item.variables[componentId] + 25 + score * 45, 0, 100)
    end
    local quality = count > 0 and total / count or 0
    stock.maintenance_kit = stock.maintenance_kit - 1
    item.maintenance.serviceCount = item.maintenance.serviceCount + 1
    item.maintenance.lastServiceAt = os.time()
    item.maintenance.lastServiceQuality = rounded(quality * 100) / 100
    item.condition = calculateCondition(item)
    return true, item
end

function Fleet.priceFor(modelId, condition, channel)
    local model = definition(modelId)
    if not model then return 0 end
    condition = clamp(tonumber(condition) or 0, 0, 100)
    local channelFactor = channel == "dealer" and 0.84 or 1
    return rounded(model.basePrice * (0.25 + condition / 100 * 0.75) * channelFactor)
end

function Fleet.resaleValue(item, channel)
    local market = Fleet.priceFor(item.modelId, Fleet.condition(item), "online")
    return rounded(market * (channel == "dealer" and 0.48 or 0.62))
end

function Fleet.offers(channel)
    channel = channel == "dealer" and "dealer" or "online"
    local result = {}
    for index, modelId in ipairs(Fleet.order) do
        local model = definition(modelId)
        local condition = channel == "dealer" and model.dealerCondition or model.onlineCondition
        result[#result + 1] = {
            id = string.format("%s-%s-%02d", channel:upper(), modelId, index),
            channel = channel,
            modelId = modelId,
            name = model.name,
            condition = condition,
            conditionStatus = Fleet.conditionStatus(condition),
            price = Fleet.priceFor(modelId, condition, channel),
        }
    end
    return result
end

function Fleet.pendingDeliveries(state)
    local result = {}
    for _, order in ipairs(Fleet.ensure(state).deliveries) do
        if order.delivery.status ~= "received" then result[#result + 1] = order end
    end
    return result
end

function Fleet.orderById(state, orderId)
    for _, order in ipairs(Fleet.ensure(state).deliveries) do
        if order.id == orderId then return order end
    end
end

function Fleet.nextInbound(state)
    for _, order in ipairs(Fleet.ensure(state).deliveries) do
        -- Truck motion is intentionally transient. Any undelivered unit is
        -- schedulable again after loading a save, even if its last saved
        -- manifest state said scheduled/backing/at_bay.
        if order.delivery.status ~= "received" and order.item then return order end
    end
end

function Fleet.orderOnline(state, offerIndex)
    local offer = Fleet.offers("online")[tonumber(offerIndex) or 0]
    if not offer then return false, "That machine listing is no longer available." end
    if (state.money or 0) < offer.price then return false, "Not enough money for this machine." end
    local fleet = Fleet.ensure(state)
    local machineId = string.format("MCH-%04d", fleet.nextId)
    local orderId = string.format("MDO-%04d", fleet.nextDeliveryId)
    fleet.nextId = fleet.nextId + 1
    fleet.nextDeliveryId = fleet.nextDeliveryId + 1
    local item = createItem(machineId, offer.modelId, offer.condition, "online", "stored", offer.price)
    local order = {
        id = orderId,
        company = "CritterNet Machine Market",
        machineId = machineId,
        modelId = offer.modelId,
        machineName = offer.name,
        condition = item.condition,
        price = offer.price,
        item = item,
        delivery = {
            status = "awaiting_delivery",
            orderedAt = os.time(),
            expectedAtHours = BusinessCalendar.absoluteHours(state),
        },
    }
    fleet.deliveries[#fleet.deliveries + 1] = order
    state.money = state.money - offer.price
    Inbox.addNotice(state, {
        id = "RECEIPT-" .. orderId,
        sender = "CritterNet Machine Market",
        subject = "Receipt for " .. orderId,
        body = string.format(
            "Payment received for %s at %.0f%% condition from www.thecritternet.com. Order %s total: $%d. Keep this email as your receipt. Flatbed delivery will bring unit %s to the shop.",
            offer.name, item.condition, orderId, offer.price, machineId),
        noticeKind = "receipt",
        orderId = orderId,
        total = offer.price,
    })
    return true, order
end

function Fleet.truckInventory(state, orderId)
    local order = Fleet.orderById(state, orderId)
    if not order or order.delivery.status == "received" or not order.item then return order, {} end
    return order, { order.item }
end

function Fleet.remainingOnTruck(state, orderId)
    local order = Fleet.orderById(state, orderId)
    return order and order.delivery.status ~= "received" and order.item and 1 or 0
end

function Fleet.unloadDelivery(state, orderId, machineId, now)
    local fleet = Fleet.ensure(state)
    local order = Fleet.orderById(state, orderId)
    if not order or order.delivery.status == "received" or not order.item then
        return false, "That machine is no longer on the flatbed."
    end
    if order.item.id ~= machineId then return false, "That machine is not on this delivery manifest." end
    local item = order.item
    item.status = Fleet.installed(state, item.modelId) and "stored" or "installed"
    local receiving = Config.machineReceiving and Config.machineReceiving[item.modelId]
    if item.status == "stored" and receiving then
        local storedCount = 0
        for _, candidate in ipairs(fleet.items) do
            if candidate.status == "stored" and candidate.world then storedCount = storedCount + 1 end
        end
        item.world = {
            x = receiving.x + storedCount * 26,
            y = receiving.y + storedCount * 22,
            direction = receiving.direction or "northwest",
        }
    end
    fleet.items[#fleet.items + 1] = item
    order.item = nil
    order.delivery.status = "received"
    order.delivery.receivedAt = now or os.time()
    order.delivery.receivedAtHours = BusinessCalendar.absoluteHours(state)
    return true, item, 0
end

function Fleet.buy(state, channel, offerIndex)
    if channel ~= "dealer" then return Fleet.orderOnline(state, offerIndex) end
    local offers = Fleet.offers(channel)
    local offer = offers[tonumber(offerIndex) or 0]
    if not offer then return false, "That machine listing is no longer available." end
    if (state.money or 0) < offer.price then return false, "Not enough money for this machine." end
    local fleet = Fleet.ensure(state)
    local id = string.format("MCH-%04d", fleet.nextId)
    fleet.nextId = fleet.nextId + 1
    local status = Fleet.installed(state, offer.modelId) and "stored" or "installed"
    local item = createItem(id, offer.modelId, offer.condition, offer.channel, status, offer.price)
    fleet.items[#fleet.items + 1] = item
    state.money = state.money - offer.price
    return true, item
end

local function machineOwnsCutterPallet(state, item)
    if item.modelId ~= "polar_115" then return false end
    for _, job in ipairs(state.jobs and state.jobs.active or {}) do
        for _, pallet in ipairs(job.pallets or {}) do
            if pallet.location == "at_cutter" then return true end
        end
    end
    return false
end

local function installedWindmillIsLoaded(state, item)
    if item.modelId ~= "heidelberg_10x15" or item.status ~= "installed" then return false end
    local placement = type(state.windmill) == "table" and state.windmill or {}
    local process = type(placement.process) == "table" and placement.process or {}
    return process.palletId ~= nil
end

local function printWorkNeedsWindmill(state)
    for _, job in ipairs(state.jobs and state.jobs.active or {}) do
        if type(job.press) == "table" then
            local pallets = type(job.pallets) == "table" and job.pallets or {}
            if #pallets == 0 then return true end
            for _, pallet in ipairs(pallets) do
                if type(pallet.press) ~= "table" or pallet.press.status ~= "complete" then
                    return true
                end
            end
        end
    end
    return false
end

local function hasStoredReplacement(fleet, item)
    for _, candidate in ipairs(fleet.items) do
        if candidate ~= item and candidate.modelId == item.modelId and candidate.status == "stored" then
            return true
        end
    end
    return false
end

function Fleet.sell(state, machineId, channel)
    local fleet = Fleet.ensure(state)
    local foundIndex, item
    for index, candidate in ipairs(fleet.items) do
        if candidate.id == machineId then foundIndex, item = index, candidate; break end
    end
    if not item then return false, "That machine is no longer owned by the shop." end
    if saleGuard then
        local allowed, reason = saleGuard(state, item)
        if allowed == false then
            return false, tostring(reason or "That machine is currently in use.")
        end
    end
    if machineOwnsCutterPallet(state, item) then
        return false, "Unload the cutter before listing it for sale."
    end
    if installedWindmillIsLoaded(state, item) then
        return false, "Unload the Windmill before listing it for sale."
    end
    if item.modelId == "heidelberg_10x15" and item.status == "installed"
        and printWorkNeedsWindmill(state) and not hasStoredReplacement(fleet, item)
    then
        return false, "Finish the active print work or keep a replacement Windmill before selling this press."
    end
    local value = Fleet.resaleValue(item, channel)
    local wasInstalled = item.status == "installed"
    table.remove(fleet.items, foundIndex)
    if wasInstalled then
        for _, candidate in ipairs(fleet.items) do
            if candidate.modelId == item.modelId and candidate.status == "stored" then
                candidate.status = "installed"
                break
            end
        end
    end
    state.money = (state.money or 0) + value
    return true, { machine = item, price = value, channel = channel == "dealer" and "dealer" or "online" }
end

function Fleet.setSaleGuard(guard)
    local previous = saleGuard
    saleGuard = type(guard) == "function" and guard or nil
    return previous
end

function Fleet.weakestComponent(item)
    local model = item and definition(item.modelId)
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

function Fleet.validState(value)
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
        local model = type(item) == "table" and definition(item.modelId)
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
        return math.abs(calculateCondition(item) - item.condition) <= 0.11
    end

    local ids, installed = {}, {}
    if not denseArray(value.items) or not denseArray(value.deliveries)
        or not denseArray(value.serviceNotices)
    then return false end
    for index, item in ipairs(value.items) do
        if not validMachineRecord(item) or ids[item.id] then return false end
        ids[item.id] = true
        if item.status == "installed" then
            if installed[item.modelId] then return false end
            installed[item.modelId] = true
        end
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
            or not definition(order.modelId) or type(order.machineName) ~= "string"
            or type(order.company) ~= "string" or type(order.price) ~= "number" or order.price < 0
            or type(order.condition) ~= "number" or order.condition < 0 or order.condition > 100
            or type(delivery) ~= "table" or not deliveryStatuses[delivery.status]
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
        then return false end
        noticeIds[notice.id] = true
    end
    return true
end

Fleet.copy = copy
return Fleet
