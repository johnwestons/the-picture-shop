local Config = require("src.config")
local PalletLogistics = require("src.pallet_logistics")
local Procurement = require("src.procurement")
local WrapperPlacement = require("src.wrapper_placement")

local Wrapper = { step = "idle", progress = 0, cycleTime = 3.0, pallet = nil, job = nil }

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

function Wrapper.nearbyPallet(state)
    local wrapper = WrapperPlacement.ensure(state, Config.wrapperPlacement)
    local best
    for _, item in ipairs(PalletLogistics.physicalPallets(state)) do
        local pallet = item.pallet
        local eligible = (pallet.status == "cut" or pallet.status == "finished") and not pallet.wrapped
        local distance = distanceSquared(wrapper, item)
        if eligible and distance <= Config.wrapperPlacement.palletRadius ^ 2 and (not best or distance < best.distance) then
            best = { pallet = pallet, job = item.job, distance = distance }
        end
    end
    return best
end

function Wrapper.reset(state)
    if not blockInterruption(state, "resetting the wrapper") then return false end
    Wrapper.step, Wrapper.progress, Wrapper.pallet, Wrapper.job = "idle", 0, nil, nil
    if state then state.message = "Skid wrapper ready. Park a finished pallet beside the turntable." end
    return true
end

function Wrapper.isActive() return Wrapper.step == "wrapping" end
function Wrapper.canExit(state) return blockInterruption(state, "leaving the console") end
function Wrapper.canRelocate(state) return blockInterruption(state, "relocating the wrapper") end

function Wrapper.start(state)
    if Wrapper.step ~= "idle" and Wrapper.step ~= "finished" then return false end
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
    Wrapper.step, Wrapper.progress = "wrapping", 0
    state.message = "Wrapping " .. nearby.pallet.id .. " as a " .. packaging .. " pallet."
    return true
end

function Wrapper.update(dt, state)
    if Wrapper.step ~= "wrapping" then return end
    assert(type(state) == "table", "wrapper update requires game state")
    Wrapper.progress = math.min(Wrapper.cycleTime, Wrapper.progress + dt)
    if Wrapper.progress < Wrapper.cycleTime then return end
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
    Wrapper.step = "finished"
    state.message = Wrapper.pallet.id .. " wrapped. " .. inventory.plasticWrapUses .. " pallet wrap(s) remain on the current roll."
end

function Wrapper.keypressed(key, state)
    if key == "l" or key == "space" or key == "return" or key == "kpenter" then return Wrapper.start(state) end
    if key == "r" then return Wrapper.reset(state) end
    return false
end

function Wrapper.filmHeight()
    if Wrapper.step ~= "wrapping" then return Wrapper.step == "finished" and 1 or 0 end
    return math.min(1, Wrapper.progress / Wrapper.cycleTime)
end

return Wrapper
