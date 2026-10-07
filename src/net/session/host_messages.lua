-- Host handshakes, peer removal, and incoming messages.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.Session:_hostWelcome(peer, hello, context)
        if self.peerToId[peer] then
            self:_sendProtocolRejection(
                peer, "already_joined", "This peer already joined the shop.")
            return false
        end
        local pending = self.pendingPeers[peer]
        if self.requireHostApproval and (type(pending) ~= "table"
            or pending.stage ~= "approval" or pending.decision ~= "approved"
            or pending.hello ~= hello)
        then
            self:_sendError(peer, "approval_required",
                "The Direct host must approve this join before shop data is available.")
            return false
        end
        if Runtime.countEntries(self.players) >= Runtime.Protocol.MAX_PLAYERS then
            self:_sendError(peer, "shop_full", "This shop already has four workers.")
            self.transport:disconnect(peer, 4, false)
            self:_discardPendingPeer(peer)
            self.protocolRejectionAt[peer] = nil
            return false
        end

        local id, index = self:_nextPlayerId()
        if not id then
            self:_sendError(peer, "shop_full", "This shop already has four workers.")
            self.transport:disconnect(peer, 4, false)
            self:_discardPendingPeer(peer)
            self.protocolRejectionAt[peer] = nil
            return false
        end
        local host = self.players[1] or Runtime.newPlayer({ x = 0, y = 0 })
        local offsets = { { 28, 0 }, { -28, 0 }, { 0, 28 } }
        local offset = offsets[(index or 2) - 1] or { 0, 0 }
        local spawnX, spawnY = host.x + offset[1], host.y + offset[2]
        if context and type(context.resolveGuestSpawn) == "function" then
            local resolved, candidateX, candidateY = pcall(context.resolveGuestSpawn,
                host.x, host.y, index, self.players)
            if resolved and Runtime.finite(candidateX) and Runtime.finite(candidateY) then
                spawnX, spawnY = candidateX, candidateY
            end
        end
        local player = Runtime.newPlayer({
            id = id,
            name = hello.payload.name,
            character = hello.payload.character,
            furColorway = hello.payload.furColorway,
            overallsColorway = hello.payload.overallsColorway,
            x = spawnX,
            y = spawnY,
        })
        player.lastInputAt = self.clock()
        player.lastInputSequence = -1
        player.inputX, player.inputY = 0, 0
        self.players[id] = player
        self.peerToId[peer] = id
        self.idToPeer[id] = peer
        self:_discardPendingPeer(peer)

        -- The joining worker needs its own spawn plus the host immediately. Other
        -- workers arrive through the next sharded motion tick. Keeping this roster
        -- bounded prevents real-world floating-point poses from exceeding the
        -- realtime packet ceiling when the fourth worker joins.
        local welcomePlayers = Runtime.Codec.array({
            Runtime.playerRecord(host),
            Runtime.playerRecord(player),
        })
        local welcomeOk, welcomeError = self:_send(peer, "welcome", {
            sessionId = self.sessionId,
            playerId = id,
            serverTick = self.serverTick,
            players = welcomePlayers,
        })
        local shop = context and context.getShopSnapshot and context.getShopSnapshot() or nil
        local shopOk, shopError
        if welcomeOk and type(shop) == "table" and type(shop.state) == "table"
            and type(shop.player) == "table"
        then
            shopOk, shopError = self:_send(peer, "shop_snapshot", {
                sessionId = self.sessionId,
                revision = self.shopRevision,
                state = shop.state,
                player = shop.player,
            })
        else
            shopError = shopError or "The host could not prepare a safe shop snapshot."
        end
        local radio = context and type(context.getRadioSnapshot) == "function"
            and context.getRadioSnapshot() or self.radioState
        local radioOk, radioError = self:_send(peer, "radio_state", {
            sessionId = self.sessionId,
            revision = self.radioRevision,
            trackIndex = radio.trackIndex,
            active = radio.active,
            paused = radio.paused,
            muted = radio.muted,
            positionMs = radio.positionMs,
        })
        if not welcomeOk or not shopOk or not radioOk then
            self:_queue("error", { message = tostring(welcomeError or shopError or radioError) })
            self:_sendError(peer, "snapshot_failed", tostring(welcomeError or shopError or radioError))
            self.transport:disconnect(peer, 5, false)
            self.players[id], self.peerToId[peer], self.idToPeer[id] = nil, nil, nil
            self.protocolRejectionAt[peer] = nil
            self.status = tostring(Runtime.countEntries(self.players)) .. "/4 workers connected"
            return false
        end
        self.status = tostring(Runtime.countEntries(self.players)) .. "/4 workers connected"
        self:_queue("player_joined", { playerId = id, name = player.name })
        return true
    end

    function Runtime.Session:_removePeer(peer, reason)
        if peer then self.protocolRejectionAt[peer] = nil end
        local pending = self:_discardPendingPeer(peer)
        self:_purgePeerWork(peer)
        local id = self.peerToId[peer]
        if not id then
            if type(pending) == "table" and pending.stage == "approval" then
                self:_queue("join_cancelled", {
                    requestId = pending.requestId,
                    name = pending.name,
                })
            end
            if pending ~= nil and self.networkKind == "direct" then
                self.status = Runtime.countEntries(self.approvalRequests) > 0
                    and "Direct worker waiting for host approval"
                    or (tostring(Runtime.countEntries(self.players)) .. "/4 workers connected")
            end
            return pending ~= nil
        end
        local player = self.players[id]
        self:_clearHighFivesForPlayer(id)
        self.pendingHostHighFiveRequests = Runtime.removePeerItems(self.pendingHostHighFiveRequests, peer)
        self.pendingHostHighFiveResponses = Runtime.removePeerItems(self.pendingHostHighFiveResponses, peer)
        self.peerToId[peer], self.idToPeer[id], self.players[id] = nil, nil, nil
        self:_broadcastJoined("leave", {
            sessionId = self.sessionId,
            playerId = id,
            reason = tostring(reason or "Disconnected"),
            serverTick = self.serverTick,
        })
        self.status = tostring(Runtime.countEntries(self.players)) .. "/4 workers connected"
        self:_queue("player_left", { playerId = id, name = player and player.name, reason = reason })
        return true
    end

    function Runtime.Session:_handleHostEnvelope(peer, envelope, context)
        if envelope.type == "hello" then
            if self.networkKind ~= "direct" then
                self:_hostWelcome(peer, envelope, context)
                return
            end
            local joinedId = self.peerToId[peer]
            if joinedId then
                self:kickPlayer(joinedId)
                return
            end
            local pending = self.pendingPeers[peer]
            if type(pending) ~= "table" then
                if self.transport then self.transport:disconnect(peer, 7, true) end
                return
            end
            if pending.stage == "hello" then
                self:_queueDirectApproval(peer, envelope)
            elseif pending.stage == "approval" then
                -- ENet reliable delivery does not duplicate messages. Still ignore
                -- an exact replay defensively and revoke on any attempted rewrite.
                if not Runtime.sameHello(pending.hello and pending.hello.payload, envelope.payload) then
                    self:_rejectDirectPending(peer, "invalid_join",
                        "The Direct join request changed while awaiting approval.",
                        "One Direct join was rejected because its request changed.")
                end
            else
                self:_rejectDirectPending(peer, "invalid_join",
                    "The Direct join request is not valid.",
                    "One invalid Direct join was rejected.")
            end
            return
        end
        local id = self.peerToId[peer]
        if not id then
            if self.networkKind == "direct" and self.pendingPeers[peer] then
                self:_rejectDirectPending(peer, "approval_required",
                    "Wait for host approval before sending gameplay data.",
                    "One Direct join sent gameplay data before approval and was rejected.")
            else
                self:_sendProtocolRejection(
                    peer, "hello_required", "Send a compatible hello before gameplay data.")
            end
            return
        end
        local payload = envelope.payload
        if payload.sessionId == self.sessionId and context
            and type(context.touchWorkshop) == "function"
        then
            context.touchWorkshop(self.players[id])
        end
        if envelope.type == "input" then
            if payload.sessionId ~= self.sessionId then return end
            local player = self.players[id]
            if not player or payload.sequence <= (player.lastInputSequence or -1) then return end
            player.lastInputSequence = payload.sequence
            player.inputSequence = payload.sequence
            player.inputX, player.inputY = payload.moveX, payload.moveY
            if payload.furColorway then player.furColorway = payload.furColorway end
            if payload.overallsColorway then player.overallsColorway = payload.overallsColorway end
            player.lastInputAt = self.clock()
        elseif envelope.type == "interaction_request" then
            if payload.sessionId ~= self.sessionId then return end
            for _, pending in ipairs(self.pendingHostInteractions) do
                if pending.peer == peer then return end
            end
            self.pendingHostInteractions[#self.pendingHostInteractions + 1] = {
                peer = peer,
                playerId = id,
                request = payload,
            }
        elseif envelope.type == "highfive_request" then
            if payload.sessionId ~= self.sessionId then return end
            for _, pending in ipairs(self.pendingHostHighFiveRequests) do
                if pending.peer == peer then return end
            end
            self.pendingHostHighFiveRequests[#self.pendingHostHighFiveRequests + 1] = {
                peer = peer, playerId = id, payload = payload,
            }
        elseif envelope.type == "highfive_response" then
            if payload.sessionId ~= self.sessionId then return end
            for _, pending in ipairs(self.pendingHostHighFiveResponses) do
                if pending.peer == peer then return end
            end
            self.pendingHostHighFiveResponses[#self.pendingHostHighFiveResponses + 1] = {
                peer = peer, playerId = id, payload = payload,
            }
        elseif envelope.type == "workshop_acquire"
            or envelope.type == "workshop_command"
            or envelope.type == "workshop_release"
        then
            if payload.sessionId ~= self.sessionId then return end
            local incomingSafety = envelope.type == "workshop_command"
                and Runtime.urgentWorkshopSafety(payload.resourceId, payload.action, payload)
            for _, pending in ipairs(self.pendingHostWorkshop) do
                if pending.peer == peer then
                    local queuedSafety = pending.operation == "workshop_command"
                        and Runtime.urgentWorkshopSafety(
                            pending.payload.resourceId, pending.payload.action, pending.payload)
                    if not incomingSafety or queuedSafety then return end
                end
            end
            self.pendingHostWorkshop[#self.pendingHostWorkshop + 1] = {
                peer = peer,
                playerId = id,
                operation = envelope.type,
                payload = payload,
            }
        elseif envelope.type == "ping" and payload.sessionId == self.sessionId then
            self:_send(peer, "pong", { sessionId = self.sessionId, nonce = payload.nonce })
        elseif envelope.type == "leave" and payload.sessionId == self.sessionId then
            self:_removePeer(peer, payload.reason)
            if self.transport then self.transport:disconnect(peer, 0, false) end
        else
            self:_sendProtocolRejection(peer, "message_not_allowed",
                "Guests may send only input, workshop, interaction, high-five, ping, or leave messages.")
        end
    end
end

return Component
