local Config = require("src.config")
local PalletState = require("src.pallet_state")

local StagingAreas = {
    MAX_AREAS = 6,
    MAX_TOTAL_AREAS = 18,
    PURPOSES = {
        { id = "used", label = "USED PALLETS" },
        { id = "machine_output", label = "MACHINE OUTPUT" },
        { id = "inbound_shipping", label = "INBOUND SHIPPING" },
        { id = "outbound_shipping", label = "OUTBOUND SHIPPING" },
        { id = "stock_supplies", label = "STOCK / SUPPLIES" },
        { id = "active_jobs", label = "ACTIVE JOBS" },
        { id = "scheduled_jobs", label = "SCHEDULED JOBS" },
    },
    COLORS = {
        { id = "yellow", label = "YELLOW", rgb = { 0.96, 0.77, 0.18 } },
        { id = "red", label = "RED", rgb = { 0.92, 0.22, 0.22 } },
        { id = "blue", label = "BLUE", rgb = { 0.20, 0.65, 0.96 } },
        { id = "green", label = "GREEN", rgb = { 0.25, 0.82, 0.48 } },
        { id = "purple", label = "PURPLE", rgb = { 0.74, 0.43, 0.95 } },
        { id = "orange", label = "ORANGE", rgb = { 1.00, 0.52, 0.16 } },
    },
}

local purposeIndex, purposeLabel, colorIndex, colorById = {}, {}, {}, {}
local machineName = {
    polar_115 = "POLAR 115 CUTTER",
    skid_wrapper = "SKID WRAPPER",
    heidelberg_10x15 = "HEIDELBERG WINDMILL",
}
for index, entry in ipairs(StagingAreas.PURPOSES) do
    purposeIndex[entry.id], purposeLabel[entry.id] = index, entry.label
end
for index, entry in ipairs(StagingAreas.COLORS) do
    colorIndex[entry.id], colorById[entry.id] = index, entry
end

local function standardSlots()
    local c = Config.cutterStaging
    local result = {}
    for row = 1, c.rows do
        for column = 1, c.columns do
            result[#result + 1] = {
                x = c.firstX - c.x + (column - 1) * c.columnSpacing,
                y = c.firstY - c.y + (row - 1) * c.rowSpacing,
            }
        end
    end
    return result
end

local function inboundSlots()
    local result = {}
    for row = 0, 2 do
        for column = 0, 1 do
            result[#result + 1] = { x = 38 + column * 100, y = 20 + row * 45 }
        end
    end
    return result
end

local function defaultArea(id, label, purpose, color, x, y, width, height, slots, machineId, sceneId)
    return { id = id, label = label, purpose = purpose, color = color,
        machineId = machineId, sceneId=sceneId or "warehouse",
        x = x, y = y, width = width, height = height, slots = slots }
end

function StagingAreas.defaultState()
    local c = Config.cutterStaging
    return {
        areas = {
            defaultArea("cutter-output", "CUTTER OUTPUT", "machine_output", "yellow",
                c.x, c.y, c.width, c.height, standardSlots(), "MCH-0001"),
            defaultArea("inbound-shipping", "INBOUND SHIPPING", "inbound_shipping", "red",
                300, 320, 176, 130, inboundSlots()),
        },
        nextId = 3,
    }
end

local function finite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function validZone(zone)
    if type(zone) ~= "table" or type(zone.id) ~= "string" or #zone.id < 1 or #zone.id > 32
        or not zone.id:match("^[%w_.%-]+$") or not purposeIndex[zone.purpose]
        or not colorIndex[zone.color] or not finite(zone.x) or not finite(zone.y)
        or not finite(zone.width) or not finite(zone.height)
        or zone.width < 120 or zone.width > 360 or zone.height < 70 or zone.height > 260
        or type(zone.slots) ~= "table" or #zone.slots < 1 or #zone.slots > 6
        or (zone.machineId ~= nil and (type(zone.machineId) ~= "string"
            or #zone.machineId > 64 or not zone.machineId:match("^MCH%-%d+$")))
    then return false end
    for _, point in ipairs(zone.slots) do
        if type(point) ~= "table" or not finite(point.x) or not finite(point.y)
            or point.x < 0 or point.x > zone.width or point.y < 0 or point.y > zone.height
        then return false end
    end
    return true
end

function StagingAreas.normalize(source)
    if source == nil then return StagingAreas.defaultState() end
    if type(source) ~= "table" or type(source.areas) ~= "table"
        or #source.areas < 2 or #source.areas > StagingAreas.MAX_TOTAL_AREAS
    then return nil, "Invalid staging area settings." end
    local result, seen, sceneCounts = { areas = {}, nextId = 3 }, {}, {}
    local areaCount = #source.areas
    for key in pairs(source.areas) do
        if type(key) ~= "number" or key ~= math.floor(key) or key < 1 or key > areaCount then
            return nil, "Invalid staging area settings."
        end
    end
    for index, zone in ipairs(source.areas) do
        if not validZone(zone) or seen[zone.id] then return nil, "Invalid staging area settings." end
        seen[zone.id] = true
        local sceneId=zone.sceneId or "warehouse"
        if sceneId~="warehouse" and sceneId~="front_left" and sceneId~="front_right" then
            return nil,"Invalid staging area room."
        end
        sceneCounts[sceneId]=(sceneCounts[sceneId] or 0)+1
        if sceneCounts[sceneId]>StagingAreas.MAX_AREAS then
            return nil,"Each room can have up to six staging areas."
        end
        if (zone.id=="cutter-output" or zone.id=="inbound-shipping") and sceneId~="warehouse" then
            return nil,"The cutter output and inbound shipping zones stay in the warehouse."
        end
        local copy = { id = zone.id, label = type(zone.label) == "string" and zone.label:sub(1, 28) or "STAGING AREA",
            purpose = zone.purpose, color = zone.color, machineId = zone.machineId,
            sceneId=sceneId,
            x = math.floor(zone.x + 0.5), y = math.floor(zone.y + 0.5),
            width = zone.width, height = zone.height, slots = {} }
        for _, point in ipairs(zone.slots) do
            copy.slots[#copy.slots + 1] = { x = point.x, y = point.y }
        end
        if (copy.id == "cutter-output" and copy.purpose ~= "machine_output")
            or (copy.id == "inbound-shipping" and copy.purpose ~= "inbound_shipping")
            or copy.x < 60 or copy.y < 80
            or copy.x > Config.baseWidth - copy.width - 60
            or copy.y > Config.baseHeight - copy.height - 30
        then return nil, "Invalid staging area position or purpose." end
        result.areas[index] = copy
    end
    if not seen["cutter-output"] or not seen["inbound-shipping"] then
        return nil, "The cutter output and inbound shipping areas are required."
    end
    result.nextId = math.max(3, math.min(7, math.floor(tonumber(source.nextId) or (#result.areas + 1))))
    return result
end

function StagingAreas.valid(source)
    if source == nil then return true end
    return StagingAreas.normalize(source) ~= nil
end

function StagingAreas.areas(state,sceneId)
    local settings = state and state.stagingAreas
    local areas=type(settings) == "table" and settings.areas or StagingAreas.defaultState().areas
    if sceneId==nil then return areas end
    local result={}
    for _,zone in ipairs(areas) do
        if (zone.sceneId or "warehouse")==sceneId then result[#result+1]=zone end
    end
    return result
end

function StagingAreas.roomOptions(state)
    local result={{id="warehouse",label="WAREHOUSE",enabled=true}}
    local Rooms=require("src.shop_rooms")
    for _,id in ipairs({"front_left","front_right"}) do
        local kind=Rooms.definition(state,id)
        if kind=="storage" or kind=="floor" then
            local letter=id=="front_left" and "A" or "B"
            result[#result+1]={id=id,label=(kind=="storage" and "STORAGE " or "UTILITY ")..letter,enabled=true}
        end
    end
    return result
end

function StagingAreas.findById(state, id)
    for _, zone in ipairs(StagingAreas.areas(state)) do
        if zone.id == id then return zone end
    end
end

function StagingAreas.purposeName(id)
    return purposeLabel[id] or "STAGING AREA"
end

function StagingAreas.color(id)
    return colorById[id] or colorById.yellow
end

function StagingAreas.machineOptions(state,sceneId)
    local result = {}
    for _, machine in ipairs(state and state.machines and state.machines.items or {}) do
        if machine.status == "installed" and machineName[machine.modelId]
            and ((machine.world and machine.world.sceneId or "warehouse")== (sceneId or "warehouse")) then
            result[#result + 1] = { id = machine.id,
                label = machineName[machine.modelId] .. " / " .. machine.id }
        end
    end
    table.sort(result, function(a, b) return a.id < b.id end)
    return result
end

function StagingAreas.label(state, zone)
    if zone and zone.id == "cutter-output" then
        for _, machine in ipairs(state and state.machines and state.machines.items or {}) do
            if machine.id == zone.machineId and machine.modelId == "polar_115" then return "CUTTER OUTPUT" end
        end
        return "MACHINE OUTPUT"
    end
    if zone and zone.id == "inbound-shipping" then return "INBOUND SHIPPING" end
    return StagingAreas.purposeName(zone and zone.purpose)
end

function StagingAreas.nextAreaId(settings,sceneId)
    local used = {}
    for _, area in ipairs(settings and settings.areas or {}) do
        if (area.sceneId or "warehouse")== (sceneId or "warehouse") then used[area.id] = true end
    end
    for index = 1, StagingAreas.MAX_AREAS do
        local id=sceneId and sceneId~="warehouse" and (sceneId.."-staging-"..index)
            or ("staging-"..(index+2))
        if not used[id] then return id, index end
    end
end

function StagingAreas.positions(zone)
    local result = {}
    for index, point in ipairs(zone and zone.slots or {}) do
        result[index] = { x = zone.x + point.x, y = zone.y + point.y,
            direction = "northwest", rotation = 1 }
    end
    return result
end

function StagingAreas.receivingPoints(state)
    local result = {}
    for _, zone in ipairs(StagingAreas.areas(state)) do
        if (zone.sceneId or "warehouse")=="warehouse" and zone.purpose == "inbound_shipping" then
            for _, point in ipairs(StagingAreas.positions(zone)) do result[#result + 1] = point end
        end
    end
    return #result > 0 and result or Config.palletLogistics.spawnPoints
end

function StagingAreas.hasMachineOutput(state, machineId,sceneId)
    if not sceneId then
        local machine=require("src.machine_fleet").byId(state,machineId)
        sceneId=machine and machine.world and machine.world.sceneId or "warehouse"
    end
    for _, zone in ipairs(StagingAreas.areas(state)) do
        if zone.purpose == "machine_output" and zone.machineId == machineId
            and (zone.sceneId or "warehouse")==sceneId then return true end
    end
    return false
end

function StagingAreas.slotClear(state, x, y, excludedPalletId,sceneId)
    sceneId=sceneId or "warehouse"
    local halfWidth = Config.palletLogistics.collisionHalfWidth
    local halfHeight = Config.palletLogistics.collisionHalfHeight
    if sceneId~="warehouse" then
        local Rooms=require("src.shop_rooms")
        for _,point in ipairs({
            {x-halfWidth,y-halfHeight},{x+halfWidth,y-halfHeight},
            {x-halfWidth,y+halfHeight},{x+halfWidth,y+halfHeight},
        }) do
            if not Rooms.walkable(point[1],point[2],sceneId) then return false end
        end
    end
    local floor = { warehouse = true, cutter_output = true, press_output = true }
    for _, item in ipairs(PalletState.items(state)) do
        local pallet, world = item.pallet, item.pallet and item.pallet.world
        if pallet and pallet.id ~= excludedPalletId and floor[pallet.location]
            and type(world) == "table"
            and (world.sceneId or "warehouse")== (sceneId or "warehouse")
            and math.abs(x - world.x) < halfWidth * 2 + 4
            and math.abs(y - world.y) < halfHeight * 2 + 4
        then return false end
    end
    local placement = {
        polar_115 = { config = Config.cutterPlacement, field = "cutter" },
        skid_wrapper = { config = Config.wrapperPlacement, field = "wrapper" },
        heidelberg_10x15 = { config = Config.windmillPlacement, field = "windmill" },
    }
    for _, machine in ipairs(state and state.machines and state.machines.items or {}) do
        local machinePlacement = placement[machine.modelId]
        if machine.status == "installed" and machinePlacement then
            local machineConfig = machinePlacement.config
            local world = machine.world or state[machinePlacement.field]
            if world and (world.sceneId or "warehouse")== (sceneId or "warehouse")
                and math.abs(x - world.x) < halfWidth + (machineConfig.collisionHalfWidth or 52)
                and math.abs(y - world.y) < halfHeight + (machineConfig.collisionHalfHeight or 32)
            then return false end
        end
    end
    return true
end

function StagingAreas.findMachineOutput(state, machineId, isClear, allowFallback)
    machineId = machineId or "MCH-0001"
    local machine=require("src.machine_fleet").byId(state,machineId)
    local sceneId=machine and machine.world and machine.world.sceneId or "warehouse"
    local matching, fallback = false, nil
    for _, zone in ipairs(StagingAreas.areas(state)) do
        if zone.purpose == "machine_output" and (zone.sceneId or "warehouse")==sceneId then
            fallback = fallback or zone
            if zone.machineId == machineId then
                matching = true
                for _, slot in ipairs(StagingAreas.positions(zone)) do
                    if isClear(slot.x, slot.y,sceneId) then return slot end
                end
            end
        end
    end
    if not matching and fallback and allowFallback ~= false then
        for _, slot in ipairs(StagingAreas.positions(fallback)) do
            if isClear(slot.x, slot.y,sceneId) then return slot end
        end
    end
    return nil, "The assigned machine output staging area is full or blocked. Move a pallet or reposition its zone."
end

function StagingAreas.isFixedPurpose(zone)
    return zone and (zone.id == "cutter-output" or zone.id == "inbound-shipping")
end

local function overlaps(a, b)
    return a.x < b.x + b.width and b.x < a.x + a.width
        and a.y < b.y + b.height and b.y < a.y + a.height
end

local function nextAreaPosition(settings, width, height,sceneId)
    local columns = { 60, 250, 440, 630 }
    local rows = { 100, 205, 330, 460 }
    for _, y in ipairs(rows) do
        for _, x in ipairs(columns) do
            local candidate = { x = x, y = y, width = width, height = height }
            local clear = true
            for _, existing in ipairs(settings.areas) do
                if (existing.sceneId or "warehouse")==sceneId and overlaps(candidate, existing) then clear = false; break end
            end
            if clear and sceneId~="warehouse" then
                local Rooms=require("src.shop_rooms")
                for _,point in ipairs({
                    {x,y},{x+width,y},{x,y+height},{x+width,y+height},
                }) do
                    if not Rooms.walkable(point[1],point[2],sceneId) then clear=false;break end
                end
            end
            if clear and x <= Config.baseWidth - width - 60 and y <= Config.baseHeight - height - 30 then
                return x, y
            end
        end
    end
end

function StagingAreas.apply(state, intent)
    state.stagingAreas = state.stagingAreas or StagingAreas.defaultState()
    local settings = state.stagingAreas
    local zone = intent.areaId and StagingAreas.findById(state, intent.areaId)
    if intent.kind == "staging_area_add" then
        local sceneId=intent.sceneId or "warehouse"
        local allowed=false
        for _,option in ipairs(StagingAreas.roomOptions(state)) do if option.id==sceneId then allowed=true end end
        if not allowed then return false,"That room is not available for pallet staging." end
        local roomAreas=StagingAreas.areas(state,sceneId)
        if #roomAreas >= StagingAreas.MAX_AREAS then return false, "You can create up to six staging areas in each room." end
        local areaId, id = StagingAreas.nextAreaId(settings,sceneId)
        if not areaId then return false, "All six staging areas already exist in this room." end
        local c = Config.cutterStaging
        local x, y = nextAreaPosition(settings, c.width, c.height,sceneId)
        if not x then return false, "Move an existing staging area to make room for another." end
        settings.areas[#settings.areas + 1] = defaultArea(areaId, "STAGING AREA " .. id,
            "used", "blue", x, y,
            c.width, c.height, standardSlots(),nil,sceneId)
        settings.nextId = math.max(tonumber(settings.nextId) or 3,id+1)
        return true, "Staging area added. Select its purpose, color, and position."
    end
    if not zone then return false, "That staging area no longer exists." end
    if intent.kind == "staging_area_remove" then
        if StagingAreas.isFixedPurpose(zone) then
            return false, "The cutter output and inbound shipping areas are required."
        end
        for index, area in ipairs(settings.areas) do
            if area.id == zone.id then table.remove(settings.areas, index); break end
        end
        return true, "Staging area removed."
    end
    local change = intent.change
    if change == "left" or change == "right" or change == "up" or change == "down" then
        local dx = change == "left" and -16 or change == "right" and 16 or 0
        local dy = change == "up" and -16 or change == "down" and 16 or 0
        zone.x = math.max(60, math.min(Config.baseWidth - zone.width - 60, zone.x + dx))
        zone.y = math.max(80, math.min(Config.baseHeight - zone.height - 30, zone.y + dy))
    elseif change == "move_to" then
        if not finite(intent.x) or not finite(intent.y) then
            return false, "Choose a valid staging area position."
        end
        zone.x = math.floor(math.max(60, math.min(Config.baseWidth - zone.width - 60, intent.x)) + 0.5)
        zone.y = math.floor(math.max(80, math.min(Config.baseHeight - zone.height - 30, intent.y)) + 0.5)
    elseif change == "purpose_next" or change == "purpose_previous" then
        if StagingAreas.isFixedPurpose(zone) then return false, "The cutter and inbound areas have fixed purposes." end
        local direction = change == "purpose_next" and 1 or -1
        local index = ((purposeIndex[zone.purpose] - 1 + direction) % #StagingAreas.PURPOSES) + 1
        zone.purpose = StagingAreas.PURPOSES[index].id
        if zone.purpose == "machine_output" and not zone.machineId then
            local machines = StagingAreas.machineOptions(state,zone.sceneId)
            zone.machineId = machines[1] and machines[1].id or nil
        end
    elseif change == "color_next" or change == "color_previous" then
        local direction = change == "color_next" and 1 or -1
        local index = ((colorIndex[zone.color] - 1 + direction) % #StagingAreas.COLORS) + 1
        zone.color = StagingAreas.COLORS[index].id
    elseif change == "machine_next" or change == "machine_previous" then
        if zone.purpose ~= "machine_output" then return false, "Choose Machine Output to assign a machine." end
        if zone.id == "cutter-output" then return false, "The cutter output area stays assigned to the Polar cutter." end
        local machines = StagingAreas.machineOptions(state,zone.sceneId)
        if #machines == 0 then return false, "Install a machine before assigning its output area." end
        local current = 0
        for index, machine in ipairs(machines) do if machine.id == zone.machineId then current = index end end
        local direction = change == "machine_next" and 1 or -1
        if current == 0 then current = direction == 1 and #machines or 1 end
        current = ((current - 1 + direction) % #machines) + 1
        zone.machineId = machines[current].id
    else
        return false, "Choose a valid staging area change."
    end
    return true, "Staging area settings saved."
end

function StagingAreas.draw(state,sceneId)
    for _, zone in ipairs(StagingAreas.areas(state,sceneId)) do
        local palette = StagingAreas.color(zone.color)
        love.graphics.push("all")
        love.graphics.setLineWidth(2)
        love.graphics.setColor(palette.rgb[1], palette.rgb[2], palette.rgb[3], 0.78)
        love.graphics.rectangle("line", zone.x, zone.y, zone.width, zone.height)
        love.graphics.push()
        love.graphics.translate(zone.x, zone.y + 3)
        love.graphics.scale(0.7)
        love.graphics.printf(StagingAreas.label(state, zone), 0, 0, zone.width / 0.7, "center")
        love.graphics.pop()
        for _, slot in ipairs(StagingAreas.positions(zone)) do
            love.graphics.setColor(palette.rgb[1], palette.rgb[2], palette.rgb[3], 0.15)
            love.graphics.polygon("fill", slot.x, slot.y - 9, slot.x + 28, slot.y, slot.x, slot.y + 9, slot.x - 28, slot.y)
            love.graphics.setColor(palette.rgb[1], palette.rgb[2], palette.rgb[3], 0.6)
            love.graphics.polygon("line", slot.x, slot.y - 9, slot.x + 28, slot.y, slot.x, slot.y + 9, slot.x - 28, slot.y)
        end
        love.graphics.pop()
    end
end

return StagingAreas
