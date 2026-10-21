local Manifest=require("src.arcade_frontier.first_person_weapon_manifest")

local Actions={}
Actions.frameSize=512

local FRAMES={
    ready=1,
    flash=2,
    recoil=3,
    reloadStart=4,
    reloadWork=5,
    reloadFinish=6,
}

local PUMP_TUBE_RELOAD_TIMING={startSeconds=.28,roundSeconds=.42,finishSeconds=.28}

local function tubeReloadTiming(profile)
    if not profile then return nil end
    if profile.style=="tubeLever" then
        return profile.startSeconds or 0,profile.roundSeconds or .38,profile.finishSeconds or 0
    end
    if profile.style=="pumpTube" then
        return PUMP_TUBE_RELOAD_TIMING.startSeconds,
            PUMP_TUBE_RELOAD_TIMING.roundSeconds,
            PUMP_TUBE_RELOAD_TIMING.finishSeconds
    end
    return nil
end

-- Sprite-space pivots for every firearm action atlas. The grip positions the
-- sprite; the bore-to-muzzle segment keeps the reticle aligned with its barrel.
-- Static calibration plus authored frame swaps are the weapon animation path.
local ANCHORS={
    ["frontier-12g-pump-shotgun"]={grip={x=.65,y=.59,aspect=1},bore={x=.48,y=.421},muzzle={x=.23,y=.266}},
    ["frontier-lever-rifle"]={grip={x=.59,y=.60,aspect=1},bore={x=.455,y=.37},muzzle={x=.255,y=.245}},
    ["frontier-22-lever-rifle"]={grip={x=.6,y=.55,aspect=1},bore={x=.47,y=.397},muzzle={x=.278,y=.267}},
    ["frontier-22-pocket-pistol"]={grip={x=.52,y=.65,aspect=1},bore={x=.50,y=.29},muzzle={x=.26,y=.21}},
    ["frontier-32-pocket-pistol"]={grip={x=.522,y=.60,aspect=1},bore={x=.463,y=.285},muzzle={x=.24,y=.22}},
    ["frontier-pearl-pocket-pistol"]={grip={x=.52,y=.64,aspect=1},bore={x=.42,y=.33},muzzle={x=.234,y=.25}},
    ["frontier-compact-9mm"]={grip={x=.52,y=.63,aspect=1},bore={x=.454,y=.343},muzzle={x=.192,y=.220}},
    ["frontier-compact-9mm-pistol"]={grip={x=.67,y=.68,aspect=1},bore={x=.49,y=.35},muzzle={x=.20,y=.34}},
    ["frontier-9mm-service-pistol"]={grip={x=.62,y=.62,aspect=1},bore={x=.52,y=.407},muzzle={x=.284,y=.341}},
    ["frontier-9mm-glock"]={grip={x=.68,y=.69,aspect=1},bore={x=.500,y=.404},muzzle={x=.301,y=.369}},
    ["frontier-22-target-pistol"]={grip={x=.60,y=.645,aspect=1},bore={x=.525,y=.35},muzzle={x=.325,y=.205}},
    ["long-barrel-22-pistol"]={grip={x=.79,y=.72,aspect=1},bore={x=.45,y=.34},muzzle={x=.18,y=.29}},
    ["heavy-frontier-pistol"]={grip={x=.77,y=.66,aspect=1},bore={x=.43,y=.31},muzzle={x=.25,y=.264}},
    ["frontier-long-barrel-revolver"]={grip={x=.21,y=.67,aspect=1},bore={x=.516,y=.353},muzzle={x=.848,y=.257}},
    ["frontier-long-22-target-pistol"]={grip={x=.285,y=.65,aspect=1},bore={x=.53,y=.398},muzzle={x=.76,y=.32}},
    ["wood-stock-survival-carbine"]={grip={x=.60,y=.60,aspect=1},bore={x=.432,y=.377},muzzle={x=.25,y=.24}},
    ["vintage-bolt-action-rifle"]={grip={x=.50,y=.55,aspect=1},bore={x=.441,y=.358},muzzle={x=.141,y=.174}},
    ["frontier-762-carbine"]={grip={x=.60,y=.58,aspect=1},bore={x=.438,y=.410},muzzle={x=.21,y=.285}},
    ["weathered-lever-rifle"]={grip={x=.65,y=.62,aspect=1},bore={x=.476,y=.393},muzzle={x=.226,y=.25}},
    ["patched-22-survival-rifle"]={grip={x=.58,y=.55,aspect=1},bore={x=.352,y=.386},muzzle={x=.192,y=.345}},
    ["frontier-lever-carbine"]={grip={x=.60,y=.57,aspect=1},bore={x=.47,y=.4},muzzle={x=.28,y=.279}},
    ["compact-carbine"]={grip={x=.56,y=.62,aspect=1},bore={x=.47,y=.465},muzzle={x=.218,y=.327}},
    ["frontier-556-carbine"]={grip={x=.58,y=.68,aspect=1},bore={x=.475,y=.471},muzzle={x=.196,y=.366}},
    ["improvised-556-rifle"]={grip={x=.58,y=.68,aspect=1},bore={x=.43,y=.466},muzzle={x=.143,y=.389}},
    ["improvised-service-rifle"]={grip={x=.52,y=.65,aspect=1},bore={x=.39,y=.43},muzzle={x=.08,y=.31}},
    ["frontier-ak-compact"]={grip={x=.56,y=.62,aspect=1},bore={x=.42,y=.45},muzzle={x=.13,y=.39}},
    ["frontier-single-shot-hunter"]={grip={x=.50,y=.525,aspect=1},bore={x=.439,y=.366},muzzle={x=.175,y=.19}},
    ["scrap-pistol"]={grip={x=.689,y=.570,aspect=1},bore={x=.430,y=.330},muzzle={x=.270,y=.301}},
    ["compact-scrap-pistol"]={grip={x=.70,y=.68,aspect=1},bore={x=.41,y=.40},muzzle={x=.27,y=.40}},
    ["machine-pistol"]={grip={x=.779,y=.699,aspect=1},bore={x=.480,y=.377},muzzle={x=.180,y=.359}},
    ["rugged-submachine-gun"]={grip={x=.41,y=.58,aspect=1},bore={x=.419,y=.345},muzzle={x=.215,y=.32}},
    ["frontier-380-revolver"]={grip={x=.69,y=.77,aspect=1},bore={x=.420,y=.311},muzzle={x=.346,y=.301}},
    ["frontier-380-pocket-pistol"]={grip={x=.66,y=.64,aspect=1},bore={x=.50,y=.34},muzzle={x=.30,y=.30}},
    ["frontier-45-1911"]={grip={x=.68,y=.72,aspect=1},bore={x=.475,y=.316},muzzle={x=.25,y=.24}},
    ["frontier-sr22-pistol"]={grip={x=.51,y=.64,aspect=1},bore={x=.46,y=.25},muzzle={x=.234,y=.24}},
    ["frontier-silver-22-revolver"]={grip={x=.68,y=.68,aspect=1},bore={x=.44,y=.29},muzzle={x=.24,y=.24}},
    ["frontier-silver-compact-pistol"]={grip={x=.53,y=.63,aspect=1},bore={x=.49,y=.27},muzzle={x=.24,y=.18}},
    ["frontier-9mm-smg"]={grip={x=.64,y=.65,aspect=1},bore={x=.566,y=.441},muzzle={x=.266,y=.394}},
    ["sawed-off-shotgun"]={grip={x=.70,y=.656,aspect=1},bore={x=.43,y=.459},muzzle={x=.20,y=.35}},
}

function Actions.anchorsFor(weapon)
    return ANCHORS[weapon]
end

function Actions.frameIndex(state)
    if not state or not Manifest.actionAtlasFor(state.weapon) then return nil end
    local action=state.weaponAction
    local elapsed=math.max(0,tonumber(state.weaponActionElapsed) or 0)
    if action=="fire" then
        if elapsed<.075 then return FRAMES.flash end
        if elapsed<.20 then return FRAMES.recoil end
    elseif action=="reload" then
        local profile=Manifest.reloadProfileFor(state.weapon)
        local tubeRounds=math.max(0,math.floor(tonumber(state.tubeReloadTotalRounds) or 0))
        local start,round,finish=tubeReloadTiming(profile)
        if start and tubeRounds>0 then
            local startSeconds=math.max(0,tonumber(start) or 0)
            local roundSeconds=math.max(.01,tonumber(round) or .38)
            local finishSeconds=math.max(0,tonumber(finish) or 0)
            local workEnd=startSeconds+tubeRounds*roundSeconds
            local duration=math.max(workEnd+finishSeconds,tonumber(state.weaponReloadDuration) or 0)
            if elapsed<startSeconds then return FRAMES.reloadStart end
            if elapsed<workEnd then return FRAMES.reloadWork end
            if elapsed<duration then return FRAMES.reloadFinish end
            return FRAMES.ready
        end
        local duration=math.max(.01,tonumber(profile and profile.duration) or 1.2)
        local progress=elapsed/duration
        if progress<.20 then return FRAMES.reloadStart end
        if progress<.66 then return FRAMES.reloadWork end
        -- The ready sprite is the SMG's authored, fully seated magazine pose.
        if progress<1 and state.weapon=="frontier-9mm-smg" then return FRAMES.ready end
        if progress<1 then return FRAMES.reloadFinish end
    end
    -- The SKS last-round stop holds the bolt carrier open after the final
    -- cartridge. Keep that state visible until a reload begins and releases it.
    if action==nil and state.weapon=="frontier-762-carbine" then
        local remaining=tonumber(state.magazine)
        if remaining==nil then remaining=tonumber(state.loaded) end
        if remaining~=nil and remaining<=0 then return FRAMES.reloadStart end
    end
    return FRAMES.ready
end

-- ADS firing has its own four-pose sprite strip: aimed ready, muzzle flash,
-- recoil, and settle back to aim. Reload continues to use the established hip
-- reload sprites.
function Actions.adsFrameIndex(state)
    if not state or state.weaponAction~="fire" then return 1 end
    local elapsed=math.max(0,tonumber(state.weaponActionElapsed) or 0)
    if elapsed<.075 then return 2 end
    if elapsed<.14 then return 3 end
    return 4
end

function Actions.beginFire(state)
    state.weaponAction="fire"
    state.weaponActionElapsed=0
end

function Actions.reloadDuration(state,rounds)
    local profile=state and Manifest.reloadProfileFor(state.weapon)
    local start,round,finish=tubeReloadTiming(profile)
    if start then
        local count=math.max(1,math.floor(tonumber(rounds) or 1))
        return math.max(.01,start+count*round+finish)
    end
    return math.max(.2,tonumber(profile and profile.duration) or 1.2)
end

function Actions.beginReload(state,rounds)
    state.weaponAction="reload"
    state.weaponActionElapsed=0
    local profile=Manifest.reloadProfileFor(state.weapon)
    local start,round=tubeReloadTiming(profile)
    if start then
        local count=math.max(1,math.floor(tonumber(rounds) or 1))
        state.tubeReloadTotalRounds=count
        state.tubeReloadRemaining=count
        state.tubeReloadCompleted=0
        state.tubeReloadRoundTimer=start+round
        state.weaponReloadDuration=Actions.reloadDuration(state,count)
    else
        state.tubeReloadTotalRounds=nil
        state.tubeReloadRemaining=nil
        state.tubeReloadCompleted=nil
        state.tubeReloadRoundTimer=nil
        state.weaponReloadDuration=nil
    end
end

function Actions.finish(state)
    state.weaponAction=nil
    state.weaponActionElapsed=0
    state.tubeReloadTotalRounds=nil
    state.tubeReloadRemaining=nil
    state.tubeReloadCompleted=nil
    state.tubeReloadRoundTimer=nil
    state.weaponReloadDuration=nil
end

function Actions.update(state,dt)
    if not state or not state.weaponAction then return end
    dt=math.max(0,tonumber(dt) or 0)
    state.weaponActionElapsed=(tonumber(state.weaponActionElapsed) or 0)+dt
    if state.weaponAction=="reload" and state.tubeReloadTotalRounds
        and (tonumber(state.tubeReloadRemaining) or 0)>0 then
        local profile=Manifest.reloadProfileFor(state.weapon)
        local _,round=tubeReloadTiming(profile)
        local roundSeconds=math.max(.01,tonumber(round) or .38)
        state.tubeReloadRoundTimer=(tonumber(state.tubeReloadRoundTimer) or 0)-dt
        while state.tubeReloadRoundTimer<=0 and (tonumber(state.tubeReloadRemaining) or 0)>0 do
            state.tubeReloadCompleted=(tonumber(state.tubeReloadCompleted) or 0)+1
            state.tubeReloadRemaining=state.tubeReloadRemaining-1
            state.tubeReloadRoundTimer=state.tubeReloadRoundTimer+roundSeconds
        end
    end
    if state.weaponAction=="fire" and state.weaponActionElapsed>=.20 then Actions.finish(state) end
end

function Actions.consumeTubeRounds(state)
    local count=math.max(0,math.floor(tonumber(state and state.tubeReloadCompleted) or 0))
    if state then state.tubeReloadCompleted=0 end
    return count
end

return Actions
