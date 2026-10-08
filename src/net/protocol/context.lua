-- Wire protocol constants, routes, and codec limits.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    Runtime.Codec = require("src.net.codec")
    Runtime.OfficeIntent = require("src.office_intent")
    Runtime.MachinePose = require("src.machine_pose")
    Runtime.WarehouseIntent = require("src.warehouse_intent")
    Runtime.Forklift = require("src.forklift")
    Runtime.MachineResource = require("src.machine_resource_id")
    Runtime.PlacementGrid = require("src.placement_grid")
    Runtime.EmployeePose = require("src.employee_pose")
    Runtime.RabbitColorways = require("src.rabbit_colorways")

    Runtime.Protocol = {
        VERSION = 30,
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

    Runtime.Protocol.CHANNELS = {
        control = Runtime.Protocol.CHANNEL_CONTROL,
        state = Runtime.Protocol.CHANNEL_STATE,
        durable = Runtime.Protocol.CHANNEL_DURABLE,
    }

    Runtime.UINT32_MAX = 4294967295
    Runtime.MAX_TOKEN_BYTES = 64
    Runtime.MAX_CHARACTER_BYTES = 48
    Runtime.MAX_REASON_BYTES = 96
    Runtime.MAX_ERROR_CODE_BYTES = 32
    Runtime.MAX_ERROR_MESSAGE_BYTES = 160
    Runtime.MAX_COORDINATE = 100000
    Runtime.MAX_VELOCITY = 10000
    Runtime.MAX_ANIMATION_DISTANCE = 1000000000
    Runtime.MAX_WORKSHOP_AMOUNT = 100000000
    Runtime.MAX_WORKSHOP_VIEW_TEXT_BYTES = 96
    Runtime.MAX_WORKSHOP_CYCLE_TIME = 600
    Runtime.MAX_WORKSHOP_DISTANCE = 100000
    Runtime.MAX_WORKSHOP_INVENTORY = 100000
    Runtime.MAX_WINDMILL_ID_BYTES = 24
    Runtime.MAX_WINDMILL_VIEW_TEXT_TOTAL_BYTES = 96

    Runtime.REALTIME_CODEC_LIMITS = {
        maxBytes = Runtime.Protocol.MAX_PACKET_BYTES,
        maxDepth = 8,
        maxEntries = 256,
        -- Typed office messages are bounded to 600 bytes; other fields keep their
        -- narrower per-message schema limits below. The packet cap stays 1,200.
        maxStringBytes = 600,
        maxNumberBytes = 32,
    }

    Runtime.SHOP_CODEC_LIMITS = {
        maxBytes = Runtime.Protocol.MAX_SHOP_SNAPSHOT_BYTES,
        maxDepth = 32,
        maxEntries = 32768,
        maxStringBytes = 128 * 1024,
        maxNumberBytes = 32,
    }

    Runtime.ROUTES = {
        hello = { channel = Runtime.Protocol.CHANNEL_CONTROL, delivery = "reliable" },
        welcome = { channel = Runtime.Protocol.CHANNEL_CONTROL, delivery = "reliable" },
        shop_snapshot = { channel = Runtime.Protocol.CHANNEL_DURABLE, delivery = "reliable" },
        shop_state = { channel = Runtime.Protocol.CHANNEL_DURABLE, delivery = "reliable" },
        radio_state = { channel = Runtime.Protocol.CHANNEL_CONTROL, delivery = "reliable" },
        interaction_request = { channel = Runtime.Protocol.CHANNEL_CONTROL, delivery = "reliable" },
        interaction_result = { channel = Runtime.Protocol.CHANNEL_CONTROL, delivery = "reliable" },
        highfive_request = { channel = Runtime.Protocol.CHANNEL_CONTROL, delivery = "reliable" },
        highfive_offer = { channel = Runtime.Protocol.CHANNEL_CONTROL, delivery = "reliable" },
        highfive_response = { channel = Runtime.Protocol.CHANNEL_CONTROL, delivery = "reliable" },
        highfive_request_result = { channel = Runtime.Protocol.CHANNEL_CONTROL, delivery = "reliable" },
        highfive_result = { channel = Runtime.Protocol.CHANNEL_CONTROL, delivery = "reliable" },
        highfive_start = { channel = Runtime.Protocol.CHANNEL_CONTROL, delivery = "reliable" },
        workshop_acquire = { channel = Runtime.Protocol.CHANNEL_CONTROL, delivery = "reliable" },
        workshop_grant = { channel = Runtime.Protocol.CHANNEL_CONTROL, delivery = "reliable" },
        workshop_command = { channel = Runtime.Protocol.CHANNEL_CONTROL, delivery = "reliable" },
        workshop_result = { channel = Runtime.Protocol.CHANNEL_CONTROL, delivery = "reliable" },
        workshop_release = { channel = Runtime.Protocol.CHANNEL_CONTROL, delivery = "reliable" },
        workshop_snapshot = { channel = Runtime.Protocol.CHANNEL_STATE, delivery = "unreliable" },
        cutter_snapshot = { channel = Runtime.Protocol.CHANNEL_STATE, delivery = "unreliable" },
        wrapper_snapshot = { channel = Runtime.Protocol.CHANNEL_STATE, delivery = "unreliable" },
        windmill_snapshot = { channel = Runtime.Protocol.CHANNEL_STATE, delivery = "unreliable" },
        pallet_jack_snapshot = { channel = Runtime.Protocol.CHANNEL_STATE, delivery = "unreliable" },
        forklift_snapshot = { channel = Runtime.Protocol.CHANNEL_STATE, delivery = "unreliable" },
        input = { channel = Runtime.Protocol.CHANNEL_STATE, delivery = "unreliable" },
        snapshot = { channel = Runtime.Protocol.CHANNEL_STATE, delivery = "unreliable" },
        visitor_snapshot = { channel = Runtime.Protocol.CHANNEL_STATE, delivery = "unreliable" },
        environment_snapshot = { channel = Runtime.Protocol.CHANNEL_STATE, delivery = "unreliable" },
        employee_snapshot = { channel = Runtime.Protocol.CHANNEL_STATE, delivery = "unreliable" },
        ping = { channel = Runtime.Protocol.CHANNEL_STATE, delivery = "unreliable" },
        pong = { channel = Runtime.Protocol.CHANNEL_STATE, delivery = "unreliable" },
        leave = { channel = Runtime.Protocol.CHANNEL_CONTROL, delivery = "reliable" },
        error = { channel = Runtime.Protocol.CHANNEL_CONTROL, delivery = "reliable" },
    }

    Runtime.Protocol.MESSAGE_TYPES = {
        "hello", "welcome", "shop_snapshot", "shop_state", "radio_state", "interaction_request",
        "interaction_result", "highfive_request", "highfive_offer", "highfive_response",
        "highfive_request_result", "highfive_result", "highfive_start",
        "workshop_acquire", "workshop_grant", "workshop_command",
        "workshop_result", "workshop_release", "workshop_snapshot", "cutter_snapshot", "wrapper_snapshot",
        "windmill_snapshot", "pallet_jack_snapshot", "forklift_snapshot", "input", "snapshot",
        "visitor_snapshot", "environment_snapshot", "employee_snapshot", "ping", "pong", "leave", "error",
    }
end

return Component
