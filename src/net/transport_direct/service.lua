-- Handshake expiry and bounded transport polling.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.Instance:_expireHandshakes()
        local now, clockError = self:_readClock()
        if now == nil then
            local pending = {}
            for peer, entry in pairs(self._peerStates) do
                if not entry.logicalConnected then pending[#pending + 1] = peer end
            end
            for _, peer in ipairs(pending) do
                self:_failPeer(peer, Runtime.DirectTransport.DISCONNECT_INTERNAL, clockError)
            end
            self.lastError = clockError
            return
        end
        local expired = {}
        for peer, entry in pairs(self._peerStates) do
            if not entry.logicalConnected and now >= entry.deadline then
                expired[#expired + 1] = peer
            end
        end
        for _, peer in ipairs(expired) do
            self:_failPeer(peer, Runtime.DirectTransport.DISCONNECT_HANDSHAKE_TIMEOUT,
                "Direct authentication timed out.")
        end
    end

    function Runtime.Instance:_poll(rawBudget)
        if self.closed then return nil end
        local queued = self:_dequeue()
        if queued then return queued, nil, 0 end
        self:_expireHandshakes()
        queued = self:_dequeue()
        if queued then return queued, nil, 0 end

        local consumed = 0
        for _ = 1, rawBudget do
            local ok, raw, errorMessage = Runtime.callMethod(self.base, "poll")
            consumed = consumed + 1
            if not ok then
                return nil, "Direct network service failed: " .. tostring(raw), consumed
            end
            if errorMessage ~= nil then return nil, tostring(errorMessage), consumed end
            if raw == nil then break end
            self:_handleRaw(raw)
            queued = self:_dequeue()
            if queued then return queued, nil, consumed end
        end
        self:_expireHandshakes()
        return self:_dequeue(), nil, consumed
    end

    function Runtime.Instance:poll()
        local event, errorMessage = self:_poll(Runtime.DirectTransport.MAX_EVENTS_PER_SERVICE)
        return event, errorMessage
    end

    function Runtime.Instance:service(maxEvents)
        maxEvents = Runtime.wholeNumber(maxEvents or Runtime.DirectTransport.MAX_EVENTS_PER_SERVICE, 1, 1024)
        if not maxEvents then return nil, "Event limit must be between 1 and 1024." end
        local events = {}
        local rawRemaining = Runtime.DirectTransport.MAX_EVENTS_PER_SERVICE
        while #events < maxEvents and (rawRemaining > 0 or #self._events > 0) do
            local event, errorMessage, consumed = self:_poll(rawRemaining)
            rawRemaining = math.max(0, rawRemaining - (consumed or 0))
            if errorMessage then return events, errorMessage end
            if not event then break end
            events[#events + 1] = event
        end
        return events
    end
end

return Component
