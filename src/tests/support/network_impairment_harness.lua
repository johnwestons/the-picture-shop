local Harness = {}
Harness.__index = Harness

local DIRECTIONS = {
    client_to_host = true,
    host_to_client = true,
}

local function wholeNumber(value, minimum, maximum)
    return type(value) == "number" and value == math.floor(value)
        and value >= minimum and value <= maximum
end

local function actionKey(direction, peerIndex, generation)
    return direction .. ":" .. tostring(peerIndex)
        .. ":" .. tostring(generation)
end

local function makeTransport(network, role, link)
    local transport = {
        role = role,
        link = link,
        inbound = {},
        closed = false,
    }

    function transport:service(maxEvents)
        if self.serviceError then return nil, self.serviceError end
        network:_releaseDue()
        local requested = math.max(0, math.floor(tonumber(maxEvents) or 0))
        local events = network:_drainInbound(self, requested)
        network.serviceCalls[#network.serviceCalls + 1] = {
            role = role,
            peerIndex = link and link.index or nil,
            requested = requested,
            delivered = #events,
            dispatch = role == "host" and network.hostDispatch or "fifo",
        }
        return events
    end

    function transport:send(peer, payload, channel, reliable)
        if self.closed or role ~= "host" then
            return false, "impairment host is unavailable"
        end
        local target = network.linksByPeer[peer]
        if not target then return false, "impairment peer is unavailable" end
        return network:_transmit(
            "host_to_client", target, payload, channel, reliable)
    end

    function transport:sendToServer(payload, channel, reliable)
        if self.closed or role ~= "client" or not link then
            return false, "impairment client is unavailable"
        end
        return network:_transmit(
            "client_to_host", link, payload, channel, reliable)
    end

    function transport:broadcast(payload, channel, reliable)
        if self.closed or role ~= "host" then
            return false, "impairment host is unavailable"
        end
        local allSent, firstError = true, nil
        for _, target in ipairs(network.links) do
            if target.active and not target.client.closed then
                local sent, sendError = network:_transmit(
                    "host_to_client", target, payload, channel, reliable)
                if not sent then
                    allSent = false
                    firstError = firstError or sendError
                end
            end
        end
        return allSent, firstError
    end

    function transport:disconnect(peer, code, immediate)
        if self.closed or role ~= "host" then
            return false, "impairment host is unavailable"
        end
        local target = network.linksByPeer[peer]
        if not target then return false, "impairment peer is unavailable" end
        network.disconnects[#network.disconnects + 1] = {
            peerIndex = target.index,
            code = code,
            immediate = immediate == true,
        }
        network:_enqueue(target.client, {
            type = "disconnect",
            peer = target.peer,
            code = code,
        })
        target.active = false
        target.failed = true
        target.failureReason = "impairment peer disconnected"
        return true
    end

    function transport:flush()
        network.flushes = network.flushes + 1
        return not self.closed
    end

    function transport:close(code, immediate)
        if self.closed then return true end
        self.closed = true
        network.closes[#network.closes + 1] = {
            role = role,
            peerIndex = link and link.index or nil,
            code = code,
            immediate = immediate == true,
        }
        if role == "host" then
            for _, target in ipairs(network.links) do
                if target.active then
                    network:_enqueue(target.client, {
                        type = "disconnect",
                        peer = target.peer,
                        code = code,
                    })
                    target.active = false
                    target.failed = true
                    target.failureReason = "impairment host closed"
                end
            end
        elseif link.active and network.host and not network.host.closed then
            network:_enqueue(network.host, {
                type = "disconnect",
                peer = link.peer,
                code = code,
            })
            link.active = false
            link.failed = true
            link.failureReason = "impairment client closed"
        end
        return true
    end

    return transport
end

function Harness.new(options)
    options = options or {}
    local maximum = tonumber(options.maxClients) or 3
    if not wholeNumber(maximum, 1, 16) then return nil end
    local hostDispatch = options.hostDispatch or "enet_round_robin"
    if hostDispatch ~= "enet_round_robin" and hostDispatch ~= "adversarial_fifo" then
        return nil
    end

    local self = setmetatable({
        step = 0,
        nextFrame = 0,
        maxClients = maximum,
        hostDispatch = hostDispatch,
        hostDispatchCursor = 1,
        host = nil,
        hostOptions = nil,
        links = {},
        allLinks = {},
        linksByPeer = {},
        generations = {},
        reliableDue = {},
        scheduled = {},
        actions = {},
        classifier = type(options.classify) == "function" and options.classify or nil,
        log = {},
        serviceCalls = {},
        disconnects = {},
        closes = {},
        flushes = 0,
        factory = {},
    }, Harness)

    function self.factory.createHost(hostOptions)
        if self.host and not self.host.closed then
            return nil, "impairment host already exists"
        end
        self.hostOptions = hostOptions
        self.host = makeTransport(self, "host")
        return self.host
    end

    function self.factory.createClient(endpoint, clientOptions)
        if not self.host or self.host.closed then
            return nil, "impairment host has not started"
        end
        local index
        for candidate = 1, self.maxClients do
            local existing = self.links[candidate]
            if not existing or not existing.active then
                index = candidate
                break
            end
        end
        if not index then
            return nil, "impairment network is full"
        end
        local previous = self.links[index]
        if previous then self.linksByPeer[previous.peer] = nil end
        local generation = (self.generations[index] or 0) + 1
        self.generations[index] = generation
        local link = {
            index = index,
            generation = generation,
            endpoint = endpoint,
            options = clientOptions,
            peer = { id = "impairment-peer-" .. tostring(index)
                .. "-generation-" .. tostring(generation) },
            active = true,
            failed = false,
            failureReason = nil,
        }
        link.client = makeTransport(self, "client", link)
        self.links[index] = link
        self.allLinks[#self.allLinks + 1] = link
        self.linksByPeer[link.peer] = link
        self:_enqueue(self.host, { type = "connect", peer = link.peer })
        self:_enqueue(link.client, { type = "connect", peer = link.peer })
        return link.client
    end

    return self
end

function Harness:_drainInbound(transport, requested)
    local events = {}
    if requested < 1 then return events end
    if transport.role ~= "host" or self.hostDispatch == "adversarial_fifo" then
        for _ = 1, math.min(requested, #transport.inbound) do
            events[#events + 1] = table.remove(transport.inbound, 1)
        end
        return events
    end

    -- ENet's native dispatch queue rotates peers after returning one receive
    -- event. Rebuild that small peer order for each deterministic service call
    -- while preserving exact FIFO order within every peer.
    local missingPeer = {}
    local order, seen = {}, {}
    for _, event in ipairs(transport.inbound) do
        local key = event.peer or missingPeer
        if not seen[key] then
            seen[key] = true
            order[#order + 1] = key
        end
    end
    if #order == 0 then return events end

    local start = ((self.hostDispatchCursor - 1) % #order) + 1
    local lastServed = start
    while #events < requested do
        local progressed = false
        for offset = 0, #order - 1 do
            local orderIndex = ((start + offset - 1) % #order) + 1
            local key = order[orderIndex]
            local inboundIndex
            for index, event in ipairs(transport.inbound) do
                if (event.peer or missingPeer) == key then
                    inboundIndex = index
                    break
                end
            end
            if inboundIndex then
                events[#events + 1] = table.remove(transport.inbound, inboundIndex)
                lastServed = orderIndex
                progressed = true
                if #events >= requested then break end
            end
        end
        if not progressed then break end
        start = (lastServed % #order) + 1
    end
    self.hostDispatchCursor = (lastServed % #order) + 1
    return events
end

function Harness:_enqueue(transport, event)
    if transport and not transport.closed then
        transport.inbound[#transport.inbound + 1] = event
        return true
    end
    return false
end

function Harness:_schedule(transport, event, delay)
    self.nextFrame = self.nextFrame + 1
    self.scheduled[#self.scheduled + 1] = {
        due = self.step + delay,
        order = self.nextFrame,
        transport = transport,
        event = event,
    }
end

function Harness:_releaseDue()
    table.sort(self.scheduled, function(left, right)
        if left.due == right.due then return left.order < right.order end
        return left.due < right.due
    end)
    local future = {}
    for _, frame in ipairs(self.scheduled) do
        if frame.due <= self.step then
            self:_enqueue(frame.transport, frame.event)
        else
            future[#future + 1] = frame
        end
    end
    self.scheduled = future
end

function Harness:_takeAction(direction, link)
    local queue = self.actions[actionKey(
        direction, link.index, link.generation)]
    if not queue or #queue == 0 then return nil end
    return table.remove(queue, 1)
end

function Harness:_classify(payload)
    if not self.classifier then return nil, nil end
    local classified, kind, code = pcall(self.classifier, payload)
    if not classified then return "classifier_error", nil end
    return kind, code
end

function Harness:_transmit(direction, link, payload, channel, reliable)
    local target = direction == "client_to_host" and self.host or link.client
    local kind, code = self:_classify(payload)
    if not link or not link.active or link.failed or not target or target.closed then
        self.log[#self.log + 1] = {
            direction = direction,
            peerIndex = link and link.index or nil,
            kind = kind,
            code = code,
            bytes = type(payload) == "string" and #payload or nil,
            channel = channel,
            reliable = reliable == true,
            outcome = "failed",
        }
        return false, (link and link.failureReason) or "impairment link failed"
    end

    local action = self:_takeAction(direction, link) or {}
    local delay = tonumber(action.delay) or 0
    local duplicates = tonumber(action.duplicates) or 0
    local outgoing = action.payload ~= nil and action.payload or payload
    local outgoingChannel = action.channel ~= nil and action.channel or channel
    kind, code = self:_classify(outgoing)
    if not wholeNumber(delay, 0, 100000)
        or not wholeNumber(duplicates, 0, 16)
    then
        return false, "invalid impairment action"
    end
    if reliable == true and action.drop == true then
        return false, "reliable packets cannot be dropped by the Session-layer harness"
    end
    if reliable == true and duplicates > 0 and action.applicationReplay ~= true then
        return false, "reliable duplication requires an explicit application replay"
    end
    if reliable == true and (action.payload ~= nil or action.channel ~= nil) then
        return false, "reliable corruption must use explicit receive injection"
    end

    local effectiveDelay = delay
    if reliable == true then
        local reliableKey = actionKey(direction, link.index, link.generation)
            .. ":" .. tostring(channel)
        local due = math.max(self.step + delay,
            self.reliableDue[reliableKey] or self.step)
        self.reliableDue[reliableKey] = due
        effectiveDelay = due - self.step
    end

    local outcome = action.drop == true and "dropped" or "queued"
    self.log[#self.log + 1] = {
        direction = direction,
        peerIndex = link.index,
        kind = kind,
        code = code,
        bytes = type(outgoing) == "string" and #outgoing or nil,
        channel = outgoingChannel,
        reliable = reliable == true,
        outcome = outcome,
        delay = effectiveDelay,
        deliveries = action.drop == true and 0 or (duplicates + 1),
    }
    if action.drop == true then return true end

    for _ = 1, duplicates + 1 do
        self:_schedule(target, {
            type = "receive",
            peer = link.peer,
            data = outgoing,
            channel = outgoingChannel,
        }, effectiveDelay)
    end
    return true
end

function Harness:queueAction(direction, peerIndex, action)
    if not DIRECTIONS[direction] or not wholeNumber(peerIndex, 1, self.maxClients)
        or type(action) ~= "table"
    then
        return false
    end
    local link = self.links[peerIndex]
    if not link or not link.active then return false end
    local key = actionKey(direction, peerIndex, link.generation)
    self.actions[key] = self.actions[key] or {}
    self.actions[key][#self.actions[key] + 1] = action
    return true
end

function Harness:dropNext(direction, peerIndex)
    return self:queueAction(direction, peerIndex, { drop = true })
end

function Harness:delayNext(direction, peerIndex, ticks)
    if not wholeNumber(ticks, 0, 100000) then return false end
    return self:queueAction(direction, peerIndex, { delay = ticks })
end

function Harness:duplicateNext(direction, peerIndex, extraCopies, applicationReplay)
    extraCopies = extraCopies == nil and 1 or extraCopies
    if not wholeNumber(extraCopies, 1, 16) then return false end
    return self:queueAction(direction, peerIndex, {
        duplicates = extraCopies,
        applicationReplay = applicationReplay == true,
    })
end

function Harness:corruptNext(direction, peerIndex, replacement, channel)
    if type(replacement) ~= "string" then return false end
    return self:queueAction(direction, peerIndex, {
        payload = replacement,
        channel = channel,
    })
end

-- Packet-ordering steps are intentionally independent from Session's clock.
-- Timeout tests must advance their injected clock explicitly.
function Harness:advanceSteps(steps)
    if not wholeNumber(steps, 0, 100000) then return false end
    self.step = self.step + steps
    self:_releaseDue()
    return true
end

function Harness:peer(peerIndex)
    local link = self.links[peerIndex]
    return link and link.peer or nil
end

function Harness:client(peerIndex)
    local link = self.links[peerIndex]
    return link and link.client or nil
end

function Harness:failPeer(peerIndex, reason)
    local link = self.links[peerIndex]
    if not link or not link.active then return false end
    link.failed = true
    link.failureReason = tostring(reason or "simulated link failure")
    return true
end

function Harness:disconnectPeer(peerIndex, code)
    local link = self.links[peerIndex]
    if not link or not link.active then return false end
    self:_enqueue(self.host, {
        type = "disconnect",
        peer = link.peer,
        code = code or 0,
    })
    self:_enqueue(link.client, {
        type = "disconnect",
        peer = link.peer,
        code = code or 0,
    })
    link.active = false
    link.failed = true
    link.failureReason = "simulated disconnect"
    return true
end

function Harness:injectToHost(peerIndex, payload, channel, copies)
    local link = self.links[peerIndex]
    copies = copies or 1
    if not link or not wholeNumber(copies, 1, 4096) then return false end
    for _ = 1, copies do
        self:_schedule(self.host, {
            type = "receive",
            peer = link.peer,
            data = payload,
            channel = channel,
        }, 0)
    end
    return true
end

function Harness:injectToClient(peerIndex, payload, channel, copies)
    local link = self.links[peerIndex]
    copies = copies or 1
    if not link or not wholeNumber(copies, 1, 4096) then return false end
    for _ = 1, copies do
        self:_schedule(link.client, {
            type = "receive",
            peer = link.peer,
            data = payload,
            channel = channel,
        }, 0)
    end
    return true
end

function Harness:pendingFor(role, peerIndex)
    self:_releaseDue()
    if role == "host" then return self.host and #self.host.inbound or 0 end
    if role == "client" then
        local client = self:client(peerIndex)
        return client and #client.inbound or 0
    end
    return nil
end

function Harness:isQuiescent()
    if #self.scheduled > 0 then return false end
    if self.host and (not self.host.closed or #self.host.inbound > 0) then return false end
    for _, link in ipairs(self.allLinks) do
        if not link.client.closed or #link.client.inbound > 0 then return false end
    end
    for _, queue in pairs(self.actions) do
        if #queue > 0 then return false end
    end
    return true
end

function Harness:dispose()
    for _, link in ipairs(self.allLinks) do
        if not link.client.closed then link.client:close(0, true) end
    end
    if self.host and not self.host.closed then self.host:close(0, true) end
    self.scheduled = {}
    self.actions = {}
    self.reliableDue = {}
    if self.host then self.host.inbound = {} end
    for _, link in ipairs(self.allLinks) do link.client.inbound = {} end
    return self:isQuiescent()
end

return Harness
