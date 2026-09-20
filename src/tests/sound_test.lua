local Test = {}

local function contains(list, value)
    for _, item in ipairs(list) do if item == value then return true end end
    return false
end

function Test.run(context, check)
    local catalog, catalogCount, pathsValid = context.Sound.catalog(), 0, true
    for _, spec in pairs(catalog) do
        catalogCount = catalogCount + 1
        pathsValid = pathsValid and love.filesystem.getInfo(spec.path, "file") ~= nil
    end
    check("sound_catalog_has_complete_palette", catalogCount == 16 and pathsValid)

    local state = { screen = "world", money = 100, jobs = { completed = {} }, windmill = {} }
    local instance = context.Sound.new({ state = state })
    local played = {}
    function instance:play(name) played[#played + 1] = name; return true end

    local baseline = {
        screen = "world", message = nil, money = 100, completedJobs = 0,
        door = "closed", truck = "absent", pallet = nil, wrapper = "idle",
        cutterStep = "positioned", cutterClamp = false,
        pressMotor = false, pressStatus = "idle",
    }
    local active = {}
    for key, value in pairs(baseline) do active[key] = value end
    active.door, active.truck, active.pallet = "opening", "backing", "PALLET-1"
    active.wrapper, active.cutterStep, active.cutterClamp = "wrapping", "cutting", true
    active.pressMotor, active.pressStatus = true, "production"
    instance:handleTransitions(baseline, active)
    check("sound_transitions_cover_physical_shop_actions",
        contains(played, "loading_door")
        and contains(played, "truck_arrival")
        and contains(played, "pallet_pickup")
        and contains(played, "wrapper_cycle")
        and contains(played, "cutter_clamp")
        and contains(played, "cutter_cut")
        and contains(played, "press_start"))

    played = {}
    local paid = {}
    for key, value in pairs(active) do paid[key] = value end
    paid.money, paid.completedJobs = 450, 1
    instance:handleTransitions(active, paid)
    check("sound_job_completion_suppresses_duplicate_cash_cue",
        #played == 1 and played[1] == "job_complete")

    local started, stopped = {}, {}
    function instance:startLoop(name, owner) started[owner] = name end
    function instance:stopLoop(owner) stopped[owner] = true end
    instance:syncPersistentLoops(active)
    check("sound_loop_ownership_tracks_warehouse_and_press",
        started.warehouse == "warehouse_ambience_loop"
        and started.press == "press_running_loop")
    active.screen, active.pressStatus = "title", "idle"
    instance:syncPersistentLoops(active)
    check("sound_loops_stop_outside_their_owners", stopped.warehouse and stopped.press)

    local loopVolume
    instance.loops = { warehouse = {
        name = "warehouse_ambience_loop",
        source = { setVolume = function(_, value) loopVolume = value end },
    } }
    instance:setLevels(0.5, 0.6, 0.4)
    check("sound_options_apply_live_mix_levels",
        instance.masterVolume == 0.5 and instance.sfxVolume == 0.6
        and instance.ambientVolume == 0.4 and loopVolume ~= nil)
end

return Test
