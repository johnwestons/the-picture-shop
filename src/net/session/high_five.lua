-- High-five requests, offers, cooldowns, and animation coordination.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.Session:_setHighFiveNotice(message)
        local now = self.clock()
        if not Runtime.finite(now) then return end
        self.highFiveNotice = {
            message = tostring(message or "High-five update."),
            expiresAt = now + Runtime.HIGH_FIVE_NOTICE_SECONDS,
        }
    end

    function Runtime.Session:_highFivePlayerBusy(playerId, now)
        for _, pending in pairs(self.pendingHighFives) do
            if pending.initiatorId == playerId or pending.receiverId == playerId then
                return true
            end
        end
        for _, active in pairs(self.activeHighFives) do
            if active.endsAt > now
                and (active.initiatorId == playerId or active.receiverId == playerId)
            then
                return true
            end
        end
        return false
    end

    function Runtime.Session:_nextHighFiveId()
        self.nextHighFiveRequestId = self.nextHighFiveRequestId % 4294967295 + 1
        return self.nextHighFiveRequestId
    end

    function Runtime.Session:_replyHighFiveRequest(peer, clientRequestId, accepted, code, message, requestId)
        return self:_send(peer, "highfive_request_result", {
            sessionId = self.sessionId,
            clientRequestId = clientRequestId,
            requestId = requestId,
            accepted = accepted == true,
            code = tostring(code or "rejected"),
            message = tostring(message or "That high-five request could not be sent."),
        })
    end

    function Runtime.Session:_createHighFive(initiatorId, receiverId, sourcePeer, clientRequestId)
        local now = self.clock()
        local function reject(code, message)
            if sourcePeer and clientRequestId then
                self:_replyHighFiveRequest(sourcePeer, clientRequestId, false, code, message)
            elseif initiatorId == self.localId then
                self:_setHighFiveNotice(message)
            end
            return false, message
        end
        if not Runtime.finite(now) or not self.ready or not self.sessionId then
            return reject("not_ready", "The high-five could not be sent right now.")
        end
        local initiator = self.players[initiatorId]
        local receiver = self.players[receiverId]
        if not initiator or not receiver or initiatorId == receiverId then
            return reject("player_unavailable", "That player is no longer available.")
        end
        if now - (initiator.lastHighFiveAttemptAt or -math.huge) < 0.35 then
            return reject("rate_limited", "Wait a moment before trying again.")
        end
        initiator.lastHighFiveAttemptAt = now
        local dx, dy = initiator.x - receiver.x, initiator.y - receiver.y
        if dx * dx + dy * dy > Runtime.HIGH_FIVE_RANGE * Runtime.HIGH_FIVE_RANGE then
            return reject("too_far", "Move closer before asking for a high five.")
        end
        if self:_highFivePlayerBusy(initiatorId, now)
            or self:_highFivePlayerBusy(receiverId, now)
        then
            return reject("busy", "One of you is already handling a high-five request.")
        end
        if now - (initiator.lastHighFiveAt or -math.huge) < Runtime.HIGH_FIVE_COOLDOWN then
            return reject("cooldown", "Give it a moment before sending another high five.")
        end

        local requestId = self:_nextHighFiveId()
        local pending = {
            requestId = requestId,
            initiatorId = initiatorId,
            receiverId = receiverId,
            createdAt = now,
            expiresAt = now + Runtime.HIGH_FIVE_OFFER_SECONDS,
        }
        self.pendingHighFives[requestId] = pending
        self.highFiveOffers[requestId] = nil

        local offer = {
            sessionId = self.sessionId,
            requestId = requestId,
            initiatorId = initiatorId,
            receiverId = receiverId,
            expiresMs = Runtime.HIGH_FIVE_OFFER_SECONDS * 1000,
        }
        if receiverId == self.localId then
            self.highFiveOffers[requestId] = {
                requestId = requestId,
                initiatorId = initiatorId,
                receiverId = receiverId,
                initiatorName = tostring(initiator.name or "Worker"),
                expiresAt = pending.expiresAt,
            }
        else
            local peer = self.idToPeer[receiverId]
            local sent, sendError
            if peer then sent, sendError = self:_send(peer, "highfive_offer", offer) end
            if not sent then
                self.pendingHighFives[requestId] = nil
                self.highFiveOffers[requestId] = nil
                if sourcePeer and clientRequestId then
                    self:_replyHighFiveRequest(sourcePeer, clientRequestId, false, "send_failed",
                        "The other player could not be reached.")
                elseif initiatorId == self.localId then
                    self:_setHighFiveNotice("The other player could not be reached.")
                end
                if not peer and sendError then self:_queue("error", { message = tostring(sendError) }) end
                return false, "The other player could not be reached."
            end
        end
        initiator.lastHighFiveAt = now
        if sourcePeer and clientRequestId then
            self:_replyHighFiveRequest(sourcePeer, clientRequestId, true, "offered",
                "High-five request sent.", requestId)
        elseif initiatorId == self.localId then
            self:_setHighFiveNotice("High-five request sent to " .. tostring(receiver.name or "Worker") .. ".")
        end
        return true, requestId
    end

    function Runtime.Session:_resolveHighFive(requestId, receiverId, accepted)
        local pending = self.pendingHighFives[requestId]
        if not pending or pending.receiverId ~= receiverId then return false end
        local now = self.clock()
        local status, message
        if not Runtime.finite(now) or now > pending.expiresAt then
            status, message = "expired", "The high-five request expired."
        elseif accepted == true then
            local initiator, receiver = self.players[pending.initiatorId], self.players[pending.receiverId]
            local dx = initiator and receiver and (initiator.x - receiver.x) or math.huge
            local dy = initiator and receiver and (initiator.y - receiver.y) or math.huge
            if not initiator or not receiver then
                status, message = "cancelled", "The other player left before the high five."
            elseif dx * dx + dy * dy > Runtime.HIGH_FIVE_RANGE * Runtime.HIGH_FIVE_RANGE then
                status, message = "cancelled", "Move closer to finish the high five."
            else
                status, message = "accepted", tostring(receiver.name or "Worker") .. " accepted the high five!"
            end
        else
            status, message = "declined", tostring(self.players[receiverId]
                and self.players[receiverId].name or "Worker") .. " declined the high five."
        end
        self.pendingHighFives[requestId] = nil
        self.highFiveOffers[requestId] = nil
        local result = {
            sessionId = self.sessionId,
            requestId = requestId,
            initiatorId = pending.initiatorId,
            receiverId = pending.receiverId,
            status = status,
            message = message,
        }
        if pending.initiatorId == self.localId then
            self:_setHighFiveNotice(message)
        else
            local peer = self.idToPeer[pending.initiatorId]
            if peer then
                local sent, sendError = self:_send(peer, "highfive_result", result)
                if not sent then self:_queue("error", { message = tostring(sendError) }) end
            end
        end
        if status == "accepted" then
            local active = {
                requestId = requestId,
                initiatorId = pending.initiatorId,
                receiverId = pending.receiverId,
                startedAt = now + Runtime.HIGH_FIVE_START_DELAY,
                endsAt = now + Runtime.HIGH_FIVE_START_DELAY + Runtime.HIGH_FIVE_ANIMATION_SECONDS,
            }
            self.activeHighFives[requestId] = active
            local sent, sendError = self:_broadcastJoined("highfive_start", {
                sessionId = self.sessionId,
                requestId = requestId,
                initiatorId = pending.initiatorId,
                receiverId = pending.receiverId,
                startDelayMs = math.floor(Runtime.HIGH_FIVE_START_DELAY * 1000 + 0.5),
            })
            if not sent then self:_queue("error", { message = tostring(sendError) }) end
        end
        return true, status
    end

    function Runtime.Session:_processHostHighFives()
        local requests = self.pendingHostHighFiveRequests
        self.pendingHostHighFiveRequests = {}
        for _, item in ipairs(requests) do
            local playerId = self.peerToId[item.peer]
            if playerId and playerId == item.playerId
                and item.payload.sessionId == self.sessionId
            then
                local player = self.players[playerId]
                if item.payload.requestId <= (player.lastHighFiveClientRequestId or 0) then
                    self:_replyHighFiveRequest(item.peer, item.payload.requestId, false,
                        "stale_request", "That high-five request is out of date.")
                else
                    player.lastHighFiveClientRequestId = item.payload.requestId
                    self:_createHighFive(playerId, item.payload.targetId,
                        item.peer, item.payload.requestId)
                end
            end
        end
        local responses = self.pendingHostHighFiveResponses
        self.pendingHostHighFiveResponses = {}
        for _, item in ipairs(responses) do
            local playerId = self.peerToId[item.peer]
            if playerId and playerId == item.playerId
                and item.payload.sessionId == self.sessionId
            then
                self:_resolveHighFive(item.payload.requestId, playerId, item.payload.accepted)
            end
        end
        local now = self.clock()
        for requestId, pending in pairs(self.pendingHighFives) do
            if not Runtime.finite(now) or now >= pending.expiresAt then
                self.pendingHighFives[requestId] = nil
                self.highFiveOffers[requestId] = nil
                if pending.initiatorId == self.localId then
                    self:_setHighFiveNotice("The high-five request expired.")
                else
                    local peer = self.idToPeer[pending.initiatorId]
                    if peer then
                        self:_send(peer, "highfive_result", {
                            sessionId = self.sessionId,
                            requestId = requestId,
                            initiatorId = pending.initiatorId,
                            receiverId = pending.receiverId,
                            status = "expired",
                            message = "The high-five request expired.",
                        })
                    end
                end
            end
        end
        for requestId, active in pairs(self.activeHighFives) do
            if not Runtime.finite(now) or now >= active.endsAt then
                self.activeHighFives[requestId] = nil
            end
        end
    end

    function Runtime.Session:_clearHighFivesForPlayer(playerId)
        for requestId, pending in pairs(self.pendingHighFives) do
            if pending.initiatorId == playerId or pending.receiverId == playerId then
                self.pendingHighFives[requestId] = nil
                self.highFiveOffers[requestId] = nil
                local result = {
                    sessionId = self.sessionId,
                    requestId = requestId,
                    initiatorId = pending.initiatorId,
                    receiverId = pending.receiverId,
                    status = "cancelled",
                    message = "The other player left before the high five.",
                }
                local otherId = pending.initiatorId == playerId
                    and pending.receiverId or pending.initiatorId
                if otherId == self.localId then
                    self:_setHighFiveNotice(result.message)
                else
                    local peer = self.idToPeer[otherId]
                    if peer then self:_send(peer, "highfive_result", result) end
                end
            end
        end
        for requestId, active in pairs(self.activeHighFives) do
            if active.initiatorId == playerId or active.receiverId == playerId then
                self.activeHighFives[requestId] = nil
            end
        end
    end
end

return Component
