-- Door, radio-adjacent, and high-five message validation.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    Runtime.NETWORK_INTERACTION_KINDS = {
        loadingBayDoor = true,
        truckCargoDoor = true,
        shopRoom = true, roomStock = true, roomRest = true, roomGame = true,
    }

    Runtime.INTERACTION_DOOR_STATES = {
        closed = true,
        open = true,
    }

    function Runtime.interactionKind(value, label)
        if type(value) ~= "string" or not Runtime.NETWORK_INTERACTION_KINDS[value] then
            return nil, label .. " is not allowed"
        end
        return value
    end

    function Runtime.normalizeInteractionRequest(payload)
        local valid, shapeError = Runtime.shape(payload, "interaction_request payload",
            { "sessionId", "requestId", "targetKind", "desiredState" })
        if not valid then return nil, shapeError end
        local sessionId, fieldError = Runtime.token(
            payload.sessionId, Runtime.MAX_TOKEN_BYTES, "interaction_request.sessionId")
        if not sessionId then return nil, fieldError end
        local requestId
        requestId, fieldError = Runtime.integerInRange(
            payload.requestId, 1, Runtime.UINT32_MAX, "interaction_request.requestId")
        if not requestId then return nil, fieldError end
        local targetKind
        targetKind, fieldError = Runtime.interactionKind(
            payload.targetKind, "interaction_request.targetKind")
        if not targetKind then return nil, fieldError end
        local roomCommand = targetKind=="shopRoom" and require("src.shop_rooms").IDS[payload.desiredState]
            or targetKind=="roomRest" and (payload.desiredState=="rest" or payload.desiredState=="stand")
            or targetKind=="roomStock" and type(payload.desiredState)=="string" and #payload.desiredState<=150
                and (payload.desiredState:match("^store:[%w_.%-]+$") or payload.desiredState:match("^retrieve:[%w_.%-]+$"))
            or targetKind=="roomGame" and type(payload.desiredState)=="string"
                and (payload.desiredState=="air_hockey:start_solo"
                    or payload.desiredState=="air_hockey:start_versus"
                    or payload.desiredState=="air_hockey:join"
                    or payload.desiredState=="air_hockey:leave"
                    or payload.desiredState=="critter_kombat:start_solo"
                    or payload.desiredState=="critter_kombat:start_versus"
                    or payload.desiredState=="critter_kombat:join"
                    or payload.desiredState=="critter_kombat:leave"
                    or payload.desiredState=="basketball:pickup"
                    or payload.desiredState=="basketball:drop"
                    or payload.desiredState=="basketball:shot_start"
                    or payload.desiredState=="basketball:shot_release"
                    or payload.desiredState=="basketball:contest"
                    or payload.desiredState=="basketball:join"
                    or payload.desiredState=="basketball:end")
        if type(payload.desiredState) ~= "string"
            or not roomCommand and not ((targetKind=="loadingBayDoor" or targetKind=="truckCargoDoor")
                and Runtime.INTERACTION_DOOR_STATES[payload.desiredState])
        then
            return nil, "interaction_request.desiredState is invalid"
        end
        return {
            sessionId = sessionId,
            requestId = requestId,
            targetKind = targetKind,
            desiredState = payload.desiredState,
        }
    end

    function Runtime.normalizeInteractionResult(payload)
        local valid, shapeError = Runtime.shape(payload, "interaction_result payload",
            { "sessionId", "requestId", "targetKind", "accepted", "code", "message" })
        if not valid then return nil, shapeError end
        local sessionId, fieldError = Runtime.token(
            payload.sessionId, Runtime.MAX_TOKEN_BYTES, "interaction_result.sessionId")
        if not sessionId then return nil, fieldError end
        local requestId
        requestId, fieldError = Runtime.integerInRange(
            payload.requestId, 1, Runtime.UINT32_MAX, "interaction_result.requestId")
        if not requestId then return nil, fieldError end
        local targetKind
        targetKind, fieldError = Runtime.interactionKind(
            payload.targetKind, "interaction_result.targetKind")
        if not targetKind then return nil, fieldError end
        if type(payload.accepted) ~= "boolean" then
            return nil, "interaction_result.accepted must be boolean"
        end
        local code
        code, fieldError = Runtime.token(payload.code, Runtime.MAX_ERROR_CODE_BYTES, "interaction_result.code")
        if not code then return nil, fieldError end
        local message
        message, fieldError = Runtime.printableString(
            payload.message, 1, Runtime.MAX_ERROR_MESSAGE_BYTES, "interaction_result.message")
        if not message then return nil, fieldError end
        return {
            sessionId = sessionId,
            requestId = requestId,
            targetKind = targetKind,
            accepted = payload.accepted,
            code = code,
            message = message,
        }
    end

    function Runtime.normalizeHighFiveRequest(payload)
        local valid, shapeError = Runtime.shape(payload, "highfive_request payload",
            { "sessionId", "requestId", "targetId" })
        if not valid then return nil, shapeError end
        local sessionId, fieldError = Runtime.token(
            payload.sessionId, Runtime.MAX_TOKEN_BYTES, "highfive_request.sessionId")
        if not sessionId then return nil, fieldError end
        local requestId
        requestId, fieldError = Runtime.integerInRange(
            payload.requestId, 1, Runtime.UINT32_MAX, "highfive_request.requestId")
        if not requestId then return nil, fieldError end
        local targetId
        targetId, fieldError = Runtime.integerInRange(
            payload.targetId, 1, Runtime.Protocol.MAX_PLAYERS, "highfive_request.targetId")
        if not targetId then return nil, fieldError end
        return { sessionId = sessionId, requestId = requestId, targetId = targetId }
    end

    function Runtime.normalizeHighFiveOffer(payload)
        local valid, shapeError = Runtime.shape(payload, "highfive_offer payload",
            { "sessionId", "requestId", "initiatorId", "receiverId", "expiresMs" })
        if not valid then return nil, shapeError end
        local sessionId, fieldError = Runtime.token(
            payload.sessionId, Runtime.MAX_TOKEN_BYTES, "highfive_offer.sessionId")
        if not sessionId then return nil, fieldError end
        local normalized = { sessionId = sessionId }
        for _, field in ipairs({ "requestId", "initiatorId", "receiverId" }) do
            normalized[field], fieldError = Runtime.integerInRange(
                payload[field], 1, field == "requestId" and Runtime.UINT32_MAX or Runtime.Protocol.MAX_PLAYERS,
                "highfive_offer." .. field)
            if not normalized[field] then return nil, fieldError end
        end
        normalized.expiresMs, fieldError = Runtime.integerInRange(
            payload.expiresMs, 1000, 15000, "highfive_offer.expiresMs")
        if not normalized.expiresMs then return nil, fieldError end
        if normalized.initiatorId == normalized.receiverId then
            return nil, "highfive_offer participants must be different"
        end
        return normalized
    end

    function Runtime.normalizeHighFiveResponse(payload)
        local valid, shapeError = Runtime.shape(payload, "highfive_response payload",
            { "sessionId", "requestId", "accepted" })
        if not valid then return nil, shapeError end
        local sessionId, fieldError = Runtime.token(
            payload.sessionId, Runtime.MAX_TOKEN_BYTES, "highfive_response.sessionId")
        if not sessionId then return nil, fieldError end
        local requestId
        requestId, fieldError = Runtime.integerInRange(
            payload.requestId, 1, Runtime.UINT32_MAX, "highfive_response.requestId")
        if not requestId then return nil, fieldError end
        if type(payload.accepted) ~= "boolean" then
            return nil, "highfive_response.accepted must be boolean"
        end
        return { sessionId = sessionId, requestId = requestId, accepted = payload.accepted }
    end

    function Runtime.normalizeHighFiveRequestResult(payload)
        local valid, shapeError = Runtime.shape(payload, "highfive_request_result payload",
            { "sessionId", "clientRequestId", "accepted", "code", "message" }, { "requestId" })
        if not valid then return nil, shapeError end
        local sessionId, fieldError = Runtime.token(
            payload.sessionId, Runtime.MAX_TOKEN_BYTES, "highfive_request_result.sessionId")
        if not sessionId then return nil, fieldError end
        local clientRequestId
        clientRequestId, fieldError = Runtime.integerInRange(
            payload.clientRequestId, 1, Runtime.UINT32_MAX, "highfive_request_result.clientRequestId")
        if not clientRequestId then return nil, fieldError end
        local accepted = payload.accepted
        if type(accepted) ~= "boolean" then
            return nil, "highfive_request_result.accepted must be boolean"
        end
        local code
        code, fieldError = Runtime.token(payload.code, Runtime.MAX_ERROR_CODE_BYTES, "highfive_request_result.code")
        if not code then return nil, fieldError end
        local message
        message, fieldError = Runtime.printableString(
            payload.message, 1, Runtime.MAX_ERROR_MESSAGE_BYTES, "highfive_request_result.message")
        if not message then return nil, fieldError end
        local normalized = {
            sessionId = sessionId, clientRequestId = clientRequestId,
            accepted = accepted, code = code, message = message,
        }
        if payload.requestId ~= nil then
            normalized.requestId, fieldError = Runtime.integerInRange(
                payload.requestId, 1, Runtime.UINT32_MAX, "highfive_request_result.requestId")
            if not normalized.requestId then return nil, fieldError end
        end
        return normalized
    end

    Runtime.HIGH_FIVE_RESULT_STATES = {
        accepted = true, declined = true, expired = true, cancelled = true,
    }

    function Runtime.normalizeHighFiveResult(payload)
        local valid, shapeError = Runtime.shape(payload, "highfive_result payload",
            { "sessionId", "requestId", "initiatorId", "receiverId", "status", "message" })
        if not valid then return nil, shapeError end
        local sessionId, fieldError = Runtime.token(
            payload.sessionId, Runtime.MAX_TOKEN_BYTES, "highfive_result.sessionId")
        if not sessionId then return nil, fieldError end
        local normalized = { sessionId = sessionId }
        for _, field in ipairs({ "requestId", "initiatorId", "receiverId" }) do
            normalized[field], fieldError = Runtime.integerInRange(
                payload[field], 1, field == "requestId" and Runtime.UINT32_MAX or Runtime.Protocol.MAX_PLAYERS,
                "highfive_result." .. field)
            if not normalized[field] then return nil, fieldError end
        end
        if not Runtime.HIGH_FIVE_RESULT_STATES[payload.status] then
            return nil, "highfive_result.status is invalid"
        end
        normalized.status = payload.status
        normalized.message, fieldError = Runtime.printableString(
            payload.message, 1, Runtime.MAX_ERROR_MESSAGE_BYTES, "highfive_result.message")
        if not normalized.message then return nil, fieldError end
        return normalized
    end

    function Runtime.normalizeHighFiveStart(payload)
        local valid, shapeError = Runtime.shape(payload, "highfive_start payload",
            { "sessionId", "requestId", "initiatorId", "receiverId", "startDelayMs" })
        if not valid then return nil, shapeError end
        local sessionId, fieldError = Runtime.token(
            payload.sessionId, Runtime.MAX_TOKEN_BYTES, "highfive_start.sessionId")
        if not sessionId then return nil, fieldError end
        local normalized = { sessionId = sessionId }
        for _, field in ipairs({ "requestId", "initiatorId", "receiverId" }) do
            normalized[field], fieldError = Runtime.integerInRange(
                payload[field], 1, field == "requestId" and Runtime.UINT32_MAX or Runtime.Protocol.MAX_PLAYERS,
                "highfive_start." .. field)
            if not normalized[field] then return nil, fieldError end
        end
        if normalized.initiatorId == normalized.receiverId then
            return nil, "highfive_start participants must be different"
        end
        normalized.startDelayMs, fieldError = Runtime.integerInRange(
            payload.startDelayMs, 0, 1000, "highfive_start.startDelayMs")
        if not normalized.startDelayMs then return nil, fieldError end
        return normalized
    end
end

return Component
