-- Network wire validation and codec regression scenarios.
-- A fresh Context belongs to each invocation; closures keep its live values.
local Component = {}

function Component.run(Context)
    Context.environmentPacket = Context.Protocol.encode("environment_snapshot", {
        sessionId = "session-001", serverTick = 42,
        bayDoor = { state = "opening", progress = 0.4 },
        truck = { state = "absent", backingProgress = 0, cargoProgress = 0 },
    })
    Context.environmentEnvelope = Context.environmentPacket and Context.Protocol.decode(Context.environmentPacket)
    Context.invalidClosedDoor = Context.Protocol.encode("environment_snapshot", {
        sessionId = "session-001", serverTick = 42,
        bayDoor = { state = "closed", progress = 0.1 },
        truck = { state = "absent", backingProgress = 0, cargoProgress = 0 },
    })
    Context.invalidAbsentTruck = Context.Protocol.encode("environment_snapshot", {
        sessionId = "session-001", serverTick = 42,
        bayDoor = { state = "closed", progress = 0 },
        truck = {
            state = "absent", jobId = "JOB-0001", mode = "delivery",
            backingProgress = 0, cargoProgress = 0,
        },
    })
    Context.invalidTruckProgress = Context.Protocol.encode("environment_snapshot", {
        sessionId = "session-001", serverTick = 42,
        bayDoor = { state = "closed", progress = 0 },
        truck = { state = "absent", backingProgress = 0, cargoProgress = 1.1 },
    })
    Context.extraEnvironmentField = Context.Protocol.encode("environment_snapshot", {
        sessionId = "session-001", serverTick = 42,
        bayDoor = { state = "closed", progress = 0, frame = 1 },
        truck = { state = "absent", backingProgress = 0, cargoProgress = 0 },
    })
    Context.check("network_protocol_environment_snapshot_is_strict_and_semantically_bounded",
        Context.environmentEnvelope and Context.environmentEnvelope.payload.serverTick == 42
        and Context.environmentEnvelope.payload.bayDoor.state == "opening"
        and Context.environmentEnvelope.payload.bayDoor.progress == 0.4
        and Context.environmentEnvelope.payload.truck.state == "absent"
        and #Context.environmentPacket <= Context.Protocol.MAX_PACKET_BYTES
        and Context.invalidClosedDoor == nil and Context.invalidAbsentTruck == nil
        and Context.invalidTruckProgress == nil and Context.extraEnvironmentField == nil)

    Context.palletJackPacket = Context.Protocol.encode("pallet_jack_snapshot", {
        sessionId = "session-001", serverTick = 43,
        jack = Context.palletJackSnapshot({ moving = true, clearCandidate = true,
            carriedPalletId = "JOB-0001-P01" }),
        machines = Context.machinePoses(),
    })
    Context.palletJackEnvelope = Context.palletJackPacket and Context.Protocol.decode(Context.palletJackPacket)
    Context.missingJackOwner = Context.Protocol.encode("pallet_jack_snapshot", {
        sessionId = "session-001", serverTick = 43,
        jack = Context.palletJackSnapshot({ clearOwner = true }),
        machines = Context.machinePoses(),
    })
    Context.parkedMovingJack = Context.Protocol.encode("pallet_jack_snapshot", {
        sessionId = "session-001", serverTick = 43,
        jack = Context.palletJackSnapshot({ operating = false, clearOwner = true,
            moving = true, clearCandidate = true }),
        machines = Context.machinePoses(),
    })
    Context.loadedCandidateJack = Context.Protocol.encode("pallet_jack_snapshot", {
        sessionId = "session-001", serverTick = 43,
        jack = Context.palletJackSnapshot({ carriedPalletId = "JOB-0001-P01" }),
        machines = Context.machinePoses(),
    })
    Context.spoofedJack = Context.Protocol.encode("pallet_jack_snapshot", {
        sessionId = "session-001", serverTick = 43,
        jack = Context.palletJackSnapshot({ playerX = 1 }),
        machines = Context.machinePoses(),
    })
    Context.invalidJackDirection = Context.Protocol.encode("pallet_jack_snapshot", {
        sessionId = "session-001", serverTick = 43,
        jack = Context.palletJackSnapshot({ direction = "up" }),
        machines = Context.machinePoses(),
    })
    Context.candidateOnParkedJack = Context.Protocol.encode("pallet_jack_snapshot", {
        sessionId = "session-001", serverTick = 43,
        jack = Context.palletJackSnapshot({ operating = false, moving = false,
            clearOwner = true }),
        machines = Context.machinePoses(),
    })
    Context.invalidJackOwner = Context.Protocol.encode("pallet_jack_snapshot", {
        sessionId = "session-001", serverTick = 43,
        jack = Context.palletJackSnapshot({ operatorPlayerId = Context.Protocol.MAX_PLAYERS + 1 }),
        machines = Context.machinePoses(),
    })
    Context.fractionalJackTick = Context.Protocol.encode("pallet_jack_snapshot", {
        sessionId = "session-001", serverTick = 43.5,
        jack = Context.palletJackSnapshot(),
        machines = Context.machinePoses(),
    })
    Context.parkedLoadedPacket = Context.Protocol.encode("pallet_jack_snapshot", {
        sessionId = "session-001", serverTick = 44,
        jack = Context.palletJackSnapshot({ operating = false, moving = false,
            clearOwner = true, clearCandidate = true,
            carriedPalletId = "JOB-0001-P01" }),
        machines = Context.machinePoses(),
    })
    Context.parkedLoadedEnvelope = Context.parkedLoadedPacket and Context.Protocol.decode(Context.parkedLoadedPacket)

    Context.relocatingJack = Context.palletJackSnapshot({
        x = 640, y = 508, direction = "east", moving = true,
        operatorPlayerId = 1, clearCandidate = true,
    })
    Context.relocatingMachines = Context.machinePoses({
        cutter = {
            x = 640, y = 500, direction = "east",
            moving = true, inMotion = true,
        },
    })
    Context.relocatingPacket = Context.Protocol.encode("pallet_jack_snapshot", {
        sessionId = "session-001", serverTick = 45,
        jack = Context.relocatingJack, machines = Context.relocatingMachines,
    })
    Context.relocatingEnvelope = Context.relocatingPacket and Context.Protocol.decode(Context.relocatingPacket)

    Context.incompleteMachines = Context.machinePoses()
    Context.incompleteMachines.windmill = nil
    Context.missingMachines = Context.Protocol.encode("pallet_jack_snapshot", {
        sessionId = "session-001", serverTick = 45, jack = Context.relocatingJack,
    })
    Context.missingMachinePose = Context.Protocol.encode("pallet_jack_snapshot", {
        sessionId = "session-001", serverTick = 45,
        jack = Context.relocatingJack, machines = Context.incompleteMachines,
    })
    Context.unknownMachine = Context.machinePoses()
    Context.unknownMachine.folder = {
        x = 1, y = 2, direction = "northwest", moving = false, inMotion = false,
    }
    Context.unknownMachinePacket = Context.Protocol.encode("pallet_jack_snapshot", {
        sessionId = "session-001", serverTick = 45,
        jack = Context.relocatingJack, machines = Context.unknownMachine,
    })
    Context.extraPoseField = Context.machinePoses()
    Context.extraPoseField.cutter.frame = 4
    Context.extraPoseFieldPacket = Context.Protocol.encode("pallet_jack_snapshot", {
        sessionId = "session-001", serverTick = 45,
        jack = Context.relocatingJack, machines = Context.extraPoseField,
    })
    Context.incompletePose = Context.machinePoses()
    Context.incompletePose.cutter.inMotion = nil
    Context.incompletePosePacket = Context.Protocol.encode("pallet_jack_snapshot", {
        sessionId = "session-001", serverTick = 45,
        jack = Context.relocatingJack, machines = Context.incompletePose,
    })
    Context.invalidWrapperDirection = Context.machinePoses()
    Context.invalidWrapperDirection.wrapper.direction = "north"
    Context.invalidWrapperDirectionPacket = Context.Protocol.encode("pallet_jack_snapshot", {
        sessionId = "session-001", serverTick = 45,
        jack = Context.relocatingJack, machines = Context.invalidWrapperDirection,
    })
    Context.invalidWindmillDirection = Context.machinePoses()
    Context.invalidWindmillDirection.windmill.direction = "west"
    Context.invalidWindmillDirectionPacket = Context.Protocol.encode("pallet_jack_snapshot", {
        sessionId = "session-001", serverTick = 45,
        jack = Context.relocatingJack, machines = Context.invalidWindmillDirection,
    })
    Context.invalidMotionFlag = Context.machinePoses()
    Context.invalidMotionFlag.cutter.moving = 1
    Context.invalidMotionFlagPacket = Context.Protocol.encode("pallet_jack_snapshot", {
        sessionId = "session-001", serverTick = 45,
        jack = Context.relocatingJack, machines = Context.invalidMotionFlag,
    })
    Context.motionWithoutAttachment = Context.machinePoses()
    Context.motionWithoutAttachment.wrapper.inMotion = true
    Context.motionWithoutAttachmentPacket = Context.Protocol.encode("pallet_jack_snapshot", {
        sessionId = "session-001", serverTick = 45,
        jack = Context.relocatingJack, machines = Context.motionWithoutAttachment,
    })
    Context.twoMovingJack = Context.palletJackSnapshot({
        x = 640, y = 508, direction = "northwest", moving = true,
        operatorPlayerId = 1, clearCandidate = true,
    })
    Context.twoMovingMachines = Context.machinePoses({
        cutter = { x = 640, y = 500, direction = "northwest",
            moving = true, inMotion = true },
        wrapper = { x = 640, y = 500, direction = "northwest",
            moving = true, inMotion = true },
    })
    Context.twoMovingMachinesPacket = Context.Protocol.encode("pallet_jack_snapshot", {
        sessionId = "session-001", serverTick = 45,
        jack = Context.twoMovingJack, machines = Context.twoMovingMachines,
    })
    Context.guestOwnedRelocation = Context.palletJackSnapshot({
        x = 640, y = 508, direction = "east", moving = true,
        operatorPlayerId = 2, clearCandidate = true,
    })
    Context.guestOwnedRelocationPacket = Context.Protocol.encode("pallet_jack_snapshot", {
        sessionId = "session-001", serverTick = 45,
        jack = Context.guestOwnedRelocation, machines = Context.relocatingMachines,
    })
    Context.loadedRelocation = Context.palletJackSnapshot({
        x = 640, y = 508, direction = "east", moving = true,
        operatorPlayerId = 1, carriedPalletId = "JOB-0001-P01", clearCandidate = true,
    })
    Context.loadedRelocationPacket = Context.Protocol.encode("pallet_jack_snapshot", {
        sessionId = "session-001", serverTick = 45,
        jack = Context.loadedRelocation, machines = Context.relocatingMachines,
    })
    Context.candidateRelocation = Context.palletJackSnapshot({
        x = 640, y = 508, direction = "east", moving = true,
        operatorPlayerId = 1,
    })
    Context.candidateRelocationPacket = Context.Protocol.encode("pallet_jack_snapshot", {
        sessionId = "session-001", serverTick = 45,
        jack = Context.candidateRelocation, machines = Context.relocatingMachines,
    })
end

return Component
