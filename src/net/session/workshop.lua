-- Host interactions and workshop requests.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.Session:_processHostInteractions(context)
        local queued = self.pendingHostInteractions
        self.pendingHostInteractions = {}
        for _, item in ipairs(queued) do
            local peer, request = item.peer, item.request
            local id = self.peerToId[peer]
            local player = id and self.players[id]
            if player and id == item.playerId and request.sessionId == self.sessionId then
                local lastId = player.lastInteractionRequestId or 0
                local now = self.clock()
                local fingerprint = tostring(request.targetKind) .. ":" .. tostring(request.desiredState)
                if request.requestId == lastId and player.lastInteractionResult
                    and player.lastInteractionFingerprint ~= fingerprint
                then
                    if now - (player.lastInteractionRejectReplyAt or -math.huge)
                        >= Runtime.INTERACTION_RATE_LIMIT
                    then
                        self:_sendInteractionResult(peer, request, false, "request_id_reused",
                            "That request ID was already used for a different interaction.")
                        player.lastInteractionRejectReplyAt = now
                    end
                elseif request.requestId == lastId and player.lastInteractionResult then
                    if now - (player.lastInteractionDuplicateReplyAt or -math.huge)
                        >= Runtime.INTERACTION_RATE_LIMIT
                    then
                        self:_send(peer, "interaction_result", player.lastInteractionResult)
                        player.lastInteractionDuplicateReplyAt = now
                    end
                elseif request.requestId < lastId then
                    if now - (player.lastInteractionRejectReplyAt or -math.huge)
                        >= Runtime.INTERACTION_RATE_LIMIT
                    then
                        self:_sendInteractionResult(peer, request, false, "stale_request",
                            "That interaction request is stale.")
                        player.lastInteractionRejectReplyAt = now
                    end
                else
                    local accepted, code, message = false, "unavailable",
                        "The host cannot process that interaction right now."
                    if now - (player.lastInteractionAt or -math.huge) < Runtime.INTERACTION_RATE_LIMIT then
                        code = "rate_limited"
                        message = "Please wait a moment before using the switch again."
                    elseif context and type(context.performInteraction) == "function" then
                        local called, result, resultCode, resultMessage = pcall(
                            context.performInteraction, player, request.targetKind,
                            request.desiredState)
                        if called then
                            accepted = result == true
                            code = tostring(resultCode or (accepted and "accepted" or "rejected"))
                            message = tostring(resultMessage or (accepted
                                and "The host accepted the interaction."
                                or "The host rejected the interaction."))
                        else
                            code = "internal_error"
                            message = "The host could not complete that interaction."
                        end
                    end
                    player.lastInteractionRequestId = request.requestId
                    player.lastInteractionFingerprint = fingerprint
                    player.lastInteractionAt = now
                    player.lastInteractionResult = {
                        sessionId = self.sessionId,
                        requestId = request.requestId,
                        targetKind = request.targetKind,
                        accepted = accepted,
                        code = code,
                        message = message,
                    }
                    local shouldReply = code ~= "rate_limited"
                        or now - (player.lastInteractionRejectReplyAt or -math.huge)
                            >= Runtime.INTERACTION_RATE_LIMIT
                    if shouldReply then
                        local ok, sendError = self:_send(peer, "interaction_result",
                            player.lastInteractionResult)
                        if code == "rate_limited" then player.lastInteractionRejectReplyAt = now end
                        if not ok then self:_queue("error", { message = sendError }) end
                    end
                end
            end
        end
    end

    function Runtime.Session:_processHostWorkshop(context)
        local queued = self.pendingHostWorkshop
        self.pendingHostWorkshop = {}
        local ordered = {}
        for _, item in ipairs(queued) do
            local payload = item.payload
            if item.operation == "workshop_command"
                and Runtime.urgentWorkshopSafety(payload.resourceId, payload.action, payload)
            then
                ordered[#ordered + 1] = item
            end
        end
        for _, item in ipairs(queued) do
            local payload = item.payload
            if item.operation ~= "workshop_command"
                or not Runtime.urgentWorkshopSafety(payload.resourceId, payload.action, payload)
            then
                ordered[#ordered + 1] = item
            end
        end
        for _, item in ipairs(ordered) do
            local peer, payload = item.peer, item.payload
            local id = self.peerToId[peer]
            local player = id and self.players[id]
            if player and id == item.playerId and payload.sessionId == self.sessionId then
                local result
                if context and type(context.performWorkshop) == "function" then
                    local called, value = pcall(context.performWorkshop,
                        player, item.operation, payload)
                    if called and type(value) == "table" then result = value end
                end
                result = result or {
                    accepted = false,
                    code = "internal_error",
                    message = "The host could not complete that workshop request.",
                    revision = 0,
                }
                if item.operation == "workshop_acquire" then
                    local response = {
                        sessionId = self.sessionId,
                        requestId = payload.requestId,
                        resourceId = payload.resourceId,
                        granted = result.accepted == true,
                        code = tostring(result.code or "rejected"),
                        message = tostring(result.message or "The workshop request was rejected."),
                        revision = math.max(0, math.floor(tonumber(result.revision) or 0)),
                    }
                    if response.granted then response.leaseId = result.leaseId end
                    if result.data ~= nil then
                        response.view = Runtime.wireWorkshopView(payload.resourceId, result.data)
                    end
                    local ok, sendError = self:_send(peer, "workshop_grant", response)
                    if not ok then self:_queue("error", { message = sendError }) end
                elseif item.operation == "workshop_command" then
                    local response = {
                        sessionId = self.sessionId,
                        commandId = payload.commandId,
                        resourceId = payload.resourceId,
                        action = payload.action,
                        accepted = result.accepted == true,
                        code = tostring(result.code or "rejected"),
                        message = tostring(result.message or "The workshop action was rejected."),
                        revision = math.max(0, math.floor(tonumber(result.revision) or 0)),
                    }
                    if result.data ~= nil then
                        response.view = Runtime.wireWorkshopView(payload.resourceId, result.data)
                    end
                    local ok, sendError = self:_send(peer, "workshop_result", response)
                    if not ok then self:_queue("error", { message = sendError }) end
                elseif item.operation == "workshop_release" and result.accepted ~= true then
                    self:_sendError(peer, tostring(result.code or "release_failed"),
                        tostring(result.message or "Workshop control could not be released cleanly."))
                end
            end
        end
    end
end

return Component
