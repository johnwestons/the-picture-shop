-- Decryption, message reception, and disconnect handling.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.Instance:_decryptData(entry, body, raw)
        local channel = Runtime.wholeNumber(raw.channel, 0, self.channels - 1)
        if not channel then
            return nil, "Encrypted game data arrived on an invalid channel."
        end
        local plaintextLimit = self:_plaintextLimit(channel, true)
        if #body > plaintextLimit + self.maxCiphertextOverheadBytes then
            return nil, "Encrypted game data exceeds the inbound wire limit."
        end
        local aad = Runtime.DirectTransport.aadForChannel(channel)
        local ok, plaintext, errorMessage = Runtime.callMethod(entry.state, "open", body, aad)
        if not ok or errorMessage ~= nil then
            return nil, "Encrypted game data failed authentication."
        end
        if type(plaintext) ~= "string" then
            return nil, tostring(errorMessage or
                "Encrypted game data failed authentication.")
        end
        if #plaintext > plaintextLimit then
            return nil, "Decrypted game data exceeds the plaintext limit."
        end
        local event = Runtime.copyEvent(raw, "receive")
        event.peer = entry.peer
        event.channel = channel
        event.data = plaintext
        event.payload = plaintext
        event.reliable = nil
        return event
    end

    function Runtime.Instance:_processData(entry, body, raw)
        local event, processError = self:_decryptData(entry, body, raw)
        if not event then return false, processError end
        self:_queue(event)
        return true
    end

    function Runtime.Instance:_handleData(entry, body, raw)
        if not entry.logicalConnected then
            if entry.role ~= "initiator" then
                return self:_failPeer(entry.peer,
                    Runtime.DirectTransport.DISCONNECT_AUTHENTICATION,
                    "Encrypted game data arrived before mutual authentication.")
            end
            local channel = Runtime.wholeNumber(raw.channel, 0, self.channels - 1)
            if not channel then
                return self:_failPeer(entry.peer,
                    Runtime.DirectTransport.DISCONNECT_AUTHENTICATION,
                    "Pre-ready encrypted data arrived on an invalid channel.")
            end
            if #entry.pendingData >= self.maxPreReadyDataFrames
                or entry.pendingDataBytes + #body > self.maxPreReadyDataBytes
            then
                return self:_failPeer(entry.peer,
                    Runtime.DirectTransport.DISCONNECT_AUTHENTICATION,
                    "Pre-ready encrypted data exceeded its bounded holding area.")
            end
            local metadata = Runtime.copyEvent(raw)
            metadata.data = nil
            metadata.payload = nil
            entry.pendingData[#entry.pendingData + 1] = {
                body = body,
                raw = metadata,
            }
            entry.pendingDataBytes = entry.pendingDataBytes + #body
            return true
        end
        local processed, processError = self:_processData(entry, body, raw)
        if not processed then
            return self:_failPeer(entry.peer,
                Runtime.DirectTransport.DISCONNECT_AUTHENTICATION, processError)
        end
        return true
    end

    function Runtime.Instance:_handleReceive(raw)
        local peer = raw.peer
        local entry = peer and self._peerStates[peer] or nil
        if not entry then
            if peer then
                self:_failPeer(peer, Runtime.DirectTransport.DISCONNECT_AUTHENTICATION,
                    "Direct packet arrived before a connection event.")
            end
            return
        end
        local wire = raw.payload or raw.data
        local preReadyWireLimit = entry.role == "initiator"
            and self.maxWireBytes
            or Runtime.DirectTransport.HEADER_BYTES + self.maxHandshakeBytes
        if not entry.logicalConnected
            and (type(wire) ~= "string"
                or #wire > preReadyWireLimit)
        then
            self:_failPeer(peer, Runtime.DirectTransport.DISCONNECT_AUTHENTICATION,
                "Direct pre-authentication packet exceeds the wire limit.")
            return
        end
        local packetType, body, parseError = Runtime.parseFrame(wire,
            self.maxHandshakeBytes, self.maxWireBytes)
        if not packetType then
            self:_failPeer(peer, Runtime.DirectTransport.DISCONNECT_AUTHENTICATION, parseError)
        elseif packetType == Runtime.DirectTransport.TYPE_HANDSHAKE then
            self:_handleHandshake(entry, body, raw)
        else
            self:_handleData(entry, body, raw)
        end
    end

    function Runtime.Instance:_handleDisconnect(raw)
        local peer = raw.peer
        local entry, closeError
        if peer then entry, closeError = self:_forgetPeer(peer) end
        if not entry or (not entry.logicalConnected and self.mode ~= "client") then return end
        local event = Runtime.copyEvent(raw, "disconnect")
        event.code = tonumber(event.code or event.data) or 0
        event.data = event.code
        event.error = closeError
        self:_queue(event)
    end

    function Runtime.Instance:_handleRaw(raw)
        if type(raw) ~= "table" then return end
        if raw.type == "connect" then
            self:_startPeer(raw)
        elseif raw.type == "receive" then
            self:_handleReceive(raw)
        elseif raw.type == "disconnect" then
            self:_handleDisconnect(raw)
        end
    end
end

return Component
