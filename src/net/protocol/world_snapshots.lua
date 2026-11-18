-- Movement, player, visitor, vehicle, and environment snapshots.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.normalizeHockeyMatch(entry)
        local fields={"bayId","mode","phase","leftId","leftX","leftY","rightX","rightY",
            "puckX","puckY","leftScore","rightScore","faceoff"}
        local okay,err=Runtime.shape(entry,"hockey match",fields,{"rightId"})
        if not okay then return nil,err end
        if not require("src.breakroom_games").BAYS[entry.bayId]
            or (entry.mode~="solo" and entry.mode~="versus")
            or (entry.phase~="waiting" and entry.phase~="playing" and entry.phase~="finished") then
            return nil,"hockey match identity is invalid"
        end
        for _,key in ipairs({"leftId","rightId"}) do
            if entry[key]~=nil then
                local id,why=Runtime.integerInRange(entry[key],1,Runtime.Protocol.MAX_PLAYERS,"hockey."..key)
                if not id then return nil,why end
            end
        end
        for _,key in ipairs({"leftX","leftY","rightX","rightY","puckX","puckY"}) do
            local n,why=Runtime.numberInRange(entry[key],0,800,"hockey."..key)
            if n==nil then return nil,why end
        end
        for _,key in ipairs({"leftScore","rightScore"}) do
            local n,why=Runtime.integerInRange(entry[key],0,7,"hockey."..key)
            if n==nil then return nil,why end
        end
        local pause,why=Runtime.numberInRange(entry.faceoff,0,2,"hockey.faceoff")
        if pause==nil then return nil,why end
        return entry
    end

    function Runtime.normalizeHockeySnapshot(payload)
        local okay,err=Runtime.shape(payload,"hockey_snapshot payload",{"sessionId","serverTick","bayId","game"})
        if not okay then return nil,err end
        local sessionId;sessionId,err=Runtime.token(payload.sessionId,Runtime.MAX_TOKEN_BYTES,"hockey_snapshot.sessionId")
        if not sessionId then return nil,err end
        local tick;tick,err=Runtime.integerInRange(payload.serverTick,0,Runtime.UINT32_MAX,"hockey_snapshot.serverTick")
        if not tick then return nil,err end
        if not require("src.breakroom_games").BAYS[payload.bayId] then return nil,"hockey_snapshot.bayId is invalid" end
        local game=payload.game
        if game~=false then
            game,err=Runtime.normalizeHockeyMatch(game)
            if not game then return nil,err end
            if game.bayId~=payload.bayId then return nil,"hockey_snapshot bay does not match" end
        end
        return {sessionId=sessionId,serverTick=tick,bayId=payload.bayId,game=game}
    end

    function Runtime.normalizeInput(payload)
        local valid, shapeError = Runtime.shape(payload, "input payload",
            { "sessionId", "sequence", "moveX", "moveY" },
            { "name", "furColorway", "overallsColorway", "taskAction", "gameX", "gameY", "combatButtons", "arcade", "boost", "commands", "commandKey" })
        if not valid then return nil, shapeError end
        if payload.name~=nil and not require('src.player_profile').validName(payload.name) then
            return nil,'input.name is invalid'
        end
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
        local boost=payload.boost
        if boost~=nil and type(boost)~='boolean' then return nil,'input.boost must be boolean' end
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
        local arcade
        if payload.arcade~=nil then
            local good,err=Runtime.shape(payload.arcade,'input.arcade',{'x','y','buttons','x2','y2','buttons2'},
                {'roundId','sequences','sequences2','suspended'})
            if not good then return nil,err end
            arcade={}
            for _,key in ipairs({'x','y','x2','y2'}) do
                arcade[key],err=Runtime.numberInRange(payload.arcade[key],-1,1,'input.arcade.'..key)
                if arcade[key]==nil then return nil,err end
            end
            for _,key in ipairs({'buttons','buttons2'}) do
                arcade[key],err=Runtime.integerInRange(payload.arcade[key],0,255,'input.arcade.'..key)
                if arcade[key]==nil then return nil,err end
            end
            if payload.arcade.roundId~=nil then
                arcade.roundId,err=Runtime.integerInRange(payload.arcade.roundId,1,Runtime.UINT32_MAX,'input.arcade.roundId')
                if not arcade.roundId then return nil,err end
                if type(payload.arcade.suspended)~='boolean' then return nil,'invalid arcade focus state' end
                arcade.suspended=payload.arcade.suspended
                for _,key in ipairs({'sequences','sequences2'}) do
                    local values=payload.arcade[key]
                    if not Runtime.Codec.isArray(values) or #values~=6 then return nil,'invalid arcade press counters' end
                    arcade[key]={}
                    for i,value in ipairs(values) do
                        arcade[key][i],err=Runtime.integerInRange(value,0,65535,'input.arcade.'..key)
                        if arcade[key][i]==nil then return nil,err end
                    end
                end
            elseif payload.arcade.sequences~=nil or payload.arcade.sequences2~=nil or payload.arcade.suspended~=nil then
                return nil,'arcade press counters require a round'
            end
        end
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
        local commands,commandKey
        if payload.commands~=nil or payload.commandKey~=nil then
            commandKey,fieldError=Runtime.token(payload.commandKey,64,'input.commandKey')
            if not commandKey then return nil,fieldError end
            if type(payload.commands)=='string' then
                local count=require('src.net.movement_commands').count(payload.commands)
                if not count or sequence<count then return nil,'Invalid packed movement command batch' end
                commands=payload.commands
            else
                if not Runtime.Codec.isArray(payload.commands) or #payload.commands<1 or #payload.commands>12
                    or sequence<#payload.commands then return nil,'Invalid movement command batch' end
                commands=Runtime.Codec.array({})
                for _,frame in ipairs(payload.commands) do
                    if not Runtime.Codec.isArray(frame) or #frame~=3
                        or not Runtime.integerInRange(frame[1],-1000,1000,'command.x')
                        or not Runtime.integerInRange(frame[2],-1000,1000,'command.y')
                        or not Runtime.integerInRange(frame[3],0,1,'command.boost') then return nil,'Invalid movement command' end
                    commands[#commands+1]=Runtime.Codec.array({frame[1],frame[2],frame[3]})
                end
            end
        end
        return { sessionId = sessionId, sequence = sequence, moveX = moveX, moveY = moveY,name=payload.name,
            commands=commands,commandKey=commandKey,
            furColorway = furColorway, overallsColorway = overallsColorway,
            taskAction = taskAction, gameX=gameX, gameY=gameY, combatButtons=combatButtons,arcade=arcade,boost=boost }
    end

    function Runtime.normalizePredictionSnapshot(payload)
        local okay,err=Runtime.shape(payload,'prediction_snapshot',
            {'sessionId','serverTick','playerId','sequence','key','mode','part','values'},{'contact'})
        if not okay then return nil,err end
        local P=require('src.commute.prediction')
        if not P.fields[payload.mode] then return nil,'Invalid physics mode' end
        local result={mode=payload.mode}
        for _,key in ipairs({'sessionId','key'}) do
            result[key],err=Runtime.token(payload[key],64,'prediction_snapshot.'..key)
            if not result[key] then return nil,err end
        end
        for _,key in ipairs({'serverTick','sequence','playerId','part'}) do
            local maximum=key=='playerId' and Runtime.Protocol.MAX_PLAYERS
                or key=='part' and math.ceil(#P.fields[payload.mode]/P.PART_VALUES) or Runtime.UINT32_MAX
            result[key],err=Runtime.integerInRange(payload[key],(key=='part' or key=='playerId') and 1 or 0,
                maximum,'prediction_snapshot.'..key)
            if not result[key] then return nil,err end
        end
        local count=math.min(P.PART_VALUES,#P.fields[payload.mode]-(result.part-1)*P.PART_VALUES)
        local values=payload.values
        if type(values)=='string' then
            values,err=require('src.net.prediction_wire').unpack(values,count)
            if not values then return nil,err end
        end
        if not Runtime.Codec.isArray(values) or #values~=count then return nil,'Invalid physics shard size' end
        result.values=Runtime.Codec.array({})
        local activeBikeContact=false
        for i,value in ipairs(values) do
            local normalized=Runtime.numberInRange(value,-1e12,1e12,'prediction_snapshot.value')
            if normalized==nil then return nil,'Invalid physics value' end
            local field=P.fields[payload.mode][(result.part-1)*P.PART_VALUES+i]
            if P.booleans[field] and value~=0 and value~=1
                or field=='gear' and (value%1~=0 or value<1 or value>4) then return nil,'Invalid physics field' end
            result.values[i]=normalized
            if payload.mode=='bike' and field=='collisionContact' then activeBikeContact=value==1 end
        end
        if payload.contact~=nil then
            if result.mode~='bike' or result.part~=1 or not activeBikeContact then
                return nil,'Contact identity requires an active bike checkpoint'
            end
            local valid,reason=Runtime.shape(payload.contact,'prediction_snapshot.contact',{'kind'},{'id'})
            if not valid then return nil,reason end
            local kind
            kind,reason=Runtime.printableString(payload.contact.kind,1,40,'prediction_snapshot.contact.kind')
            if not kind then return nil,reason end
            local id=payload.contact.id
            if id~=nil then
                if type(id)=='string' then
                    id,reason=Runtime.printableString(id,0,80,'prediction_snapshot.contact.id')
                else
                    id,reason=Runtime.numberInRange(id,-1e12,1e12,'prediction_snapshot.contact.id')
                end
                if id==nil then return nil,reason end
            end
            -- Keep exact identity and type: motorcycle contact damage compares
            -- these values, so a hash or tostring conversion changes physics.
            result.contact={kind=kind,id=id}
        end
        return result
    end

    function Runtime.normalizeSnapshot(payload)
        local valid, shapeError = Runtime.shape(payload, "snapshot payload",
            { "sessionId", "serverTick", "players" }, { "games", "balls", "bike", "truck" })
        if not valid then return nil, shapeError end
        local sessionId, fieldError = Runtime.token(payload.sessionId, Runtime.MAX_TOKEN_BYTES, "snapshot.sessionId")
        if not sessionId then return nil, fieldError end
        local serverTick
        serverTick, fieldError = Runtime.integerInRange(payload.serverTick, 0, Runtime.UINT32_MAX, "snapshot.serverTick")
        if not serverTick then return nil, fieldError end
        local ballShard=Runtime.Codec.isArray(payload.players) and #payload.players==0
            and Runtime.Codec.isArray(payload.balls) and #payload.balls==1 and payload.games==nil
        if not Runtime.Codec.isArray(payload.players) or not ballShard and
            (#payload.players<1 or #payload.players>Runtime.Protocol.MAX_PLAYERS
                or (payload.bike~=nil or payload.truck~=nil) and #payload.players~=1) then
            return nil, "snapshot.players must contain a bounded player batch or one vehicle/ball shard"
        end
        local players
        if ballShard then players=Runtime.Codec.array({}) else players,fieldError=Runtime.normalizePlayers(payload.players,"snapshot.players") end
        if not players then return nil, fieldError end
        local bike=payload.bike
        if bike~=nil then
            if Runtime.Codec.isArray(bike)then bike=require('src.net.vehicle_wire').unpack('bike',bike)end
            if not players[1] or players[1].sceneId~='commute'
                or not Runtime.shape(bike,"snapshot.bike",{"token","heading","speed","steer","brake"})
                or not Runtime.integerInRange(bike.token,1,1e12,"bike.token")
                or not Runtime.numberInRange(bike.heading,-2*math.pi,2*math.pi,"bike.heading")
                or not Runtime.numberInRange(bike.speed,0,100,"bike.speed")
                or not Runtime.numberInRange(bike.steer,-1,1,"bike.steer")
                or not Runtime.numberInRange(bike.brake,0,1,"bike.brake") then
                return nil,"snapshot.bike is invalid"
            end
        end
        local truck=payload.truck
        if truck~=nil then
            if Runtime.Codec.isArray(truck)then truck=require('src.net.vehicle_wire').unpack('truck',truck)end
            if bike or not players[1] or players[1].sceneId~='commute'
                or not Runtime.shape(truck,'snapshot.truck',
                    {'token','model','heading','speed','steer','brake','throttle','reverse','h','pitch'})
                or not Runtime.integerInRange(truck.token,1,1e12,'truck.token')
                or (truck.model~='box' and truck.model~='kei')
                or type(truck.reverse)~='boolean'
                or not Runtime.numberInRange(truck.heading,-2*math.pi,2*math.pi,'truck.heading')
                or not Runtime.numberInRange(truck.speed,0,100,'truck.speed')
                or not Runtime.numberInRange(truck.steer,-1,1,'truck.steer')
                or not Runtime.numberInRange(truck.brake,0,1,'truck.brake')
                or not Runtime.numberInRange(truck.throttle,0,1,'truck.throttle')
                or not Runtime.numberInRange(truck.h,-2,100,'truck.h')
                or not Runtime.numberInRange(truck.pitch,-1.6,1.6,'truck.pitch') then
                return nil,'snapshot.truck is invalid'
            end
        end
        local games
        if payload.games ~= nil then
            if not Runtime.Codec.isArray(payload.games) or #payload.games > 2 then
                return nil,"snapshot.games must contain at most two room matches"
            end
            games = {}
            local seen = {}
            for index, entry in ipairs(payload.games) do
                local game,err=Runtime.normalizeHockeyMatch(entry)
                if not game then return nil,err end
                if seen[entry.bayId] then return nil,"duplicate hockey bay" end
                seen[entry.bayId]=true
                games[index]=game
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
                     "leftId","rightId","contestPhase","shotStartX","shotStartY","directionX",
                     "aimX","arcHeight","releaseTime","releaseElapsed","boardHit"})
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
                    local elapsed,elapsedErr=Runtime.numberInRange(entry.shotElapsed,0,3,"snapshot.balls.shotElapsed")
                    if not elapsed then return nil,elapsedErr end
                end
                if entry.rimHit~=nil and type(entry.rimHit)~="boolean" then
                    return nil,"snapshot.balls.rimHit must be boolean"
                end
                if entry.boardHit~=nil and type(entry.boardHit)~="boolean" then
                    return nil,"snapshot.balls.boardHit must be boolean"
                end
                for _,field in ipairs({{"shotStartX",0,960},{"shotStartY",0,678},{"directionX",-960,960},
                    {"aimX",-100,100},{"arcHeight",45,190},{"releaseTime",0,1.08},{"releaseElapsed",0,2}}) do
                    if entry[field[1]]~=nil then
                        local n,nErr=Runtime.numberInRange(entry[field[1]],field[2],field[3],"snapshot.balls."..field[1])
                        if n==nil then return nil,nErr end
                    end
                end
                if entry.contestPhase~=nil and entry.contestPhase~="waiting"
                    and entry.contestPhase~="playing" and entry.contestPhase~="finished" then
                    return nil,"snapshot.balls.contestPhase is invalid"
                end
                balls[index]=entry
            end
        end
        return { sessionId = sessionId, serverTick = serverTick, players = players, bike = bike, truck = truck,
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
            { "state", "backingProgress", "cargoProgress" }, { "jobId", "mode", "sceneId" })
        if not valid then return nil, shapeError end
        if not Runtime.TRUCK_STATES[value.state] then return nil, label .. ".state is invalid" end
        local normalized = { state = value.state }
        if value.sceneId~=nil then
            if value.sceneId~="warehouse" and value.sceneId~="front_left" and value.sceneId~="front_right" then
                return nil,label..".sceneId is invalid"
            end
            if value.sceneId~="warehouse" and value.mode~="pickup" then return nil,label..".room truck must be a pickup" end
            normalized.sceneId=value.sceneId
        end
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
            { "sessionId", "serverTick", "bayDoor", "truck" },
            { "employees", "technician", "roomDoors", "deliveryDriver" })
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
        local technician
        if payload.technician~=nil then
            technician=Runtime.TechnicianPose.normalize(payload.technician)
            if not technician then return nil,"environment_snapshot.technician is inconsistent" end
        end
        local deliveryDriver
        if payload.deliveryDriver~=nil then
            deliveryDriver=Runtime.DeliveryDriverPose.normalize(payload.deliveryDriver)
            if not deliveryDriver then return nil,"environment_snapshot.deliveryDriver is inconsistent" end
        end
        local roomDoors
        if payload.roomDoors~=nil then
            local okay,errorMessage=Runtime.shape(payload.roomDoors,"roomDoors",{"front_left","front_right"})
            if not okay then return nil,errorMessage end
            roomDoors={}
            for _,id in ipairs({"front_left","front_right"}) do
                roomDoors[id],errorMessage=Runtime.normalizeBayDoor(payload.roomDoors[id],"roomDoors."..id)
                if not roomDoors[id] then return nil,errorMessage end
            end
        end
        return {sessionId=sessionId,serverTick=serverTick,bayDoor=bayDoor,
            truck=truck,employees=employees,technician=technician,roomDoors=roomDoors,
            deliveryDriver=deliveryDriver}
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
        }, { "operatorPlayerId", "carriedPalletId", "sceneId" })
        if not valid then return nil, fieldError end
        if not Runtime.Forklift.validState(payload.forklift) then return nil, "forklift_snapshot.forklift is inconsistent" end
        return { sessionId = sessionId, serverTick = tick, forklift = Runtime.Forklift.normalize(payload.forklift) }
    end
end

return Component
