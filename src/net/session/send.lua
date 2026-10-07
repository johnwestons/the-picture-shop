-- Transport encoding, sending, and protocol rejection.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.Session:_encode(kind, payload)
        return Runtime.Protocol.encode(kind, payload)
    end

    function Runtime.Session:_route(kind)
        local channel, delivery = Runtime.Protocol.route(kind)
        return channel, delivery == "reliable"
    end

    function Runtime.Session:_send(peer, kind, payload)
        local encoded, encodeError = self:_encode(kind, payload)
        if not encoded then return false, encodeError end
        local channel, reliable = self:_route(kind)
        return self.transport:send(peer, encoded, channel, reliable)
    end

    function Runtime.Session:_sendToServer(kind, payload)
        if not self.transport then return false, "Transport is unavailable." end
        local encoded, encodeError = self:_encode(kind, payload)
        if not encoded then return false, encodeError end
        local channel, reliable = self:_route(kind)
        return self.transport:sendToServer(encoded, channel, reliable)
    end

    function Runtime.Session:_broadcast(kind, payload)
        if not self.transport then return false, "Transport is unavailable." end
        local encoded, encodeError = self:_encode(kind, payload)
        if not encoded then return false, encodeError end
        local channel, reliable = self:_route(kind)
        return self.transport:broadcast(encoded, channel, reliable)
    end

    -- Full shop snapshots contain the player's entire durable save state. Send
    -- them only to peers that completed the hello/welcome handshake; ENet's host
    -- broadcast also includes sockets still waiting in pendingPeers.
    function Runtime.Session:_broadcastJoined(kind, payload)
        if not self.transport then return false, "Transport is unavailable.", 0 end
        if not next(self.idToPeer) then return true, nil, 0 end
        local encoded, encodeError = self:_encode(kind, payload)
        if not encoded then return false, encodeError, 0 end
        local channel, reliable = self:_route(kind)
        local sent = 0
        for _, peer in pairs(self.idToPeer) do
            local ok, sendError = self.transport:send(peer, encoded, channel, reliable)
            if not ok then return false, sendError, sent end
            sent = sent + 1
        end
        return true, nil, sent
    end

    function Runtime.Session:_sendError(peer, code, message)
        return self:_send(peer, "error", {
            code = tostring(code or "network_error"),
            message = tostring(message or "The network request was rejected."),
            sessionId = self.sessionId,
        })
    end

    function Runtime.Session:_sendProtocolRejection(peer, code, message)
        -- Malformed and host-only packet families share one reply token so an
        -- abusive peer cannot rotate error codes into a reliable-response flood.
        -- Consume the token before attempting the send; a failed send must not
        -- grant another immediate attempt.
        if not peer or (not self.pendingPeers[peer] and not self.peerToId[peer]) then
            return false, "Network peer is no longer active."
        end
        local now = self.clock()
        if not Runtime.finite(now) then return false, "Network clock is unavailable." end
        local previous = self.protocolRejectionAt[peer]
        if previous ~= nil then
            if not Runtime.finite(previous) or now < previous
                or now - previous < Runtime.PROTOCOL_REJECTION_INTERVAL
            then
                return false, "Protocol rejection reply is rate limited."
            end
        end
        self.protocolRejectionAt[peer] = now
        return self:_sendError(peer, code, message)
    end

    function Runtime.Session:_sendInteractionResult(peer, request, accepted, code, message)
        return self:_send(peer, "interaction_result", {
            sessionId = self.sessionId,
            requestId = request.requestId,
            targetKind = request.targetKind,
            accepted = accepted == true,
            code = tostring(code or "rejected"),
            message = tostring(message or "The host rejected that interaction."),
        })
    end
end

return Component
