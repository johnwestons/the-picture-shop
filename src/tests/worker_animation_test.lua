local Catalog = require("src.worker_catalog")
local Renderer = require("src.employee_renderer")

local Test = {}
local ACTIONS = {
    { model = "polar_115", action = "work_cutter" },
    { model = "heidelberg_10x15", action = "work_press" },
    { model = "skid_wrapper", action = "work_wrapping" },
}

local function quadSize(quad)
    if not quad then return nil, nil end
    local _, _, width, height = quad:getViewport()
    return width, height
end

function Test.run(context, check)
    local assets = context.characterAssets
    local cacheOkay = true
    for _, profile in ipairs(Catalog.profiles) do
        for _, task in ipairs(ACTIONS) do
            local entry = {
                worker = { character = profile.character, assignment = { machineModel = task.model } },
                actor = { phase = "working", moving = false, intentX = 1, intentY = 0,
                    idleClock = 0, workFrame = 1 },
            }
            local action, firstFrame = Renderer.pose(entry, assets)
            local firstImage, firstQuad, firstCount = assets.get(profile.character, action, firstFrame)
            entry.actor.idleClock = 0.75
            local laterAction, laterFrame = Renderer.pose(entry, assets)
            local laterImage, laterQuad, laterCount = assets.get(profile.character, laterAction, laterFrame)
            local width1, height1 = quadSize(firstQuad)
            local width2, height2 = quadSize(laterQuad)
            local valid = action == task.action and laterAction == task.action
                and firstImage and laterImage and firstCount == 4 and laterCount == 4
                and firstFrame == 1 and laterFrame == 4
                and width1 == 256 and height1 == 256 and width2 == 256 and height2 == 256
            cacheOkay = cacheOkay and valid
            check("worker_" .. profile.character .. "_" .. task.action .. "_loops_four_anchored_frames", valid)
        end

        local pushAction = Catalog.pushAction(profile.character)
        local pushImage, pushQuad, pushCount = assets.get(profile.character, pushAction, 4)
        local pushWidth, pushHeight = quadSize(pushQuad)
        local validPush = pushAction == "push_jack" and pushImage and pushCount == 4
            and pushWidth == 256 and pushHeight == 256
        cacheOkay = cacheOkay and validPush
        check("worker_" .. profile.character .. "_has_future_pallet_jack_push_loop", validPush)
    end
    check("worker_action_texture_cache_stays_within_budget",
        cacheOkay and assets.cachedTextureBytes() <= 16 * 1024 * 1024)
end

return Test
