-- Job templates, artwork, delivery services, and deterministic selection.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    -- Connects pure job-domain rules to the game's saved shop state.
    Runtime.Jobs = require("src.jobs")
    Runtime.PalletState = require("src.pallet_state")
    Runtime.Config = require("src.config")
    Runtime.BusinessCalendar = require("src.business_calendar")
    Runtime.MachineFleet = require("src.machine_fleet")
    Runtime.Inbox = require("src.inbox")
    Runtime.Reputation = require("src.reputation")
    Runtime.Labor = require("src.employee_labor")

    Runtime.JobService = {}

    Runtime.DELIVERY_SERVICES = {
        express = { id = "express", label = "EXPRESS / URGENT", description = "Arrives within hours" },
        quick = { id = "quick", label = "QUICK", description = "Arrives within half a day" },
        standard = { id = "standard", label = "STANDARD", description = "Arrives within a day" },
    }

    Runtime.templates = {
        {
            difficulty = "easy",
            company = "Blue Ridge Packaging",
            sourceSize = { width = 25, height = 19 },
            finishedSize = { width = 12.5, height = 9.5 },
            sheetCounts = { 1000, 750 },
            packaging = "boxed",
            details = {
                stockDescription = "80 lb customer-supplied cover stock",
                dueDate = "Standard 5-business-day turnaround",
                grainDirection = "Grain long; keep orientation consistent",
                notes = "Keep the two pallets separated and retain all customer skid labels.",
            },
        },
        {
            difficulty = "medium",
            company = "Northstar Bindery",
            sourceSize = { width = 23, height = 17.5 },
            finishedSize = { width = 11.5, height = 8.75 },
            sheetCounts = { 1500 },
            packaging = "flat",
            details = {
                stockDescription = "100 lb gloss text",
                dueDate = "Standard 5-business-day turnaround",
                grainDirection = "Grain long",
                notes = "Protect the gloss surface and wrap the finished skid before pickup.",
            },
        },
        {
            difficulty = "hard",
            company = "Keystone Paper Supply",
            sourceSize = { width = 25, height = 25 },
            finishedSize = { width = 20, height = 12.5 },
            sheetCounts = { 3000, 3000, 2000 },
            packaging = "flat",
            details = {
                stockDescription = "Uncoated offset sheets",
                dueDate = "Standard 7-business-day turnaround",
                grainDirection = "Grain short",
                notes = "Count and label every finished pallet separately.",
            },
        },
    }

    Runtime.starterTemplate = {
        difficulty = "easy",
        company = "Corner Copy & Mail",
        sourceSize = { width = 17, height = 11 },
        finishedSize = { width = 8.5, height = 11 },
        sheetCounts = { 500 },
        packaging = "flat",
        stockSpec = { suppliedBy = "client", grade = "text", weight = 60, finish = "uncoated",
            color = "white", grain = "long", description = "60 lb white uncoated text" },
        details = {
            stockDescription = "60 lb white uncoated text",
            dueDate = "Flexible starter-job turnaround",
            grainDirection = "Grain long",
            notes = "Your shop is unrated, so this client is offering one small trial pallet.",
        },
    }

    Runtime.pressTemplates = {
        {
            difficulty = "easy",
            company = "Foundry Coffee Roasters",
            sourceSize = { width = 10, height = 15 },
            finishedSize = { width = 5, height = 7 },
            sheetCounts = { 1050 },
            packaging = "flat",
            artworkKey = "ad-garlic-bread",
            artwork = { key = "ad-garlic-bread", displayName = "Foundry Coffee Table Card",
                fileName = "foundry-coffee-table-card.png", suppliedBy = "client", orientation = "portrait" },
            stockSpec = { suppliedBy = "client", grade = "cover", weight = 80, finish = "uncoated",
                color = "natural white", grain = "long", description = "80 lb uncoated cover" },
            press = { colors = 1, coverage = 0.32, artworkSize = { width = 4.25, height = 6.25 },
                colorSequence = { "Black" }, requestedCopies = { 1000 } },
            details = { stockDescription = "80 lb uncoated cover", dueDate = "Five business days",
                grainDirection = "Grain long", notes = "Client supplied final artwork and 50 extra sheets for setup and spoilage." },
        },
        {
            difficulty = "hard",
            company = "Lantern House Events",
            sourceSize = { width = 10, height = 15 },
            finishedSize = { width = 7, height = 10 },
            sheetCounts = { 1575 },
            packaging = "boxed",
            artworkKey = "ad-fashion-tailored",
            artwork = { key = "ad-fashion-tailored", displayName = "Lantern House Gala Invitation",
                fileName = "lantern-house-gala-invitation.png", suppliedBy = "client", orientation = "portrait" },
            stockSpec = { suppliedBy = "client", grade = "cover", weight = 100, finish = "gloss",
                color = "bright white", grain = "long", description = "100 lb gloss cover" },
            press = { colors = 2, coverage = 0.48, artworkSize = { width = 6.25, height = 9 },
                colorSequence = { "Warm Red", "Black" }, requestedCopies = { 1500 } },
            details = { stockDescription = "100 lb gloss cover", dueDate = "Seven business days",
                grainDirection = "Grain long", notes = "Client supplied final gala artwork and 75 extra sheets; hold tight register." },
        },
        {
            difficulty = "medium",
            company = "Maple Street Books",
            sourceSize = { width = 10, height = 15 },
            finishedSize = { width = 6, height = 9 },
            sheetCounts = { 2100 },
            packaging = "flat",
            artworkKey = "ad-photos",
            artwork = { key = "ad-photos", displayName = "Maple Street Reading Series Poster",
                fileName = "maple-street-reading-series.png", suppliedBy = "client", orientation = "portrait" },
            stockSpec = { suppliedBy = "client", grade = "cover", weight = 90, finish = "uncoated",
                color = "cream", grain = "long", description = "90 lb cream uncoated cover" },
            press = { colors = 2, coverage = 0.42, artworkSize = { width = 5.4, height = 8.25 },
                colorSequence = { "Forest Green", "Black" }, requestedCopies = { 2000 } },
            details = { stockDescription = "90 lb cream uncoated cover", dueDate = "Six business days",
                grainDirection = "Grain long", notes = "Client supplied poster art and 100 extra sheets for proofing and spoilage." },
        },
    }

    function Runtime.copy(value)
        if type(value) ~= "table" then return value end
        local result = {}
        for key, item in pairs(value) do result[key] = Runtime.copy(item) end
        return result
    end

    function Runtime.artworkName(key)
        local value = tostring(key or "artwork"):gsub("[-_]", " ")
        return (value:gsub("(%a)([%w']*)", function(first, rest) return first:upper() .. rest end))
    end

    function Runtime.artworkRecord(key, artworkSize)
        return {
            key = key,
            displayName = Runtime.artworkName(key),
            fileName = key .. ".png",
            suppliedBy = "client",
            orientation = artworkSize and artworkSize.width > artworkSize.height and "landscape" or "portrait",
        }
    end

    function Runtime.nextSequence(state)
        local sequence = type(state.nextJobId) == "number" and math.floor(state.nextJobId) or 1
        return math.max(1, sequence)
    end

    -- Keep the choice stable for a given job number so it survives save/load,
    -- while still distributing the full artwork library unpredictably.
    function Runtime.artworkSeed(state)
        state.jobs = type(state.jobs) == "table" and state.jobs or {}
        if type(state.jobs.artworkSeed) ~= "number" then
            local timerPart = love and love.timer and math.floor(love.timer.getTime() * 100000) or 0
            state.jobs.artworkSeed = (os.time() * 1009 + timerPart) % 2147483647
        end
        return state.jobs.artworkSeed
    end

    function Runtime.artworkForSequence(state, sequence)
        local artwork = Runtime.Config.artworkOrder or {}
        if #artwork == 0 then return "flower" end
        local hash = (sequence * 1103515245 + Runtime.artworkSeed(state) * 1664525 + 12345) % 2147483648
        return artwork[(hash % #artwork) + 1]
    end

    function Runtime.stableDeliveryHash(job, sequence)
        if type(sequence) == "number" then return math.max(1, math.floor(sequence)) end
        local hash = 0
        for index = 1, #(job and job.id or "job") do
            hash = (hash * 31 + string.byte(job.id, index)) % 2147483647
        end
        return hash
    end

    function Runtime.deliveryService(job, sequence)
        local hash = Runtime.stableDeliveryHash(job, sequence)
        local earlyOrder = { "express", "quick", "standard", "express", "express" }
        local order = type(sequence) == "number" and sequence <= 15
            and earlyOrder or { "express", "quick", "standard" }
        local id = order[(hash - 1) % #order + 1]
        local service = Runtime.copy(Runtime.DELIVERY_SERVICES[id])
        if id == "express" then
            service.delayHours = 2 + (hash * 3) % 5 -- deterministic 2-6 hour window
        elseif id == "quick" then
            service.delayHours = 6 + hash % 7 -- deterministic 6-12 hour window
        else
            service.delayHours = 12 + hash % 13 -- deterministic 12-24 hour window
        end
        return service
    end

    function Runtime.JobService.deliveryServiceFor(job, sequence)
        return Runtime.deliveryService(job, sequence)
    end
end

return Component
