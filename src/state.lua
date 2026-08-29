local State = {}
local PaperWork = require("src.paper_work")
local Config = require("src.config")
local CutterPlacement = require("src.cutter_placement")
local PalletJack = require("src.pallet_jack")
local WrapperPlacement = require("src.wrapper_placement")
local Procurement = require("src.procurement")
local SaveSchema = require("src.save_schema")
local PalletState = require("src.pallet_state")
local BusinessCalendar = require("src.business_calendar")
local MachineFleet = require("src.machine_fleet")
local MachinePose = require("src.machine_pose")
local WindmillPlacement = require("src.windmill_placement")
local Windmill = require("src.windmill")

local SHARED_FIELDS = {
    "money",
    "inventory",
    "shopProgress",
    "cutterMemory",
    "jobs",
    "palletJack",
    "wrapper",
    "windmill",
    "technicianVisit",
    "cutter",
    "nextJobId",
    "accountsReceivable",
    "procurement",
    "vendorCategory",
    "calendar",
    "bills",
    "clientEmails",
    "machines",
}

function State.new()
    local state = SaveSchema.defaultState()
    state.screen = "title"
    state.activeSlot = nil
    state.currentOffer = nil
    state.message = "Welcome to your new print shop!"
    return state
end

function State.applySave(state, payload)
    local saved = type(payload) == "table" and payload.state
    if type(saved) ~= "table" then return false end
    saved = SaveSchema.copy(saved)

    state.activeSlot = payload.slot
    state.money = type(saved.money) == "number" and saved.money or 0
    state.inventory = type(saved.inventory) == "table" and saved.inventory or {}
    state.inventory.paper = type(state.inventory.paper) == "number" and state.inventory.paper or 0
    state.inventory.prints = type(state.inventory.prints) == "number" and state.inventory.prints or 0
    state.inventory.rawPallets = type(state.inventory.rawPallets) == "number" and state.inventory.rawPallets or 0
    state.inventory.inProcessPallets = type(state.inventory.inProcessPallets) == "number" and state.inventory.inProcessPallets or 0
    state.inventory.finishedPallets = type(state.inventory.finishedPallets) == "number" and state.inventory.finishedPallets or 0
    state.inventory.plasticWrapRolls = type(state.inventory.plasticWrapRolls) == "number" and math.max(0, state.inventory.plasticWrapRolls) or 0
    state.inventory.plasticWrapUses = type(state.inventory.plasticWrapUses) == "number" and math.max(0, state.inventory.plasticWrapUses) or 0
    state.shopProgress = type(saved.shopProgress) == "table" and saved.shopProgress or { completedCuts = 0 }
    state.cutterMemory = type(saved.cutterMemory) == "table" and saved.cutterMemory or {}
    state.jobs = type(saved.jobs) == "table" and saved.jobs or { active = {}, completed = {}, declined = {} }
    state.jobs.active = type(state.jobs.active) == "table" and state.jobs.active or {}
    state.jobs.completed = type(state.jobs.completed) == "table" and state.jobs.completed or {}
    state.jobs.declined = type(state.jobs.declined) == "table" and state.jobs.declined or {}
    for _, job in ipairs(state.jobs.active) do
        job.difficulty = job.difficulty or "easy"
        for index, pallet in ipairs(job.pallets or {}) do
            job.packaging = job.packaging == "boxed" and "boxed" or "flat"
            pallet.packaging = pallet.packaging == "boxed" and "boxed" or job.packaging
            pallet.wrapped = pallet.wrapped == true or pallet.status == "wrapped"
            if not pallet.paper and job.sourceSize and job.finishedSize and pallet.id then
                pallet.paper = PaperWork.create(job, pallet, job.difficulty, index)
            end
            if pallet.paper then PaperWork.normalizeOrientations(pallet.paper) end
        end
    end
    state.palletJack = type(saved.palletJack) == "table"
        and saved.palletJack
        or PalletJack.defaultState(Config.palletJack)
    PalletJack.ensure(state, Config.palletJack)
    state.palletJack.operating, state.palletJack.moving = false, false
    state.wrapper = type(saved.wrapper) == "table" and saved.wrapper or WrapperPlacement.defaultState(Config.wrapperPlacement)
    if state.wrapper.x == 825 and state.wrapper.y == 300 and not state.wrapper.moving then
        state.wrapper.x, state.wrapper.y = Config.wrapperPlacement.spawnX, Config.wrapperPlacement.spawnY
    end
    WrapperPlacement.ensure(state, Config.wrapperPlacement)
    state.wrapper.moving, state.wrapper.inMotion = false, false
    state.windmill = type(saved.windmill) == "table" and saved.windmill
        or WindmillPlacement.defaultState(Config.windmillPlacement)
    WindmillPlacement.ensure(state, Config.windmillPlacement)
    state.windmill.moving, state.windmill.inMotion = false, false
    Windmill.ensure(state)
    state.technicianVisit = type(saved.technicianVisit) == "table" and saved.technicianVisit or nil
    state.cutter = type(saved.cutter) == "table"
        and saved.cutter
        or CutterPlacement.defaultState(Config.cutterPlacement)
    CutterPlacement.ensure(state, Config.cutterPlacement)
    state.cutter.moving, state.cutter.inMotion = false, false
    state.nextJobId = type(saved.nextJobId) == "number"
        and saved.nextJobId >= 1
        and saved.nextJobId == math.floor(saved.nextJobId)
        and saved.nextJobId
        or 1
    state.accountsReceivable = type(saved.accountsReceivable) == "number"
        and math.max(0, saved.accountsReceivable)
        or 0
    state.procurement = type(saved.procurement) == "table" and saved.procurement
        or { orders = {}, nextOrderId = 1, shipments = {}, nextShipmentId = 1 }
    state.vendorCategory = tonumber(saved.vendorCategory) or 1
    state.calendar = type(saved.calendar) == "table" and saved.calendar or BusinessCalendar.defaultCalendar()
    state.bills = type(saved.bills) == "table" and saved.bills or BusinessCalendar.defaultBills()
    state.clientEmails = type(saved.clientEmails) == "table" and saved.clientEmails
        or { nextEmailId = 1, nextPromotionId = 1,
            pending = {}, inbox = {}, archive = {}, sentPromotions = {} }
    state.machines = type(saved.machines) == "table" and saved.machines or MachineFleet.defaultState()
    MachineFleet.ensure(state)
    BusinessCalendar.ensure(state)
    Procurement.ensure(state)
    PalletState.reconcile(state)
    SaveSchema.reconcile(state)
    state.currentOffer = nil
    state._networkMachinePoses = nil
    state.screen = "world"
    state.message = "Shop opened."
    return true
end

-- A LAN guest receives only the host's normalized persistent shop state. The
-- guest intentionally has no local save slot, so autosave and quit can never
-- overwrite one of its offline shops.
function State.applySharedSnapshot(state, snapshot)
    if type(snapshot) ~= "table" or not SaveSchema.validState(snapshot) then return false end
    local staged = State.new()
    if not State.applySave(staged, { state = snapshot, slot = nil }) then return false end
    for _, field in ipairs(SHARED_FIELDS) do state[field] = staged[field] end
    state.activeSlot = nil
    state.currentOffer = nil
    state._networkMachinePoses = nil
    state.screen = "world"
    state.message = "Shop opened."
    return true
end

-- Continuous authoritative updates replace only durable domain fields. The
-- guest keeps its local screen/message/input state and never gains a save slot.
function State.applySharedUpdate(state, snapshot)
    if type(snapshot) ~= "table" or not SaveSchema.validState(snapshot) then return false end
    local livePalletJack = state.palletJack and state.palletJack.operating
        and PalletJack.snapshot(state, Config.palletJack) or nil
    local liveMachinePoses = state._networkMachinePoses
        and MachinePose.copy(state._networkMachinePoses) or nil
    local staged = State.new()
    if not State.applySave(staged, { state = snapshot, slot = nil }) then return false end
    for _, field in ipairs(SHARED_FIELDS) do state[field] = staged[field] end
    state._networkMachinePoses = nil
    -- Durable saves intentionally strip active-operation flags. Reapply the
    -- newer realtime view so a reliable shop update cannot visually park a
    -- jack that a LAN worker is still driving.
    local compositeMachinePoses
    if liveMachinePoses and livePalletJack then
        livePalletJack.carriedPalletId = state.palletJack.carriedPalletId
        livePalletJack.candidatePalletId = nil
        compositeMachinePoses = MachinePose.normalize(
            liveMachinePoses, livePalletJack, 100000, "cached network machine poses")
    end
    if livePalletJack and (not liveMachinePoses or compositeMachinePoses) then
        PalletJack.applySnapshot(state, livePalletJack, Config.palletJack)
    end
    if compositeMachinePoses then
        MachinePose.apply(state, compositeMachinePoses)
        state._networkMachinePoses = compositeMachinePoses
    end
    state.activeSlot = nil
    return true
end

return State
