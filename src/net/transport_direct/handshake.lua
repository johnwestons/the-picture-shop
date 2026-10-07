-- Cryptographic handshakes and peer lifecycle.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.Instance:_sendHandshake(entry, payload)
        if payload == nil then return true end
        if type(payload) ~= "string" or #payload == 0 then
            return false, "Cryptographic handshake output must be a nonempty string."
        end
        if #payload > self.maxHandshakeBytes then
            return false, "Cryptographic handshake output exceeds the handshake limit."
        end
        local wire = Runtime.frame(Runtime.DirectTransport.TYPE_HANDSHAKE, payload)
        if #wire > self.maxWireBytes then
            return false, "Cryptographic handshake output exceeds the wire limit."
        end
        local ok, result, errorMessage = Runtime.callMethod(self.base, "send", entry.peer, wire,
            Runtime.DirectTransport.HANDSHAKE_CHANNEL, true)
        if not ok then return false, "Direct handshake send failed: " .. tostring(result) end
        if not Runtime.sendSucceeded(result) then
            return false, tostring(errorMessage or "The network rejected the direct handshake.")
        end
        entry.handshakeSent = true
        return true
    end

    function Runtime.Instance:_newState(role)
        local constructor = role == "initiator"
            and self.cryptoProvider.newInitiator or self.cryptoProvider.newResponder
        local ok, state, errorMessage = pcall(constructor, self._key)
        if not ok or errorMessage ~= nil then return nil, "Cryptographic state creation failed." end
        if not state then return nil, "Cryptographic state creation failed." end
        local validated, validationError = Runtime.validateState(state)
        if validated and role == "initiator" then self._key = nil end
        return validated, validationError
    end

    function Runtime.Instance:_forgetPeer(peer)
        local entry = self._peerStates[peer]
        if not entry then return nil end
        local closed, closeError = Runtime.closeState(entry)
        if not closed then self.lastError = closeError end
        self._peerStates[peer] = nil
        self._readyPeers[peer] = nil
        if self.peer == peer then self.peer = nil end
        return entry, closeError
    end

    function Runtime.Instance:_failPeer(peer, code, reason)
        local entry, closeError = self:_forgetPeer(peer)
        self.lastError = closeError and (reason .. "; " .. closeError) or reason
        local ok, result = Runtime.callMethod(self.base, "disconnect", peer, code, true)
        if not ok or result == false then
            self.lastError = reason .. "; disconnect failed: " .. tostring(result)
        end
        if entry and (entry.logicalConnected or self.mode == "client") then
            local event = Runtime.copyEvent(entry.connectEvent, "disconnect")
            event.peer = peer
            event.code = code
            event.data = code
            event.error = reason
            self:_queue(event)
        end
        return false, reason
    end

    function Runtime.Instance:_startPeer(raw)
        local peer = raw.peer
        if not peer then return false, "Direct connection event is missing its peer." end
        if self._peerStates[peer] then
            return self:_failPeer(peer, Runtime.DirectTransport.DISCONNECT_AUTHENTICATION,
                "Duplicate direct connection event.")
        end
        if self.mode == "host"
            and tonumber(raw.code or raw.data) ~= self.admissionToken
        then
            return self:_failPeer(peer, Runtime.DirectTransport.DISCONNECT_AUTHENTICATION,
                "Direct invitation pre-authentication failed.")
        end
        if self.mode == "client" and next(self._peerStates) ~= nil then
            return self:_failPeer(peer, Runtime.DirectTransport.DISCONNECT_AUTHENTICATION,
                "A direct client accepted more than one server peer.")
        end
        if self.mode == "host" then
            if self:_readyPeerCount() >= self.maxReadyPeers then
                return self:_failPeer(peer, Runtime.DirectTransport.DISCONNECT_AUTHENTICATION,
                    "Direct authentication capacity is temporarily full.")
            end
            local pending = 0
            for _, existing in pairs(self._peerStates) do
                if not existing.logicalConnected then pending = pending + 1 end
            end
            if pending >= self.maxPendingPeers then
                return self:_failPeer(peer, Runtime.DirectTransport.DISCONNECT_AUTHENTICATION,
                    "Direct authentication capacity is temporarily full.")
            end
        end

        local now
        if self.mode == "host" then
            local permitted, permitTime, permitError = self:_takeAdmissionPermit()
            if permitted == nil then
                return self:_failPeer(peer, Runtime.DirectTransport.DISCONNECT_AUTHENTICATION,
                    permitError)
            end
            if not permitted then
                return self:_failPeer(peer, Runtime.DirectTransport.DISCONNECT_AUTHENTICATION,
                    "Direct authentication capacity is temporarily full.")
            end
            now = permitTime
        else
            local clockError
            now, clockError = self:_readClock()
            if now == nil then
                return self:_failPeer(peer, Runtime.DirectTransport.DISCONNECT_AUTHENTICATION,
                    clockError)
            end
        end
        local deadline = now + self.handshakeTimeout
        if deadline ~= deadline or deadline <= -math.huge or deadline >= math.huge
            or deadline <= now
        then
            self._clockFailed = true
            return self:_failPeer(peer, Runtime.DirectTransport.DISCONNECT_AUTHENTICATION,
                "Direct authentication timing failed.")
        end

        local role = self.mode == "client" and "initiator" or "responder"
        local state, stateError = self:_newState(role)
        if not state then
            return self:_failPeer(peer, Runtime.DirectTransport.DISCONNECT_INTERNAL, stateError)
        end
        local entry = {
            peer = peer,
            state = state,
            role = role,
            connectEvent = Runtime.copyEvent(raw, "connect"),
            startedAt = now,
            deadline = deadline,
            handshakeSent = false,
            handshakeReceived = false,
            handshakeFrames = 0,
            handshakeBytes = 0,
            pendingData = {},
            pendingDataBytes = 0,
            logicalConnected = false,
            closed = false,
        }
        self._peerStates[peer] = entry
        if self.mode == "client" then self._serverPeer = peer end

        local ok, outbound, errorMessage = Runtime.callMethod(state, "start")
        if not ok then
            return self:_failPeer(peer, Runtime.DirectTransport.DISCONNECT_INTERNAL,
                "Cryptographic handshake start failed.")
        end
        if errorMessage ~= nil then
            return self:_failPeer(peer, Runtime.DirectTransport.DISCONNECT_AUTHENTICATION,
                "Direct authentication failed.")
        end
        local sent, sendError = self:_sendHandshake(entry, outbound)
        if not sent then
            return self:_failPeer(peer, Runtime.DirectTransport.DISCONNECT_INTERNAL, sendError)
        end
        local marked, markError, markAuthenticationFailure = self:_markReady(entry)
        if not marked then
            return self:_failPeer(peer, markAuthenticationFailure
                and Runtime.DirectTransport.DISCONNECT_AUTHENTICATION
                or Runtime.DirectTransport.DISCONNECT_INTERNAL, markError)
        end
        return true
    end

    function Runtime.Instance:_handleHandshake(entry, body, raw)
        if raw.channel ~= Runtime.DirectTransport.HANDSHAKE_CHANNEL then
            return self:_failPeer(entry.peer, Runtime.DirectTransport.DISCONNECT_AUTHENTICATION,
                "Direct handshakes are only accepted on channel zero.")
        end
        if entry.logicalConnected then
            return self:_failPeer(entry.peer, Runtime.DirectTransport.DISCONNECT_AUTHENTICATION,
                "A handshake packet arrived after authentication completed.")
        end
        entry.handshakeFrames = entry.handshakeFrames + 1
        entry.handshakeBytes = entry.handshakeBytes + #body
        if entry.handshakeFrames > self.maxHandshakeFrames
            or entry.handshakeBytes > self.maxHandshakeTotalBytes
        then
            return self:_failPeer(entry.peer, Runtime.DirectTransport.DISCONNECT_AUTHENTICATION,
                "Direct authentication exceeded its pre-authentication limit.")
        end
        entry.handshakeReceived = true
        local ok, outbound, errorMessage = Runtime.callMethod(entry.state, "handshake", body)
        if not ok then
            return self:_failPeer(entry.peer, Runtime.DirectTransport.DISCONNECT_AUTHENTICATION,
                "Direct authentication failed.")
        end
        if errorMessage ~= nil then
            return self:_failPeer(entry.peer, Runtime.DirectTransport.DISCONNECT_AUTHENTICATION,
                "Direct authentication failed.")
        end
        local sent, sendError = self:_sendHandshake(entry, outbound)
        if not sent then
            return self:_failPeer(entry.peer, Runtime.DirectTransport.DISCONNECT_INTERNAL, sendError)
        end
        local marked, markError, pendingAuthenticationFailure = self:_markReady(entry)
        if not marked then
            return self:_failPeer(entry.peer, pendingAuthenticationFailure
                and Runtime.DirectTransport.DISCONNECT_AUTHENTICATION
                or Runtime.DirectTransport.DISCONNECT_INTERNAL, markError)
        end
        return true
    end
end

return Component
