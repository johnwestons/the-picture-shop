-- Primitive field, player, and handshake validation.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.protocolError(message)
        return nil, "protocol: " .. message
    end

    function Runtime.shape(value, label, required, optional)
        if type(value) ~= "table" then return nil, label .. " must be a table" end
        local allowed = {}
        for _, name in ipairs(required) do allowed[name] = true end
        for _, name in ipairs(optional or {}) do allowed[name] = true end
        for key in next, value do
            if type(key) ~= "string" or not allowed[key] then
                return nil, label .. " has unknown field: " .. tostring(key)
            end
        end
        for _, name in ipairs(required) do
            if value[name] == nil then return nil, label .. " is missing field: " .. name end
        end
        return true
    end

    function Runtime.integerInRange(value, minimum, maximum, label)
        if type(value) ~= "number" or value ~= math.floor(value)
            or value < minimum or value > maximum
        then
            return nil, label .. " is out of range"
        end
        return value
    end

    function Runtime.numberInRange(value, minimum, maximum, label)
        if type(value) ~= "number" or value ~= value
            or value == math.huge or value == -math.huge
            or value < minimum or value > maximum
        then
            return nil, label .. " is out of range"
        end
        return value
    end

    function Runtime.printableString(value, minimumBytes, maximumBytes, label)
        if type(value) ~= "string" or #value < minimumBytes or #value > maximumBytes then
            return nil, label .. " has invalid length"
        end
        for index = 1, #value do
            local byte = value:byte(index)
            if byte < 32 or byte == 127 then return nil, label .. " contains control bytes" end
        end
        return value
    end

    function Runtime.token(value, maximumBytes, label)
        local valid, stringError = Runtime.printableString(value, 1, maximumBytes, label)
        if not valid then return nil, stringError end
        if not value:match("^[A-Za-z0-9][A-Za-z0-9_.%-]*$") then
            return nil, label .. " contains unsupported characters"
        end
        return value
    end

    function Runtime.characterToken(value, label)
        local valid, stringError = Runtime.printableString(value, 1, Runtime.MAX_CHARACTER_BYTES, label)
        if not valid then return nil, stringError end
        if not value:match("^[a-z0-9][a-z0-9_%-]*$") then
            return nil, label .. " contains unsupported characters"
        end
        return value
    end

    Runtime.PLAYER_FIELDS = {
        "id", "name", "x", "y", "velocityX", "velocityY", "intentX", "intentY",
        "moving", "facing", "animationDistance", "character", "inputSequence",
    }

    function Runtime.normalizePlayer(value, label)
        local valid, shapeError = Runtime.shape(value, label, Runtime.PLAYER_FIELDS,
            { "furColorway", "overallsColorway", "sceneId", "resting" })
        if not valid then return nil, shapeError end
        if value.sceneId~=nil and not require("src.shop_rooms").IDS[value.sceneId] then
            return nil,label..".sceneId is invalid"
        end
        if value.resting~=nil and type(value.resting)~="boolean" then return nil,label..".resting is invalid" end
        local id, fieldError = Runtime.integerInRange(value.id, 1, Runtime.Protocol.MAX_PLAYERS, label .. ".id")
        if not id then return nil, fieldError end
        local name
        name, fieldError = Runtime.printableString(value.name, 1, Runtime.Protocol.MAX_NAME_BYTES, label .. ".name")
        if not name then return nil, fieldError end
        local x
        x, fieldError = Runtime.numberInRange(value.x, -Runtime.MAX_COORDINATE, Runtime.MAX_COORDINATE, label .. ".x")
        if not x then return nil, fieldError end
        local y
        y, fieldError = Runtime.numberInRange(value.y, -Runtime.MAX_COORDINATE, Runtime.MAX_COORDINATE, label .. ".y")
        if not y then return nil, fieldError end
        local velocityX
        velocityX, fieldError = Runtime.numberInRange(
            value.velocityX, -Runtime.MAX_VELOCITY, Runtime.MAX_VELOCITY, label .. ".velocityX")
        if not velocityX then return nil, fieldError end
        local velocityY
        velocityY, fieldError = Runtime.numberInRange(
            value.velocityY, -Runtime.MAX_VELOCITY, Runtime.MAX_VELOCITY, label .. ".velocityY")
        if not velocityY then return nil, fieldError end
        local intentX
        intentX, fieldError = Runtime.numberInRange(value.intentX, -1, 1, label .. ".intentX")
        if not intentX then return nil, fieldError end
        local intentY
        intentY, fieldError = Runtime.numberInRange(value.intentY, -1, 1, label .. ".intentY")
        if not intentY then return nil, fieldError end
        if type(value.moving) ~= "boolean" then return nil, label .. ".moving must be boolean" end
        if value.facing ~= -1 and value.facing ~= 1 then return nil, label .. ".facing must be -1 or 1" end
        local animationDistance
        animationDistance, fieldError = Runtime.numberInRange(
            value.animationDistance, 0, Runtime.MAX_ANIMATION_DISTANCE, label .. ".animationDistance")
        if not animationDistance then return nil, fieldError end
        local character
        character, fieldError = Runtime.characterToken(value.character, label .. ".character")
        if not character then return nil, fieldError end
        local furColorway = value.furColorway
        if furColorway == nil then furColorway = 1 end
        furColorway, fieldError = Runtime.integerInRange(furColorway, 1, Runtime.RabbitColorways.count("fur"),
            label .. ".furColorway")
        if not furColorway then return nil, fieldError end
        local overallsColorway = value.overallsColorway
        if overallsColorway == nil then overallsColorway = 1 end
        overallsColorway, fieldError = Runtime.integerInRange(overallsColorway, 1, Runtime.RabbitColorways.count("overalls"),
            label .. ".overallsColorway")
        if not overallsColorway then return nil, fieldError end
        local inputSequence
        inputSequence, fieldError = Runtime.integerInRange(
            value.inputSequence, 0, Runtime.UINT32_MAX, label .. ".inputSequence")
        if not inputSequence then return nil, fieldError end

        return {
            id = id,
            name = name,
            sceneId = value.sceneId or "warehouse",
            resting = value.resting==true,
            x = x,
            y = y,
            velocityX = velocityX,
            velocityY = velocityY,
            intentX = intentX,
            intentY = intentY,
            moving = value.moving,
            facing = value.facing,
            animationDistance = animationDistance,
            character = character,
            furColorway = furColorway,
            overallsColorway = overallsColorway,
            inputSequence = inputSequence,
        }
    end

    function Runtime.normalizePlayers(value, label)
        if not Runtime.Codec.isArray(value) then return nil, label .. " must be an array" end
        if #value < 1 or #value > Runtime.Protocol.MAX_PLAYERS then
            return nil, label .. " must contain between 1 and " .. Runtime.Protocol.MAX_PLAYERS .. " players"
        end
        local players, seen = {}, {}
        for index = 1, #value do
            local player, playerError = Runtime.normalizePlayer(value[index], label .. "[" .. index .. "]")
            if not player then return nil, playerError end
            if seen[player.id] then return nil, label .. " contains a duplicate player id" end
            seen[player.id] = true
            players[#players + 1] = player
        end
        table.sort(players, function(a, b) return a.id < b.id end)
        return Runtime.Codec.array(players)
    end

    function Runtime.normalizeHello(payload)
        local valid, shapeError = Runtime.shape(payload, "hello payload",
            { "clientNonce", "name", "character" }, { "furColorway", "overallsColorway" })
        if not valid then return nil, shapeError end
        local clientNonce, fieldError = Runtime.token(payload.clientNonce, Runtime.MAX_TOKEN_BYTES, "hello.clientNonce")
        if not clientNonce then return nil, fieldError end
        local name
        name, fieldError = Runtime.printableString(payload.name, 1, Runtime.Protocol.MAX_NAME_BYTES, "hello.name")
        if not name then return nil, fieldError end
        local character
        character, fieldError = Runtime.characterToken(payload.character, "hello.character")
        if not character then return nil, fieldError end
        local furColorway = payload.furColorway
        if furColorway == nil then furColorway = 1 end
        furColorway, fieldError = Runtime.integerInRange(furColorway, 1, Runtime.RabbitColorways.count("fur"),
            "hello.furColorway")
        if not furColorway then return nil, fieldError end
        local overallsColorway = payload.overallsColorway
        if overallsColorway == nil then overallsColorway = 1 end
        overallsColorway, fieldError = Runtime.integerInRange(overallsColorway, 1, Runtime.RabbitColorways.count("overalls"),
            "hello.overallsColorway")
        if not overallsColorway then return nil, fieldError end
        return { clientNonce = clientNonce, name = name, character = character,
            furColorway = furColorway, overallsColorway = overallsColorway }
    end

    function Runtime.normalizeWelcome(payload)
        local valid, shapeError = Runtime.shape(payload, "welcome payload",
            { "sessionId", "playerId", "serverTick", "players" })
        if not valid then return nil, shapeError end
        local sessionId, fieldError = Runtime.token(payload.sessionId, Runtime.MAX_TOKEN_BYTES, "welcome.sessionId")
        if not sessionId then return nil, fieldError end
        local playerId
        playerId, fieldError = Runtime.integerInRange(
            payload.playerId, 1, Runtime.Protocol.MAX_PLAYERS, "welcome.playerId")
        if not playerId then return nil, fieldError end
        local serverTick
        serverTick, fieldError = Runtime.integerInRange(payload.serverTick, 0, Runtime.UINT32_MAX, "welcome.serverTick")
        if not serverTick then return nil, fieldError end
        local players
        players, fieldError = Runtime.normalizePlayers(payload.players, "welcome.players")
        if not players then return nil, fieldError end
        local assignedPresent = false
        for _, player in ipairs(players) do
            if player.id == playerId then assignedPresent = true; break end
        end
        if not assignedPresent then return nil, "welcome.playerId is absent from welcome.players" end
        return {
            sessionId = sessionId,
            playerId = playerId,
            serverTick = serverTick,
            players = players,
        }
    end

    function Runtime.normalizeShopSnapshot(payload)
        local valid, shapeError = Runtime.shape(payload, "shop_snapshot payload",
            { "sessionId", "revision", "state", "player" })
        if not valid then return nil, shapeError end
        local sessionId, fieldError = Runtime.token(
            payload.sessionId, Runtime.MAX_TOKEN_BYTES, "shop_snapshot.sessionId")
        if not sessionId then return nil, fieldError end
        local revision
        revision, fieldError = Runtime.integerInRange(
            payload.revision, 0, Runtime.UINT32_MAX, "shop_snapshot.revision")
        if not revision then return nil, fieldError end
        if type(payload.state) ~= "table" then return nil, "shop_snapshot.state must be a table" end
        if type(payload.player) ~= "table" then return nil, "shop_snapshot.player must be a table" end
        return {
            sessionId = sessionId,
            revision = revision,
            state = payload.state,
            player = payload.player,
        }
    end

    function Runtime.normalizeShopState(payload)
        local valid, shapeError = Runtime.shape(payload, "shop_state payload",
            { "sessionId", "revision", "state" })
        if not valid then return nil, shapeError end
        local sessionId, fieldError = Runtime.token(
            payload.sessionId, Runtime.MAX_TOKEN_BYTES, "shop_state.sessionId")
        if not sessionId then return nil, fieldError end
        local revision
        revision, fieldError = Runtime.integerInRange(
            payload.revision, 1, Runtime.UINT32_MAX, "shop_state.revision")
        if not revision then return nil, fieldError end
        if type(payload.state) ~= "table" then return nil, "shop_state.state must be a table" end
        return { sessionId = sessionId, revision = revision, state = payload.state }
    end

    function Runtime.normalizeRadioState(payload)
        local valid, shapeError = Runtime.shape(payload, "radio_state payload",
            { "sessionId", "revision", "trackIndex", "active", "paused", "muted", "positionMs" })
        if not valid then return nil, shapeError end
        local sessionId, fieldError = Runtime.token(payload.sessionId, Runtime.MAX_TOKEN_BYTES, "radio_state.sessionId")
        if not sessionId then return nil, fieldError end
        local revision
        revision, fieldError = Runtime.integerInRange(payload.revision, 0, Runtime.UINT32_MAX, "radio_state.revision")
        if not revision then return nil, fieldError end
        local trackIndex
        trackIndex, fieldError = Runtime.integerInRange(payload.trackIndex, 1, 9, "radio_state.trackIndex")
        if not trackIndex then return nil, fieldError end
        if type(payload.active) ~= "boolean" then return nil, "radio_state.active must be boolean" end
        if type(payload.paused) ~= "boolean" then return nil, "radio_state.paused must be boolean" end
        if type(payload.muted) ~= "boolean" then return nil, "radio_state.muted must be boolean" end
        local positionMs
        positionMs, fieldError = Runtime.integerInRange(payload.positionMs, 0, 3600000, "radio_state.positionMs")
        if not positionMs then return nil, fieldError end
        return {
            sessionId = sessionId,
            revision = revision,
            trackIndex = trackIndex,
            active = payload.active,
            paused = payload.paused,
            muted = payload.muted,
            positionMs = positionMs,
        }
    end
end

return Component
