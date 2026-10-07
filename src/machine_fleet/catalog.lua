-- Machine definitions, components, pricing helpers, and default inventory.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    Runtime.Fleet = {}
    Runtime.BusinessCalendar = require("src.business_calendar")
    Runtime.Procurement = require("src.procurement")
    Runtime.Config = require("src.config")
    Runtime.Inbox = require("src.inbox")
    Runtime.WarehouseLayout = require("src.warehouse_layout")
    Runtime.Navigation = require("src.navigation")
    Runtime.Assets = require("src.assets")

    Runtime.saleGuard = nil

    Runtime.deliveryStatuses = {
        awaiting_delivery = true,
        scheduled = true,
        backing = true,
        at_bay = true,
        received = true,
    }

    function Runtime.clamp(value, minimum, maximum)
        return math.max(minimum, math.min(maximum, value))
    end

    function Runtime.rounded(value)
        return math.floor(value + 0.5)
    end

    function Runtime.copy(value)
        if type(value) ~= "table" then return value end
        local result = {}
        for key, item in pairs(value) do result[key] = Runtime.copy(item) end
        return result
    end

    Runtime.Fleet.order = { "polar_115", "skid_wrapper", "heidelberg_10x15" }
    Runtime.Fleet.definitions = {
        polar_115 = {
            id = "polar_115",
            name = "Polar 115 programmable cutter",
            shortName = "Polar 115 cutter",
            placementKey = "cutter",
            basePrice = 13134,
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
            basePrice = 23560,
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
            basePrice = 6000,
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

    function Runtime.definition(modelId)
        return Runtime.Fleet.definitions[modelId]
    end

    function Runtime.componentValues(model, startingCondition)
        local values, index = {}, 0
        local offsets = { 2, -3, 1, -1 }
        for componentId in pairs(model.components) do
            index = index + 1
            values[componentId] = startingCondition >= 100 and 100
                or Runtime.clamp(startingCondition + offsets[(index - 1) % #offsets + 1], 0, 100)
        end
        return values
    end

    function Runtime.calculateCondition(item)
        local model = item and Runtime.definition(item.modelId)
        if not model then return 0 end
        local total, weight = 0, 0
        for componentId, component in pairs(model.components) do
            local value = Runtime.clamp(tonumber(item.variables and item.variables[componentId]) or 0, 0, 100)
            total = total + value * component.weight
            weight = weight + component.weight
        end
        return weight > 0 and Runtime.rounded(total / weight * 10) / 10 or 0
    end

    function Runtime.createItem(id, modelId, startingCondition, source, status, price)
        local model = assert(Runtime.definition(modelId), "unknown machine model: " .. tostring(modelId))
        local item = {
            id = id,
            serial = "PS-" .. id,
            modelId = modelId,
            name = model.name,
            source = source or "starter",
            status = status or "stored",
            purchasePrice = math.max(0, Runtime.rounded(price or 0)),
            acquiredAt = os.time(),
            cycles = 0,
            operatingMinutes = 0,
            variables = Runtime.componentValues(model, startingCondition or 100),
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
        item.condition = Runtime.calculateCondition(item)
        return item
    end

    function Runtime.Fleet.defaultState()
        return {
            nextId = 3,
            nextDeliveryId = 1,
            items = {
                Runtime.createItem("MCH-0001", "polar_115", 100, "starter", "installed", 0),
                Runtime.createItem("MCH-0002", "skid_wrapper", 100, "starter", "installed", 0),
            },
            deliveries = {},
            nextServiceNoticeId = 1,
            serviceNotices = {},
        }
    end
end

return Component
