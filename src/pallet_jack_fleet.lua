-- The original jack remains the player/network control slot. Extra physical
-- jacks share the same transport code through a view selecting one vehicle.
local Fleet = {}
local choices = setmetatable({}, {__mode="k"})

function Fleet.root(state) return rawget(state, "_jackRoot") or state end

function Fleet.all(state)
    state = Fleet.root(state)
    local result = {}
    if type(state.palletJack)=="table" then result[1]=state.palletJack end
    for _,jack in ipairs(state.extraPalletJacks or {}) do result[#result+1]=jack end
    return result
end

function Fleet.view(state, jack)
    local root=Fleet.root(state)
    if jack==root.palletJack then return root end
    return setmetatable({palletJack=jack,_jackRoot=root}, {__index=root,__newindex=root})
end

function Fleet.owned(state, employeeId)
    for _,jack in ipairs(Fleet.all(state)) do
        if jack.operating and jack.operatorEmployeeId==employeeId then return jack end
    end
end

function Fleet.employee(state, worker, palletId)
    palletId=palletId or worker._shippingPalletId or (worker.assignment and worker.assignment.palletId)
    local owned=Fleet.owned(state,worker.id)
    if owned then return owned end
    local selected,best
    for _,jack in ipairs(Fleet.all(state)) do
        if not jack.operating
            and (not jack.carriedPalletId or jack.carriedPalletId==palletId) then
            -- Resume a parked load on its actual vehicle, even when an empty
            -- jack is closer to the returning employee.
            if palletId and jack.carriedPalletId==palletId then choices[worker]=jack;return jack end
            local distance=(worker.x-jack.x)^2+(worker.y-jack.y)^2
            if (jack.sceneId or "warehouse")~=(worker.sceneId or "warehouse") then distance=distance+1000000 end
            if choices[worker]==jack then distance=distance-64^2 end
            if not best or distance<best then selected,best=jack,distance end
        end
    end
    choices[worker]=selected
    return selected
end

function Fleet.employeeView(state, worker, palletId)
    local jack=Fleet.employee(state,worker,palletId or (worker.assignment and worker.assignment.palletId))
    return Fleet.view(state,jack or Fleet.root(state).palletJack)
end

function Fleet.add(state, id, point)
    state=Fleet.root(state)
    state.palletJack.id=state.palletJack.id or "JACK-0001"
    for _,jack in ipairs(Fleet.all(state)) do if jack.id==id then return jack end end
    local jack=require("src.pallet_jack").defaultState(require("src.config").palletJack)
    jack.id,jack.x,jack.y=id,point.x,point.y
    state.extraPalletJacks=state.extraPalletJacks or {}
    state.extraPalletJacks[#state.extraPalletJacks+1]=jack
    return jack
end

function Fleet.byId(state,id)
    for _,jack in ipairs(Fleet.all(state)) do if jack.id==id then return jack end end
end

function Fleet.snapshots(state)
    local result={}
    local Jack,Config=require("src.pallet_jack"),require("src.config")
    for _,jack in ipairs(Fleet.root(state).extraPalletJacks or {}) do
        local snapshot=Jack.snapshot(Fleet.view(state,jack),Config.palletJack)
        snapshot.frame,snapshot.palletFrame=nil,nil
        snapshot.motion=Jack.presentationSnapshot(Fleet.view(state,jack),Config.palletJack)
        result[#result+1]={id=jack.id,jack=snapshot}
    end
    return result
end

function Fleet.applySnapshot(state,id,snapshot)
    local jack=Fleet.byId(state,id)
    if not jack or jack==state.palletJack then return false,"awaiting_durable" end
    return require("src.pallet_jack").applySnapshot(Fleet.view(state,jack),snapshot,require("src.config").palletJack)
end

-- Selecting a parked extra jack promotes it to the existing control slot.
-- Employees locate their vehicle by ownership, so promotion cannot steal it.
function Fleet.playerChoice(state, player)
    state=Fleet.root(state)
    local primary=state.palletJack
    if primary.operating and primary.operatorPlayerId then return primary end
    local selected,best=primary,math.huge
    for _,jack in ipairs(Fleet.all(state)) do
        if (jack.sceneId or "warehouse")== (player.sceneId or "warehouse") and not jack.operating then
            local distance=(player.x-jack.x)^2+(player.y-jack.y)^2
            if distance<best then selected,best=jack,distance end
        end
    end
    return selected
end

function Fleet.selectPlayer(state, player)
    state=Fleet.root(state)
    local primary=state.palletJack
    local selected=Fleet.playerChoice(state,player)
    if selected~=primary then
        for index,jack in ipairs(state.extraPalletJacks or {}) do
            if jack==selected then state.extraPalletJacks[index]=primary;break end
        end
        state.palletJack=selected
    end
    return state.palletJack
end

-- Validate one cargo owner per jack and one vehicle per operator, including
-- the forklift. This is also used before save normalization strips operators.
function Fleet.validate(state)
    if state.extraPalletJacks~=nil then
        if type(state.extraPalletJacks)~="table" then return false end
        local count=0
        for key,jack in pairs(state.extraPalletJacks) do
            count=count+1
            if type(key)~="number" or key%1~=0 or key<1 or key>#state.extraPalletJacks
                or type(jack)~="table" or type(jack.id)~="string" then return false end
        end
        if count~=#state.extraPalletJacks then return false end
    end
    local players,employees,loads,ids={},{},{},{}
    local lift=state.forklift
    if type(lift)=="table" and lift.operating and lift.operatorPlayerId then players[lift.operatorPlayerId]=true end
    for _,jack in ipairs(Fleet.all(state)) do
        if jack.id then
            if type(jack.id)~="string" or #jack.id>64 or not jack.id:match("^[%w_.%-]+$") or ids[jack.id] then return false end
            ids[jack.id]=true
        end
        if jack.carriedPalletId then
            if loads[jack.carriedPalletId] then return false end
            loads[jack.carriedPalletId]=jack
        end
        if jack.operating then
            if jack.operatorEmployeeId then
                if jack.operatorPlayerId or employees[jack.operatorEmployeeId] then return false end
                employees[jack.operatorEmployeeId]=true
            elseif jack.operatorPlayerId then
                if players[jack.operatorPlayerId] then return false end
                players[jack.operatorPlayerId]=true
            end
        end
    end
    return true,loads
end

return Fleet
