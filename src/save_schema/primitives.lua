-- Save schema version, dependencies, and primitive validators.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    Runtime.Config = require("src.config")
    Runtime.PaperWork = require("src.paper_work")
    Runtime.BusinessCalendar = require("src.business_calendar")
    Runtime.MachineFleet = require("src.machine_fleet")
    Runtime.Reputation = require("src.reputation")
    Runtime.PalletState = require("src.pallet_state")
    Runtime.WarehouseUpgrades = require("src.warehouse_upgrades")
    Runtime.BreakroomGames = require("src.breakroom_games")
    Runtime.PalletStorage = require("src.pallet_storage")
    Runtime.Forklift = require("src.forklift")
    Runtime.WarehouseConstruction = require("src.warehouse_construction")
    Runtime.StagingAreas = require("src.staging_areas")
    Runtime.Credit = require("src.credit")
    Runtime.Employees = require("src.employees")
    Runtime.Labor = require("src.employee_labor")

    Runtime.Schema = { VERSION = 23, SLOT_COUNT = 3 }
    Runtime.directions = {
        northwest = true, north = true, northeast = true, east = true,
        southeast = true, south = true, southwest = true, west = true,
    }

    function Runtime.copy(value)
        if type(value) ~= "table" then return value end
        local result = {}
        for key, item in pairs(value) do result[key] = Runtime.copy(item) end
        return result
    end

    function Runtime.number(value)
        return type(value) == "number" and value == value and value > -math.huge and value < math.huge
    end

    function Runtime.nonnegative(value) return Runtime.number(value) and value >= 0 end
    function Runtime.integer(value) return Runtime.number(value) and value == math.floor(value) end
    function Runtime.nonnegativeInteger(value) return Runtime.integer(value) and value >= 0 end
    function Runtime.positiveInteger(value) return Runtime.integer(value) and value >= 1 end
    function Runtime.text(value) return type(value) == "string" and value ~= "" end
    function Runtime.optionalNumber(value) return value == nil or Runtime.number(value) end
    function Runtime.optionalText(value) return value == nil or Runtime.text(value) end
    function Runtime.optionalNonnegative(value) return value == nil or Runtime.nonnegative(value) end
    function Runtime.optionalNonnegativeInteger(value) return value == nil or Runtime.nonnegativeInteger(value) end
    function Runtime.optionalPositiveInteger(value) return value == nil or Runtime.positiveInteger(value) end
    function Runtime.optionalBoolean(value) return value == nil or type(value) == "boolean" end

    function Runtime.validSlot(slot)
        return Runtime.integer(slot) and slot >= 1 and slot <= Runtime.Schema.SLOT_COUNT
    end

    function Runtime.array(value, validator)
        if type(value) ~= "table" then return false end
        local count, highest = 0, 0
        for key, item in pairs(value) do
            if not Runtime.positiveInteger(key) then return false end
            count = count + 1
            highest = math.max(highest, key)
            if validator and not validator(item) then return false end
        end
        return count == highest
    end

    -- Raw local loads and legacy normalization can precede the full schema check.
    -- Reject malformed physical containers before traversing them, and reject a
    -- shared vehicle operator before snapshot normalization removes active flags.
    function Runtime.Schema.validPhysicalSource(value)
        if type(value) ~= "table" then return false end
        for _, field in ipairs({"jobs", "procurement", "palletJack", "forklift", "constructionWorker"}) do
            if value[field] ~= nil and type(value[field]) ~= "table" then return false end
        end
        local function group(record)
            return type(record) == "table" and (record.pallets == nil
                or Runtime.array(record.pallets, function(pallet) return type(pallet) == "table" end))
        end
        for _, field in ipairs({"active", "completed", "declined"}) do
            local collection = value.jobs and value.jobs[field]
            if collection ~= nil and not Runtime.array(collection, group) then return false end
        end
        if value.procurement and value.procurement.orders ~= nil
            and not Runtime.array(value.procurement.orders, group) then return false end
        local jack, lift = value.palletJack, value.forklift
        if jack and lift and jack.operating == true and lift.operating == true
            and jack.operatorPlayerId ~= nil and jack.operatorPlayerId == lift.operatorPlayerId then return false end
        return true
    end
end

return Component
