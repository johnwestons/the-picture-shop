local MachineResource = require("src.machine_resource_id")

local Activity = {}

local taskScreens = {
    job_offer = true,
    pallet_work_order = true,
    shop_clock = true,
    shop_rooms = true,
    truck_inventory = true,
    vendor = true,
}

local function resourceAction(resourceId)
    local base = MachineResource.parse(resourceId) or resourceId
    if base == "cutter" then return "work_cutter" end
    if base == "windmill" then return "work_press" end
    if base == "skid_wrapper" then return "work_wrapping" end
    if base == "office_computer" then return "use_computer" end
    if base == "work_phone" then return "answer_phone" end
    if base == "pallet_jack" then return nil end
    if base then return "work_task" end
end

function Activity.forState(state, remoteScreen, player)
    if type(state) ~= "table" then return nil end
    local screen = state.screen
    if screen == "machine" then
        local machineType = state.machineType
        return machineType == "skid_wrapper" and "work_wrapping" or "work_cutter"
    end
    if screen == "press" then return "work_press" end
    if screen == "computer" then return "use_computer" end
    if screen == "work_phone" then return "answer_phone" end
    if screen == "workshop_remote" then
        local resourceId = remoteScreen and remoteScreen.leaseResourceId
        return resourceAction(resourceId)
    end
    if screen == "options" and state.optionsReturnScreen
        and state.optionsReturnScreen ~= "title" and state.optionsReturnScreen ~= "lan"
        and state.optionsReturnScreen ~= "direct" then
        return "work_task"
    end
    if taskScreens[screen] then return "work_task" end

    local forklift = state.forklift
    if type(forklift) == "table" and forklift.operating == true and player then
        local playerId = tonumber(player.id) or 1
        if tonumber(forklift.operatorPlayerId) == playerId then return "operate_forklift" end
    end
    return nil
end

function Activity.resourceAction(resourceId)
    return resourceAction(resourceId)
end

return Activity
