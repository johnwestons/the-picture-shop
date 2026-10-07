-- Connection queues, clocks, rate limits, and peer admission.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.Instance:_plaintextLimit(channel, inbound)
        local guestToHost = (self.mode == "host" and inbound == true)
            or (self.mode == "client" and inbound ~= true)
        if guestToHost or channel ~= Runtime.DirectTransport.DURABLE_CHANNEL then
            return self.maxRealtimePlaintextBytes
        end
        return self.maxPlaintextBytes
    end

    function Runtime.Instance:_queue(event)
        self._events[#self._events + 1] = event
    end

    function Runtime.Instance:_dequeue()
        if #self._events == 0 then return nil end
        return table.remove(self._events, 1)
    end

    function Runtime.Instance:_ready(entry)
        local ok, ready, errorMessage = Runtime.callMethod(entry.state, "isReady")
        if not ok or errorMessage ~= nil then return nil, "Cryptographic readiness check failed." end
        if type(ready) ~= "boolean" then
            return nil, "Cryptographic readiness check did not return a boolean."
        end
        return ready
    end

    function Runtime.Instance:_readyPeerCount()
        local count = 0
        for _ in pairs(self._readyPeers) do count = count + 1 end
        return count
    end

    function Runtime.Instance:_readClock()
        if self._clockFailed then
            return nil, "Direct authentication timing failed."
        end
        local ok, now = pcall(self.clock)
        if not ok or type(now) ~= "number" or now ~= now
            or now <= -math.huge or now >= math.huge
            or (self._lastClock ~= nil and now < self._lastClock)
        then
            self._clockFailed = true
            return nil, "Direct authentication timing failed."
        end
        self._lastClock = now
        return now
    end

    function Runtime.Instance:_takeAdmissionPermit()
        local now, clockError = self:_readClock()
        if now == nil then return nil, nil, clockError end

        if self._admissionLastRefill == nil then
            self._admissionLastRefill = now
        else
            local elapsed = now - self._admissionLastRefill
            self._admissionTokens = math.min(self.admissionBurst,
                self._admissionTokens + elapsed / self.admissionRefillSeconds)
            self._admissionLastRefill = now
        end
        if self._admissionTokens < 1 then return false, now end
        self._admissionTokens = self._admissionTokens - 1
        return true, now
    end

    function Runtime.Instance:_markReady(entry)
        if entry.logicalConnected then return true end
        local ready, readyError = self:_ready(entry)
        if ready == nil then return false, readyError end
        if not ready or not entry.handshakeSent or not entry.handshakeReceived then return true end
        if self.mode == "host" and self:_readyPeerCount() >= self.maxReadyPeers then
            return false, "Direct authentication capacity is temporarily full.", true
        end
        local pending = entry.pendingData
        entry.pendingData = {}
        entry.pendingDataBytes = 0
        local pendingEvents = {}
        for _, item in ipairs(pending) do
            local pendingEvent, processError = self:_decryptData(entry, item.body, item.raw)
            if not pendingEvent then return false, processError, true end
            pendingEvents[#pendingEvents + 1] = pendingEvent
        end
        entry.logicalConnected = true
        self._readyPeers[entry.peer] = true
        if self.mode == "client" then self.peer = entry.peer end
        local event = Runtime.copyEvent(entry.connectEvent, "connect")
        event.peer = entry.peer
        self:_queue(event)
        for _, pendingEvent in ipairs(pendingEvents) do
            self:_queue(pendingEvent)
        end
        return true
    end
end

return Component
