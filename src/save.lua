-- Versioned, local-only save slots. The payload is plain Lua data written by
-- our serializer; loading executes it in an empty environment and validates
-- the resulting table before it reaches game state.
local Config = require("src.config")
local Schema = require("src.save_schema")

local save = {}
local recoveryNotices = {}

local function slotFiles(slot)
    if not Schema.validSlot(slot) then return nil end
    local primary = string.format("saves/slot%d.lua", slot)
    return {
        primary = primary,
        temporary = primary .. ".tmp",
        backup = primary .. ".bak",
        backupTemporary = primary .. ".bak.tmp",
    }
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

local function parse(source)
    if not source then return nil end
    local chunk = loadstring("return " .. source)
    if not chunk then return nil end
    setfenv(chunk, {})
    local ok, payload = pcall(chunk)
    if not ok then return nil end
    return Schema.migrate(payload)
end

local function readCandidate(path)
    if not path or not love.filesystem.getInfo(path) then return nil end
    local source = love.filesystem.read(path)
    if not source then return nil end
    return parse(source), source
end

local function writeValidated(path, source)
    if not parse(source) then return false end
    if not love.filesystem.write(path, source) then return false end
    local payload = readCandidate(path)
    return payload ~= nil
end

local function absolutePath(path)
    local separator = package.config:sub(1, 1)
    return love.filesystem.getSaveDirectory() .. separator .. path:gsub("/", separator)
end

local function promote(sourcePath, targetPath)
    local payload, source = readCandidate(sourcePath)
    if not payload then return false end
    if love.filesystem.getInfo(targetPath) and not love.filesystem.remove(targetPath) then return false end
    local renamed = os.rename(absolutePath(sourcePath), absolutePath(targetPath))
    if not renamed then
        if not writeValidated(targetPath, source) then return false end
        love.filesystem.remove(sourcePath)
    end
    return readCandidate(targetPath) ~= nil
end

local function restore(slot, files, sourcePath, sourceName)
    local payload, source = readCandidate(sourcePath)
    if not payload then return nil end
    love.filesystem.remove(files.temporary)
    if writeValidated(files.temporary, source) then promote(files.temporary, files.primary) end
    recoveryNotices[slot] = sourceName
    payload.recovered = true
    payload.recoverySource = sourceName
    return payload
end

local function read(slot)
    local files = slotFiles(slot)
    if not files then return nil, "invalid" end
    local primary = readCandidate(files.primary)
    if primary then
        local source = recoveryNotices[slot]
        if source then
            primary.recovered = true
            primary.recoverySource = source
            return primary, "recovered"
        end
        return primary, "ok"
    end

    local temporary = readCandidate(files.temporary)
    if temporary then return restore(slot, files, files.temporary, "temporary"), "recovered" end
    local backup = readCandidate(files.backup)
    if backup then return restore(slot, files, files.backup, "backup"), "recovered" end

    local hasFiles = love.filesystem.getInfo(files.primary)
        or love.filesystem.getInfo(files.temporary)
        or love.filesystem.getInfo(files.backup)
        or love.filesystem.getInfo(files.backupTemporary)
    return nil, hasFiles and "corrupted" or "empty"
end

function save.newGame(slot)
    return Schema.newPayload(slot)
end

function save.load(slot)
    local payload, status = read(slot)
    if payload then payload.slot = slot end
    return payload, status
end

function save.save(slot, state, worldSnapshot)
    local files = assert(slotFiles(slot), "save slot must be 1, 2, or 3")
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
    local source = encode(payload)
    love.filesystem.remove(files.temporary)
    if not writeValidated(files.temporary, source) then return false end

    local currentPayload, currentSource = readCandidate(files.primary)
    if currentPayload then
        love.filesystem.remove(files.backupTemporary)
        if not writeValidated(files.backupTemporary, currentSource) then return false end
        if not promote(files.backupTemporary, files.backup) then return false end
    end
    if not promote(files.temporary, files.primary) then return false end
    recoveryNotices[slot] = nil
    return true
end

function save.delete(slot)
    local files = assert(slotFiles(slot), "save slot must be 1, 2, or 3")
    local succeeded = true
    for _, path in pairs(files) do
        if love.filesystem.getInfo(path) and not love.filesystem.remove(path) then succeeded = false end
    end
    recoveryNotices[slot] = nil
    return succeeded
end

function save.listSlots()
    local slots = {}
    for slot = 1, Schema.SLOT_COUNT do
        local payload, status = read(slot)
        slots[slot] = {
            slot = slot,
            empty = status == "empty",
            corrupted = status == "corrupted",
            recovered = status == "recovered",
            recoverySource = payload and payload.recoverySource or nil,
            updatedAt = payload and payload.updatedAt or nil,
            money = payload and payload.state.money or nil,
        }
    end
    return slots
end

save.VERSION = Schema.VERSION
save.SLOT_COUNT = Schema.SLOT_COUNT
return save
