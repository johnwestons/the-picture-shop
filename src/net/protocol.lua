local Codec = require("src.net.codec")
local OfficeIntent = require("src.office_intent")
local MachinePose = require("src.machine_pose")
local WarehouseIntent = require("src.warehouse_intent")
local Forklift = require("src.forklift")

local Protocol = {
    VERSION = 19,
    MAX_PACKET_BYTES = 1200,
    MAX_SHOP_SNAPSHOT_BYTES = 512 * 1024,
    MAX_PLAYERS = 4,
    MAX_EVENTS_PER_UPDATE = 64,
    CHANNEL_CONTROL = 0,
    CHANNEL_STATE = 1,
    CHANNEL_DURABLE = 2,
    CHANNEL_COUNT = 3,
    MAX_NAME_BYTES = 24,
}

Protocol.CHANNELS = {
    control = Protocol.CHANNEL_CONTROL,
    state = Protocol.CHANNEL_STATE,
    durable = Protocol.CHANNEL_DURABLE,
}

local UINT32_MAX = 4294967295
local MAX_TOKEN_BYTES = 64
local MAX_CHARACTER_BYTES = 48
local MAX_REASON_BYTES = 96
local MAX_ERROR_CODE_BYTES = 32
local MAX_ERROR_MESSAGE_BYTES = 160
local MAX_COORDINATE = 100000
local MAX_VELOCITY = 10000
local MAX_ANIMATION_DISTANCE = 1000000000
local MAX_WORKSHOP_AMOUNT = 100000000
local MAX_WORKSHOP_VIEW_TEXT_BYTES = 96
local MAX_WORKSHOP_CYCLE_TIME = 600
local MAX_WORKSHOP_DISTANCE = 100000
local MAX_WORKSHOP_INVENTORY = 100000
local MAX_WINDMILL_ID_BYTES = 24
local MAX_WINDMILL_VIEW_TEXT_TOTAL_BYTES = 96

local REALTIME_CODEC_LIMITS = {
    maxBytes = Protocol.MAX_PACKET_BYTES,
    maxDepth = 8,
    maxEntries = 128,
    -- Typed office messages are bounded to 600 bytes; other fields keep their
    -- narrower per-message schema limits below. The packet cap stays 1,200.
    maxStringBytes = 600,
    maxNumberBytes = 32,
}

local SHOP_CODEC_LIMITS = {
    maxBytes = Protocol.MAX_SHOP_SNAPSHOT_BYTES,
    maxDepth = 32,
    maxEntries = 32768,
    maxStringBytes = 128 * 1024,
    maxNumberBytes = 32,
}

local ROUTES = {
    hello = { channel = Protocol.CHANNEL_CONTROL, delivery = "reliable" },
    welcome = { channel = Protocol.CHANNEL_CONTROL, delivery = "reliable" },
    shop_snapshot = { channel = Protocol.CHANNEL_DURABLE, delivery = "reliable" },
    shop_state = { channel = Protocol.CHANNEL_DURABLE, delivery = "reliable" },
    interaction_request = { channel = Protocol.CHANNEL_CONTROL, delivery = "reliable" },
    interaction_result = { channel = Protocol.CHANNEL_CONTROL, delivery = "reliable" },
    workshop_acquire = { channel = Protocol.CHANNEL_CONTROL, delivery = "reliable" },
    workshop_grant = { channel = Protocol.CHANNEL_CONTROL, delivery = "reliable" },
    workshop_command = { channel = Protocol.CHANNEL_CONTROL, delivery = "reliable" },
    workshop_result = { channel = Protocol.CHANNEL_CONTROL, delivery = "reliable" },
    workshop_release = { channel = Protocol.CHANNEL_CONTROL, delivery = "reliable" },
    workshop_snapshot = { channel = Protocol.CHANNEL_STATE, delivery = "unreliable" },
    cutter_snapshot = { channel = Protocol.CHANNEL_STATE, delivery = "unreliable" },
    windmill_snapshot = { channel = Protocol.CHANNEL_STATE, delivery = "unreliable" },
    pallet_jack_snapshot = { channel = Protocol.CHANNEL_STATE, delivery = "unreliable" },
    forklift_snapshot = { channel = Protocol.CHANNEL_STATE, delivery = "unreliable" },
    input = { channel = Protocol.CHANNEL_STATE, delivery = "unreliable" },
    snapshot = { channel = Protocol.CHANNEL_STATE, delivery = "unreliable" },
    visitor_snapshot = { channel = Protocol.CHANNEL_STATE, delivery = "unreliable" },
    environment_snapshot = { channel = Protocol.CHANNEL_STATE, delivery = "unreliable" },
    ping = { channel = Protocol.CHANNEL_STATE, delivery = "unreliable" },
    pong = { channel = Protocol.CHANNEL_STATE, delivery = "unreliable" },
    leave = { channel = Protocol.CHANNEL_CONTROL, delivery = "reliable" },
    error = { channel = Protocol.CHANNEL_CONTROL, delivery = "reliable" },
}

Protocol.MESSAGE_TYPES = {
    "hello", "welcome", "shop_snapshot", "shop_state", "interaction_request",
    "interaction_result", "workshop_acquire", "workshop_grant", "workshop_command",
    "workshop_result", "workshop_release", "workshop_snapshot", "cutter_snapshot",
    "windmill_snapshot", "pallet_jack_snapshot", "forklift_snapshot", "input", "snapshot",
    "visitor_snapshot", "environment_snapshot", "ping", "pong", "leave", "error",
}

local function protocolError(message)
    return nil, "protocol: " .. message
end

local function shape(value, label, required, optional)
    if type(value) ~= "table" then return nil, label .. " must be a table" end
    local allowed = {}
    for _, name in ipairs(required) do allowed[name] = true end
    for _, name in ipairs(optional or {}) do allowed[name] = true end
    for key in next, value do
        if type(key) ~= "string" or not allowed[key] then
            return nil, label .. " has unknown field: " .. tostring(key)
        end
    end
    for _, name in ipairs(required) do
        if value[name] == nil then return nil, label .. " is missing field: " .. name end
    end
    return true
end

local function integerInRange(value, minimum, maximum, label)
    if type(value) ~= "number" or value ~= math.floor(value)
        or value < minimum or value > maximum
    then
        return nil, label .. " is out of range"
    end
    return value
end

local function numberInRange(value, minimum, maximum, label)
    if type(value) ~= "number" or value ~= value
        or value == math.huge or value == -math.huge
        or value < minimum or value > maximum
    then
        return nil, label .. " is out of range"
    end
    return value
end

local function printableString(value, minimumBytes, maximumBytes, label)
    if type(value) ~= "string" or #value < minimumBytes or #value > maximumBytes then
        return nil, label .. " has invalid length"
    end
    for index = 1, #value do
        local byte = value:byte(index)
        if byte < 32 or byte == 127 then return nil, label .. " contains control bytes" end
    end
    return value
end

local function token(value, maximumBytes, label)
    local valid, stringError = printableString(value, 1, maximumBytes, label)
    if not valid then return nil, stringError end
    if not value:match("^[A-Za-z0-9][A-Za-z0-9_.%-]*$") then
        return nil, label .. " contains unsupported characters"
    end
    return value
end

local function characterToken(value, label)
    local valid, stringError = printableString(value, 1, MAX_CHARACTER_BYTES, label)
    if not valid then return nil, stringError end
    if not value:match("^[a-z0-9][a-z0-9_%-]*$") then
        return nil, label .. " contains unsupported characters"
    end
    return value
end

local PLAYER_FIELDS = {
    "id", "name", "x", "y", "velocityX", "velocityY", "intentX", "intentY",
    "moving", "facing", "animationDistance", "character", "inputSequence",
}

local function normalizePlayer(value, label)
    local valid, shapeError = shape(value, label, PLAYER_FIELDS)
    if not valid then return nil, shapeError end
    local id, fieldError = integerInRange(value.id, 1, Protocol.MAX_PLAYERS, label .. ".id")
    if not id then return nil, fieldError end
    local name
    name, fieldError = printableString(value.name, 1, Protocol.MAX_NAME_BYTES, label .. ".name")
    if not name then return nil, fieldError end
    local x
    x, fieldError = numberInRange(value.x, -MAX_COORDINATE, MAX_COORDINATE, label .. ".x")
    if not x then return nil, fieldError end
    local y
    y, fieldError = numberInRange(value.y, -MAX_COORDINATE, MAX_COORDINATE, label .. ".y")
    if not y then return nil, fieldError end
    local velocityX
    velocityX, fieldError = numberInRange(
        value.velocityX, -MAX_VELOCITY, MAX_VELOCITY, label .. ".velocityX")
    if not velocityX then return nil, fieldError end
    local velocityY
    velocityY, fieldError = numberInRange(
        value.velocityY, -MAX_VELOCITY, MAX_VELOCITY, label .. ".velocityY")
    if not velocityY then return nil, fieldError end
    local intentX
    intentX, fieldError = numberInRange(value.intentX, -1, 1, label .. ".intentX")
    if not intentX then return nil, fieldError end
    local intentY
    intentY, fieldError = numberInRange(value.intentY, -1, 1, label .. ".intentY")
    if not intentY then return nil, fieldError end
    if type(value.moving) ~= "boolean" then return nil, label .. ".moving must be boolean" end
    if value.facing ~= -1 and value.facing ~= 1 then return nil, label .. ".facing must be -1 or 1" end
    local animationDistance
    animationDistance, fieldError = numberInRange(
        value.animationDistance, 0, MAX_ANIMATION_DISTANCE, label .. ".animationDistance")
    if not animationDistance then return nil, fieldError end
    local character
    character, fieldError = characterToken(value.character, label .. ".character")
    if not character then return nil, fieldError end
    local inputSequence
    inputSequence, fieldError = integerInRange(
        value.inputSequence, 0, UINT32_MAX, label .. ".inputSequence")
    if not inputSequence then return nil, fieldError end

    return {
        id = id,
        name = name,
        x = x,
        y = y,
        velocityX = velocityX,
        velocityY = velocityY,
        intentX = intentX,
        intentY = intentY,
        moving = value.moving,
        facing = value.facing,
        animationDistance = animationDistance,
        character = character,
        inputSequence = inputSequence,
    }
end

local function normalizePlayers(value, label)
    if not Codec.isArray(value) then return nil, label .. " must be an array" end
    if #value < 1 or #value > Protocol.MAX_PLAYERS then
        return nil, label .. " must contain between 1 and " .. Protocol.MAX_PLAYERS .. " players"
    end
    local players, seen = {}, {}
    for index = 1, #value do
        local player, playerError = normalizePlayer(value[index], label .. "[" .. index .. "]")
        if not player then return nil, playerError end
        if seen[player.id] then return nil, label .. " contains a duplicate player id" end
        seen[player.id] = true
        players[#players + 1] = player
    end
    table.sort(players, function(a, b) return a.id < b.id end)
    return Codec.array(players)
end

local function normalizeHello(payload)
    local valid, shapeError = shape(payload, "hello payload",
        { "clientNonce", "name", "character" })
    if not valid then return nil, shapeError end
    local clientNonce, fieldError = token(payload.clientNonce, MAX_TOKEN_BYTES, "hello.clientNonce")
    if not clientNonce then return nil, fieldError end
    local name
    name, fieldError = printableString(payload.name, 1, Protocol.MAX_NAME_BYTES, "hello.name")
    if not name then return nil, fieldError end
    local character
    character, fieldError = characterToken(payload.character, "hello.character")
    if not character then return nil, fieldError end
    return { clientNonce = clientNonce, name = name, character = character }
end

local function normalizeWelcome(payload)
    local valid, shapeError = shape(payload, "welcome payload",
        { "sessionId", "playerId", "serverTick", "players" })
    if not valid then return nil, shapeError end
    local sessionId, fieldError = token(payload.sessionId, MAX_TOKEN_BYTES, "welcome.sessionId")
    if not sessionId then return nil, fieldError end
    local playerId
    playerId, fieldError = integerInRange(
        payload.playerId, 1, Protocol.MAX_PLAYERS, "welcome.playerId")
    if not playerId then return nil, fieldError end
    local serverTick
    serverTick, fieldError = integerInRange(payload.serverTick, 0, UINT32_MAX, "welcome.serverTick")
    if not serverTick then return nil, fieldError end
    local players
    players, fieldError = normalizePlayers(payload.players, "welcome.players")
    if not players then return nil, fieldError end
    local assignedPresent = false
    for _, player in ipairs(players) do
        if player.id == playerId then assignedPresent = true; break end
    end
    if not assignedPresent then return nil, "welcome.playerId is absent from welcome.players" end
    return {
        sessionId = sessionId,
        playerId = playerId,
        serverTick = serverTick,
        players = players,
    }
end

local function normalizeShopSnapshot(payload)
    local valid, shapeError = shape(payload, "shop_snapshot payload",
        { "sessionId", "revision", "state", "player" })
    if not valid then return nil, shapeError end
    local sessionId, fieldError = token(
        payload.sessionId, MAX_TOKEN_BYTES, "shop_snapshot.sessionId")
    if not sessionId then return nil, fieldError end
    local revision
    revision, fieldError = integerInRange(
        payload.revision, 0, UINT32_MAX, "shop_snapshot.revision")
    if not revision then return nil, fieldError end
    if type(payload.state) ~= "table" then return nil, "shop_snapshot.state must be a table" end
    if type(payload.player) ~= "table" then return nil, "shop_snapshot.player must be a table" end
    return {
        sessionId = sessionId,
        revision = revision,
        state = payload.state,
        player = payload.player,
    }
end

local function normalizeShopState(payload)
    local valid, shapeError = shape(payload, "shop_state payload",
        { "sessionId", "revision", "state" })
    if not valid then return nil, shapeError end
    local sessionId, fieldError = token(
        payload.sessionId, MAX_TOKEN_BYTES, "shop_state.sessionId")
    if not sessionId then return nil, fieldError end
    local revision
    revision, fieldError = integerInRange(
        payload.revision, 1, UINT32_MAX, "shop_state.revision")
    if not revision then return nil, fieldError end
    if type(payload.state) ~= "table" then return nil, "shop_state.state must be a table" end
    return { sessionId = sessionId, revision = revision, state = payload.state }
end

local NETWORK_INTERACTION_KINDS = {
    loadingBayDoor = true,
    truckCargoDoor = true,
}

local INTERACTION_DOOR_STATES = {
    closed = true,
    open = true,
}

local function interactionKind(value, label)
    if type(value) ~= "string" or not NETWORK_INTERACTION_KINDS[value] then
        return nil, label .. " is not allowed"
    end
    return value
end

local function normalizeInteractionRequest(payload)
    local valid, shapeError = shape(payload, "interaction_request payload",
        { "sessionId", "requestId", "targetKind", "desiredState" })
    if not valid then return nil, shapeError end
    local sessionId, fieldError = token(
        payload.sessionId, MAX_TOKEN_BYTES, "interaction_request.sessionId")
    if not sessionId then return nil, fieldError end
    local requestId
    requestId, fieldError = integerInRange(
        payload.requestId, 1, UINT32_MAX, "interaction_request.requestId")
    if not requestId then return nil, fieldError end
    local targetKind
    targetKind, fieldError = interactionKind(
        payload.targetKind, "interaction_request.targetKind")
    if not targetKind then return nil, fieldError end
    if type(payload.desiredState) ~= "string"
        or not INTERACTION_DOOR_STATES[payload.desiredState]
    then
        return nil, "interaction_request.desiredState is invalid"
    end
    return {
        sessionId = sessionId,
        requestId = requestId,
        targetKind = targetKind,
        desiredState = payload.desiredState,
    }
end

local function normalizeInteractionResult(payload)
    local valid, shapeError = shape(payload, "interaction_result payload",
        { "sessionId", "requestId", "targetKind", "accepted", "code", "message" })
    if not valid then return nil, shapeError end
    local sessionId, fieldError = token(
        payload.sessionId, MAX_TOKEN_BYTES, "interaction_result.sessionId")
    if not sessionId then return nil, fieldError end
    local requestId
    requestId, fieldError = integerInRange(
        payload.requestId, 1, UINT32_MAX, "interaction_result.requestId")
    if not requestId then return nil, fieldError end
    local targetKind
    targetKind, fieldError = interactionKind(
        payload.targetKind, "interaction_result.targetKind")
    if not targetKind then return nil, fieldError end
    if type(payload.accepted) ~= "boolean" then
        return nil, "interaction_result.accepted must be boolean"
    end
    local code
    code, fieldError = token(payload.code, MAX_ERROR_CODE_BYTES, "interaction_result.code")
    if not code then return nil, fieldError end
    local message
    message, fieldError = printableString(
        payload.message, 1, MAX_ERROR_MESSAGE_BYTES, "interaction_result.message")
    if not message then return nil, fieldError end
    return {
        sessionId = sessionId,
        requestId = requestId,
        targetKind = targetKind,
        accepted = payload.accepted,
        code = code,
        message = message,
    }
end

local WORKSHOP_RESOURCES = {
    warehouse = true,
    work_phone = true,
    reception_customer = true,
    vendor = true,
    truck = true,
    office_computer = true,
    skid_wrapper = true,
    pallet_jack = true,
    cutter = true,
    windmill = true,
}

local WORKSHOP_ACTION_ARGUMENTS = {
    warehouse = { warehouse_action = "warehouseIntent" },
    reception_customer = {
        request_details = false,
        submit_quote = "amount",
        decline = false,
    },
    vendor = {
        purchase_stock = "itemIndex",
        purchase_machine = "itemIndex",
        dismiss = false,
    },
    truck = {
        move_item = "itemIndex",
        page_next = false,
        page_previous = false,
        close_truck = false,
    },
    office_computer = {
        request_pickup = "jobId",
        office_action = "officeIntent",
    },
    work_phone = { phone_answer = "callId", phone_respond = "callId", phone_dismiss = "callId" },
    skid_wrapper = {
        select_pallet = "palletId",
        start_cycle = "palletId",
        begin_service = false,
        service_target = "itemIndex",
        service_miss = false,
        cancel_service = false,
    },
    pallet_jack = {
        warehouse_action = "warehouseIntent",
        lift_pallet = "palletId",
        lower_pallet = "palletId",
        park_jack = false,
        move_machine = "machineIndex",
        rotate_machine = false,
        place_machine = "placementCell",
    },
    cutter = {
        load_pallet = "palletId",
        load_stock = false,
        select_program = "programIndex",
        set_gauge = "gaugeCentiInch",
        auto_gauge = false,
        save_gauge = false,
        recall_gauge = false,
        rotate_paper = false,
        position_paper = false,
        set_clamp = "clamp",
        set_barrier = "barrierClear",
        guarded_cut = false,
        emergency_stop = false,
        reset_safety = false,
        return_to_pallet = false,
        run_next_lift = false,
        begin_lubrication = false,
        service_advance = false,
        service_view = "itemIndex",
        service_tool = "itemIndex",
        service_point = "itemIndex",
        service_pump = false,
        service_gear = false,
        finish_lubrication = false,
        cancel_service = false,
        begin_blade = false,
        remove_blade_bolt = "itemIndex",
        lift_blade = false,
        sleeve_blade = false,
        book_blade_technician = false,
        set_weekly_technician = "enabled",
    },
    windmill = {
        load_pallet = "palletId",
        toggle_motor = false,
        toggle_feeder = false,
        toggle_impression = false,
        speed_up = false,
        speed_down = false,
        emergency_stop = false,
        reset_safety = false,
        take_proof = false,
        verify_artwork = false,
        approve_proof = false,
        start_run = false,
        stop_run = false,
        clean_unload = false,
        order_plate = "plateId",
        begin_plate = "plateId",
        process_plate = "plateId",
        begin_setup = "setupTask",
        setup_action = "setupAction",
        cancel_setup = false,
        begin_service = false,
        service_lockout = false,
        service_task = false,
        book_technician = false,
    },
}

local WORKSHOP_RELEASE_REASONS = {
    closed = true,
    cancelled = true,
}

local WORKSHOP_PACKAGING = {
    flat = true,
    boxed = true,
}

local WORKSHOP_WRAPPER_STEPS = {
    idle = true,
    wrapping = true,
    finished = true,
}

local WORKSHOP_WRAPPER_SERVICE_TASKS = {
    turntableBearing = 3,
    filmCarriage = 3,
    driveBelt = 1,
    controlBoard = 3,
}

local WORKSHOP_TRUCK_MODES = {
    delivery = true,
    vendor_delivery = true,
    machine_delivery = true,
    pickup = true,
}

local WORKSHOP_TRUCK_STATES = {
    parked_closed = true,
    cargo_open = true,
    cargo_closing = true,
    departing = true,
}

local WORKSHOP_CUTTER_STEPS = {
    idle = true,
    loading = true,
    loaded = true,
    positioning = true,
    positioned = true,
    clamped = true,
    armed = true,
    cutting = true,
    cut_complete = true,
    lift_returning = true,
    repeat_ready = true,
    unloading = true,
    finished = true,
    blocked = true,
    resetting = true,
}

local WORKSHOP_CUTTER_SERVICE_STEPS = {
    idle = true,
    lockout_disconnect = true,
    lockout_key = true,
    lockout_tag = true,
    prep_cartridge = true,
    prep_prime = true,
    lubricate = true,
    blade_bolts = true,
    blade_lift = true,
    blade_sleeve = true,
}

local WORKSHOP_CUTTER_ORIENTATIONS = {
    [0] = true,
    [90] = true,
    [180] = true,
    [270] = true,
}

local WORKSHOP_CUTTER_PAPER_STATUSES = {
    uncut = true,
    in_process = true,
    complete = true,
}

local WORKSHOP_CUTTER_EDGES = {
    right = true,
    bottom = true,
    left = true,
    top = true,
}

local WORKSHOP_WINDMILL_STATUSES = {
    idle = true,
    setup = true,
    proof = true,
    approved = true,
    production = true,
    pass_complete = true,
    stock_shortage = true,
    stopped = true,
}

local WORKSHOP_WINDMILL_SETUP_TASKS = {
    chase = true,
    packing = true,
    rollers = true,
    ink = true,
    feeder = true,
    register = true,
}

local WORKSHOP_WINDMILL_SETUP_ACTIONS = {
    align = true,
    square = true,
    tighten = true,
    layer = true,
    smooth = true,
    clamp = true,
    left_down = true,
    left_up = true,
    right_down = true,
    right_up = true,
    key_1 = true,
    key_2 = true,
    key_3 = true,
    ductor = true,
    prepare = true,
    suction_down = true,
    suction_up = true,
    air_down = true,
    air_up = true,
    test = true,
    left = true,
    right = true,
    up = true,
    down = true,
}

local WORKSHOP_WINDMILL_SERVICE_STEPS = {
    idle = true,
    lockout_disconnect = true,
    lockout_key = true,
    lockout_tag = true,
    task = true,
}

local function workshopResource(value, label)
    if type(value) ~= "string" or not WORKSHOP_RESOURCES[value] then
        return nil, label .. " is not allowed"
    end
    return value
end

local function workshopAction(value, resourceId, label)
    local actions = WORKSHOP_ACTION_ARGUMENTS[resourceId]
    if type(value) ~= "string" or not actions or actions[value] == nil then
        return nil, label .. " is not allowed for " .. tostring(resourceId)
    end
    return value, actions[value]
end

local function workshopPackaging(value, label)
    if type(value) ~= "string" or not WORKSHOP_PACKAGING[value] then
        return nil, label .. " is invalid"
    end
    return value
end

local function normalizeWorkshopSize(value, label)
    local valid, shapeError = shape(value, label, { "width", "height" })
    if not valid then return nil, shapeError end
    local width, fieldError = numberInRange(value.width, 0.01, 1000, label .. ".width")
    if not width then return nil, fieldError end
    local height
    height, fieldError = numberInRange(value.height, 0.01, 1000, label .. ".height")
    if not height then return nil, fieldError end
    return { width = width, height = height }
end

local function normalizeWorkshopQuoteRows(value, printJob, label)
    if not Codec.isArray(value) then return nil, label .. " must be an array" end
    if #value < 1 or #value > 5 then
        return nil, label .. " must contain between 1 and 5 rows"
    end
    local rows, seen = {}, {}
    for index = 1, #value do
        local rowLabel = label .. "[" .. index .. "]"
        local required = printJob
            and { "number", "sheetCount", "requiredLifts", "requestedCopies", "spoilageAllowance" }
            or { "number", "sheetCount", "requiredLifts", "price" }
        local valid, shapeError = shape(value[index], rowLabel, required)
        if not valid then return nil, shapeError end
        local number, fieldError = integerInRange(value[index].number, 1, 5, rowLabel .. ".number")
        if not number then return nil, fieldError end
        if seen[number] then return nil, label .. " contains a duplicate row number" end
        seen[number] = true
        local sheetCount
        sheetCount, fieldError = integerInRange(
            value[index].sheetCount, 1, 3000, rowLabel .. ".sheetCount")
        if not sheetCount then return nil, fieldError end
        local requiredLifts
        requiredLifts, fieldError = integerInRange(
            value[index].requiredLifts, 1, 1000, rowLabel .. ".requiredLifts")
        if not requiredLifts then return nil, fieldError end
        local row = {
            number = number,
            sheetCount = sheetCount,
            requiredLifts = requiredLifts,
        }
        if printJob then
            row.requestedCopies, fieldError = integerInRange(
                value[index].requestedCopies, 1, 3000, rowLabel .. ".requestedCopies")
            if not row.requestedCopies then return nil, fieldError end
            row.spoilageAllowance, fieldError = integerInRange(
                value[index].spoilageAllowance, 0, 3000, rowLabel .. ".spoilageAllowance")
            if row.spoilageAllowance == nil then return nil, fieldError end
            if row.requestedCopies + row.spoilageAllowance ~= sheetCount then
                return nil, rowLabel .. " copy counts do not match sheetCount"
            end
        else
            row.price, fieldError = numberInRange(
                value[index].price, 0, MAX_WORKSHOP_AMOUNT, rowLabel .. ".price")
            if row.price == nil then return nil, fieldError end
        end
        rows[#rows + 1] = row
    end
    table.sort(rows, function(a, b) return a.number < b.number end)
    for index, row in ipairs(rows) do
        if row.number ~= index then return nil, label .. " row numbers must be contiguous" end
    end
    return Codec.array(rows)
end

local function normalizeReceptionWorkshopView(value, label)
    local valid, shapeError = shape(value, label, {
        "jobId", "company", "sourceSize", "finishedSize", "stock", "packaging",
        "delivery", "artworkKey", "artworkName", "printJob", "quoteRows",
        "recommendedTotal",
    }, { "colorCount", "colorSequence" })
    if not valid then return nil, shapeError end
    local jobId, fieldError = token(value.jobId, MAX_TOKEN_BYTES, label .. ".jobId")
    if not jobId then return nil, fieldError end
    local company
    company, fieldError = printableString(
        value.company, 1, MAX_WORKSHOP_VIEW_TEXT_BYTES, label .. ".company")
    if not company then return nil, fieldError end
    local sourceSize
    sourceSize, fieldError = normalizeWorkshopSize(value.sourceSize, label .. ".sourceSize")
    if not sourceSize then return nil, fieldError end
    local finishedSize
    finishedSize, fieldError = normalizeWorkshopSize(value.finishedSize, label .. ".finishedSize")
    if not finishedSize then return nil, fieldError end
    local stock
    stock, fieldError = printableString(
        value.stock, 1, MAX_WORKSHOP_VIEW_TEXT_BYTES, label .. ".stock")
    if not stock then return nil, fieldError end
    local packaging
    packaging, fieldError = workshopPackaging(value.packaging, label .. ".packaging")
    if not packaging then return nil, fieldError end
    local delivery
    delivery, fieldError = printableString(
        value.delivery, 1, MAX_WORKSHOP_VIEW_TEXT_BYTES, label .. ".delivery")
    if not delivery then return nil, fieldError end
    local artworkKey
    artworkKey, fieldError = token(value.artworkKey, MAX_TOKEN_BYTES, label .. ".artworkKey")
    if not artworkKey then return nil, fieldError end
    local artworkName
    artworkName, fieldError = printableString(
        value.artworkName, 1, MAX_WORKSHOP_VIEW_TEXT_BYTES, label .. ".artworkName")
    if not artworkName then return nil, fieldError end
    if type(value.printJob) ~= "boolean" then return nil, label .. ".printJob must be boolean" end
    local colorCount,colorSequence
    if value.colorCount~=nil then
        colorCount,fieldError=integerInRange(value.colorCount,1,4,label..".colorCount")
        if not colorCount or not value.printJob then return nil,fieldError or "Unexpected press colors." end
    end
    if value.colorSequence~=nil then
        colorSequence,fieldError=printableString(value.colorSequence,1,96,label..".colorSequence")
        if not colorSequence or not value.printJob then return nil,fieldError or "Unexpected press colors." end
    end
    local quoteRows
    quoteRows, fieldError = normalizeWorkshopQuoteRows(
        value.quoteRows, value.printJob, label .. ".quoteRows")
    if not quoteRows then return nil, fieldError end
    local recommendedTotal
    recommendedTotal, fieldError = numberInRange(
        value.recommendedTotal, 0, MAX_WORKSHOP_AMOUNT, label .. ".recommendedTotal")
    if recommendedTotal == nil then return nil, fieldError end
    return {
        jobId = jobId,
        company = company,
        sourceSize = sourceSize,
        finishedSize = finishedSize,
        stock = stock,
        packaging = packaging,
        delivery = delivery,
        artworkKey = artworkKey,
        artworkName = artworkName,
        printJob = value.printJob,
        colorCount = colorCount,
        colorSequence = colorSequence,
        quoteRows = quoteRows,
        recommendedTotal = recommendedTotal,
    }
end

local function normalizeWorkshopWrapperRuntimeFields(value, label)
    if type(value.step) ~= "string" or not WORKSHOP_WRAPPER_STEPS[value.step] then
        return nil, label .. ".step is invalid"
    end
    local cycleTime, fieldError = numberInRange(
        value.cycleTime, 0.01, MAX_WORKSHOP_CYCLE_TIME, label .. ".cycleTime")
    if not cycleTime then return nil, fieldError end
    local progress
    progress, fieldError = numberInRange(
        value.progress, 0, MAX_WORKSHOP_CYCLE_TIME, label .. ".progress")
    if progress == nil then return nil, fieldError end
    if progress > cycleTime then return nil, label .. ".progress exceeds cycleTime" end
    local selectedPalletId
    if value.selectedPalletId ~= nil then
        selectedPalletId, fieldError = token(
            value.selectedPalletId, MAX_TOKEN_BYTES, label .. ".selectedPalletId")
        if not selectedPalletId then return nil, fieldError end
    end
    local palletId
    if value.palletId ~= nil then
        palletId, fieldError = token(value.palletId, MAX_TOKEN_BYTES, label .. ".palletId")
        if not palletId then return nil, fieldError end
    end
    if value.step == "idle" then
        if progress ~= 0 or palletId ~= nil then
            return nil, label .. " idle runtime cannot carry progress or an active pallet"
        end
    elseif value.step == "wrapping" then
        if not palletId or selectedPalletId ~= palletId or progress >= cycleTime then
            return nil, label .. " wrapping runtime is inconsistent"
        end
    elseif not palletId or selectedPalletId ~= palletId or progress ~= cycleTime then
        return nil, label .. " finished runtime is inconsistent"
    end
    return {
        step = value.step,
        progress = progress,
        cycleTime = cycleTime,
        selectedPalletId = selectedPalletId,
        palletId = palletId,
    }
end

local function normalizeWorkshopPallets(value, label)
    if not Codec.isArray(value) then return nil, label .. " must be an array" end
    if #value > 5 then return nil, label .. " must contain at most 5 pallets" end
    local pallets, seen = {}, {}
    for index = 1, #value do
        local palletLabel = label .. "[" .. index .. "]"
        local valid, shapeError = shape(value[index], palletLabel,
            { "palletId", "jobLabel", "packaging", "distance" })
        if not valid then return nil, shapeError end
        local palletId, fieldError = token(
            value[index].palletId, MAX_TOKEN_BYTES, palletLabel .. ".palletId")
        if not palletId then return nil, fieldError end
        if seen[palletId] then return nil, label .. " contains a duplicate palletId" end
        seen[palletId] = true
        local jobLabel
        jobLabel, fieldError = printableString(
            value[index].jobLabel, 1, MAX_WORKSHOP_VIEW_TEXT_BYTES,
            palletLabel .. ".jobLabel")
        if not jobLabel then return nil, fieldError end
        local packaging
        packaging, fieldError = workshopPackaging(
            value[index].packaging, palletLabel .. ".packaging")
        if not packaging then return nil, fieldError end
        local distance
        distance, fieldError = numberInRange(
            value[index].distance, 0, MAX_WORKSHOP_DISTANCE, palletLabel .. ".distance")
        if distance == nil then return nil, fieldError end
        pallets[#pallets + 1] = {
            palletId = palletId,
            jobLabel = jobLabel,
            packaging = packaging,
            distance = distance,
        }
    end
    return Codec.array(pallets)
end

local WRAPPER_SERVICE_FIELDS = {
    "serviceStep", "serviceTaskId", "serviceTaskIndex", "serviceTaskCount",
    "servicePhase", "serviceTargetCount", "serviceAttempts", "serviceMisses",
    "servicePermille",
}

local function normalizeWrapperService(value, runtime, pallets, label)
    if value.serviceStep == nil then
        for _, field in ipairs(WRAPPER_SERVICE_FIELDS) do
            if field ~= "serviceStep" and value[field] ~= nil then
                return nil, label .. "." .. field .. " requires an active serviceStep"
            end
        end
        return runtime
    end
    if value.serviceStep ~= "task" then
        return nil, label .. ".serviceStep is invalid"
    end
    if runtime.step ~= "idle" or runtime.progress ~= 0
        or runtime.selectedPalletId ~= nil or runtime.palletId ~= nil or #pallets ~= 0
    then
        return nil, label .. " active service requires an idle wrapper with an empty turntable"
    end
    local targetCount = WORKSHOP_WRAPPER_SERVICE_TASKS[value.serviceTaskId]
    if not targetCount then return nil, label .. ".serviceTaskId is invalid" end
    local fieldError
    runtime.serviceStep = "task"
    runtime.serviceTaskId = value.serviceTaskId
    runtime.serviceTaskIndex, fieldError = integerInRange(
        value.serviceTaskIndex, 1, 4, label .. ".serviceTaskIndex")
    if not runtime.serviceTaskIndex then return nil, fieldError end
    runtime.serviceTaskCount, fieldError = integerInRange(
        value.serviceTaskCount, 4, 4, label .. ".serviceTaskCount")
    if not runtime.serviceTaskCount then return nil, fieldError end
    runtime.servicePhase, fieldError = integerInRange(
        value.servicePhase, 1, targetCount, label .. ".servicePhase")
    if not runtime.servicePhase then return nil, fieldError end
    runtime.serviceTargetCount, fieldError = integerInRange(
        value.serviceTargetCount, targetCount, targetCount, label .. ".serviceTargetCount")
    if not runtime.serviceTargetCount then return nil, fieldError end
    runtime.serviceAttempts, fieldError = integerInRange(
        value.serviceAttempts, 0, 9999, label .. ".serviceAttempts")
    if runtime.serviceAttempts == nil then return nil, fieldError end
    runtime.serviceMisses, fieldError = integerInRange(
        value.serviceMisses, 0, runtime.serviceAttempts, label .. ".serviceMisses")
    if runtime.serviceMisses == nil then return nil, fieldError end
    if runtime.serviceAttempts < runtime.servicePhase - 1 then
        return nil, label .. ".serviceAttempts is inconsistent with servicePhase"
    end
    runtime.servicePermille, fieldError = integerInRange(
        value.servicePermille, 0, 999, label .. ".servicePermille")
    if runtime.servicePermille == nil then return nil, fieldError end
    return runtime
end

local function normalizeWorkshopWrapperRuntime(value, label)
    local valid, shapeError = shape(value, label,
        { "step", "progress", "cycleTime", "pallets" },
        { "selectedPalletId", "palletId", "serviceStep", "serviceTaskId",
            "serviceTaskIndex", "serviceTaskCount", "servicePhase",
            "serviceTargetCount", "serviceAttempts", "serviceMisses",
            "servicePermille" })
    if not valid then return nil, shapeError end
    local runtime, fieldError = normalizeWorkshopWrapperRuntimeFields(value, label)
    if not runtime then return nil, fieldError end
    local pallets
    pallets, fieldError = normalizeWorkshopPallets(value.pallets, label .. ".pallets")
    if not pallets then return nil, fieldError end
    runtime.pallets = pallets
    return normalizeWrapperService(value, runtime, pallets, label)
end

local function normalizeWrapperWorkshopView(value, label)
    local valid, shapeError = shape(value, label, {
        "step", "progress", "cycleTime", "plasticWrapRolls", "plasticWrapUses", "pallets",
    }, { "selectedPalletId", "palletId", "serviceStep", "serviceTaskId",
        "serviceTaskIndex", "serviceTaskCount", "servicePhase",
        "serviceTargetCount", "serviceAttempts", "serviceMisses",
        "servicePermille" })
    if not valid then return nil, shapeError end
    local runtime, fieldError = normalizeWorkshopWrapperRuntimeFields(value, label)
    if not runtime then return nil, fieldError end
    local plasticWrapRolls
    plasticWrapRolls, fieldError = integerInRange(
        value.plasticWrapRolls, 0, MAX_WORKSHOP_INVENTORY, label .. ".plasticWrapRolls")
    if plasticWrapRolls == nil then return nil, fieldError end
    local plasticWrapUses
    plasticWrapUses, fieldError = integerInRange(
        value.plasticWrapUses, 0, MAX_WORKSHOP_INVENTORY, label .. ".plasticWrapUses")
    if plasticWrapUses == nil then return nil, fieldError end
    local pallets
    pallets, fieldError = normalizeWorkshopPallets(value.pallets, label .. ".pallets")
    if not pallets then return nil, fieldError end
    runtime.plasticWrapRolls = plasticWrapRolls
    runtime.plasticWrapUses = plasticWrapUses
    runtime.pallets = pallets
    return normalizeWrapperService(value, runtime, pallets, label)
end

local function normalizeCutterMemory(value, label)
    if not Codec.isArray(value) then return nil, label .. " must be an array" end
    if #value > 3 then return nil, label .. " must contain at most 3 measurements" end
    local memory = {}
    for index = 1, #value do
        local measurement, fieldError = integerInRange(
            value[index], 0, 2500, label .. "[" .. index .. "]")
        if measurement == nil then return nil, fieldError end
        memory[#memory + 1] = measurement
    end
    return Codec.array(memory)
end

local function normalizeCutterSelectedCut(value, label)
    local valid, shapeError = shape(value, label, {
        "number", "edge", "marginCentiInch", "gaugeCentiInch", "orientation", "active",
    })
    if not valid then return nil, shapeError end
    local number, fieldError = integerInRange(value.number, 1, 4, label .. ".number")
    if not number then return nil, fieldError end
    if type(value.edge) ~= "string" or not WORKSHOP_CUTTER_EDGES[value.edge] then
        return nil, label .. ".edge is invalid"
    end
    local marginCentiInch
    marginCentiInch, fieldError = integerInRange(
        value.marginCentiInch, 0, 100000, label .. ".marginCentiInch")
    if marginCentiInch == nil then return nil, fieldError end
    local gaugeCentiInch
    gaugeCentiInch, fieldError = integerInRange(
        value.gaugeCentiInch, 0, 2500, label .. ".gaugeCentiInch")
    if gaugeCentiInch == nil then return nil, fieldError end
    local orientation
    orientation, fieldError = integerInRange(
        value.orientation, 0, 270, label .. ".orientation")
    if orientation == nil then return nil, fieldError end
    if not WORKSHOP_CUTTER_ORIENTATIONS[orientation] then
        return nil, label .. ".orientation is invalid"
    end
    if type(value.active) ~= "boolean" then return nil, label .. ".active must be boolean" end
    return {
        number = number,
        edge = value.edge,
        marginCentiInch = marginCentiInch,
        gaugeCentiInch = gaugeCentiInch,
        orientation = orientation,
        active = value.active,
    }
end

local function normalizeCutterPaper(value, label)
    local valid, shapeError = shape(value, label, {
        "palletId", "orientation", "status", "activeCut", "cutCount", "activeLift",
        "requiredLifts", "remainingSheets",
    }, { "selectedCut", "widthCentiInch", "heightCentiInch", "offSpec" })
    if not valid then return nil, shapeError end
    local palletId, fieldError = token(value.palletId, MAX_TOKEN_BYTES, label .. ".palletId")
    if not palletId then return nil, fieldError end
    local orientation
    orientation, fieldError = integerInRange(value.orientation, 0, 270, label .. ".orientation")
    if orientation == nil then return nil, fieldError end
    if not WORKSHOP_CUTTER_ORIENTATIONS[orientation] then
        return nil, label .. ".orientation is invalid"
    end
    if type(value.status) ~= "string" or not WORKSHOP_CUTTER_PAPER_STATUSES[value.status] then
        return nil, label .. ".status is invalid"
    end
    local activeCut
    activeCut, fieldError = integerInRange(value.activeCut, 1, 5, label .. ".activeCut")
    if not activeCut then return nil, fieldError end
    local cutCount
    cutCount, fieldError = integerInRange(value.cutCount, 1, 4, label .. ".cutCount")
    if not cutCount then return nil, fieldError end
    local activeLift
    activeLift, fieldError = integerInRange(value.activeLift, 1, 1000, label .. ".activeLift")
    if not activeLift then return nil, fieldError end
    local requiredLifts
    requiredLifts, fieldError = integerInRange(
        value.requiredLifts, 1, 1000, label .. ".requiredLifts")
    if not requiredLifts then return nil, fieldError end
    local remainingSheets
    remainingSheets, fieldError = integerInRange(
        value.remainingSheets, 0, 100000, label .. ".remainingSheets")
    if remainingSheets == nil then return nil, fieldError end
    local paper = {
        palletId = palletId,
        orientation = orientation,
        status = value.status,
        activeCut = activeCut,
        cutCount = cutCount,
        activeLift = activeLift,
        requiredLifts = requiredLifts,
        remainingSheets = remainingSheets,
    }
    if value.selectedCut ~= nil then
        paper.selectedCut, fieldError = normalizeCutterSelectedCut(
            value.selectedCut, label .. ".selectedCut")
        if not paper.selectedCut then return nil, fieldError end
    end
    if value.widthCentiInch ~= nil or value.heightCentiInch ~= nil or value.offSpec ~= nil then
        paper.widthCentiInch, fieldError = integerInRange(value.widthCentiInch, 1, 100000,
            label .. ".widthCentiInch")
        if not paper.widthCentiInch then return nil, fieldError end
        paper.heightCentiInch, fieldError = integerInRange(value.heightCentiInch, 1, 100000,
            label .. ".heightCentiInch")
        if not paper.heightCentiInch then return nil, fieldError end
        if type(value.offSpec) ~= "boolean" then return nil, label .. ".offSpec must be boolean" end
        paper.offSpec = value.offSpec
    end
    return paper
end

local function normalizeCutterCandidates(value, label)
    if not Codec.isArray(value) then return nil, label .. " must be an array" end
    if #value > 3 then return nil, label .. " must contain at most 3 pallets" end
    local candidates, seen = {}, {}
    for index = 1, #value do
        local candidateLabel = label .. "[" .. index .. "]"
        local valid, shapeError = shape(
            value[index], candidateLabel, { "palletId", "distancePixels" })
        if not valid then return nil, shapeError end
        local palletId, fieldError = token(
            value[index].palletId, MAX_TOKEN_BYTES, candidateLabel .. ".palletId")
        if not palletId then return nil, fieldError end
        if seen[palletId] then return nil, label .. " contains a duplicate palletId" end
        seen[palletId] = true
        local distancePixels
        distancePixels, fieldError = integerInRange(
            value[index].distancePixels, 0, 100000, candidateLabel .. ".distancePixels")
        if distancePixels == nil then return nil, fieldError end
        candidates[#candidates + 1] = {
            palletId = palletId,
            distancePixels = distancePixels,
        }
    end
    return Codec.array(candidates)
end

local function normalizeCutterServiceItems(value, label)
    if not Codec.isArray(value) then return nil, label .. " must be an array" end
    if #value > 2 then return nil, label .. " must contain at most 2 visible points" end
    local items, seen = {}, {}
    for index = 1, #value do
        local itemLabel = label .. "[" .. index .. "]"
        local valid, shapeError = shape(value[index], itemLabel, {
            "itemIndex", "label", "cleaned", "coupled", "strokes", "complete",
        })
        if not valid then return nil, shapeError end
        local itemIndex, fieldError = integerInRange(
            value[index].itemIndex, 1, 7, itemLabel .. ".itemIndex")
        if not itemIndex then return nil, fieldError end
        if seen[itemIndex] then return nil, label .. " contains a duplicate itemIndex" end
        seen[itemIndex] = true
        local displayLabel
        displayLabel, fieldError = printableString(
            value[index].label, 1, 48, itemLabel .. ".label")
        if not displayLabel then return nil, fieldError end
        for _, field in ipairs({ "cleaned", "coupled", "complete" }) do
            if type(value[index][field]) ~= "boolean" then
                return nil, itemLabel .. "." .. field .. " must be boolean"
            end
        end
        local strokes
        strokes, fieldError = integerInRange(
            value[index].strokes, 0, 99, itemLabel .. ".strokes")
        if strokes == nil then return nil, fieldError end
        items[#items + 1] = {
            itemIndex = itemIndex,
            label = displayLabel,
            cleaned = value[index].cleaned,
            coupled = value[index].coupled,
            strokes = strokes,
            complete = value[index].complete,
        }
    end
    return Codec.array(items)
end

local function normalizeCutterWorkshopView(value, label)
    local valid, shapeError = shape(value, label, {
        "runtimeRevision", "step", "phasePermille", "loaded", "clamp", "clampPermille",
        "bladePermille", "barrierClear", "emergencyStopped", "gaugeCentiInch",
        "programIndex", "memoryCentiInch",
    }, {
        "paper", "candidates", "genericSheets", "serviceStep", "servicePermille",
        "serviceView", "serviceTool", "serviceItems", "centralInstalled",
        "gearInspected", "gearLevelPermille", "bladeBoltsDone", "bladeBoltMask",
    })
    if not valid then return nil, shapeError end
    local runtimeRevision, fieldError = integerInRange(
        value.runtimeRevision, 0, UINT32_MAX, label .. ".runtimeRevision")
    if runtimeRevision == nil then return nil, fieldError end
    if type(value.step) ~= "string" or not WORKSHOP_CUTTER_STEPS[value.step] then
        return nil, label .. ".step is invalid"
    end
    local phasePermille
    phasePermille, fieldError = integerInRange(
        value.phasePermille, 0, 1000, label .. ".phasePermille")
    if phasePermille == nil then return nil, fieldError end
    if type(value.loaded) ~= "boolean" then return nil, label .. ".loaded must be boolean" end
    if type(value.clamp) ~= "boolean" then return nil, label .. ".clamp must be boolean" end
    local clampPermille
    clampPermille, fieldError = integerInRange(
        value.clampPermille, 0, 1000, label .. ".clampPermille")
    if clampPermille == nil then return nil, fieldError end
    local bladePermille
    bladePermille, fieldError = integerInRange(
        value.bladePermille, 0, 1000, label .. ".bladePermille")
    if bladePermille == nil then return nil, fieldError end
    if type(value.barrierClear) ~= "boolean" then
        return nil, label .. ".barrierClear must be boolean"
    end
    if type(value.emergencyStopped) ~= "boolean" then
        return nil, label .. ".emergencyStopped must be boolean"
    end
    local gaugeCentiInch
    gaugeCentiInch, fieldError = integerInRange(
        value.gaugeCentiInch, 0, 2500, label .. ".gaugeCentiInch")
    if gaugeCentiInch == nil then return nil, fieldError end
    local programIndex
    programIndex, fieldError = integerInRange(
        value.programIndex, 1, 4, label .. ".programIndex")
    if not programIndex then return nil, fieldError end
    local memoryCentiInch
    memoryCentiInch, fieldError = normalizeCutterMemory(
        value.memoryCentiInch, label .. ".memoryCentiInch")
    if not memoryCentiInch then return nil, fieldError end
    local serviceStep, servicePermille
    if value.serviceStep ~= nil then
        if type(value.serviceStep) ~= "string"
            or not WORKSHOP_CUTTER_SERVICE_STEPS[value.serviceStep]
            or value.serviceStep == "idle"
        then
            return nil, label .. ".serviceStep is invalid"
        end
        serviceStep = value.serviceStep
        servicePermille, fieldError = integerInRange(
            value.servicePermille, 0, 1000, label .. ".servicePermille")
        if servicePermille == nil then return nil, fieldError end
    elseif value.servicePermille ~= nil then
        return nil, label .. ".servicePermille requires an active serviceStep"
    end
    if value.paper ~= nil and (value.candidates ~= nil or value.genericSheets ~= nil) then
        return nil, label .. " cannot include load candidates while paper is present"
    end
    if serviceStep and value.paper ~= nil then
        return nil, label .. " cannot service the cutter while paper is present"
    end
    if serviceStep and (value.loaded ~= false or value.step ~= "idle"
        or value.candidates ~= nil or value.genericSheets ~= nil)
    then
        return nil, label .. " active service requires an idle unloaded cutter without load candidates"
    end
    local normalized = {
        runtimeRevision = runtimeRevision,
        step = value.step,
        phasePermille = phasePermille,
        loaded = value.loaded,
        clamp = value.clamp,
        clampPermille = clampPermille,
        bladePermille = bladePermille,
        barrierClear = value.barrierClear,
        emergencyStopped = value.emergencyStopped,
        gaugeCentiInch = gaugeCentiInch,
        programIndex = programIndex,
        memoryCentiInch = memoryCentiInch,
    }
    if serviceStep then
        normalized.serviceStep = serviceStep
        normalized.servicePermille = servicePermille
    end
    if value.paper ~= nil then
        normalized.paper, fieldError = normalizeCutterPaper(value.paper, label .. ".paper")
        if not normalized.paper then return nil, fieldError end
    end
    if value.candidates ~= nil then
        normalized.candidates, fieldError = normalizeCutterCandidates(
            value.candidates, label .. ".candidates")
        if not normalized.candidates then return nil, fieldError end
    end
    if value.genericSheets ~= nil then
        normalized.genericSheets, fieldError = integerInRange(
            value.genericSheets, 0, 100000, label .. ".genericSheets")
        if normalized.genericSheets == nil then return nil, fieldError end
    end
    local serviceFields = {
        "serviceView", "serviceTool", "serviceItems", "centralInstalled",
        "gearInspected", "gearLevelPermille",
    }
    if serviceStep == "lubricate" then
        for _, field in ipairs(serviceFields) do
            if value[field] == nil then return nil, label .. "." .. field .. " is required" end
        end
        normalized.serviceView, fieldError = integerInRange(
            value.serviceView, 1, 5, label .. ".serviceView")
        if not normalized.serviceView then return nil, fieldError end
        normalized.serviceTool, fieldError = integerInRange(
            value.serviceTool, 1, 4, label .. ".serviceTool")
        if not normalized.serviceTool then return nil, fieldError end
        normalized.serviceItems, fieldError = normalizeCutterServiceItems(
            value.serviceItems, label .. ".serviceItems")
        if not normalized.serviceItems then return nil, fieldError end
        for _, item in ipairs(normalized.serviceItems) do
            local matchesView = (normalized.serviceView == 1 and item.itemIndex <= 2)
                or (normalized.serviceView == 2 and item.itemIndex >= 3 and item.itemIndex <= 4)
                or (normalized.serviceView == 3 and item.itemIndex >= 5 and item.itemIndex <= 6)
                or (normalized.serviceView == 5 and item.itemIndex == 7)
            if not matchesView then
                return nil, label .. ".serviceItems contains a point outside serviceView"
            end
        end
        if type(value.centralInstalled) ~= "boolean" then
            return nil, label .. ".centralInstalled must be boolean"
        end
        if type(value.gearInspected) ~= "boolean" then
            return nil, label .. ".gearInspected must be boolean"
        end
        normalized.centralInstalled = value.centralInstalled
        normalized.gearInspected = value.gearInspected
        normalized.gearLevelPermille, fieldError = integerInRange(
            value.gearLevelPermille, 0, 1000, label .. ".gearLevelPermille")
        if normalized.gearLevelPermille == nil then return nil, fieldError end
    else
        for _, field in ipairs(serviceFields) do
            if value[field] ~= nil then
                return nil, label .. "." .. field .. " is only valid during lubrication"
            end
        end
    end
    local bladeActive = serviceStep == "blade_bolts"
        or serviceStep == "blade_lift" or serviceStep == "blade_sleeve"
    if bladeActive then
        normalized.bladeBoltsDone, fieldError = integerInRange(
            value.bladeBoltsDone, 0, 4, label .. ".bladeBoltsDone")
        if normalized.bladeBoltsDone == nil then return nil, fieldError end
        if (serviceStep == "blade_lift" or serviceStep == "blade_sleeve")
            and normalized.bladeBoltsDone ~= 4
        then
            return nil, label .. ".bladeBoltsDone must be 4 after bolt removal"
        elseif serviceStep == "blade_bolts" and normalized.bladeBoltsDone >= 4 then
            return nil, label .. ".blade_bolts must advance after the fourth bolt"
        end
    elseif value.bladeBoltsDone ~= nil then
        return nil, label .. ".bladeBoltsDone is only valid during blade service"
    end
    if value.bladeBoltMask ~= nil then
        if not bladeActive then return nil, "Blade display requires blade service." end
        normalized.bladeBoltMask, fieldError = integerInRange(value.bladeBoltMask,0,15,label..".bladeBoltMask")
        if normalized.bladeBoltMask == nil then return nil,fieldError end
        local count=0
        for index=0,3 do count=count+math.floor(normalized.bladeBoltMask/2^index)%2 end
        if count~=normalized.bladeBoltsDone then return nil,"Blade display count mismatch." end
    end
    return normalized
end

local function normalizeWindmillSetupPermille(value, label)
    if not Codec.isArray(value) then return nil, label .. " must be an array" end
    if #value ~= 6 then return nil, label .. " must contain exactly 6 setup values" end
    local setup = {}
    for index = 1, 6 do
        local progress, fieldError = integerInRange(
            value[index], 0, 1000, label .. "[" .. index .. "]")
        if progress == nil then return nil, fieldError end
        setup[index] = progress
    end
    return Codec.array(setup)
end

local function normalizeWindmillCandidates(value, label)
    if not Codec.isArray(value) then return nil, label .. " must be an array" end
    if #value > 3 then return nil, label .. " must contain at most 3 pallets" end
    local candidates, seen = {}, {}
    for index = 1, #value do
        local candidateLabel = label .. "[" .. index .. "]"
        local valid, shapeError = shape(
            value[index], candidateLabel, { "palletId", "colorIndex" })
        if not valid then return nil, shapeError end
        local palletId, fieldError = token(
            value[index].palletId, MAX_WINDMILL_ID_BYTES, candidateLabel .. ".palletId")
        if not palletId then return nil, fieldError end
        if seen[palletId] then return nil, label .. " contains a duplicate palletId" end
        seen[palletId] = true
        local colorIndex
        colorIndex, fieldError = integerInRange(
            value[index].colorIndex, 1, 4, candidateLabel .. ".colorIndex")
        if not colorIndex then return nil, fieldError end
        candidates[#candidates + 1] = {
            palletId = palletId,
            colorIndex = colorIndex,
        }
    end
    return Codec.array(candidates)
end

local function normalizeWindmillWorkshopView(value, label)
    local valid, shapeError = shape(value, label, {
        "runtimeRevision", "status", "speed", "motor", "feeder", "impression",
        "emergency", "counter", "goodSheets", "spoilage", "targetSheets", "feedStart",
        "feedRemaining", "proofApproved", "artworkVerified", "setupPermille", "candidates",
        "serviceStep", "servicePermille", "plateMarkerPermille",
    }, {
        "jobId", "palletId", "colorIndex", "colorCount", "proofPermille", "warning",
        "setupTask", "setupSummary", "serviceTask", "setupVisual",
    })
    if not valid then return nil, shapeError end
    local normalized, fieldError = {}
    normalized.runtimeRevision, fieldError = integerInRange(
        value.runtimeRevision, 0, UINT32_MAX, label .. ".runtimeRevision")
    if normalized.runtimeRevision == nil then return nil, fieldError end
    if type(value.status) ~= "string" or not WORKSHOP_WINDMILL_STATUSES[value.status] then
        return nil, label .. ".status is invalid"
    end
    normalized.status = value.status
    normalized.speed, fieldError = integerInRange(value.speed, 1000, 5500, label .. ".speed")
    if normalized.speed == nil then return nil, fieldError end
    for _, field in ipairs({
        "motor", "feeder", "impression", "emergency", "proofApproved", "artworkVerified",
    }) do
        if type(value[field]) ~= "boolean" then
            return nil, label .. "." .. field .. " must be boolean"
        end
        normalized[field] = value[field]
    end
    for _, field in ipairs({
        "counter", "goodSheets", "spoilage", "targetSheets", "feedStart", "feedRemaining",
    }) do
        normalized[field], fieldError = integerInRange(
            value[field], 0, UINT32_MAX, label .. "." .. field)
        if normalized[field] == nil then return nil, fieldError end
    end
    normalized.setupPermille, fieldError = normalizeWindmillSetupPermille(
        value.setupPermille, label .. ".setupPermille")
    if not normalized.setupPermille then return nil, fieldError end
    normalized.candidates, fieldError = normalizeWindmillCandidates(
        value.candidates, label .. ".candidates")
    if not normalized.candidates then return nil, fieldError end
    if type(value.serviceStep) ~= "string"
        or not WORKSHOP_WINDMILL_SERVICE_STEPS[value.serviceStep]
    then
        return nil, label .. ".serviceStep is invalid"
    end
    normalized.serviceStep = value.serviceStep
    normalized.servicePermille, fieldError = integerInRange(
        value.servicePermille, 0, 1000, label .. ".servicePermille")
    if normalized.servicePermille == nil then return nil, fieldError end
    normalized.plateMarkerPermille, fieldError = integerInRange(
        value.plateMarkerPermille, 0, 1000, label .. ".plateMarkerPermille")
    if normalized.plateMarkerPermille == nil then return nil, fieldError end

    for _, field in ipairs({ "jobId", "palletId" }) do
        if value[field] ~= nil then
            normalized[field], fieldError = token(
                value[field], MAX_WINDMILL_ID_BYTES, label .. "." .. field)
            if not normalized[field] then return nil, fieldError end
        end
    end
    for _, field in ipairs({ "colorIndex", "colorCount" }) do
        if value[field] ~= nil then
            normalized[field], fieldError = integerInRange(
                value[field], 1, 4, label .. "." .. field)
            if not normalized[field] then return nil, fieldError end
        end
    end
    if value.proofPermille ~= nil then
        normalized.proofPermille, fieldError = integerInRange(
            value.proofPermille, 0, 1000, label .. ".proofPermille")
        if normalized.proofPermille == nil then return nil, fieldError end
    end
    local viewTextBytes = 0
    for _, field in ipairs({ "warning", "setupSummary", "serviceTask" }) do
        if value[field] ~= nil then
            normalized[field], fieldError = printableString(
                value[field], 1, MAX_WINDMILL_VIEW_TEXT_TOTAL_BYTES,
                label .. "." .. field)
            if not normalized[field] then return nil, fieldError end
            viewTextBytes = viewTextBytes + #normalized[field]
        end
    end
    if viewTextBytes > MAX_WINDMILL_VIEW_TEXT_TOTAL_BYTES then
        return nil, label .. " optional display text exceeds "
            .. MAX_WINDMILL_VIEW_TEXT_TOTAL_BYTES .. " bytes"
    end
    if value.setupTask ~= nil then
        if type(value.setupTask) ~= "string"
            or not WORKSHOP_WINDMILL_SETUP_TASKS[value.setupTask]
        then
            return nil, label .. ".setupTask is invalid"
        end
        normalized.setupTask = value.setupTask
    end
    if value.setupVisual ~= nil then
        normalized.setupVisual, fieldError = require("src.press_setup_view").normalize(value.setupTask, value.setupVisual)
        if not normalized.setupVisual then return nil, fieldError end
    end
    return normalized
end

local function normalizeWorkshopView(value, resourceId, label)
    if resourceId == "reception_customer" then
        return normalizeReceptionWorkshopView(value, label)
    elseif resourceId == "vendor" then
        local valid, shapeError = shape(value, label, {
            "categoryIndex", "categoryName", "salesman", "kind", "cash", "items",
        })
        if not valid then return nil, shapeError end
        local normalized, fieldError = {}
        normalized.categoryIndex, fieldError = integerInRange(
            value.categoryIndex, 1, 5, label .. ".categoryIndex")
        if not normalized.categoryIndex then return nil, fieldError end
        for _, field in ipairs({ "categoryName", "salesman" }) do
            normalized[field], fieldError = printableString(
                value[field], 1, 64, label .. "." .. field)
            if not normalized[field] then return nil, fieldError end
        end
        if value.kind ~= "products" and value.kind ~= "machines" then
            return nil, label .. ".kind is invalid"
        end
        normalized.kind = value.kind
        normalized.cash, fieldError = integerInRange(value.cash, 0, UINT32_MAX,
            label .. ".cash")
        if normalized.cash == nil then return nil, fieldError end
        if not Codec.isArray(value.items) or #value.items > 5 then
            return nil, label .. ".items must be an array of at most 5 rows"
        end
        local rows = {}
        for index, row in ipairs(value.items) do
            local rowLabel = label .. ".items[" .. index .. "]"
            local rowValid, rowError = shape(row, rowLabel,
                { "itemIndex", "name", "price", "available", "detail" })
            if not rowValid then return nil, rowError end
            local projected = {}
            projected.itemIndex, fieldError = integerInRange(
                row.itemIndex, 1, 16, rowLabel .. ".itemIndex")
            if not projected.itemIndex or projected.itemIndex ~= index then
                return nil, rowLabel .. ".itemIndex must match its row"
            end
            for _, field in ipairs({ "name", "detail" }) do
                projected[field], fieldError = printableString(
                    row[field], 1, 96, rowLabel .. "." .. field)
                if not projected[field] then return nil, fieldError end
            end
            projected.price, fieldError = integerInRange(
                row.price, 0, UINT32_MAX, rowLabel .. ".price")
            if projected.price == nil then return nil, fieldError end
            if type(row.available) ~= "boolean" then
                return nil, rowLabel .. ".available must be boolean"
            end
            projected.available = row.available
            rows[#rows + 1] = projected
        end
        normalized.items = Codec.array(rows)
        return normalized
    elseif resourceId == "truck" then
        local valid, shapeError = shape(value, label, {
            "mode", "state", "manifestId", "title", "page", "pageCount",
            "remaining", "canClose", "items",
        })
        if not valid then return nil, shapeError end
        if not WORKSHOP_TRUCK_MODES[value.mode] then
            return nil, label .. ".mode is invalid"
        end
        if not WORKSHOP_TRUCK_STATES[value.state] then
            return nil, label .. ".state is invalid"
        end
        local normalized, fieldError = {
            mode = value.mode,
            state = value.state,
        }
        normalized.manifestId, fieldError = token(
            value.manifestId, MAX_TOKEN_BYTES, label .. ".manifestId")
        if not normalized.manifestId then return nil, fieldError end
        normalized.title, fieldError = printableString(
            value.title, 1, 96, label .. ".title")
        if not normalized.title then return nil, fieldError end
        normalized.page, fieldError = integerInRange(value.page, 1, 64, label .. ".page")
        if not normalized.page then return nil, fieldError end
        normalized.pageCount, fieldError = integerInRange(
            value.pageCount, 1, 64, label .. ".pageCount")
        if not normalized.pageCount or normalized.page > normalized.pageCount then
            return nil, label .. ".page must not exceed pageCount"
        end
        normalized.remaining, fieldError = integerInRange(
            value.remaining, 0, 10000, label .. ".remaining")
        if normalized.remaining == nil then return nil, fieldError end
        if type(value.canClose) ~= "boolean" then
            return nil, label .. ".canClose must be boolean"
        end
        normalized.canClose = value.canClose
        if value.canClose ~= (value.remaining == 0
            and (value.mode == "machine_delivery" and value.state == "parked_closed"
                or value.mode ~= "machine_delivery" and value.state == "cargo_open"))
        then
            return nil, label .. ".canClose is inconsistent"
        end
        if not Codec.isArray(value.items) or #value.items > 3 then
            return nil, label .. ".items must be an array of at most 3 rows"
        end
        local rows = {}
        for index, row in ipairs(value.items) do
            local rowLabel = label .. ".items[" .. index .. "]"
            local rowValid, rowError = shape(row, rowLabel,
                { "itemIndex", "label", "detail", "available" })
            if not rowValid then return nil, rowError end
            local projected = {}
            projected.itemIndex, fieldError = integerInRange(
                row.itemIndex, 1, 3, rowLabel .. ".itemIndex")
            if not projected.itemIndex or projected.itemIndex ~= index then
                return nil, rowLabel .. ".itemIndex must match its row"
            end
            for _, field in ipairs({ "label", "detail" }) do
                projected[field], fieldError = printableString(
                    row[field], 1, 96, rowLabel .. "." .. field)
                if not projected[field] then return nil, fieldError end
            end
            if type(row.available) ~= "boolean" then
                return nil, rowLabel .. ".available must be boolean"
            end
            projected.available = row.available
            rows[#rows + 1] = projected
        end
        normalized.items = Codec.array(rows)
        return normalized
    elseif resourceId == "office_computer" or resourceId == "work_phone" or resourceId == "warehouse" then
        local valid, shapeError = shape(value, label, {})
        if not valid then return nil, shapeError end
        return {}
    elseif resourceId == "skid_wrapper" then
        return normalizeWrapperWorkshopView(value, label)
    elseif resourceId == "pallet_jack" then
        local valid, shapeError = shape(value, label, {})
        if not valid then return nil, shapeError end
        return {}
    elseif resourceId == "cutter" then
        return normalizeCutterWorkshopView(value, label)
    elseif resourceId == "windmill" then
        return normalizeWindmillWorkshopView(value, label)
    end
    return nil, label .. " has no resource validator"
end

local function normalizeWorkshopAcquire(payload)
    local valid, shapeError = shape(payload, "workshop_acquire payload",
        { "sessionId", "requestId", "resourceId", "expectedRevision" })
    if not valid then return nil, shapeError end
    local sessionId, fieldError = token(
        payload.sessionId, MAX_TOKEN_BYTES, "workshop_acquire.sessionId")
    if not sessionId then return nil, fieldError end
    local requestId
    requestId, fieldError = integerInRange(
        payload.requestId, 1, UINT32_MAX, "workshop_acquire.requestId")
    if not requestId then return nil, fieldError end
    local resourceId
    resourceId, fieldError = workshopResource(
        payload.resourceId, "workshop_acquire.resourceId")
    if not resourceId then return nil, fieldError end
    local expectedRevision
    expectedRevision, fieldError = integerInRange(
        payload.expectedRevision, 0, UINT32_MAX, "workshop_acquire.expectedRevision")
    if expectedRevision == nil then return nil, fieldError end
    return {
        sessionId = sessionId,
        requestId = requestId,
        resourceId = resourceId,
        expectedRevision = expectedRevision,
    }
end

local function normalizeWorkshopGrant(payload)
    local valid, shapeError = shape(payload, "workshop_grant payload", {
        "sessionId", "requestId", "resourceId", "granted", "code", "message", "revision",
    }, { "leaseId", "view" })
    if not valid then return nil, shapeError end
    local sessionId, fieldError = token(
        payload.sessionId, MAX_TOKEN_BYTES, "workshop_grant.sessionId")
    if not sessionId then return nil, fieldError end
    local requestId
    requestId, fieldError = integerInRange(
        payload.requestId, 1, UINT32_MAX, "workshop_grant.requestId")
    if not requestId then return nil, fieldError end
    local resourceId
    resourceId, fieldError = workshopResource(payload.resourceId, "workshop_grant.resourceId")
    if not resourceId then return nil, fieldError end
    if type(payload.granted) ~= "boolean" then
        return nil, "workshop_grant.granted must be boolean"
    end
    local leaseId
    if payload.leaseId ~= nil then
        leaseId, fieldError = token(payload.leaseId, MAX_TOKEN_BYTES, "workshop_grant.leaseId")
        if not leaseId then return nil, fieldError end
    end
    if payload.granted ~= (leaseId ~= nil) then
        return nil, "workshop_grant.leaseId must be present exactly when granted"
    end
    local code
    code, fieldError = token(payload.code, MAX_ERROR_CODE_BYTES, "workshop_grant.code")
    if not code then return nil, fieldError end
    local message
    message, fieldError = printableString(
        payload.message, 1, MAX_ERROR_MESSAGE_BYTES, "workshop_grant.message")
    if not message then return nil, fieldError end
    local revision
    revision, fieldError = integerInRange(
        payload.revision, 0, UINT32_MAX, "workshop_grant.revision")
    if revision == nil then return nil, fieldError end
    local normalized = {
        sessionId = sessionId,
        requestId = requestId,
        resourceId = resourceId,
        granted = payload.granted,
        code = code,
        message = message,
        revision = revision,
        leaseId = leaseId,
    }
    if payload.view ~= nil then
        normalized.view, fieldError = normalizeWorkshopView(
            payload.view, resourceId, "workshop_grant.view")
        if not normalized.view then return nil, fieldError end
    end
    return normalized
end

local function normalizeWorkshopCommand(payload)
    local valid, shapeError = shape(payload, "workshop_command payload", {
        "sessionId", "commandId", "leaseId", "resourceId", "action", "expectedRevision",
    }, {
        "amount", "jobId", "palletId", "programIndex", "gaugeCentiInch", "clamp",
        "barrierClear", "plateId", "setupTask", "setupAction", "itemIndex", "enabled",
        "machineIndex", "placementCell", "callId", "officeIntent", "warehouseIntent",
    })
    if not valid then return nil, shapeError end
    local sessionId, fieldError = token(
        payload.sessionId, MAX_TOKEN_BYTES, "workshop_command.sessionId")
    if not sessionId then return nil, fieldError end
    local commandId
    commandId, fieldError = integerInRange(
        payload.commandId, 1, UINT32_MAX, "workshop_command.commandId")
    if not commandId then return nil, fieldError end
    local leaseId
    leaseId, fieldError = token(payload.leaseId, MAX_TOKEN_BYTES, "workshop_command.leaseId")
    if not leaseId then return nil, fieldError end
    local resourceId
    resourceId, fieldError = workshopResource(payload.resourceId, "workshop_command.resourceId")
    if not resourceId then return nil, fieldError end
    local action, argumentField = workshopAction(
        payload.action, resourceId, "workshop_command.action")
    if not action then return nil, argumentField end
    local expectedRevision
    expectedRevision, fieldError = integerInRange(
        payload.expectedRevision, 0, UINT32_MAX, "workshop_command.expectedRevision")
    if expectedRevision == nil then return nil, fieldError end
    for _, field in ipairs({
        "amount", "jobId", "palletId", "programIndex", "gaugeCentiInch", "clamp",
        "barrierClear", "plateId", "setupTask", "setupAction", "itemIndex", "enabled",
        "machineIndex", "placementCell", "callId", "officeIntent", "warehouseIntent",
    }) do
        if field ~= argumentField and payload[field] ~= nil then
            return nil, "workshop_command." .. field .. " is invalid for " .. action
        end
    end
    local normalized = {
        sessionId = sessionId,
        commandId = commandId,
        leaseId = leaseId,
        resourceId = resourceId,
        action = action,
        expectedRevision = expectedRevision,
    }
    if argumentField == "warehouseIntent" then
        normalized.warehouseIntent, fieldError = WarehouseIntent.normalize(payload.warehouseIntent)
        if not normalized.warehouseIntent then return nil, fieldError end
        if resourceId == "pallet_jack" and (normalized.warehouseIntent.vehicle ~= "pallet_jack"
            or (normalized.warehouseIntent.kind ~= "store" and normalized.warehouseIntent.kind ~= "retrieve")) then
            return nil, "pallet_jack warehouse actions are limited to its rack transfers"
        end
    elseif argumentField == "officeIntent" then
        normalized.officeIntent, fieldError = OfficeIntent.normalize(payload.officeIntent)
        if not normalized.officeIntent then return nil, fieldError end
    elseif argumentField == "amount" then
        normalized.amount, fieldError = integerInRange(
            payload.amount, 1, MAX_WORKSHOP_AMOUNT, "workshop_command.amount")
        if not normalized.amount then return nil, fieldError end
    elseif argumentField == "programIndex" then
        normalized.programIndex, fieldError = integerInRange(
            payload.programIndex, 1, 4, "workshop_command.programIndex")
        if not normalized.programIndex then return nil, fieldError end
    elseif argumentField == "itemIndex" then
        normalized.itemIndex, fieldError = integerInRange(
            payload.itemIndex, 1, 16, "workshop_command.itemIndex")
        if not normalized.itemIndex then return nil, fieldError end
    elseif argumentField == "machineIndex" then
        normalized.machineIndex, fieldError = integerInRange(
            payload.machineIndex, 1, 3, "workshop_command.machineIndex")
        if not normalized.machineIndex then return nil, fieldError end
    elseif argumentField == "placementCell" then
        normalized.placementCell, fieldError = token(
            payload.placementCell, 8, "workshop_command.placementCell")
        local column, row
        if normalized.placementCell then
            column, row = normalized.placementCell:match("^c(%d+)r(%d+)$")
        end
        column, row = tonumber(column), tonumber(row)
        if not column or not row or column > 64 or row > 64 then
            return nil, "workshop_command.placementCell is invalid"
        end
    elseif argumentField == "gaugeCentiInch" then
        normalized.gaugeCentiInch, fieldError = integerInRange(
            payload.gaugeCentiInch, 0, 2500, "workshop_command.gaugeCentiInch")
        if normalized.gaugeCentiInch == nil then return nil, fieldError end
    elseif argumentField == "clamp" or argumentField == "barrierClear"
        or argumentField == "enabled"
    then
        if type(payload[argumentField]) ~= "boolean" then
            return nil, "workshop_command." .. argumentField .. " must be boolean"
        end
        normalized[argumentField] = payload[argumentField]
    elseif argumentField == "setupTask" then
        if type(payload.setupTask) ~= "string"
            or not WORKSHOP_WINDMILL_SETUP_TASKS[payload.setupTask]
        then
            return nil, "workshop_command.setupTask is invalid"
        end
        normalized.setupTask = payload.setupTask
    elseif argumentField == "setupAction" then
        if type(payload.setupAction) ~= "string"
            or not WORKSHOP_WINDMILL_SETUP_ACTIONS[payload.setupAction]
        then
            return nil, "workshop_command.setupAction is invalid"
        end
        normalized.setupAction = payload.setupAction
    elseif argumentField then
        normalized[argumentField], fieldError = token(
            payload[argumentField], MAX_TOKEN_BYTES, "workshop_command." .. argumentField)
        if not normalized[argumentField] then return nil, fieldError end
    end
    return normalized
end

local function normalizeWorkshopResult(payload)
    local valid, shapeError = shape(payload, "workshop_result payload", {
        "sessionId", "commandId", "resourceId", "action", "accepted", "code", "message",
        "revision",
    }, { "view" })
    if not valid then return nil, shapeError end
    local sessionId, fieldError = token(
        payload.sessionId, MAX_TOKEN_BYTES, "workshop_result.sessionId")
    if not sessionId then return nil, fieldError end
    local commandId
    commandId, fieldError = integerInRange(
        payload.commandId, 1, UINT32_MAX, "workshop_result.commandId")
    if not commandId then return nil, fieldError end
    local resourceId
    resourceId, fieldError = workshopResource(payload.resourceId, "workshop_result.resourceId")
    if not resourceId then return nil, fieldError end
    local action, actionError = workshopAction(
        payload.action, resourceId, "workshop_result.action")
    if not action then return nil, actionError end
    if type(payload.accepted) ~= "boolean" then
        return nil, "workshop_result.accepted must be boolean"
    end
    local code
    code, fieldError = token(payload.code, MAX_ERROR_CODE_BYTES, "workshop_result.code")
    if not code then return nil, fieldError end
    local message
    message, fieldError = printableString(
        payload.message, 1, MAX_ERROR_MESSAGE_BYTES, "workshop_result.message")
    if not message then return nil, fieldError end
    local revision
    revision, fieldError = integerInRange(
        payload.revision, 0, UINT32_MAX, "workshop_result.revision")
    if revision == nil then return nil, fieldError end
    local normalized = {
        sessionId = sessionId,
        commandId = commandId,
        resourceId = resourceId,
        action = action,
        accepted = payload.accepted,
        code = code,
        message = message,
        revision = revision,
    }
    if payload.view ~= nil then
        normalized.view, fieldError = normalizeWorkshopView(
            payload.view, resourceId, "workshop_result.view")
        if not normalized.view then return nil, fieldError end
    end
    return normalized
end

local function normalizeWorkshopRelease(payload)
    local valid, shapeError = shape(payload, "workshop_release payload",
        { "sessionId", "requestId", "leaseId", "resourceId", "reason" })
    if not valid then return nil, shapeError end
    local sessionId, fieldError = token(
        payload.sessionId, MAX_TOKEN_BYTES, "workshop_release.sessionId")
    if not sessionId then return nil, fieldError end
    local requestId
    requestId, fieldError = integerInRange(
        payload.requestId, 1, UINT32_MAX, "workshop_release.requestId")
    if not requestId then return nil, fieldError end
    local leaseId
    leaseId, fieldError = token(payload.leaseId, MAX_TOKEN_BYTES, "workshop_release.leaseId")
    if not leaseId then return nil, fieldError end
    local resourceId
    resourceId, fieldError = workshopResource(payload.resourceId, "workshop_release.resourceId")
    if not resourceId then return nil, fieldError end
    if type(payload.reason) ~= "string" or not WORKSHOP_RELEASE_REASONS[payload.reason] then
        return nil, "workshop_release.reason is invalid"
    end
    return {
        sessionId = sessionId,
        requestId = requestId,
        leaseId = leaseId,
        resourceId = resourceId,
        reason = payload.reason,
    }
end

local function normalizeWorkshopResources(value, label)
    if not Codec.isArray(value) then return nil, label .. " must be an array" end
    if #value ~= 10 then return nil, label .. " must contain all 10 workshop resources" end
    local resources, seen = {}, {}
    for index = 1, #value do
        local resourceLabel = label .. "[" .. index .. "]"
        local valid, shapeError = shape(value[index], resourceLabel,
            { "resourceId", "revision", "occupied" }, { "ownerPlayerId" })
        if not valid then return nil, shapeError end
        local resourceId, fieldError = workshopResource(
            value[index].resourceId, resourceLabel .. ".resourceId")
        if not resourceId then return nil, fieldError end
        if seen[resourceId] then return nil, label .. " contains a duplicate resourceId" end
        seen[resourceId] = true
        local revision
        revision, fieldError = integerInRange(
            value[index].revision, 0, UINT32_MAX, resourceLabel .. ".revision")
        if revision == nil then return nil, fieldError end
        if type(value[index].occupied) ~= "boolean" then
            return nil, resourceLabel .. ".occupied must be boolean"
        end
        local ownerPlayerId
        if value[index].ownerPlayerId ~= nil then
            ownerPlayerId, fieldError = integerInRange(
                value[index].ownerPlayerId, 1, Protocol.MAX_PLAYERS,
                resourceLabel .. ".ownerPlayerId")
            if not ownerPlayerId then return nil, fieldError end
        end
        if value[index].occupied ~= (ownerPlayerId ~= nil) then
            return nil, resourceLabel .. ".ownerPlayerId must be present exactly when occupied"
        end
        resources[#resources + 1] = {
            resourceId = resourceId,
            revision = revision,
            occupied = value[index].occupied,
            ownerPlayerId = ownerPlayerId,
        }
    end
    table.sort(resources, function(a, b) return a.resourceId < b.resourceId end)
    return Codec.array(resources)
end

local PALLET_JACK_DIRECTIONS = {
    northwest = true, north = true, northeast = true, east = true,
    southeast = true, south = true, southwest = true, west = true,
}

local function normalizePalletJackState(value, label)
    local valid, shapeError = shape(value, label,
        { "x", "y", "direction", "operating", "moving" },
        { "operatorPlayerId", "carriedPalletId", "candidatePalletId" })
    if not valid then return nil, shapeError end
    local x, fieldError = numberInRange(
        value.x, -MAX_COORDINATE, MAX_COORDINATE, label .. ".x")
    if x == nil then return nil, fieldError end
    local y
    y, fieldError = numberInRange(
        value.y, -MAX_COORDINATE, MAX_COORDINATE, label .. ".y")
    if y == nil then return nil, fieldError end
    if type(value.direction) ~= "string" or not PALLET_JACK_DIRECTIONS[value.direction] then
        return nil, label .. ".direction is invalid"
    end
    if type(value.operating) ~= "boolean" then
        return nil, label .. ".operating must be boolean"
    end
    if type(value.moving) ~= "boolean" then
        return nil, label .. ".moving must be boolean"
    end
    if value.moving and not value.operating then
        return nil, label .. ".moving requires an operator"
    end
    local operatorPlayerId
    if value.operatorPlayerId ~= nil then
        operatorPlayerId, fieldError = integerInRange(
            value.operatorPlayerId, 1, Protocol.MAX_PLAYERS, label .. ".operatorPlayerId")
        if not operatorPlayerId then return nil, fieldError end
    end
    if value.operating ~= (operatorPlayerId ~= nil) then
        return nil, label .. ".operatorPlayerId must be present exactly when operating"
    end
    local carriedPalletId
    if value.carriedPalletId ~= nil then
        carriedPalletId, fieldError = token(
            value.carriedPalletId, MAX_TOKEN_BYTES, label .. ".carriedPalletId")
        if not carriedPalletId then return nil, fieldError end
    end
    local candidatePalletId
    if value.candidatePalletId ~= nil then
        candidatePalletId, fieldError = token(
            value.candidatePalletId, MAX_TOKEN_BYTES, label .. ".candidatePalletId")
        if not candidatePalletId then return nil, fieldError end
        if not value.operating or carriedPalletId then
            return nil, label .. ".candidatePalletId requires an operating empty jack"
        end
    end
    return {
        x = x,
        y = y,
        direction = value.direction,
        operating = value.operating,
        moving = value.moving,
        operatorPlayerId = operatorPlayerId,
        carriedPalletId = carriedPalletId,
        candidatePalletId = candidatePalletId,
    }
end

local function normalizePalletJackSnapshot(payload)
    local valid, shapeError = shape(payload, "pallet_jack_snapshot payload",
        { "sessionId", "serverTick", "jack", "machines" })
    if not valid then return nil, shapeError end
    local sessionId, fieldError = token(
        payload.sessionId, MAX_TOKEN_BYTES, "pallet_jack_snapshot.sessionId")
    if not sessionId then return nil, fieldError end
    local serverTick
    serverTick, fieldError = integerInRange(
        payload.serverTick, 0, UINT32_MAX, "pallet_jack_snapshot.serverTick")
    if serverTick == nil then return nil, fieldError end
    local jack
    jack, fieldError = normalizePalletJackState(
        payload.jack, "pallet_jack_snapshot.jack")
    if not jack then return nil, fieldError end
    local machines
    machines, fieldError = MachinePose.normalize(
        payload.machines, jack, MAX_COORDINATE, "pallet_jack_snapshot.machines")
    if not machines then return nil, fieldError end
    return {
        sessionId = sessionId,
        serverTick = serverTick,
        jack = jack,
        machines = machines,
    }
end

local function normalizeWorkshopSnapshot(payload)
    local valid, shapeError = shape(payload, "workshop_snapshot payload",
        { "sessionId", "revision", "resources", "wrapper" })
    if not valid then return nil, shapeError end
    local sessionId, fieldError = token(
        payload.sessionId, MAX_TOKEN_BYTES, "workshop_snapshot.sessionId")
    if not sessionId then return nil, fieldError end
    local revision
    revision, fieldError = integerInRange(
        payload.revision, 0, UINT32_MAX, "workshop_snapshot.revision")
    if revision == nil then return nil, fieldError end
    local resources
    resources, fieldError = normalizeWorkshopResources(
        payload.resources, "workshop_snapshot.resources")
    if not resources then return nil, fieldError end
    local wrapper
    wrapper, fieldError = normalizeWorkshopWrapperRuntime(
        payload.wrapper, "workshop_snapshot.wrapper")
    if not wrapper then return nil, fieldError end
    return {
        sessionId = sessionId,
        revision = revision,
        resources = resources,
        wrapper = wrapper,
    }
end

local function normalizeCutterSnapshot(payload)
    local valid, shapeError = shape(payload, "cutter_snapshot payload",
        { "sessionId", "serverTick", "resourceRevision", "view" })
    if not valid then return nil, shapeError end
    local sessionId, fieldError = token(
        payload.sessionId, MAX_TOKEN_BYTES, "cutter_snapshot.sessionId")
    if not sessionId then return nil, fieldError end
    local serverTick
    serverTick, fieldError = integerInRange(
        payload.serverTick, 0, UINT32_MAX, "cutter_snapshot.serverTick")
    if serverTick == nil then return nil, fieldError end
    local resourceRevision
    resourceRevision, fieldError = integerInRange(
        payload.resourceRevision, 0, UINT32_MAX, "cutter_snapshot.resourceRevision")
    if resourceRevision == nil then return nil, fieldError end
    local view
    view, fieldError = normalizeCutterWorkshopView(
        payload.view, "cutter_snapshot.view")
    if not view then return nil, fieldError end
    return {
        sessionId = sessionId,
        serverTick = serverTick,
        resourceRevision = resourceRevision,
        view = view,
    }
end

local function normalizeWindmillSnapshot(payload)
    local valid, shapeError = shape(payload, "windmill_snapshot payload",
        { "sessionId", "serverTick", "resourceRevision", "view" })
    if not valid then return nil, shapeError end
    local sessionId, fieldError = token(
        payload.sessionId, MAX_TOKEN_BYTES, "windmill_snapshot.sessionId")
    if not sessionId then return nil, fieldError end
    local serverTick
    serverTick, fieldError = integerInRange(
        payload.serverTick, 0, UINT32_MAX, "windmill_snapshot.serverTick")
    if serverTick == nil then return nil, fieldError end
    local resourceRevision
    resourceRevision, fieldError = integerInRange(
        payload.resourceRevision, 0, UINT32_MAX, "windmill_snapshot.resourceRevision")
    if resourceRevision == nil then return nil, fieldError end
    local view
    view, fieldError = normalizeWindmillWorkshopView(
        payload.view, "windmill_snapshot.view")
    if not view then return nil, fieldError end
    return {
        sessionId = sessionId,
        serverTick = serverTick,
        resourceRevision = resourceRevision,
        view = view,
    }
end

local function normalizeInput(payload)
    local valid, shapeError = shape(payload, "input payload",
        { "sessionId", "sequence", "moveX", "moveY" })
    if not valid then return nil, shapeError end
    local sessionId, fieldError = token(payload.sessionId, MAX_TOKEN_BYTES, "input.sessionId")
    if not sessionId then return nil, fieldError end
    local sequence
    sequence, fieldError = integerInRange(payload.sequence, 0, UINT32_MAX, "input.sequence")
    if not sequence then return nil, fieldError end
    local moveX
    moveX, fieldError = numberInRange(payload.moveX, -1, 1, "input.moveX")
    if not moveX then return nil, fieldError end
    local moveY
    moveY, fieldError = numberInRange(payload.moveY, -1, 1, "input.moveY")
    if not moveY then return nil, fieldError end
    return { sessionId = sessionId, sequence = sequence, moveX = moveX, moveY = moveY }
end

local function normalizeSnapshot(payload)
    local valid, shapeError = shape(payload, "snapshot payload",
        { "sessionId", "serverTick", "players" })
    if not valid then return nil, shapeError end
    local sessionId, fieldError = token(payload.sessionId, MAX_TOKEN_BYTES, "snapshot.sessionId")
    if not sessionId then return nil, fieldError end
    local serverTick
    serverTick, fieldError = integerInRange(payload.serverTick, 0, UINT32_MAX, "snapshot.serverTick")
    if not serverTick then return nil, fieldError end
    if not Codec.isArray(payload.players) or #payload.players ~= 1 then
        return nil, "snapshot.players must contain exactly one player"
    end
    local players
    players, fieldError = normalizePlayers(payload.players, "snapshot.players")
    if not players then return nil, fieldError end
    return { sessionId = sessionId, serverTick = serverTick, players = players }
end

local VISITOR_STATES = {
    scheduled = true,
    entering = true,
    waiting = true,
    reviewing = true,
    exiting = true,
    finished = true,
}

local VISITOR_DECISIONS = {
    accepted = true,
    declined = true,
    timed_out = true,
}

local VISITOR_FIELDS = {
    "state", "visible", "x", "y", "waypoint", "seatIndex", "character",
    "facing", "intentX", "intentY", "motionX", "motionY", "currentSpeed",
    "animationDistance", "animationClock", "idleClock", "inMotion", "waitTimer",
    "arrivalTimer",
}

local function normalizeVisitor(value, label)
    local valid, shapeError = shape(value, label, VISITOR_FIELDS, { "decision" })
    if not valid then return nil, shapeError end
    if not VISITOR_STATES[value.state] then return nil, label .. ".state is invalid" end
    if type(value.visible) ~= "boolean" then return nil, label .. ".visible must be boolean" end
    local normalized = { state = value.state, visible = value.visible }
    local fieldError
    normalized.x, fieldError = numberInRange(value.x, -MAX_COORDINATE, MAX_COORDINATE,
        label .. ".x")
    if normalized.x == nil then return nil, fieldError end
    normalized.y, fieldError = numberInRange(value.y, -MAX_COORDINATE, MAX_COORDINATE,
        label .. ".y")
    if normalized.y == nil then return nil, fieldError end
    normalized.waypoint, fieldError = integerInRange(value.waypoint, 1, 64,
        label .. ".waypoint")
    if normalized.waypoint == nil then return nil, fieldError end
    normalized.seatIndex, fieldError = integerInRange(value.seatIndex, 0, 64,
        label .. ".seatIndex")
    if normalized.seatIndex == nil then return nil, fieldError end
    normalized.character, fieldError = characterToken(value.character, label .. ".character")
    if not normalized.character then return nil, fieldError end
    if value.facing ~= -1 and value.facing ~= 1 then
        return nil, label .. ".facing must be -1 or 1"
    end
    normalized.facing = value.facing
    for _, field in ipairs({ "intentX", "intentY", "motionX", "motionY" }) do
        normalized[field], fieldError = numberInRange(value[field], -1, 1,
            label .. "." .. field)
        if normalized[field] == nil then return nil, fieldError end
    end
    normalized.currentSpeed, fieldError = numberInRange(value.currentSpeed, 0, MAX_VELOCITY,
        label .. ".currentSpeed")
    if normalized.currentSpeed == nil then return nil, fieldError end
    for _, field in ipairs({
        "animationDistance", "animationClock", "idleClock", "waitTimer",
    }) do
        normalized[field], fieldError = numberInRange(value[field], 0,
            MAX_ANIMATION_DISTANCE, label .. "." .. field)
        if normalized[field] == nil then return nil, fieldError end
    end
    normalized.arrivalTimer, fieldError = numberInRange(value.arrivalTimer,
        -MAX_ANIMATION_DISTANCE, MAX_ANIMATION_DISTANCE, label .. ".arrivalTimer")
    if normalized.arrivalTimer == nil then return nil, fieldError end
    if type(value.inMotion) ~= "boolean" then return nil, label .. ".inMotion must be boolean" end
    normalized.inMotion = value.inMotion
    if value.decision ~= nil then
        if not VISITOR_DECISIONS[value.decision] then
            return nil, label .. ".decision is invalid"
        end
        normalized.decision = value.decision
    end
    return normalized
end

local function normalizeVisitorSnapshot(payload)
    local valid, shapeError = shape(payload, "visitor_snapshot payload",
        { "sessionId", "serverTick", "customer", "vendor" })
    if not valid then return nil, shapeError end
    local sessionId, fieldError = token(
        payload.sessionId, MAX_TOKEN_BYTES, "visitor_snapshot.sessionId")
    if not sessionId then return nil, fieldError end
    local serverTick
    serverTick, fieldError = integerInRange(
        payload.serverTick, 0, UINT32_MAX, "visitor_snapshot.serverTick")
    if not serverTick then return nil, fieldError end
    local customer
    customer, fieldError = normalizeVisitor(payload.customer, "visitor_snapshot.customer")
    if not customer then return nil, fieldError end
    local vendor
    vendor, fieldError = normalizeVisitor(payload.vendor, "visitor_snapshot.vendor")
    if not vendor then return nil, fieldError end
    return {
        sessionId = sessionId,
        serverTick = serverTick,
        customer = customer,
        vendor = vendor,
    }
end

local BAY_DOOR_STATES = {
    closed = true,
    opening = true,
    open = true,
    closing = true,
}

local TRUCK_STATES = {
    absent = true,
    scheduled = true,
    waiting_for_bay = true,
    backing = true,
    parked_closed = true,
    cargo_opening = true,
    cargo_open = true,
    cargo_closing = true,
    departing = true,
}

local TRUCK_MODES = {
    delivery = true,
    vendor_delivery = true,
    machine_delivery = true,
    pickup = true,
}

local function normalizeBayDoor(value, label)
    local valid, shapeError = shape(value, label, { "state", "progress" })
    if not valid then return nil, shapeError end
    if not BAY_DOOR_STATES[value.state] then return nil, label .. ".state is invalid" end
    local progress, fieldError = numberInRange(value.progress, 0, 1, label .. ".progress")
    if progress == nil then return nil, fieldError end
    if value.state == "closed" and progress ~= 0 then
        return nil, label .. ".closed progress must be zero"
    end
    if value.state == "open" and progress ~= 1 then
        return nil, label .. ".open progress must be one"
    end
    return { state = value.state, progress = progress }
end

local function normalizeTruck(value, label)
    local valid, shapeError = shape(value, label,
        { "state", "backingProgress", "cargoProgress" }, { "jobId", "mode" })
    if not valid then return nil, shapeError end
    if not TRUCK_STATES[value.state] then return nil, label .. ".state is invalid" end
    local normalized = { state = value.state }
    local fieldError
    normalized.backingProgress, fieldError = numberInRange(
        value.backingProgress, 0, 1, label .. ".backingProgress")
    if normalized.backingProgress == nil then return nil, fieldError end
    normalized.cargoProgress, fieldError = numberInRange(
        value.cargoProgress, 0, 1, label .. ".cargoProgress")
    if normalized.cargoProgress == nil then return nil, fieldError end
    if value.state == "absent" then
        if value.jobId ~= nil or value.mode ~= nil then
            return nil, label .. ".absent truck cannot have a job or mode"
        end
        if normalized.backingProgress ~= 0 or normalized.cargoProgress ~= 0 then
            return nil, label .. ".absent truck progress must be zero"
        end
    else
        normalized.jobId, fieldError = token(value.jobId, MAX_TOKEN_BYTES, label .. ".jobId")
        if not normalized.jobId then return nil, fieldError end
        if type(value.mode) ~= "string" or not TRUCK_MODES[value.mode] then
            return nil, label .. ".mode is invalid"
        end
        normalized.mode = value.mode
    end
    return normalized
end

local function normalizeEnvironmentSnapshot(payload)
    local valid, shapeError = shape(payload, "environment_snapshot payload",
        { "sessionId", "serverTick", "bayDoor", "truck" })
    if not valid then return nil, shapeError end
    local sessionId, fieldError = token(
        payload.sessionId, MAX_TOKEN_BYTES, "environment_snapshot.sessionId")
    if not sessionId then return nil, fieldError end
    local serverTick
    serverTick, fieldError = integerInRange(
        payload.serverTick, 0, UINT32_MAX, "environment_snapshot.serverTick")
    if not serverTick then return nil, fieldError end
    local bayDoor
    bayDoor, fieldError = normalizeBayDoor(payload.bayDoor, "environment_snapshot.bayDoor")
    if not bayDoor then return nil, fieldError end
    local truck
    truck, fieldError = normalizeTruck(payload.truck, "environment_snapshot.truck")
    if not truck then return nil, fieldError end
    return {
        sessionId = sessionId,
        serverTick = serverTick,
        bayDoor = bayDoor,
        truck = truck,
    }
end

local function normalizeForkliftSnapshot(payload)
    local valid, fieldError = shape(payload, "forklift_snapshot payload", { "sessionId", "serverTick", "forklift" })
    if not valid then return nil, fieldError end
    local sessionId
    sessionId, fieldError = token(payload.sessionId, MAX_TOKEN_BYTES, "forklift_snapshot.sessionId")
    if not sessionId then return nil, fieldError end
    local tick
    tick, fieldError = integerInRange(payload.serverTick, 0, UINT32_MAX, "forklift_snapshot.serverTick")
    if tick == nil then return nil, fieldError end
    valid, fieldError = shape(payload.forklift, "forklift_snapshot.forklift", {
        "owned", "x", "y", "direction", "operating", "moving", "animationDistance",
        "forkHeight", "targetForkHeight", "lifting",
    }, { "operatorPlayerId", "carriedPalletId" })
    if not valid then return nil, fieldError end
    if not Forklift.validState(payload.forklift) then return nil, "forklift_snapshot.forklift is inconsistent" end
    return { sessionId = sessionId, serverTick = tick, forklift = Forklift.normalize(payload.forklift) }
end

local function normalizePing(payload, kind)
    local valid, shapeError = shape(payload, kind .. " payload", { "sessionId", "nonce" })
    if not valid then return nil, shapeError end
    local sessionId, fieldError = token(payload.sessionId, MAX_TOKEN_BYTES, kind .. ".sessionId")
    if not sessionId then return nil, fieldError end
    local nonce
    nonce, fieldError = integerInRange(payload.nonce, 0, UINT32_MAX, kind .. ".nonce")
    if not nonce then return nil, fieldError end
    return { sessionId = sessionId, nonce = nonce }
end

local function normalizeLeave(payload)
    local valid, shapeError = shape(payload, "leave payload",
        { "sessionId", "playerId", "reason" }, { "serverTick" })
    if not valid then return nil, shapeError end
    local sessionId, fieldError = token(payload.sessionId, MAX_TOKEN_BYTES, "leave.sessionId")
    if not sessionId then return nil, fieldError end
    local playerId
    playerId, fieldError = integerInRange(
        payload.playerId, 1, Protocol.MAX_PLAYERS, "leave.playerId")
    if not playerId then return nil, fieldError end
    local reason
    reason, fieldError = printableString(payload.reason, 1, MAX_REASON_BYTES, "leave.reason")
    if not reason then return nil, fieldError end
    local normalized = { sessionId = sessionId, playerId = playerId, reason = reason }
    if payload.serverTick ~= nil then
        normalized.serverTick, fieldError = integerInRange(
            payload.serverTick, 0, UINT32_MAX, "leave.serverTick")
        if not normalized.serverTick then return nil, fieldError end
    end
    return normalized
end

local function normalizeError(payload)
    local valid, shapeError = shape(payload, "error payload",
        { "code", "message" }, { "sessionId" })
    if not valid then return nil, shapeError end
    local code, fieldError = token(payload.code, MAX_ERROR_CODE_BYTES, "error.code")
    if not code then return nil, fieldError end
    local message
    message, fieldError = printableString(
        payload.message, 1, MAX_ERROR_MESSAGE_BYTES, "error.message")
    if not message then return nil, fieldError end
    local normalized = { code = code, message = message }
    if payload.sessionId ~= nil then
        normalized.sessionId, fieldError = token(
            payload.sessionId, MAX_TOKEN_BYTES, "error.sessionId")
        if not normalized.sessionId then return nil, fieldError end
    end
    return normalized
end

local PAYLOAD_NORMALIZERS = {
    hello = normalizeHello,
    welcome = normalizeWelcome,
    shop_snapshot = normalizeShopSnapshot,
    shop_state = normalizeShopState,
    interaction_request = normalizeInteractionRequest,
    interaction_result = normalizeInteractionResult,
    workshop_acquire = normalizeWorkshopAcquire,
    workshop_grant = normalizeWorkshopGrant,
    workshop_command = normalizeWorkshopCommand,
    workshop_result = normalizeWorkshopResult,
    workshop_release = normalizeWorkshopRelease,
    workshop_snapshot = normalizeWorkshopSnapshot,
    cutter_snapshot = normalizeCutterSnapshot,
    windmill_snapshot = normalizeWindmillSnapshot,
    pallet_jack_snapshot = normalizePalletJackSnapshot,
    forklift_snapshot = normalizeForkliftSnapshot,
    input = normalizeInput,
    snapshot = normalizeSnapshot,
    visitor_snapshot = normalizeVisitorSnapshot,
    environment_snapshot = normalizeEnvironmentSnapshot,
    ping = function(payload) return normalizePing(payload, "ping") end,
    pong = function(payload) return normalizePing(payload, "pong") end,
    leave = normalizeLeave,
    error = normalizeError,
}

local function normalizeEnvelope(envelope)
    local valid, shapeError = shape(envelope, "envelope", { "version", "type", "payload" })
    if not valid then return nil, shapeError end
    if envelope.version ~= Protocol.VERSION then return nil, "unsupported protocol version" end
    if type(envelope.type) ~= "string" or not PAYLOAD_NORMALIZERS[envelope.type] then
        return nil, "unsupported message type"
    end
    local payload, payloadError = PAYLOAD_NORMALIZERS[envelope.type](envelope.payload)
    if not payload then return nil, payloadError end
    return { version = Protocol.VERSION, type = envelope.type, payload = payload }
end

local function limitsFor(kind)
    return (kind == "shop_snapshot" or kind == "shop_state")
        and SHOP_CODEC_LIMITS or REALTIME_CODEC_LIMITS
end

function Protocol.packetLimitFor(kindOrEnvelope)
    local kind = type(kindOrEnvelope) == "table" and kindOrEnvelope.type or kindOrEnvelope
    if type(kind) ~= "string" or not PAYLOAD_NORMALIZERS[kind] then
        return protocolError("unsupported message type")
    end
    return (kind == "shop_snapshot" or kind == "shop_state")
        and Protocol.MAX_SHOP_SNAPSHOT_BYTES
        or Protocol.MAX_PACKET_BYTES
end

function Protocol.route(kindOrEnvelope)
    local kind = type(kindOrEnvelope) == "table" and kindOrEnvelope.type or kindOrEnvelope
    local route = type(kind) == "string" and ROUTES[kind] or nil
    if not route then return protocolError("unsupported message type") end
    return route.channel, route.delivery
end

function Protocol.validate(envelope)
    local normalized, validationError = normalizeEnvelope(envelope)
    if not normalized then return protocolError(validationError) end
    local _, codecError = Codec.encode(normalized, limitsFor(normalized.type))
    if codecError then return protocolError("codec validation failed: " .. tostring(codecError)) end
    return normalized
end

function Protocol.make(kind, payload)
    return Protocol.validate({ version = Protocol.VERSION, type = kind, payload = payload })
end

function Protocol.encode(envelopeOrKind, payload)
    local envelope
    if type(envelopeOrKind) == "string" then
        envelope = { version = Protocol.VERSION, type = envelopeOrKind, payload = payload }
    elseif type(envelopeOrKind) == "table" and payload == nil then
        envelope = envelopeOrKind
    else
        return protocolError("encode expects an envelope or a message type and payload")
    end
    local normalized, validationError = normalizeEnvelope(envelope)
    if not normalized then return protocolError(validationError) end
    local encoded, codecError = Codec.encode(normalized, limitsFor(normalized.type))
    if not encoded then return protocolError("codec encode failed: " .. tostring(codecError)) end
    return encoded
end

function Protocol.decode(packet)
    if type(packet) ~= "string" then return protocolError("packet must be a string") end
    if #packet > Protocol.MAX_SHOP_SNAPSHOT_BYTES then
        return protocolError("packet exceeds maximum size")
    end
    local decoded, codecError = Codec.decode(packet, SHOP_CODEC_LIMITS)
    if not decoded then return protocolError("codec decode failed: " .. tostring(codecError)) end
    local normalized, validationError = normalizeEnvelope(decoded)
    if not normalized then return protocolError(validationError) end
    local limit = (normalized.type == "shop_snapshot" or normalized.type == "shop_state")
        and Protocol.MAX_SHOP_SNAPSHOT_BYTES or Protocol.MAX_PACKET_BYTES
    if #packet > limit then return protocolError("packet exceeds limit for " .. normalized.type) end
    local canonical, canonicalError = Codec.encode(normalized, limitsFor(normalized.type))
    if not canonical then return protocolError("codec encode failed: " .. tostring(canonicalError)) end
    if canonical ~= packet then return protocolError("packet is not canonical") end
    return normalized
end

return Protocol
