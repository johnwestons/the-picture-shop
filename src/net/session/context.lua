-- Session dependencies, transport constants, and helper functions.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    Runtime.Address = require("src.net.address")
    Runtime.Codec = require("src.net.codec")
    Runtime.Protocol = require("src.net.protocol")
    Runtime.MachineResource = require("src.machine_resource_id")
    Runtime.Transport = require("src.net.transport_enet")

    Runtime.Session = {}
    Runtime.Session.__index = Runtime.Session

    Runtime.INPUT_INTERVAL = 1 / 20
    Runtime.SNAPSHOT_INTERVAL = 1 / 12
    Runtime.SHOP_STATE_INTERVAL = 0.25
    Runtime.SHOP_STATE_FALLBACK_INTERVAL = 30
    Runtime.INPUT_HOLD_TIMEOUT = 0.35
    Runtime.CONNECT_TIMEOUT = 10
    Runtime.DIRECT_APPROVAL_TIMEOUT = 60
    Runtime.DIRECT_CLIENT_TIMEOUT = Runtime.CONNECT_TIMEOUT + Runtime.DIRECT_APPROVAL_TIMEOUT
    Runtime.TELEPORT_DISTANCE = 140
    Runtime.CORRECTION_RATE = 12
    Runtime.REMOTE_SMOOTH_RATE = 14
    Runtime.INTERACTION_RATE_LIMIT = 0.20
    Runtime.INTERACTION_TIMEOUT = 3
    Runtime.WORKSHOP_TIMEOUT = 4
    Runtime.HIGH_FIVE_RANGE = 108
    Runtime.HIGH_FIVE_OFFER_SECONDS = 8
    Runtime.HIGH_FIVE_COOLDOWN = 1.1
    Runtime.HIGH_FIVE_START_DELAY = 0.12
    Runtime.HIGH_FIVE_ANIMATION_SECONDS = 0.95
    Runtime.HIGH_FIVE_NOTICE_SECONDS = 4
    Runtime.PROTOCOL_REJECTION_INTERVAL = 1
    Runtime.NETWORK_CLEANUP_ERROR =
        "Network cleanup could not be verified; restart the game before starting another session."

    function Runtime.urgentWorkshopSafety(resourceId, action, arguments)
        resourceId = Runtime.MachineResource.parse(resourceId) or resourceId
        if action == "emergency_stop" then
            return resourceId == "cutter" or resourceId == "windmill"
        end
        return resourceId == "cutter" and action == "set_barrier"
            and type(arguments) == "table" and arguments.barrierClear == false
    end

    function Runtime.defaultClock()
        if love and love.timer and love.timer.getTime then return love.timer.getTime() end
        return os.clock()
    end

    function Runtime.finite(value)
        return type(value) == "number" and value == value
            and value ~= math.huge and value ~= -math.huge
    end

    function Runtime.clamp(value, minimum, maximum)
        value = tonumber(value) or 0
        return math.max(minimum, math.min(maximum, value))
    end

    function Runtime.countEntries(values)
        local count = 0
        for _ in pairs(values or {}) do count = count + 1 end
        return count
    end

    function Runtime.directDisplayName(value)
        if type(value) ~= "string" or #value < 1 or #value > Runtime.Protocol.MAX_NAME_BYTES then
            return nil
        end
        -- Direct join names are self-asserted and cross an Internet trust boundary.
        -- Keep the first approval UI deliberately ASCII-only so malformed UTF-8,
        -- bidi controls, and invisible formatting cannot spoof another worker.
        for index = 1, #value do
            local byte = value:byte(index)
            if byte < 32 or byte > 126 then return nil end
        end
        return value
    end

    function Runtime.sameHello(left, right)
        return type(left) == "table" and type(right) == "table"
            and left.clientNonce == right.clientNonce
            and left.name == right.name
            and left.character == right.character
            and (left.furColorway or 1) == (right.furColorway or 1)
            and (left.overallsColorway or 1) == (right.overallsColorway or 1)
    end

    function Runtime.removePeerItems(items, peer)
        local kept = {}
        for _, item in ipairs(items or {}) do
            if item.peer ~= peer then kept[#kept + 1] = item end
        end
        return kept
    end

    function Runtime.wireWorkshopView(resourceId, view)
        if type(view) ~= "table" then return view end
        resourceId = Runtime.MachineResource.parse(resourceId) or resourceId
        if resourceId == "reception_customer" and type(view.quoteRows) == "table" then
            if not Runtime.Codec.isArray(view.quoteRows) then
                view.quoteRows = Runtime.Codec.array(view.quoteRows)
            end
        elseif (resourceId == "vendor" or resourceId == "truck")
            and type(view.items) == "table"
        then
            if not Runtime.Codec.isArray(view.items) then view.items = Runtime.Codec.array(view.items) end
        elseif resourceId == "skid_wrapper" and type(view.pallets) == "table" then
            if not Runtime.Codec.isArray(view.pallets) then
                view.pallets = Runtime.Codec.array(view.pallets)
            end
        elseif resourceId == "cutter" then
            if type(view.memoryCentiInch) == "table"
                and not Runtime.Codec.isArray(view.memoryCentiInch)
            then
                view.memoryCentiInch = Runtime.Codec.array(view.memoryCentiInch)
            end
            if type(view.candidates) == "table" and not Runtime.Codec.isArray(view.candidates) then
                view.candidates = Runtime.Codec.array(view.candidates)
            end
            if type(view.serviceItems) == "table" and not Runtime.Codec.isArray(view.serviceItems) then
                view.serviceItems = Runtime.Codec.array(view.serviceItems)
            end
        elseif resourceId == "windmill" then
            if type(view.setupPermille) == "table" and not Runtime.Codec.isArray(view.setupPermille) then
                view.setupPermille = Runtime.Codec.array(view.setupPermille)
            end
            if type(view.candidates) == "table" and not Runtime.Codec.isArray(view.candidates) then
                view.candidates = Runtime.Codec.array(view.candidates)
            end
        end
        return view
    end

    function Runtime.identifier(prefix, clock)
        local seconds = math.floor((clock() or 0) * 1000) % 0x7fffffff
        local random = math.random(0, 0x7fffffff)
        return string.format("%s%08x%08x", prefix, seconds, random)
    end

    function Runtime.newPlayer(record)
        record = record or {}
        return {
            id = tonumber(record.id),
            name = record.name or "Worker",
            character = record.character or "rabbit-worker",
            furColorway = tonumber(record.furColorway) or 1,
            overallsColorway = tonumber(record.overallsColorway) or 1,
            x = tonumber(record.x) or 0,
            y = tonumber(record.y) or 0,
            speed = tonumber(record.speed) or 0,
            velocityX = tonumber(record.velocityX) or 0,
            velocityY = tonumber(record.velocityY) or 0,
            intentX = tonumber(record.intentX) or 1,
            intentY = tonumber(record.intentY) or 0,
            moving = record.moving == true,
            facing = record.facing == -1 and -1 or 1,
            animationDistance = tonumber(record.animationDistance) or 0,
            idleClock = tonumber(record.idleClock) or 0,
            interactionClock = 0,
            lastInteractionRequestId = 0,
            lastInteractionResult = nil,
            lastInteractionFingerprint = nil,
            lastInteractionAt = -math.huge,
            lastInteractionDuplicateReplyAt = -math.huge,
            lastInteractionRejectReplyAt = -math.huge,
            inputSequence = tonumber(record.inputSequence) or 0,
            _targetX = tonumber(record.x) or 0,
            _targetY = tonumber(record.y) or 0,
        }
    end

    function Runtime.copyMotion(target, source, includePosition)
        if not target or not source then return end
        if includePosition then
            if Runtime.finite(source.x) then target.x = source.x end
            if Runtime.finite(source.y) then target.y = source.y end
        end
        if Runtime.finite(source.velocityX) then target.velocityX = source.velocityX end
        if Runtime.finite(source.velocityY) then target.velocityY = source.velocityY end
        if Runtime.finite(source.intentX) then target.intentX = source.intentX end
        if Runtime.finite(source.intentY) then target.intentY = source.intentY end
        if Runtime.finite(source.animationDistance) then target.animationDistance = source.animationDistance end
        if source.facing == -1 or source.facing == 1 then target.facing = source.facing end
        if type(source.moving) == "boolean" then target.moving = source.moving end
        if type(source.character) == "string" then target.character = source.character end
        if Runtime.finite(source.furColorway) then target.furColorway = source.furColorway end
        if Runtime.finite(source.overallsColorway) then target.overallsColorway = source.overallsColorway end
    end

    function Runtime.playerRecord(player)
        return {
            id = tonumber(player.id),
            name = tostring(player.name or "Worker"),
            x = tonumber(player.x) or 0,
            y = tonumber(player.y) or 0,
            velocityX = tonumber(player.velocityX) or 0,
            velocityY = tonumber(player.velocityY) or 0,
            intentX = tonumber(player.intentX) or 0,
            intentY = tonumber(player.intentY) or 0,
            moving = player.moving == true,
            facing = player.facing == -1 and -1 or 1,
            animationDistance = tonumber(player.animationDistance) or 0,
            character = tostring(player.character or "rabbit-worker"),
            furColorway = tonumber(player.furColorway) or 1,
            overallsColorway = tonumber(player.overallsColorway) or 1,
            inputSequence = tonumber(player.inputSequence) or 0,
        }
    end
end

return Component
