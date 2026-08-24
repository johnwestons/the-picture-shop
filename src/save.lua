-- Versioned, local-only save slots. The payload is plain Lua data written by
-- our serializer; loading executes it in an empty environment and validates
-- the resulting table before it reaches game state.
local Config = require("src.config")
local Schema = require("src.save_schema")

local save = {}

local function slotPath(slot)
    if not Schema.validSlot(slot) then return nil end
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

local function read(slot)
    local path = slotPath(slot)
    if not path or not love.filesystem.getInfo(path) then return nil end
    local source = love.filesystem.read(path)
    if not source then return nil end
    local chunk = loadstring("return " .. source)
    if not chunk then return nil end
    setfenv(chunk, {})
    local ok, payload = pcall(chunk)
    if not ok then return nil end
    return Schema.migrate(payload)
end

function save.newGame(slot)
    return Schema.newPayload(slot)
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
        version = Schema.VERSION,
        slot = slot,
        createdAt = previous and previous.createdAt or os.time(),
        updatedAt = os.time(),
        state = Schema.snapshot(state),
        player = {
            x = worldSnapshot and worldSnapshot.x or Config.player.spawnX,
            y = worldSnapshot and worldSnapshot.y or Config.player.spawnY,
        },
    }
    if not Schema.validPayload(payload) then return false end
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
    for slot = 1, Schema.SLOT_COUNT do
        local payload = read(slot)
        slots[slot] = {
            slot = slot,
            empty = payload == nil,
            updatedAt = payload and payload.updatedAt or nil,
            money = payload and payload.state.money or nil,
        }
    end
    return slots
end

save.VERSION = Schema.VERSION
save.SLOT_COUNT = Schema.SLOT_COUNT
return save
