-- Default save state and legacy job normalization helpers.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.defaultPlacement(config)
        return {
            x = config.spawnX,
            y = config.spawnY,
            direction = config.defaultDirection or "northwest",
            moving = false,
            inMotion = false,
        }
    end

    function Runtime.Schema.defaultState()
        local jack = Runtime.defaultPlacement(Runtime.Config.palletJack)
        jack.operating = false
        jack.animationClock = 0
        return {
            money = 180,
            inventory = {
                paper = 40,
                prints = 0,
                rawPallets = 0,
                inProcessPallets = 0,
                finishedPallets = 0,
                plasticWrapRolls = 1,
                plasticWrapUses = 11,
                stock = { shipping_cartons = 20 },
            },
            shopProgress = { completedCuts = 0 },
            jobs = { active = {}, completed = {}, declined = {} },
            nextJobId = 1,
            accountsReceivable = 0,
            reputation = Runtime.Reputation.defaultState(),
            cutterMemory = {},
            procurement = { orders = {}, nextOrderId = 1, shipments = {}, nextShipmentId = 1 },
            vendorCategory = 1,
            calendar = Runtime.BusinessCalendar.defaultCalendar(),
            bills = Runtime.BusinessCalendar.defaultBills(),
            credit = Runtime.Credit.defaultState(),
            employment = Runtime.Employees.defaultState(0),
            clientEmails = { nextEmailId = 1, nextPromotionId = 1,
                pending = {}, inbox = {}, archive = {}, sentPromotions = {} },
            workPhone = { nextCallId = 1, nextCallAtHours = 6, incoming = nil, history = {} },
            machines = Runtime.MachineFleet.defaultState(),
            cutter = Runtime.defaultPlacement(Runtime.Config.cutterPlacement),
            palletJack = jack,
            warehouse = Runtime.WarehouseUpgrades.defaultState(),
            storage = Runtime.PalletStorage.defaultState(),
            forklift = Runtime.Forklift.defaultState(Runtime.Config.forklift),
            wrapper = Runtime.defaultPlacement(Runtime.Config.wrapperPlacement),
            windmill = Runtime.defaultPlacement(Runtime.Config.windmillPlacement),
        }
    end

    function Runtime.mergePlacement(fallback, source)
        local result = Runtime.copy(fallback)
        if type(source) ~= "table" then return result end
        if Runtime.number(source.x) then result.x = source.x end
        if Runtime.number(source.y) then result.y = source.y end
        if Runtime.directions[source.direction] then result.direction = source.direction end
        result.moving = source.moving == true
        result.inMotion = source.inMotion == true
        return result
    end

    function Runtime.titleForKey(key)
        local result = tostring(key or "client-artwork"):gsub("[_%-]+", " ")
        return (result:gsub("(%a)([%w']*)", function(first, rest)
            return string.upper(first) .. string.lower(rest)
        end))
    end

    function Runtime.artworkOrientation(job)
        local size = job.press and job.press.artworkSize or job.finishedSize
        return Runtime.dimensions(size) and size.width > size.height and "landscape" or "portrait"
    end

    function Runtime.normalizeArtwork(job, required)
        if job.artwork == nil and not required then return end
        if job.artwork == nil then job.artwork = {} end
        if type(job.artwork) ~= "table" then return end
        local key = Runtime.text(job.artwork.key) and job.artwork.key
            or Runtime.text(job.artworkKey) and job.artworkKey or "client-artwork"
        if job.artwork.key == nil then job.artwork.key = key end
        if job.artwork.displayName == nil then job.artwork.displayName = Runtime.titleForKey(key) end
        if job.artwork.fileName == nil then job.artwork.fileName = key .. ".png" end
        if job.artwork.suppliedBy == nil then job.artwork.suppliedBy = "client" end
        if job.artwork.orientation == nil then job.artwork.orientation = Runtime.artworkOrientation(job) end
        if job.artworkKey == nil then job.artworkKey = key end
    end

    function Runtime.legacyStockDescription(job)
        local details = type(job.details) == "table" and job.details or {}
        return Runtime.text(details.stockDescription) and details.stockDescription or "Customer supplied paper"
    end

    function Runtime.normalizeStockSpec(job, required)
        if job.stockSpec == nil and not required then return end
        if job.stockSpec == nil then job.stockSpec = {} end
        if type(job.stockSpec) ~= "table" then return end
        local description = Runtime.legacyStockDescription(job)
        local lower = string.lower(description)
        if job.stockSpec.suppliedBy == nil then job.stockSpec.suppliedBy = "client" end
        if job.stockSpec.grade == nil then
            job.stockSpec.grade = lower:find("cover", 1, true) and "cover"
                or lower:find("text", 1, true) and "text" or "unspecified"
        end
        if job.stockSpec.weight == nil then
            job.stockSpec.weight = tonumber(lower:match("(%d+)%s*lb")) or 0
        end
        if job.stockSpec.finish == nil then
            job.stockSpec.finish = lower:find("gloss", 1, true) and "gloss"
                or lower:find("uncoated", 1, true) and "uncoated" or "unspecified"
        end
        if job.stockSpec.color == nil then job.stockSpec.color = "unspecified" end
        if job.stockSpec.grain == nil then
            local details = type(job.details) == "table" and job.details or {}
            job.stockSpec.grain = Runtime.text(details.grainDirection) and details.grainDirection or "unspecified"
        end
        if job.stockSpec.description == nil then job.stockSpec.description = description end
    end
end

return Component
