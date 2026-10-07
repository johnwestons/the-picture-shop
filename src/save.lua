-- Versioned, local-only save slots. The payload is plain Lua data written by
-- our serializer; loading executes it in an empty environment and validates
-- the resulting table before it reaches game state.
local Config = require("src.config")
local Schema = require("src.save_schema")

local save = {}
local recoveryNotices = {}
local writableProbeCounter = 0
local changeVersion = 0
local verifiedPrimaries, verifiedDirectory = {}, nil

function save.revision() return changeVersion end

local function primaryCache()
    local directory = love.filesystem.getSaveDirectory()
    if verifiedDirectory ~= directory then
        verifiedPrimaries, verifiedDirectory = {}, directory
    end
    return verifiedPrimaries
end

local function rememberPrimary(slot, source, createdAt)
    primaryCache()[slot] = #source <= 2 * 1024 * 1024
        and {source=source,createdAt=createdAt} or nil
end

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

local function appendEncoded(lines, value, indent)
    local kind = type(value)
    if kind == "number" or kind == "boolean" then lines[#lines+1]=tostring(value);return end
    if kind == "string" then lines[#lines+1]=string.format("%q", value);return end
    if kind ~= "table" then lines[#lines+1]="nil";return end
    lines[#lines+1]="{\n"
    local childIndent=indent.."  "
    for key, item in pairs(value) do
        local keyText = type(key) == "string" and string.format("[%q]", key) or "[" .. tostring(key) .. "]"
        lines[#lines+1]=childIndent..keyText.." = "
        appendEncoded(lines,item,childIndent)
        lines[#lines+1]=",\n"
    end
    lines[#lines + 1] = indent .. "}"
end

local function encode(value)
    local lines={}
    appendEncoded(lines,value,"")
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

local function writeVerified(path, source)
    if not love.filesystem.write(path, source) then return false end
    -- The caller already validated these bytes. Verify the entire disk write
    -- without repeatedly parsing, copying and migrating the same payload.
    return love.filesystem.read(path) == source
end

local function absolutePath(path)
    local separator = package.config:sub(1, 1)
    return love.filesystem.getSaveDirectory() .. separator .. path:gsub("/", separator)
end

local function removeIfPresent(path)
    local inspected, info = pcall(love.filesystem.getInfo, path)
    if not inspected then return false end
    if not info then return true end
    local removed, result = pcall(love.filesystem.remove, path)
    return removed and result ~= false and result ~= nil
end

local function reserveWritableProbe(slot)
    for _ = 1, 64 do
        writableProbeCounter = writableProbeCounter + 1
        local stem = string.format("saves/.host-write-probe-%d-%d-%d",
            slot, tonumber(os.time()) or 0, writableProbeCounter)
        local temporary, promoted = stem .. ".tmp", stem .. ".ready"
        local inspectedTemporary, temporaryInfo = pcall(love.filesystem.getInfo, temporary)
        local inspectedPromoted, promotedInfo = pcall(love.filesystem.getInfo, promoted)
        if not inspectedTemporary or not inspectedPromoted then return nil end
        if not temporaryInfo and not promotedInfo then return temporary, promoted end
    end
end

-- Hosting makes this device the sole owner of the durable shop. Verify the
-- complete private save path without touching any slot or recovery file: make
-- the directory, write/read a unique marker, promote it by the same
-- rename-or-copy strategy used by saves, then remove every probe artifact.
function save.preflightWritable(slot)
    if not Schema.validSlot(slot) then return false, "Save slot must be 1, 2, or 3." end

    local created, createResult = pcall(love.filesystem.createDirectory, "saves")
    if not created or createResult == false or createResult == nil then
        return false, "This device could not create the private save folder."
    end

    local temporary, promoted = reserveWritableProbe(slot)
    if not temporary then
        return false, "This device could not reserve a private host-save check."
    end
    local marker = string.format("picture-shop-host-save-check:%d:%d",
        slot, writableProbeCounter)
    local function cleanup()
        local temporaryRemoved = removeIfPresent(temporary)
        local promotedRemoved = removeIfPresent(promoted)
        return temporaryRemoved and promotedRemoved
    end
    local function fail(message)
        local cleaned = cleanup()
        return false, cleaned and message
            or (message .. " The temporary save check could not be removed.")
    end

    local wrote, writeResult = pcall(love.filesystem.write, temporary, marker)
    if not wrote or writeResult == false or writeResult == nil then
        return fail("This device could not write a private host save.")
    end
    local readTemporary, temporaryBytes = pcall(love.filesystem.read, temporary)
    if not readTemporary or temporaryBytes ~= marker then
        return fail("This device could not verify a private host save.")
    end

    local resolvedTemporary, temporaryPath = pcall(absolutePath, temporary)
    local resolvedPromoted, promotedPath = pcall(absolutePath, promoted)
    local renamed, renameResult = false, nil
    if resolvedTemporary and resolvedPromoted then
        renamed, renameResult = pcall(os.rename, temporaryPath, promotedPath)
    end
    if not renamed or renameResult == false or renameResult == nil then
        local copied, copyResult = pcall(love.filesystem.write, promoted, marker)
        if not copied or copyResult == false or copyResult == nil then
            return fail("This device could not promote a private host save.")
        end
        if not removeIfPresent(temporary) then
            return fail("This device could not replace a private host save safely.")
        end
    end

    local readPromoted, promotedBytes = pcall(love.filesystem.read, promoted)
    if not readPromoted or promotedBytes ~= marker then
        return fail("This device could not verify a promoted host save.")
    end
    if not cleanup() then
        return false, "This device wrote a host-save check but could not clean it up."
    end
    return true
end

local function promote(sourcePath, targetPath, verifiedSource)
    local source = love.filesystem.read(sourcePath)
    if not source or source ~= verifiedSource then return false end
    if love.filesystem.getInfo(targetPath) and not love.filesystem.remove(targetPath) then return false end
    local renamed = os.rename(absolutePath(sourcePath), absolutePath(targetPath))
    if not renamed then
        if not writeVerified(targetPath, source) then return false end
        love.filesystem.remove(sourcePath)
    end
    return love.filesystem.read(targetPath) == source
end

local function restore(slot, files, sourcePath, sourceName)
    local payload, source = readCandidate(sourcePath)
    if not payload then return nil end
    love.filesystem.remove(files.temporary)
    if writeVerified(files.temporary, source) then promote(files.temporary, files.primary, source) end
    changeVersion = changeVersion + 1
    recoveryNotices[slot] = sourceName
    payload.recovered = true
    payload.recoverySource = sourceName
    return payload
end

local function read(slot)
    local files = slotFiles(slot)
    if not files then return nil, "invalid" end
    local primary, source = readCandidate(files.primary)
    if primary then
        local source = recoveryNotices[slot]
        if source then
            primary.recovered = true
            primary.recoverySource = source
            return primary, "recovered", source
        end
        return primary, "ok", source
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

function save.newGame(slot,options)
    local minutes=options and options.dayLengthMinutes or Config.businessCalendar.secondsPerDay/60
    if type(minutes)~="number" or minutes~=math.floor(minutes) or minutes<5 or minutes>60 then
        return nil,"Choose a game day between 5 and 60 minutes."
    end
    local payload=Schema.newPayload(slot)
    payload.state.calendar.secondsPerDay=minutes*60
    return payload
end

function save.load(slot)
    local payload, status, source = read(slot)
    if payload then payload.slot = slot end
    if payload and source then rememberPrimary(slot, source, payload.createdAt) end
    return payload, status
end

function save.save(slot, state, worldSnapshot)
    local files = assert(slotFiles(slot), "save slot must be 1, 2, or 3")
    assert(type(state) == "table", "state table is required")
    changeVersion = changeVersion + 1
    local previousSource = love.filesystem.getInfo(files.primary) and love.filesystem.read(files.primary)
    local cached = primaryCache()[slot]
    -- A byte-for-byte match with our last validated commit needs no migration.
    -- External edits, recovery files and another save identity still go through
    -- the complete parser and schema checks.
    local previous = previousSource and cached and previousSource == cached.source
        and {createdAt=cached.createdAt} or (previousSource and parse(previousSource))
    if not previous then
        previous = read(slot)
        previousSource = nil
    end
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
    if not love.filesystem.createDirectory("saves") then return false end
    local source = encode(payload)
    love.filesystem.remove(files.temporary)
    if not writeVerified(files.temporary, source) then return false end

    local currentSource = love.filesystem.getInfo(files.primary) and love.filesystem.read(files.primary)
    local currentPayload = currentSource and currentSource == previousSource and previous
        or (currentSource and parse(currentSource))
    if currentPayload then
        love.filesystem.remove(files.backupTemporary)
        if not writeVerified(files.backupTemporary, currentSource) then return false end
        if not promote(files.backupTemporary, files.backup, currentSource) then return false end
    end
    if not promote(files.temporary, files.primary, source) then return false end
    recoveryNotices[slot] = nil
    rememberPrimary(slot, source, payload.createdAt)
    return true
end

function save.delete(slot)
    local files = assert(slotFiles(slot), "save slot must be 1, 2, or 3")
    changeVersion = changeVersion + 1
    primaryCache()[slot] = nil
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
