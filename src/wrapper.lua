local Config = require("src.config")
local PalletLogistics = require("src.pallet_logistics")
local Procurement = require("src.procurement")
local WrapperPlacement = require("src.wrapper_placement")
local MachineFleet = require("src.machine_fleet")

local Wrapper = { step = "idle", progress = 0, cycleTime = 3.0, pallet = nil, job = nil,
    selectedPalletId = nil }

local function blockInterruption(state, action)
    if Wrapper.step ~= "wrapping" then return true end
    if state then
        state.message = "Wrapping is in progress. Wait for the cycle to finish before " .. action .. "."
    end
    return false
end

local function distanceSquared(a, b)
    local dx, dy = a.x - b.x, a.y - b.y
    return dx * dx + dy * dy
end

function Wrapper.nearbyPallets(state)
    local wrapper = WrapperPlacement.ensure(state, Config.wrapperPlacement)
    local nearby = {}
    for _, item in ipairs(PalletLogistics.physicalPallets(state)) do
        local pallet = item.pallet
        local printJob = type(item.job.press) == "table" or type(pallet.press) == "table"
        local printComplete = not printJob
            or (type(pallet.press) == "table" and pallet.press.status == "complete")
        local eligible = (pallet.status == "cut" or pallet.status == "finished"
            or pallet.status == "printed") and printComplete and not pallet.wrapped
        local distance = distanceSquared(wrapper, item)
        if eligible and distance <= Config.wrapperPlacement.palletRadius ^ 2 then
            nearby[#nearby + 1] = { pallet = pallet, job = item.job, distance = distance }
        end
    end
    table.sort(nearby, function(a, b)
        if a.distance == b.distance then return tostring(a.pallet.id) < tostring(b.pallet.id) end
        return a.distance < b.distance
    end)
    return nearby
end

function Wrapper.nearbyPallet(state)
    local nearby = Wrapper.nearbyPallets(state)
    for _, item in ipairs(nearby) do
        if item.pallet.id == Wrapper.selectedPalletId then return item end
    end
    return nearby[1]
end

function Wrapper.selectPallet(state, palletId)
    if Wrapper.step == "wrapping" then return false end
    for _, item in ipairs(Wrapper.nearbyPallets(state)) do
        if item.pallet.id == palletId then
            if Wrapper.step == "finished" then
                Wrapper.step, Wrapper.progress, Wrapper.pallet, Wrapper.job = "idle", 0, nil, nil
            end
            Wrapper.selectedPalletId = palletId
            state.message = "Selected " .. palletId .. " for stretch wrapping."
            return true
        end
    end
    state.message = "That pallet is no longer close enough to the skid wrapper."
    return false
end

function Wrapper.reset(state)
    if not blockInterruption(state, "resetting the wrapper") then return false end
    Wrapper.step, Wrapper.progress, Wrapper.pallet, Wrapper.job = "idle", 0, nil, nil
    Wrapper.selectedPalletId = nil
    if state then state.message = "Skid wrapper ready. Park a finished pallet beside the turntable." end
    return true
end

function Wrapper.isActive() return Wrapper.step == "wrapping" end
function Wrapper.canExit(state) return blockInterruption(state, "leaving the console") end
function Wrapper.canRelocate(state) return blockInterruption(state, "relocating the wrapper") end

function Wrapper.start(state)
    if Wrapper.step ~= "idle" and Wrapper.step ~= "finished" then return false end
    local operable, machineOrError = MachineFleet.canOperate(state, "skid_wrapper")
    if not operable then state.message = machineOrError; return false end
    local nearby = Wrapper.nearbyPallet(state)
    if not nearby then state.message = "Move a finished, unwrapped pallet beside the skid wrapper first."; return false end
    local inventory = state.inventory or {}
    if (inventory.plasticWrapUses or 0) < 1 then
        state.message = "No stretch film remains. Order it from the packaging supplier and unload the delivery."
        return false
    end
    local packaging = nearby.pallet.packaging or nearby.job.packaging or "flat"
    if packaging == "boxed" and Procurement.cartonsAvailable(state) < 1 then
        state.message = "This boxed pallet needs a shipping carton. Order cartons from the packaging supplier."
        return false
    end
    Wrapper.pallet, Wrapper.job = nearby.pallet, nearby.job
    Wrapper.selectedPalletId = nearby.pallet.id
    Wrapper.step, Wrapper.progress = "wrapping", 0
    state.message = "Wrapping " .. nearby.pallet.id .. " as a " .. packaging .. " pallet."
    return true
end

function Wrapper.update(dt, state)
    if Wrapper.step ~= "wrapping" then return false end
    assert(type(state) == "table", "wrapper update requires game state")
    Wrapper.progress = math.min(Wrapper.cycleTime, Wrapper.progress + dt)
    if Wrapper.progress < Wrapper.cycleTime then return false end
    local inventory = state.inventory
    inventory.plasticWrapUses = math.max(0, (inventory.plasticWrapUses or 0) - 1)
    if inventory.plasticWrapUses == 0 then
        inventory.plasticWrapRolls = math.max(0, (inventory.plasticWrapRolls or 0) - 1)
        if inventory.plasticWrapRolls > 0 then inventory.plasticWrapUses = 11 end
    end
    local packaging = Wrapper.pallet.packaging or (Wrapper.job and Wrapper.job.packaging) or "flat"
    if packaging == "boxed" then Procurement.consumeCartons(state, 1) end
    Wrapper.pallet.wrapped, Wrapper.pallet.status = true, "wrapped"
    Wrapper.pallet.packagedAs = packaging
    MachineFleet.recordUse(state, "skid_wrapper", 1)
    Wrapper.step = "finished"
    state.message = Wrapper.pallet.id .. " wrapped. " .. inventory.plasticWrapUses .. " pallet wrap(s) remain on the current roll."
    return true
end

-- The wrapper animation/runtime lives outside the durable save table. LAN
-- workers receive this small authoritative view so the console and cycle sound
-- follow the host without gaining references to mutable host objects.
function Wrapper.snapshot()
    return {
        step = Wrapper.step,
        progress = Wrapper.progress,
        cycleTime = Wrapper.cycleTime,
        selectedPalletId = Wrapper.selectedPalletId,
        palletId = Wrapper.pallet and Wrapper.pallet.id or nil,
    }
end

function Wrapper.applySnapshot(snapshot, state)
    if type(snapshot) ~= "table"
        or (snapshot.step ~= "idle" and snapshot.step ~= "wrapping"
            and snapshot.step ~= "finished")
        or type(snapshot.progress) ~= "number" or snapshot.progress < 0
        or type(snapshot.cycleTime) ~= "number" or snapshot.cycleTime <= 0
        or (snapshot.selectedPalletId ~= nil and type(snapshot.selectedPalletId) ~= "string")
        or (snapshot.palletId ~= nil and type(snapshot.palletId) ~= "string")
    then
        return false
    end
    Wrapper.step = snapshot.step
    Wrapper.cycleTime = snapshot.cycleTime
    Wrapper.progress = math.min(snapshot.cycleTime, snapshot.progress)
    Wrapper.selectedPalletId = snapshot.selectedPalletId
    Wrapper.pallet, Wrapper.job = nil, nil
    if state and snapshot.palletId then
        for _, item in ipairs(PalletLogistics.physicalPallets(state)) do
            if item.pallet and item.pallet.id == snapshot.palletId then
                Wrapper.pallet, Wrapper.job = item.pallet, item.job
                break
            end
        end
    end
    return true
end

function Wrapper.keypressed(key, state)
    if key == "l" or key == "space" or key == "return" or key == "kpenter" then return Wrapper.start(state) end
    local number = tonumber(key)
    if number then
        local nearby = Wrapper.nearbyPallets(state)
        return nearby[number] and Wrapper.selectPallet(state, nearby[number].pallet.id) or false
    end
    if key == "r" then return Wrapper.reset(state) end
    return false
end

function Wrapper.filmHeight()
    if Wrapper.step ~= "wrapping" then return Wrapper.step == "finished" and 1 or 0 end
    return math.min(1, Wrapper.progress / Wrapper.cycleTime)
end

return Wrapper
