local SaveEditor = {}

local FIELDS = {
    { id = "money", label = "Cash", path = { "money" }, step = 1000, maximum = 999999999, money = true },
    { id = "accounts_receivable", label = "Accounts receivable", path = { "accountsReceivable" }, step = 500, maximum = 999999999, money = true },
    { id = "paper", label = "Loose paper sheets", path = { "inventory", "paper" }, step = 100, maximum = 999999999 },
    { id = "prints", label = "Finished prints", path = { "inventory", "prints" }, step = 100, maximum = 999999999 },
    { id = "shipping_cartons", label = "Shipping cartons", path = { "inventory", "stock", "shipping_cartons" }, step = 10, maximum = 999999999 },
    { id = "plastic_wrap_rolls", label = "Plastic wrap rolls", path = { "inventory", "plasticWrapRolls" }, step = 1, maximum = 999999999 },
    { id = "completed_cuts", label = "Completed cuts", path = { "shopProgress", "completedCuts" }, step = 10, maximum = 999999999 },
}

local BY_ID = {}
for _, field in ipairs(FIELDS) do BY_ID[field.id] = field end

local function getPath(root, path)
    local value = root
    for _, key in ipairs(path) do
        if type(value) ~= "table" then return nil end
        value = value[key]
    end
    return value
end

local function setPath(root, path, value)
    local target = root
    for index = 1, #path - 1 do
        local key = path[index]
        if type(target[key]) ~= "table" then target[key] = {} end
        target = target[key]
    end
    target[path[#path]] = value
end

function SaveEditor.fields()
    return FIELDS
end

function SaveEditor.field(id)
    return BY_ID[id]
end

function SaveEditor.value(state, id)
    local field = BY_ID[id]
    return field and getPath(state, field.path) or nil
end

function SaveEditor.setValue(state, id, value)
    local field = BY_ID[id]
    if type(state) ~= "table" or not field then return false, "Unknown save field." end
    value = tonumber(value)
    if not value or value ~= value or value == math.huge or value == -math.huge then
        return false, "Enter a whole number."
    end
    value = math.max(0, math.min(field.maximum, math.floor(value + 0.5)))
    local previous = getPath(state, field.path)
    setPath(state, field.path, value)
    return true, value, previous
end

function SaveEditor.editSlot(context, slot, id, value)
    if type(context) ~= "table" or not context.save then
        return false, "Save editor is unavailable."
    end
    if context.isNetworkClient and context.isNetworkClient() then
        return false, "Only the host can change shop saves."
    end
    slot = math.floor(tonumber(slot) or 0)
    if slot < 1 or slot > (context.save.SLOT_COUNT or 3) then
        return false, "Choose a valid save slot."
    end

    local live = context.useActiveState == true and context.state
        and context.state.activeSlot == slot
    if live then
        local ok, applied, previous = SaveEditor.setValue(context.state, id, value)
        if not ok then return false, applied end
        if not context.saveCurrent or not context.saveCurrent() then
            setPath(context.state, BY_ID[id].path, previous)
            return false, "The live shop could not be saved; the change was rolled back."
        end
        return true, applied, "Live slot " .. slot .. " saved."
    end

    local payload, status = context.save.load(slot)
    if not payload then
        return false, status == "corrupted"
            and "That slot is damaged and has no valid recovery copy."
            or "That slot is empty. Create a shop before editing it."
    end
    local ok, applied = SaveEditor.setValue(payload.state, id, value)
    if not ok then return false, applied end
    if not context.save.save(slot, payload.state, payload.player) then
        return false, "That save file could not be updated safely."
    end
    return true, applied, "Slot " .. slot .. " saved."
end

function SaveEditor.inspectSlot(context, slot)
    if context.useActiveState == true and context.state
        and context.state.activeSlot == slot
    then
        return context.state, "live"
    end
    local payload, status = context.save.load(slot)
    return payload and payload.state or nil, status
end

return SaveEditor
