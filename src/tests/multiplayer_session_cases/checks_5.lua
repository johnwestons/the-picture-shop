-- Multiplayer session regression scenarios.
-- A fresh Context belongs to each invocation; closures keep its live values.
local Component = {}

function Component.run(Context)
    Context.check("multiplayer_session_disconnect_does_not_queue_followup_send_error",
        Context.disconnectCount == 1 and Context.errorCount == 0 and Context.disconnectClient.terminal
        and Context.disconnectClient.transport == nil)
    Context.disconnectClient:stop("Disconnect test complete")
    Context.disconnectHost:stop("Disconnect test complete")

    Context.syncNetwork = Context.fakeNetwork()
    Context.syncHost = Context.Session.new({ transportFactory = Context.syncNetwork.factory, clock = Context.clock })
    Context.syncClient = Context.Session.new({ transportFactory = Context.syncNetwork.factory, clock = Context.clock })
    Context.syncHostPlayer = Context.motionPlayer(500, 520)
    Context.syncGuestPlayer = Context.motionPlayer(530, 520)
    Context.authoritativeState = {
        money = 180,
        inventory = { paper = 40, prints = 0, stock = { shipping_cartons = 20 } },
        calendar = { year = 2026, month = 1, day = 3, weekday = 6,
            elapsed = 20, totalDays = 2 },
        jobs = { active = {}, completed = {}, declined = {} },
        clientEmails = { nextEmailId = 1, nextPromotionId = 1,
            pending = {}, inbox = {}, archive = {}, sentPromotions = {} },
    }
    Context.authoritativeVisitors = {
        customer = Context.visitorState("entering", true, 580, 350, "business-cat"),
        vendor = Context.visitorState("scheduled", false, 500, 300, "green-blazer-cat"),
    }
    Context.authoritativeEnvironment = {
        bayDoor = { state = "closed", progress = 0 },
        truck = { state = "absent", backingProgress = 0, cargoProgress = 0 },
    }
    Context.authoritativePalletJack = Context.palletJackState()
    Context.authoritativeMachinePoses = Context.machinePoseState()
    Context.syncHostContext = {
        localPlayer = Context.syncHostPlayer,
        resolveGuestSpawn = function() return 530, 520 end,
        getShopSnapshot = function()
            return {
                state = Context.authoritativeState,
                player = { x = Context.syncHostPlayer.x, y = Context.syncHostPlayer.y,
                    character = Context.syncHostPlayer.character },
            }
        end,
        getVisitorSnapshot = function() return Context.authoritativeVisitors end,
        getEnvironmentSnapshot = function() return Context.authoritativeEnvironment end,
        getPalletJackSnapshot = function() return Context.authoritativePalletJack end,
        getMachinePoseSnapshot = function() return Context.authoritativeMachinePoses end,
        getRadioSnapshot = function()
            return { trackIndex = 4, active = true, paused = false,
                muted = false, positionMs = 3700 }
        end,
        moveRemote = function() end,
    }
    Context.syncClientContext = {
        localPlayer = Context.syncGuestPlayer,
        inputX = 0,
        inputY = 0,
    }
    Context.syncHost:startHost({ name = "State Host", character = "rabbit-worker",
        x = Context.syncHostPlayer.x, y = Context.syncHostPlayer.y, addressOptions = Context.addressOptions })
    Context.syncHost.sessionId = "shop-state-test"
    Context.syncClient:startClient("192.168.1.50:22122", {
        name = "State Guest", character = "rabbit-worker",
    })
    Context.syncClient.clientNonce = "shop-state-nonce"
    Context.syncClient:update(0, Context.syncClientContext)
    Context.syncHost:update(0, Context.syncHostContext)
    Context.syncClient:update(0, Context.syncClientContext)
    Context.syncHost:drainEvents();
    (function()
        local initialClientEvents = Context.syncClient:drainEvents()
        local initialRadioState = Context.eventNamed(initialClientEvents, "radio_state")
        local initialRadioPackets = Context.syncNetwork:messages("host_to_client", "radio_state")
        Context.check("multiplayer_host_sends_current_radio_state_to_joining_client",
            initialRadioState and initialRadioState.trackIndex == 4
            and initialRadioState.active and not initialRadioState.paused
            and initialRadioState.positionMs == 3700
            and #initialRadioPackets == 1
            and initialRadioPackets[1].channel == Context.Protocol.CHANNEL_CONTROL
            and initialRadioPackets[1].reliable)

        local radioSent = Context.syncHost:publishRadioState({
            trackIndex = 5, active = true, paused = true, muted = true, positionMs = 9100,
        })
        Context.syncClient:update(0, Context.syncClientContext)
        local updatedRadioEvents = Context.syncClient:drainEvents()
        local updatedRadioState = Context.eventNamed(updatedRadioEvents, "radio_state")
        local radioPackets = Context.syncNetwork:messages("host_to_client", "radio_state")
        Context.check("multiplayer_host_broadcasts_radio_controls_to_clients",
            radioSent and updatedRadioState and updatedRadioState.trackIndex == 5
            and updatedRadioState.active and updatedRadioState.paused and updatedRadioState.muted
            and updatedRadioState.positionMs == 9100 and updatedRadioState.revision > 0
            and #radioPackets == 2 and Context.syncClient.lastRadioRevision == updatedRadioState.revision)
    end)()

    -- Let the host establish its comparison baseline, then prove that an
    -- unchanged normalized shop never consumes durable bandwidth or revisions.
    Context.syncHost:update(1, Context.syncHostContext)
    Context.syncClient:update(0, Context.syncClientContext)
    Context.syncClient:drainEvents()
    Context.baselineStatePackets = #Context.syncNetwork:messages("host_to_client", "shop_state")
    Context.syncHost:update(1, Context.syncHostContext)
    Context.syncClient:update(0, Context.syncClientContext)
    Context.unchangedEvents = Context.syncClient:drainEvents()
    Context.check("multiplayer_session_unchanged_shop_state_is_not_rebroadcast",
        #Context.syncNetwork:messages("host_to_client", "shop_state") == Context.baselineStatePackets
        and Context.eventNamed(Context.unchangedEvents, "shop_state") == nil)

    Context.authoritativeState.money = 925
    Context.authoritativeState.inventory.paper = 2375
    Context.authoritativeState.inventory.prints = 18
    Context.authoritativeState.calendar.day = 5
    Context.authoritativeState.calendar.weekday = 1
    Context.authoritativeState.calendar.totalDays = 4
    Context.authoritativeState.jobs.active = {
        { id = "LAN-JOB-0001", company = "Cross-platform Customer", status = "accepted" },
    }
    Context.authoritativeState.clientEmails.inbox = {
        { id = "EMAIL-0001", sender = "Cross-platform Customer", subject = "Print quote" },
    }
    Context.authoritativeVisitors.customer.state = "waiting"
    Context.authoritativeVisitors.customer.x = 612
    Context.authoritativeVisitors.customer.y = 318
    Context.authoritativeVisitors.customer.waypoint = 3
    Context.authoritativeVisitors.customer.waitTimer = 22
    Context.authoritativeVisitors.vendor.arrivalTimer = 9
    Context.authoritativeEnvironment.bayDoor.state = "opening"
    Context.authoritativeEnvironment.bayDoor.progress = 0.5
    Context.authoritativeEnvironment.truck = {
        state = "parked_closed", jobId = "LAN-JOB-0001", mode = "delivery",
        backingProgress = 1, cargoProgress = 0,
    }
    Context.authoritativePalletJack = Context.palletJackState({
        x = 552,
        y = 490,
        direction = "west",
        operating = true,
        moving = true,
        operatorPlayerId = 2,
        carriedPalletId = "LAN-JOB-0001-P01",
    })
    Context.syncHost:markShopDirty()
    Context.syncHost:update(1, Context.syncHostContext)
    Context.syncClient:update(0, Context.syncClientContext)
    Context.changedEvents = Context.syncClient:drainEvents()
    Context.changed = Context.eventNamed(Context.changedEvents, "shop_state")
    Context.visitorChanged = Context.eventNamed(Context.changedEvents, "visitor_state")
    Context.environmentChanged = Context.eventNamed(Context.changedEvents, "environment_state")
    Context.palletJackChanged = Context.eventNamed(Context.changedEvents, "pallet_jack_state")
    Context.durablePackets = Context.syncNetwork:messages("host_to_client", "shop_state")
    Context.visitorPackets = Context.syncNetwork:messages("host_to_client", "visitor_snapshot")
    Context.environmentPackets = Context.syncNetwork:messages("host_to_client", "environment_snapshot")
    Context.palletJackPackets = Context.syncNetwork:messages("host_to_client", "pallet_jack_snapshot")
    Context.check("multiplayer_session_host_broadcasts_authoritative_shop_state_to_guest",
        #Context.durablePackets == Context.baselineStatePackets + 1
        and Context.durablePackets[#Context.durablePackets].channel == Context.Protocol.CHANNEL_DURABLE
        and Context.durablePackets[#Context.durablePackets].reliable
        and Context.changed and Context.changed.revision > 0
        and Context.changed.state.money == 925
        and Context.changed.state.inventory.paper == 2375
        and Context.changed.state.inventory.prints == 18
        and Context.changed.state.calendar.day == 5
        and Context.changed.state.jobs.active[1].id == "LAN-JOB-0001"
        and Context.changed.state.clientEmails.inbox[1].sender == "Cross-platform Customer"
        and Context.syncClient.lastShopRevision == Context.changed.revision)
    Context.check("multiplayer_session_host_streams_customer_and_vendor_state_to_guest",
        #Context.visitorPackets > 0
        and Context.visitorPackets[#Context.visitorPackets].channel == Context.Protocol.CHANNEL_STATE
        and not Context.visitorPackets[#Context.visitorPackets].reliable
        and Context.visitorChanged and Context.visitorChanged.serverTick == Context.syncHost.serverTick
        and Context.visitorChanged.customer.state == "waiting"
        and Context.visitorChanged.customer.x == 612 and Context.visitorChanged.customer.y == 318
        and Context.visitorChanged.customer.waitTimer == 22
        and Context.visitorChanged.vendor.state == "scheduled"
        and Context.visitorChanged.vendor.arrivalTimer == 9)
    Context.check("multiplayer_session_host_streams_environment_state_to_guest",
        #Context.environmentPackets > 0
        and Context.environmentPackets[#Context.environmentPackets].channel == Context.Protocol.CHANNEL_STATE
        and not Context.environmentPackets[#Context.environmentPackets].reliable
        and Context.environmentChanged and Context.environmentChanged.serverTick == Context.syncHost.serverTick
        and Context.environmentChanged.bayDoor.state == "opening"
        and Context.environmentChanged.bayDoor.progress == 0.5
        and Context.environmentChanged.truck.state == "parked_closed"
        and Context.environmentChanged.truck.jobId == "LAN-JOB-0001"
        and Context.environmentChanged.truck.mode == "delivery"
        and Context.environmentChanged.truck.backingProgress == 1
        and Context.environmentChanged.truck.cargoProgress == 0
        and Context.syncClient.lastEnvironmentTick == Context.environmentChanged.serverTick)
    Context.check("multiplayer_session_host_streams_authoritative_pallet_jack_state_to_guest",
        #Context.palletJackPackets > 0
        and Context.palletJackPackets[#Context.palletJackPackets].channel == Context.Protocol.CHANNEL_STATE
        and not Context.palletJackPackets[#Context.palletJackPackets].reliable
        and Context.palletJackChanged and Context.palletJackChanged.serverTick == Context.syncHost.serverTick
        and Context.palletJackChanged.serverTick == Context.syncClient.lastServerTick
        and Context.palletJackChanged.jack.x == 552 and Context.palletJackChanged.jack.y == 490
        and Context.palletJackChanged.jack.direction == "west"
        and Context.palletJackChanged.jack.operating and Context.palletJackChanged.jack.moving
        and Context.palletJackChanged.jack.operatorPlayerId == 2
        and Context.palletJackChanged.jack.carriedPalletId == "LAN-JOB-0001-P01"
        and Context.palletJackChanged.jack.candidatePalletId == nil
        and Context.palletJackChanged.machines.cutter.x == 700
        and Context.palletJackChanged.machines.wrapper.x == 820
        and Context.palletJackChanged.machines.windmill.x == 850
        and not Context.palletJackChanged.machines.cutter.moving
        and Context.syncClient.lastPalletJackTick == Context.palletJackChanged.serverTick)
end

return Component
