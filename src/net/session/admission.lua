-- Direct join approval, rejection, and kicking.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.Session:_discardPendingPeer(peer)
        local pending = self.pendingPeers[peer]
        self.pendingPeers[peer] = nil
        if type(pending) == "table" and pending.requestId then
            if self.approvalRequests[pending.requestId] == pending then
                self.approvalRequests[pending.requestId] = nil
            end
        end
        return pending
    end

    function Runtime.Session:_purgePeerWork(peer)
        self.pendingHostInteractions = Runtime.removePeerItems(self.pendingHostInteractions, peer)
        self.pendingHostWorkshop = Runtime.removePeerItems(self.pendingHostWorkshop, peer)
    end

    function Runtime.Session:_rejectDirectPending(peer, code, guestMessage, hostMessage, eventType)
        local pending = self:_discardPendingPeer(peer)
        if not pending then return false end
        self.protocolRejectionAt[peer] = nil
        self:_purgePeerWork(peer)
        if self.transport then
            self:_sendError(peer, tostring(code or "join_rejected"),
                tostring(guestMessage or "The host did not admit this Direct connection."))
            self.transport:flush()
            self.transport:disconnect(peer, 7, false)
        end
        self:_queue(eventType or "join_rejected", {
            requestId = type(pending) == "table" and pending.requestId or nil,
            name = type(pending) == "table" and pending.name or nil,
        })
        self.status = tostring(hostMessage or "Direct join request closed safely.")
        return true
    end

    function Runtime.Session:_queueDirectApproval(peer, hello)
        local pending = self.pendingPeers[peer]
        if type(pending) ~= "table" or pending.stage ~= "hello" then return false end
        local name = Runtime.directDisplayName(hello and hello.payload and hello.payload.name)
        if not name then
            return self:_rejectDirectPending(peer, "invalid_join",
                "That Direct player name cannot be displayed safely.",
                "One Direct join was rejected because its player name was invalid.")
        end
        if Runtime.countEntries(self.players) >= Runtime.Protocol.MAX_PLAYERS then
            return self:_rejectDirectPending(peer, "shop_full",
                "This Direct shop already has four workers.",
                "Direct join declined because the shop is full.")
        end
        local requestId = self:_nextRuntimeHandle("nextJoinRequestId")
        if not requestId then
            return self:_rejectDirectPending(peer, "join_unavailable",
                "The Direct invitation cannot accept this request.",
                "That Direct join could not be tracked safely.")
        end
        local now = self.clock()
        if not Runtime.finite(now) then
            return self:_rejectDirectPending(peer, "join_unavailable",
                "The Direct invitation cannot accept this request.",
                "That Direct join was declined because its approval clock was unavailable.")
        end
        pending.stage = "approval"
        pending.requestId = requestId
        pending.requestedAt = now
        pending.hello = {
            type = "hello",
            payload = {
                clientNonce = hello.payload.clientNonce,
                name = name,
                character = hello.payload.character,
                furColorway = hello.payload.furColorway,
                overallsColorway = hello.payload.overallsColorway,
            },
        }
        pending.name = name
        pending.character = hello.payload.character
        pending.furColorway = hello.payload.furColorway
        pending.overallsColorway = hello.payload.overallsColorway
        self.approvalRequests[requestId] = pending
        self.status = "Direct worker waiting for host approval"
        self:_queue("join_requested", {
            requestId = requestId,
            name = name,
            character = pending.character,
            expiresIn = Runtime.DIRECT_APPROVAL_TIMEOUT,
        })
        return true
    end

    function Runtime.Session:approveJoin(requestId)
        if not self:isHost() or self.networkKind ~= "direct" or self.terminal then
            return false, "No Direct join request is available."
        end
        if type(requestId) ~= "number" or requestId ~= math.floor(requestId) then
            return false, "That Direct join request is no longer available."
        end
        local pending = self.approvalRequests[requestId]
        if type(pending) ~= "table" or pending.stage ~= "approval"
            or self.pendingPeers[pending.peer] ~= pending
        then
            return false, "That Direct join request is no longer available."
        end
        local now = self.clock()
        if not Runtime.finite(now) or now < pending.requestedAt
            or now - pending.requestedAt > Runtime.DIRECT_APPROVAL_TIMEOUT
        then
            self:_rejectDirectPending(pending.peer, "approval_timeout",
                "The host did not approve this Direct request in time.",
                "One Direct approval timed out; the host remains open.", "join_expired")
            return false, "That Direct join request expired."
        end
        if Runtime.countEntries(self.players) >= Runtime.Protocol.MAX_PLAYERS then
            self:_rejectDirectPending(pending.peer, "shop_full",
                "This Direct shop already has four workers.",
                "One Direct join was declined because the shop is full.")
            return false, "The Direct shop is full."
        end
        pending.decision = "approved"
        self.status = "Approving Direct worker"
        return true, "Worker approved. Finishing the encrypted join."
    end

    function Runtime.Session:rejectJoin(requestId)
        if not self:isHost() or self.networkKind ~= "direct" or self.terminal then
            return false, "No Direct join request is available."
        end
        local pending = type(requestId) == "number" and self.approvalRequests[requestId] or nil
        if type(pending) ~= "table" or self.pendingPeers[pending.peer] ~= pending then
            return false, "That Direct join request is no longer available."
        end
        self:_rejectDirectPending(pending.peer, "join_rejected",
            "The host declined this Direct join request.",
            "One Direct join was declined; the host remains open.")
        return true, "Join declined. That Direct connection is closed."
    end

    function Runtime.Session:kickPlayer(playerId)
        if not self:isHost() or self.networkKind ~= "direct" or self.terminal then
            return false, "Direct player controls are unavailable."
        end
        if type(playerId) ~= "number" or playerId ~= math.floor(playerId)
            or playerId == self.localId
        then
            return false, "The host cannot be removed."
        end
        local peer = self.idToPeer[playerId]
        local player = peer and self.players[playerId] or nil
        if not peer or not player then return false, "That worker is no longer connected." end
        self:_purgePeerWork(peer)
        self:_removePeer(peer, "Removed by the host")
        if self.transport then
            self:_sendError(peer, "kicked",
                "The host removed this worker. A fresh Direct invitation is required.")
            self.transport:flush()
            self.transport:disconnect(peer, 7, false)
        end
        self:_queue("player_kicked", { playerId = playerId, name = player.name })
        return true, tostring(player.name or "Worker") .. " was removed."
    end
end

return Component
