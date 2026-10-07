-- Encrypted sends, broadcasting, flushing, and closure.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.Instance:send(peer, payload, channelOrOptions, reliable)
        if self.closed then return false, "Transport is closed." end
        if type(payload) ~= "string" then return false, "Network payload must be a string." end
        local entry = self._peerStates[peer]
        if not entry or not entry.logicalConnected then
            return false, "Peer authentication is not complete."
        end
        local channel, useReliable = Runtime.sendOptions(channelOrOptions, reliable)
        channel = Runtime.wholeNumber(channel, 0, self.channels - 1)
        if not channel then return false, "Network channel is outside this session's channel range." end
        local plaintextLimit = self:_plaintextLimit(channel, false)
        if #payload > plaintextLimit then
            return false, "Network payload exceeds the direct plaintext limit."
        end
        local aad = Runtime.DirectTransport.aadForChannel(channel)
        local ok, ciphertext, errorMessage = Runtime.callMethod(entry.state, "seal", payload, aad)
        if not ok or errorMessage ~= nil then return false, "Game data encryption failed." end
        if type(ciphertext) ~= "string" or #ciphertext == 0 then
            return false, tostring(errorMessage or "Game data encryption failed.")
        end
        local wire = Runtime.frame(Runtime.DirectTransport.TYPE_DATA, ciphertext)
        if #wire > self.maxWireBytes
            or #ciphertext > plaintextLimit + self.maxCiphertextOverheadBytes
        then
            return false, "Encrypted game data exceeds the direct wire limit."
        end
        local sent, result, sendError = Runtime.callMethod(self.base, "send", peer, wire,
            channel, useReliable)
        if not sent then return false, "Direct network send failed: " .. tostring(result) end
        if not Runtime.sendSucceeded(result) then
            return false, tostring(sendError or "The network rejected the encrypted packet.")
        end
        return true
    end

    function Runtime.Instance:sendToServer(payload, channelOrOptions, reliable)
        if not self.peer then return false, "Server authentication is not complete." end
        return self:send(self.peer, payload, channelOrOptions, reliable)
    end

    function Runtime.Instance:broadcast(payload, channelOrOptions, reliable)
        if self.closed then return false, "Transport is closed." end
        if type(payload) ~= "string" then return false, "Network payload must be a string." end
        local peers = {}
        for peer in pairs(self._readyPeers) do peers[#peers + 1] = peer end
        for _, peer in ipairs(peers) do
            local ok, errorMessage = self:send(peer, payload, channelOrOptions, reliable)
            if not ok then return false, errorMessage end
        end
        return true
    end

    function Runtime.Instance:flush()
        if self.closed or type(self.base.flush) ~= "function" then return true end
        local ok, result, errorMessage = Runtime.callMethod(self.base, "flush")
        if not ok then return false, "Direct network flush failed: " .. tostring(result) end
        if result == false then return false, tostring(errorMessage or "Direct network flush failed.") end
        return true
    end

    function Runtime.Instance:disconnect(peer, code, immediate)
        if self.closed then return false, "Transport is closed." end
        code = Runtime.wholeNumber(code or 0, 0, 2147483647)
        if not code then return false, "Disconnect code must be a nonnegative whole number." end
        local ok, result, errorMessage = Runtime.callMethod(self.base, "disconnect", peer, code, immediate)
        if not ok then return false, "Direct disconnect failed: " .. tostring(result) end
        if result == false then return false, tostring(errorMessage or "Direct disconnect failed.") end
        local _, closeError = self:_forgetPeer(peer)
        if closeError then return false, closeError end
        return true
    end

    function Runtime.Instance:close(code, immediate)
        if self.closed then
            if self._closeOk == true then return true end
            return false, self._closeError
        end
        code = Runtime.wholeNumber(code or 0, 0, 2147483647)
        if not code then return false, "Disconnect code must be a nonnegative whole number." end
        local errors = {}
        local peers = {}
        for peer in pairs(self._peerStates) do peers[#peers + 1] = peer end
        for _, peer in ipairs(peers) do
            local entry = self._peerStates[peer]
            local ok, closeError = Runtime.closeState(entry)
            if not ok then errors[#errors + 1] = closeError end
        end
        self._peerStates = {}
        self._readyPeers = {}
        self._events = {}
        self.peer = nil
        self._serverPeer = nil
        self._key = nil
        local ok, result, errorMessage = Runtime.callMethod(self.base, "close", code, immediate)
        if not ok then
            errors[#errors + 1] = "Direct network close failed: " .. tostring(result)
        elseif result == false then
            errors[#errors + 1] = tostring(errorMessage or "Direct network close failed.")
        end
        self.closed = true
        self._closeOk = #errors == 0
        self._closeError = nil
        if not self._closeOk then self._closeError = table.concat(errors, "; ") end
        return self._closeOk, self._closeError
    end

    Runtime.Instance.destroy = Runtime.Instance.close
end

return Component
