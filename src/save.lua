-- Versioned, local-only save slots. The payload is plain Lua data written by
-- our serializer; loading executes it in an empty environment and validates
-- the resulting table before it reaches game state.
local Config = require("src.config")

local save = {}
local VERSION = 2
local LEGACY_VERSION = 1
local SLOT_COUNT = 3

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end

local function slotPath(slot)
    if type(slot) ~= "number" or slot < 1 or slot > SLOT_COUNT or slot % 1 ~= 0 then return nil end
    return string.format("saves/slot%d.lua", slot)
end

local function encode(value, indent)
    indent = indent or ""
    local kind = type(value)
    if kind == "number" or kind == "boolean" then return tostring(value) end
    if kind == "string" then return string.format("%q", value) end
    if kind ~= "table" then return "nil" end
    local lines = { "{\n" }
    for key, item in pairs(value) do
        local keyText = type(key) == "string" and string.format("[%q]", key) or "[" .. tostring(key) .. "]"
        lines[#lines + 1] = indent .. "  " .. keyText .. " = " .. encode(item, indent .. "  ") .. ",\n"
    end
    lines[#lines + 1] = indent .. "}"
    return table.concat(lines)
end

local function validCore(payload)
    return type(payload) == "table"
        and type(payload.state) == "table"
        and type(payload.state.money) == "number"
        and type(payload.state.inventory) == "table"
        and (payload.state.inventory.paper == nil or type(payload.state.inventory.paper) == "number")
        and (payload.state.inventory.prints == nil or type(payload.state.inventory.prints) == "number")
        and (payload.state.shopProgress == nil or type(payload.state.shopProgress) == "table")
        and type(payload.player) == "table"
        and type(payload.player.x) == "number"
        and type(payload.player.y) == "number"
end

local function validV2(payload)
    local state = payload and payload.state
    local inventory = state and state.inventory
    local jobs = state and state.jobs
    return validCore(payload)
        and type(jobs) == "table"
        and type(jobs.active) == "table"
        and type(jobs.completed) == "table"
        and type(jobs.declined) == "table"
        and type(state.nextJobId) == "number"
        and state.nextJobId >= 1
        and state.nextJobId == math.floor(state.nextJobId)
        and type(state.accountsReceivable) == "number"
        and (inventory.rawPallets == nil or type(inventory.rawPallets) == "number")
        and (inventory.inProcessPallets == nil or type(inventory.inProcessPallets) == "number")
        and (inventory.finishedPallets == nil or type(inventory.finishedPallets) == "number")
end

local function migrate(payload)
    if type(payload) ~= "table" or not validCore(payload) then return nil end
    if payload.version == VERSION then return payload end
    if payload.version ~= LEGACY_VERSION then return nil end

    -- Keep all legacy gameplay data while adding the v2 fields. Optional
    -- fields are deliberately defaulted so old saves remain playable.
    local state = payload.state
    local inventory = copy(state.inventory)
    inventory.paper = type(inventory.paper) == "number" and inventory.paper or 0
    inventory.prints = type(inventory.prints) == "number" and inventory.prints or 0
    inventory.rawPallets = 0
    inventory.inProcessPallets = 0
    inventory.finishedPallets = 0
    return {
        version = VERSION,
        slot = payload.slot,
        createdAt = payload.createdAt,
        updatedAt = payload.updatedAt,
        state = {
            money = state.money,
            inventory = inventory,
            shopProgress = state.shopProgress or { completedCuts = 0 },
            jobs = { active = {}, completed = {}, declined = {} },
            nextJobId = 1,
            accountsReceivable = 0,
            procurement = { orders = {}, nextOrderId = 1 },
            vendorCategory = 1,
            cutter = {
                x = Config.cutterPlacement.spawnX,
                y = Config.cutterPlacement.spawnY,
                direction = Config.cutterPlacement.defaultDirection,
                moving = false,
            },
            palletJack = {
                x = Config.palletJack.spawnX,
                y = Config.palletJack.spawnY,
                direction = "northwest",
                operating = false,
                moving = false,
            },
        },
        player = { x = payload.player.x, y = payload.player.y },
    }
end

local function validPayload(payload)
    return payload ~= nil
        and payload.version == VERSION
        and validV2(payload)
end

local function read(slot)
    local path = slotPath(slot)
    if not path or not love.filesystem.getInfo(path) then return nil end
    local source = love.filesystem.read(path)
    if not source then return nil end
    local chunk = loadstring("return " .. source)
    if not chunk then return nil end
    setfenv(chunk, {})
    local ok, payload = pcall(chunk)
    if ok then
        local migrated = migrate(payload)
        if validPayload(migrated) then return migrated end
    end
    return nil
end

function save.newGame(slot)
    assert(slotPath(slot), "save slot must be 1, 2, or 3")
    local now = os.time()
    return {
        version = VERSION,
        slot = slot,
        createdAt = now,
        updatedAt = now,
        state = {
            money = 180,
            inventory = {
                paper = 40,
                prints = 0,
                rawPallets = 0,
                inProcessPallets = 0,
                finishedPallets = 0,
            },
            shopProgress = { completedCuts = 0 },
            jobs = { active = {}, completed = {}, declined = {} },
            nextJobId = 1,
            accountsReceivable = 0,
            procurement = { orders = {}, nextOrderId = 1 },
            vendorCategory = 1,
            cutter = {
                x = Config.cutterPlacement.spawnX,
                y = Config.cutterPlacement.spawnY,
                direction = Config.cutterPlacement.defaultDirection,
                moving = false,
            },
            palletJack = {
                x = Config.palletJack.spawnX,
                y = Config.palletJack.spawnY,
                direction = "northwest",
                operating = false,
                moving = false,
            },
        },
        player = { x = Config.player.spawnX, y = Config.player.spawnY },
    }
end

function save.load(slot)
    local payload = read(slot)
    if payload then payload.slot = slot end
    return payload
end

function save.save(slot, state, worldSnapshot)
    local path = assert(slotPath(slot), "save slot must be 1, 2, or 3")
    assert(type(state) == "table", "state table is required")
    local previous = read(slot)
    local payload = {
        version = VERSION,
        slot = slot,
        createdAt = previous and previous.createdAt or os.time(),
        updatedAt = os.time(),
        state = {
            money = state.money or 0,
            inventory = type(state.inventory) == "table" and state.inventory or {},
            shopProgress = state.shopProgress or {},
            jobs = type(state.jobs) == "table" and state.jobs or { active = {}, completed = {}, declined = {} },
            nextJobId = type(state.nextJobId) == "number" and state.nextJobId or 1,
            accountsReceivable = type(state.accountsReceivable) == "number" and state.accountsReceivable or 0,
            procurement = type(state.procurement) == "table" and state.procurement or { orders = {}, nextOrderId = 1 },
            vendorCategory = tonumber(state.vendorCategory) or 1,
            cutter = type(state.cutter) == "table" and state.cutter or {
                x = Config.cutterPlacement.spawnX,
                y = Config.cutterPlacement.spawnY,
                direction = Config.cutterPlacement.defaultDirection,
                moving = false,
            },
            palletJack = type(state.palletJack) == "table" and state.palletJack or {
                x = Config.palletJack.spawnX,
                y = Config.palletJack.spawnY,
                direction = "northwest",
                operating = false,
                moving = false,
            },
        },
        player = {
            x = worldSnapshot and worldSnapshot.x or Config.player.spawnX,
            y = worldSnapshot and worldSnapshot.y or Config.player.spawnY,
        },
    }
    love.filesystem.createDirectory("saves")
    return love.filesystem.write(path, encode(payload))
end

function save.delete(slot)
    local path = assert(slotPath(slot), "save slot must be 1, 2, or 3")
    if love.filesystem.getInfo(path) then return love.filesystem.remove(path) end
    return true
end

function save.listSlots()
    local slots = {}
    for slot = 1, SLOT_COUNT do
        local payload = read(slot)
        slots[slot] = { slot = slot, empty = payload == nil, updatedAt = payload and payload.updatedAt or nil, money = payload and payload.state.money or nil }
    end
    return slots
end

save.VERSION = VERSION
save.SLOT_COUNT = SLOT_COUNT
return save
