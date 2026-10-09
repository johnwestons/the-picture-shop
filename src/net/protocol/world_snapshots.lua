-- Movement, player, visitor, vehicle, and environment snapshots.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.normalizeInput(payload)
        local valid, shapeError = Runtime.shape(payload, "input payload",
            { "sessionId", "sequence", "moveX", "moveY" },
            { "furColorway", "overallsColorway", "taskAction", "gameX", "gameY", "combatButtons" })
        if not valid then return nil, shapeError end
        local taskAction, taskActionError = Runtime.normalizeTaskAction(
            payload.taskAction, "input.taskAction")
        if taskActionError then return nil, taskActionError end
        local sessionId, fieldError = Runtime.token(payload.sessionId, Runtime.MAX_TOKEN_BYTES, "input.sessionId")
        if not sessionId then return nil, fieldError end
        local sequence
        sequence, fieldError = Runtime.integerInRange(payload.sequence, 0, Runtime.UINT32_MAX, "input.sequence")
        if not sequence then return nil, fieldError end
        local moveX
        moveX, fieldError = Runtime.numberInRange(payload.moveX, -1, 1, "input.moveX")
        if not moveX then return nil, fieldError end
        local moveY
        moveY, fieldError = Runtime.numberInRange(payload.moveY, -1, 1, "input.moveY")
        if not moveY then return nil, fieldError end
        local gameX,gameY=0,0
        if payload.gameX~=nil then
            gameX,fieldError=Runtime.numberInRange(payload.gameX,-1,1,"input.gameX")
            if gameX==nil then return nil,fieldError end
        end
        if payload.gameY~=nil then
            gameY,fieldError=Runtime.numberInRange(payload.gameY,-1,1,"input.gameY")
            if gameY==nil then return nil,fieldError end
        end
        local combatButtons=0
        if payload.combatButtons~=nil then
            combatButtons,fieldError=Runtime.integerInRange(payload.combatButtons,0,15,"input.combatButtons")
            if combatButtons==nil then return nil,fieldError end
        end
        local furColorway = payload.furColorway
        if furColorway ~= nil then
            furColorway, fieldError = Runtime.integerInRange(furColorway, 1, Runtime.RabbitColorways.count("fur"),
                "input.furColorway")
            if not furColorway then return nil, fieldError end
        end
        local overallsColorway = payload.overallsColorway
        if overallsColorway ~= nil then
            overallsColorway, fieldError = Runtime.integerInRange(overallsColorway, 1,
                Runtime.RabbitColorways.count("overalls"), "input.overallsColorway")
            if not overallsColorway then return nil, fieldError end
        end
        return { sessionId = sessionId, sequence = sequence, moveX = moveX, moveY = moveY,
            furColorway = furColorway, overallsColorway = overallsColorway,
            taskAction = taskAction, gameX=gameX, gameY=gameY, combatButtons=combatButtons }
    end

    function Runtime.normalizeSnapshot(payload)
        local valid, shapeError = Runtime.shape(payload, "snapshot payload",
            { "sessionId", "serverTick", "players" }, { "games", "balls" })
        if not valid then return nil, shapeError end
        local sessionId, fieldError = Runtime.token(payload.sessionId, Runtime.MAX_TOKEN_BYTES, "snapshot.sessionId")
        if not sessionId then return nil, fieldError end
        local serverTick
        serverTick, fieldError = Runtime.integerInRange(payload.serverTick, 0, Runtime.UINT32_MAX, "snapshot.serverTick")
        if not serverTick then return nil, fieldError end
        if not Runtime.Codec.isArray(payload.players) or #payload.players ~= 1 then
            return nil, "snapshot.players must contain exactly one player"
        end
        local players
        players, fieldError = Runtime.normalizePlayers(payload.players, "snapshot.players")
        if not players then return nil, fieldError end
        local games
        if payload.games ~= nil then
            if not Runtime.Codec.isArray(payload.games) or #payload.games > 2 then
                return nil,"snapshot.games must contain at most two room matches"
            end
            games = {}
            local seen = {}
            for index, entry in ipairs(payload.games) do
                local fields={"bayId","mode","phase","leftId","leftX","leftY","rightX","rightY",
                    "puckX","puckY","leftScore","rightScore","faceoff"}
                local okay, err=Runtime.shape(entry,"snapshot.games["..index.."]",fields,{"rightId"})
                if not okay then return nil,err end
                if not require("src.breakroom_games").BAYS[entry.bayId] or seen[entry.bayId]
                    or (entry.mode~="solo" and entry.mode~="versus")
                    or (entry.phase~="waiting" and entry.phase~="playing" and entry.phase~="finished")
                    then return nil,"snapshot.games match identity is invalid" end
                seen[entry.bayId]=true
                for _,key in ipairs({"leftId","rightId"}) do
                    if entry[key]~=nil then
                        local id,idErr=Runtime.integerInRange(entry[key],1,Runtime.Protocol.MAX_PLAYERS,
                            "snapshot.games."..key)
                        if not id then return nil,idErr end
                    end
                end
                for _,key in ipairs({"leftX","leftY","rightX","rightY","puckX","puckY"}) do
                    local n,nErr=Runtime.numberInRange(entry[key],0,800,"snapshot.games."..key)
                    if n==nil then return nil,nErr end
                end
                for _,key in ipairs({"leftScore","rightScore"}) do
                    local n,nErr=Runtime.integerInRange(entry[key],0,7,"snapshot.games."..key)
                    if n==nil then return nil,nErr end
                end
                local pause,pauseErr=Runtime.numberInRange(entry.faceoff,0,2,"snapshot.games.faceoff")
                if pause==nil then return nil,pauseErr end
                games[index]=entry
            end
        end
        local balls
        if payload.balls~=nil then
            if not Runtime.Codec.isArray(payload.balls) or #payload.balls>2 then
                return nil,"snapshot.balls must contain at most two basketballs"
            end
            balls={}
            local seen={}
            for index,entry in ipairs(payload.balls) do
                local okay,err=Runtime.shape(entry,"snapshot.balls["..index.."]",
                    {"bayId","sceneId","x","y","displayY","mode","leftScore","rightScore","streak"},
                    {"holderPlayerId","shooterId","shotPhase","shotElapsed","rimHit",
                     "leftId","rightId","contestPhase"})
                if not okay then return nil,err end
                local bay=require("src.breakroom_games").BAYS
                if not bay[entry.bayId] or seen[entry.bayId]
                    or (entry.sceneId~="warehouse" and not bay[entry.sceneId])
                    or (entry.mode~="placed" and entry.mode~="held" and entry.mode~="flight") then
                    return nil,"snapshot.balls identity is invalid"
                end
                seen[entry.bayId]=true
                for _,key in ipairs({"x","y","displayY"}) do
                    local n,nErr=Runtime.numberInRange(entry[key],key=="displayY" and -250 or 0,
                        key=="x" and 960 or 678,"snapshot.balls."..key)
                    if n==nil then return nil,nErr end
                end
                for _,key in ipairs({"holderPlayerId","shooterId","leftId","rightId"}) do
                    if entry[key]~=nil then
                        local n,nErr=Runtime.integerInRange(entry[key],1,Runtime.Protocol.MAX_PLAYERS,
                            "snapshot.balls."..key)
                        if not n then return nil,nErr end
                    end
                end
                for _,key in ipairs({"leftScore","rightScore"}) do
                    local n,nErr=Runtime.integerInRange(entry[key],0,11,"snapshot.balls."..key)
                    if not n then return nil,nErr end
                end
                local streak,streakErr=Runtime.integerInRange(entry.streak,0,1000000,"snapshot.balls.streak")
                if not streak then return nil,streakErr end
                if entry.shotPhase~=nil and entry.shotPhase~="charge" and entry.shotPhase~="flight"
                    and entry.shotPhase~="fall" and entry.shotPhase~="rebound" then
                    return nil,"snapshot.balls.shotPhase is invalid"
                end
                if entry.shotElapsed~=nil then
                    local elapsed,elapsedErr=Runtime.numberInRange(entry.shotElapsed,0,2,"snapshot.balls.shotElapsed")
                    if not elapsed then return nil,elapsedErr end
                end
                if entry.rimHit~=nil and type(entry.rimHit)~="boolean" then
                    return nil,"snapshot.balls.rimHit must be boolean"
                end
                if entry.contestPhase~=nil and entry.contestPhase~="waiting"
                    and entry.contestPhase~="playing" and entry.contestPhase~="finished" then
                    return nil,"snapshot.balls.contestPhase is invalid"
                end
                balls[index]=entry
            end
        end
        return { sessionId = sessionId, serverTick = serverTick, players = players,
            games = games and Runtime.Codec.array(games) or nil,
            balls = balls and Runtime.Codec.array(balls) or nil }
    end

    Runtime.VISITOR_STATES = {
        scheduled = true,
        entering = true,
        waiting = true,
        reviewing = true,
        exiting = true,
        finished = true,
    }

    Runtime.VISITOR_DECISIONS = {
        accepted = true,
        declined = true,
        timed_out = true,
    }

    Runtime.VISITOR_FIELDS = {
        "state", "visible", "x", "y", "waypoint", "seatIndex", "character",
        "facing", "intentX", "intentY", "motionX", "motionY", "currentSpeed",
        "animationDistance", "animationClock", "idleClock", "inMotion", "waitTimer",
        "arrivalTimer",
    }

    function Runtime.normalizeVisitor(value, label)
        local valid, shapeError = Runtime.shape(value, label, Runtime.VISITOR_FIELDS, { "decision" })
        if not valid then return nil, shapeError end
        if not Runtime.VISITOR_STATES[value.state] then return nil, label .. ".state is invalid" end
        if type(value.visible) ~= "boolean" then return nil, label .. ".visible must be boolean" end
        local normalized = { state = value.state, visible = value.visible }
        local fieldError
        normalized.x, fieldError = Runtime.numberInRange(value.x, -Runtime.MAX_COORDINATE, Runtime.MAX_COORDINATE,
            label .. ".x")
        if normalized.x == nil then return nil, fieldError end
        normalized.y, fieldError = Runtime.numberInRange(value.y, -Runtime.MAX_COORDINATE, Runtime.MAX_COORDINATE,
            label .. ".y")
        if normalized.y == nil then return nil, fieldError end
        normalized.waypoint, fieldError = Runtime.integerInRange(value.waypoint, 1, 64,
            label .. ".waypoint")
        if normalized.waypoint == nil then return nil, fieldError end
        normalized.seatIndex, fieldError = Runtime.integerInRange(value.seatIndex, 0, 64,
            label .. ".seatIndex")
        if normalized.seatIndex == nil then return nil, fieldError end
        normalized.character, fieldError = Runtime.characterToken(value.character, label .. ".character")
        if not normalized.character then return nil, fieldError end
        if value.facing ~= -1 and value.facing ~= 1 then
            return nil, label .. ".facing must be -1 or 1"
        end
        normalized.facing = value.facing
        for _, field in ipairs({ "intentX", "intentY", "motionX", "motionY" }) do
            normalized[field], fieldError = Runtime.numberInRange(value[field], -1, 1,
                label .. "." .. field)
            if normalized[field] == nil then return nil, fieldError end
        end
        normalized.currentSpeed, fieldError = Runtime.numberInRange(value.currentSpeed, 0, Runtime.MAX_VELOCITY,
            label .. ".currentSpeed")
        if normalized.currentSpeed == nil then return nil, fieldError end
        for _, field in ipairs({
            "animationDistance", "animationClock", "idleClock", "waitTimer",
        }) do
            normalized[field], fieldError = Runtime.numberInRange(value[field], 0,
                Runtime.MAX_ANIMATION_DISTANCE, label .. "." .. field)
            if normalized[field] == nil then return nil, fieldError end
        end
        normalized.arrivalTimer, fieldError = Runtime.numberInRange(value.arrivalTimer,
            -Runtime.MAX_ANIMATION_DISTANCE, Runtime.MAX_ANIMATION_DISTANCE, label .. ".arrivalTimer")
        if normalized.arrivalTimer == nil then return nil, fieldError end
        if type(value.inMotion) ~= "boolean" then return nil, label .. ".inMotion must be boolean" end
        normalized.inMotion = value.inMotion
        if value.decision ~= nil then
            if not Runtime.VISITOR_DECISIONS[value.decision] then
                return nil, label .. ".decision is invalid"
            end
            normalized.decision = value.decision
        end
        return normalized
    end

    function Runtime.normalizeVisitorSnapshot(payload)
        local valid, shapeError = Runtime.shape(payload, "visitor_snapshot payload",
            { "sessionId", "serverTick", "customer", "vendor" })
        if not valid then return nil, shapeError end
        local sessionId, fieldError = Runtime.token(
            payload.sessionId, Runtime.MAX_TOKEN_BYTES, "visitor_snapshot.sessionId")
        if not sessionId then return nil, fieldError end
        local serverTick
        serverTick, fieldError = Runtime.integerInRange(
            payload.serverTick, 0, Runtime.UINT32_MAX, "visitor_snapshot.serverTick")
        if not serverTick then return nil, fieldError end
        local customer
        customer, fieldError = Runtime.normalizeVisitor(payload.customer, "visitor_snapshot.customer")
        if not customer then return nil, fieldError end
        local vendor
        vendor, fieldError = Runtime.normalizeVisitor(payload.vendor, "visitor_snapshot.vendor")
        if not vendor then return nil, fieldError end
        return {
            sessionId = sessionId,
            serverTick = serverTick,
            customer = customer,
            vendor = vendor,
        }
    end

    Runtime.BAY_DOOR_STATES = {
        closed = true,
        opening = true,
        open = true,
        closing = true,
    }

    Runtime.TRUCK_STATES = {
        absent = true,
        scheduled = true,
        waiting_for_bay = true,
        backing = true,
        parked_closed = true,
        cargo_opening = true,
        cargo_open = true,
        cargo_closing = true,
        departing = true,
    }

    Runtime.TRUCK_MODES = {
        delivery = true,
        vendor_delivery = true,
        machine_delivery = true,
        pickup = true,
    }

    function Runtime.normalizeBayDoor(value, label)
        local valid, shapeError = Runtime.shape(value, label, { "state", "progress" })
        if not valid then return nil, shapeError end
        if not Runtime.BAY_DOOR_STATES[value.state] then return nil, label .. ".state is invalid" end
        local progress, fieldError = Runtime.numberInRange(value.progress, 0, 1, label .. ".progress")
        if progress == nil then return nil, fieldError end
        if value.state == "closed" and progress ~= 0 then
            return nil, label .. ".closed progress must be zero"
        end
        if value.state == "open" and progress ~= 1 then
            return nil, label .. ".open progress must be one"
        end
        return { state = value.state, progress = progress }
    end

    function Runtime.normalizeTruck(value, label)
        local valid, shapeError = Runtime.shape(value, label,
            { "state", "backingProgress", "cargoProgress" }, { "jobId", "mode" })
        if not valid then return nil, shapeError end
        if not Runtime.TRUCK_STATES[value.state] then return nil, label .. ".state is invalid" end
        local normalized = { state = value.state }
        local fieldError
        normalized.backingProgress, fieldError = Runtime.numberInRange(
            value.backingProgress, 0, 1, label .. ".backingProgress")
        if normalized.backingProgress == nil then return nil, fieldError end
        normalized.cargoProgress, fieldError = Runtime.numberInRange(
            value.cargoProgress, 0, 1, label .. ".cargoProgress")
        if normalized.cargoProgress == nil then return nil, fieldError end
        if value.state == "absent" then
            if value.jobId ~= nil or value.mode ~= nil then
                return nil, label .. ".absent truck cannot have a job or mode"
            end
            if normalized.backingProgress ~= 0 or normalized.cargoProgress ~= 0 then
                return nil, label .. ".absent truck progress must be zero"
            end
        else
            normalized.jobId, fieldError = Runtime.token(value.jobId, Runtime.MAX_TOKEN_BYTES, label .. ".jobId")
            if not normalized.jobId then return nil, fieldError end
            if type(value.mode) ~= "string" or not Runtime.TRUCK_MODES[value.mode] then
                return nil, label .. ".mode is invalid"
            end
            normalized.mode = value.mode
        end
        return normalized
    end

    function Runtime.normalizeEnvironmentSnapshot(payload)
        local valid, shapeError = Runtime.shape(payload, "environment_snapshot payload",
            { "sessionId", "serverTick", "bayDoor", "truck" }, { "employees" })
        if not valid then return nil, shapeError end
        local sessionId, fieldError = Runtime.token(
            payload.sessionId, Runtime.MAX_TOKEN_BYTES, "environment_snapshot.sessionId")
        if not sessionId then return nil, fieldError end
        local serverTick
        serverTick, fieldError = Runtime.integerInRange(
            payload.serverTick, 0, Runtime.UINT32_MAX, "environment_snapshot.serverTick")
        if not serverTick then return nil, fieldError end
        local bayDoor
        bayDoor, fieldError = Runtime.normalizeBayDoor(payload.bayDoor, "environment_snapshot.bayDoor")
        if not bayDoor then return nil, fieldError end
        local truck
        truck, fieldError = Runtime.normalizeTruck(payload.truck, "environment_snapshot.truck")
        if not truck then return nil, fieldError end
        local employees
        if payload.employees~=nil then
            employees=Runtime.EmployeePose.normalize(payload.employees)
            if not employees then return nil,"environment_snapshot.employees is inconsistent" end
        end
        return {
            sessionId = sessionId,
            serverTick = serverTick,
            bayDoor = bayDoor,
            truck = truck,
            employees = employees,
        }
    end

    function Runtime.normalizeEmployeeSnapshot(payload)
        local valid,err=Runtime.shape(payload,"employee_snapshot payload",{"sessionId","serverTick","employees"})
        if not valid then return nil,err end
        local sessionId,fieldError=Runtime.token(payload.sessionId,Runtime.MAX_TOKEN_BYTES,"employee_snapshot.sessionId")
        if not sessionId then return nil,fieldError end
        local tick
        tick,fieldError=Runtime.integerInRange(payload.serverTick,0,Runtime.UINT32_MAX,"employee_snapshot.serverTick")
        if tick==nil then return nil,fieldError end
        local employees=Runtime.EmployeePose.normalize(payload.employees)
        if not employees then return nil,"employee_snapshot.employees is inconsistent" end
        return {sessionId=sessionId,serverTick=tick,employees=employees}
    end

    function Runtime.normalizeForkliftSnapshot(payload)
        local valid, fieldError = Runtime.shape(payload, "forklift_snapshot payload", { "sessionId", "serverTick", "forklift" })
        if not valid then return nil, fieldError end
        local sessionId
        sessionId, fieldError = Runtime.token(payload.sessionId, Runtime.MAX_TOKEN_BYTES, "forklift_snapshot.sessionId")
        if not sessionId then return nil, fieldError end
        local tick
        tick, fieldError = Runtime.integerInRange(payload.serverTick, 0, Runtime.UINT32_MAX, "forklift_snapshot.serverTick")
        if tick == nil then return nil, fieldError end
        valid, fieldError = Runtime.shape(payload.forklift, "forklift_snapshot.forklift", {
            "owned", "x", "y", "direction", "operating", "moving", "animationDistance",
            "forkHeight", "targetForkHeight", "lifting",
        }, { "operatorPlayerId", "carriedPalletId" })
        if not valid then return nil, fieldError end
        if not Runtime.Forklift.validState(payload.forklift) then return nil, "forklift_snapshot.forklift is inconsistent" end
        return { sessionId = sessionId, serverTick = tick, forklift = Runtime.Forklift.normalize(payload.forklift) }
    end
end

return Component
