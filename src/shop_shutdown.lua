local Fleet=require("src.machine_fleet")
local Shutdown={}
local busy={armed=true,cutting=true,loading=true,positioning=true,unloading=true,lift_returning=true,resetting=true}
function Shutdown.checklist(state,world)
    local rows={}
    local function wait(text) rows[#rows+1]=text end
    for _,unit in ipairs(Fleet.owned(state)) do
        if unit.world and unit.world.moving then wait("Finish placing "..unit.id..".") end
        if unit.modelId=="polar_115" and busy[require("src.machine").forId(unit.id).step] then
            wait(unit.id..": finishing its current cutter step.")
        elseif unit.modelId=="skid_wrapper" and require("src.wrapper").forId(unit.id).isActive() then
            wait(unit.id..": finishing its current wrap (a few seconds).")
        end
    end
    for _,jack in ipairs(require("src.pallet_jack_fleet").all(state)) do
        if jack.operating and jack.operatorPlayerId then wait("Park pallet jack "..tostring(jack.id).." with F. Cargo stays on it.") end
    end
    if state.forklift and state.forklift.operating then wait("Park the forklift before leaving.") end
    for _,worker in ipairs(state.employment and state.employment.staff or {}) do
        if worker.visible or worker.clockedIn or not require("src.employee_work").safe(worker,state) then
            wait(worker.name..": "..tostring(worker.activity or "finishing and parking work")..".")
        end
    end
    local truck=world and world.truck
    if truck then
        if truck.state~="absent" then
            wait("Truck: finish "..truck.state:gsub("_"," ").." and close the loading bay.")
        end
    end
    if world and world.bayDoor and world.bayDoor.state~="closed" then
        wait("Close the loading bay door.")
    end
    for scene,door in pairs(world and world.roomDoors or {}) do
        if door.state~="closed" then wait("Close the "..scene:gsub("_"," ").." loading bay door.") end
    end
    return rows
end
function Shutdown.closedCalendar(state)
    local now=require("src.business_calendar").absoluteHours(state)
    local changed=require("src.employees").advance(state,now)
    if state.employment then state.employment.lastAtHours=now end
    return require("src.payroll").pay(state,now,true) or changed
end
function Shutdown.pauseConstruction(state)
    local upgrades=require("src.warehouse_upgrades")
    local project=upgrades.activeProject(state)
    if not project or project.phase~="building" or project.pausedAtHours then return false end
    local now=require("src.business_calendar").absoluteHours(state)
    -- The normal warehouse update has already accounted for this frame's work.
    -- Reuse its durable pause checkpoint so Monday cannot replay closed hours.
    return upgrades.update(state,now,{blockedProjectId=project.id})
end
return Shutdown
