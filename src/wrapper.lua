local Config = require("src.config")
local PalletLogistics = require("src.pallet_logistics")
local WrapperPlacement = require("src.wrapper_placement")

local Wrapper = { step = "idle", progress = 0, cycleTime = 3.0, pallet = nil, job = nil }

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
    Wrapper.step, Wrapper.progress, Wrapper.pallet, Wrapper.job = "idle", 0, nil, nil
    if state then state.message = "Skid wrapper ready. Park a finished pallet beside the turntable." end
end

function Wrapper.start(state)
    if Wrapper.step ~= "idle" and Wrapper.step ~= "finished" then return false end
    local nearby = Wrapper.nearbyPallet(state)
    if not nearby then state.message = "Move a finished, unwrapped pallet beside the skid wrapper first."; return false end
    local inventory = state.inventory or {}
    if (inventory.plasticWrapUses or 0) < 1 then state.message = "No plastic film remains. Buy a $20 roll at the office computer."; return false end
    Wrapper.pallet, Wrapper.job = nearby.pallet, nearby.job
    Wrapper.step, Wrapper.progress = "wrapping", 0
    state.message = "Wrapping " .. nearby.pallet.id .. " as a " .. (nearby.pallet.packaging or nearby.job.packaging or "flat") .. " pallet."
    return true
end

function Wrapper.update(dt, state)
    if Wrapper.step ~= "wrapping" then return end
    Wrapper.progress = math.min(Wrapper.cycleTime, Wrapper.progress + dt)
    if Wrapper.progress < Wrapper.cycleTime then return end
    local inventory = state.inventory
    inventory.plasticWrapUses = math.max(0, (inventory.plasticWrapUses or 0) - 1)
    if inventory.plasticWrapUses == 0 then
        inventory.plasticWrapRolls = math.max(0, (inventory.plasticWrapRolls or 0) - 1)
        if inventory.plasticWrapRolls > 0 then inventory.plasticWrapUses = 11 end
    end
    Wrapper.pallet.wrapped, Wrapper.pallet.status = true, "wrapped"
    Wrapper.pallet.packagedAs = Wrapper.pallet.packaging or (Wrapper.job and Wrapper.job.packaging) or "flat"
    Wrapper.step = "finished"
    state.message = Wrapper.pallet.id .. " wrapped. " .. inventory.plasticWrapUses .. " pallet wrap(s) remain on the current roll."
end

function Wrapper.keypressed(key, state)
    if key == "l" or key == "space" or key == "return" or key == "kpenter" then return Wrapper.start(state) end
    if key == "r" then Wrapper.reset(state); return true end
    return false
end

function Wrapper.filmHeight()
    if Wrapper.step ~= "wrapping" then return Wrapper.step == "finished" and 1 or 0 end
    return math.min(1, Wrapper.progress / Wrapper.cycleTime)
end

return Wrapper
