local Sound = {}
Sound.__index = Sound

local CATALOG = {
    ui_click = { path = "assets/audio/sfx/ui_click.wav", volume = 0.55 },
    ui_confirm = { path = "assets/audio/sfx/ui_confirm.wav", volume = 0.58 },
    ui_error = { path = "assets/audio/sfx/ui_error.wav", volume = 0.62 },
    cash_sale = { path = "assets/audio/sfx/cash_sale.wav", volume = 0.72 },
    job_complete = { path = "assets/audio/sfx/job_complete.wav", volume = 0.78 },
    loading_door = { path = "assets/audio/sfx/loading_door.wav", volume = 0.72 },
    truck_arrival = { path = "assets/audio/sfx/truck_arrival.wav", volume = 0.72 },
    pallet_pickup = { path = "assets/audio/sfx/pallet_pickup.wav", volume = 0.76 },
    pallet_place = { path = "assets/audio/sfx/pallet_place.wav", volume = 0.78 },
    cutter_clamp = { path = "assets/audio/sfx/cutter_clamp.wav", volume = 0.72 },
    cutter_cut = { path = "assets/audio/sfx/cutter_cut.wav", volume = 0.82 },
    press_start = { path = "assets/audio/sfx/press_start.wav", volume = 0.68 },
    press_running_loop = {
        path = "assets/audio/sfx/press_running_loop.wav", volume = 0.48, loop = true,
    },
    wrapper_cycle = { path = "assets/audio/sfx/wrapper_cycle.wav", volume = 0.68 },
    maintenance_tool = { path = "assets/audio/sfx/maintenance_tool.wav", volume = 0.72 },
    warehouse_ambience_loop = {
        path = "assets/audio/sfx/warehouse_ambience_loop.wav", volume = 0.34,
        loop = true, group = "ambient",
    },
}

local ERROR_WORDS = {
    "could not", "not enough", "is blocked", "is missing", "requires",
    "must ", "no unfinished", "no stretch", "wait for", "cannot ",
}

local function report(self, message)
    self.lastError = message
    self.errors[#self.errors + 1] = message
    print("[SOUND] " .. message)
end

local function audioAvailable()
    return love and love.audio and type(love.audio.newSource) == "function"
end

local function count(list)
    return type(list) == "table" and #list or 0
end

local function includes(text, fragment)
    return type(text) == "string" and text:lower():find(fragment, 1, true) ~= nil
end

local function isErrorMessage(message)
    for _, fragment in ipairs(ERROR_WORDS) do
        if includes(message, fragment) then return true end
    end
    return false
end

local function cloneSource(prototype)
    if not prototype then return nil end
    local ok, source = pcall(prototype.clone, prototype)
    return ok and source or nil
end

function Sound.catalog()
    local result = {}
    for name, spec in pairs(CATALOG) do
        result[name] = {
            path = spec.path, volume = spec.volume, loop = spec.loop == true,
            group = spec.group or "sfx",
        }
    end
    return result
end

function Sound.new(context)
    assert(type(context) == "table", "sound context is required")
    assert(type(context.state) == "table", "sound context requires state")
    return setmetatable({
        context = context,
        prototypes = {},
        active = {},
        loops = {},
        errors = {},
        lastError = nil,
        previous = nil,
        clock = 0,
        lastPlayed = {},
        masterVolume = 1.0,
        sfxVolume = 0.85,
        ambientVolume = 0.42,
        muted = false,
        paused = false,
        initialized = false,
    }, Sound)
end

function Sound:initialize()
    if self.initialized then return #self.errors == 0, self.errors end
    self.initialized = true
    if not audioAvailable() then
        report(self, "LÖVE audio is unavailable; continuing without sound.")
        self.previous = self:capture()
        return false, self.errors
    end
    for name, spec in pairs(CATALOG) do
        local ok, source = pcall(love.audio.newSource, spec.path, "static")
        if ok and source then
            source:setLooping(spec.loop == true)
            self.prototypes[name] = source
        else
            report(self, "Could not load " .. spec.path .. ": " .. tostring(source))
        end
    end
    self.previous = self:capture()
    self:syncPersistentLoops(self.previous)
    print(string.format("[SOUND] Loaded %d/%d cues", self:loadedCount(), self:catalogCount()))
    return #self.errors == 0, self.errors
end

function Sound:catalogCount()
    local total = 0
    for _ in pairs(CATALOG) do total = total + 1 end
    return total
end

function Sound:loadedCount()
    local total = 0
    for _ in pairs(self.prototypes) do total = total + 1 end
    return total
end

function Sound:volumeFor(name, multiplier)
    local spec = CATALOG[name]
    if not spec or self.muted then return 0 end
    local group = spec.group == "ambient" and self.ambientVolume or self.sfxVolume
    return self.masterVolume * group * spec.volume * (multiplier or 1)
end

function Sound:play(name, options)
    options = options or {}
    local spec, prototype = CATALOG[name], self.prototypes[name]
    if not spec or not prototype or self.paused then return nil end
    local cooldown = tonumber(options.cooldown) or 0
    if cooldown > 0 and self.clock - (self.lastPlayed[name] or -math.huge) < cooldown then return nil end
    local source = cloneSource(prototype)
    if not source then
        report(self, "Could not clone cue " .. tostring(name))
        return nil
    end
    source:setLooping(false)
    source:setVolume(self:volumeFor(name, options.volume))
    source:play()
    self.active[#self.active + 1] = source
    self.lastPlayed[name] = self.clock
    return source
end

function Sound:startLoop(name, owner)
    owner = owner or name
    if self.loops[owner] then return self.loops[owner] end
    local spec, prototype = CATALOG[name], self.prototypes[name]
    if not spec or not spec.loop or not prototype or self.paused then return nil end
    local source = cloneSource(prototype)
    if not source then report(self, "Could not clone loop " .. tostring(name)); return nil end
    source:setLooping(true)
    source:setVolume(self:volumeFor(name))
    source:play()
    self.loops[owner] = { name = name, source = source }
    return source
end

function Sound:stopLoop(owner)
    local entry = self.loops[owner]
    if not entry then return false end
    entry.source:stop()
    if entry.source.release then pcall(entry.source.release, entry.source) end
    self.loops[owner] = nil
    return true
end

function Sound:capture()
    local state, world = self.context.state, self.context.world
    local machine, wrapper = self.context.machine, self.context.wrapper
    local pressPlacement = state.windmill or {}
    if state.screen == "press" and state.machineId then
        for _, item in ipairs(state.machines and state.machines.items or {}) do
            if item.id == state.machineId and item.modelId == "heidelberg_10x15" then
                pressPlacement = item.world or pressPlacement
                break
            end
        end
    end
    local press = pressPlacement.process or {}
    local jack = state.palletJack or {}
    local effectiveScreen = state.screen == "options" and state.optionsReturnScreen
        or state.screen
    return {
        screen = effectiveScreen,
        message = state.message,
        money = tonumber(state.money) or 0,
        completedJobs = count(state.jobs and state.jobs.completed),
        door = world and world.bayDoor and world.bayDoor.state,
        truck = world and world.truck and world.truck.state,
        pallet = jack.carriedPalletId,
        wrapper = wrapper and wrapper.step,
        cutterStep = machine and machine.step,
        cutterClamp = machine and machine.clamp == true,
        pressMotor = press.motor == true,
        pressStatus = press.status,
    }
end

function Sound:syncPersistentLoops(snapshot)
    local inShop = snapshot.screen ~= "title" and snapshot.screen ~= "asset_error"
    if inShop then self:startLoop("warehouse_ambience_loop", "warehouse")
    else self:stopLoop("warehouse") end
    if snapshot.pressStatus == "production" then
        self:startLoop("press_running_loop", "press")
    else
        self:stopLoop("press")
    end
end

function Sound:handleTransitions(before, after)
    if before.door ~= after.door and (after.door == "opening" or after.door == "closing") then
        self:play("loading_door", { cooldown = 0.25 })
    end
    if before.truck ~= after.truck then
        if after.truck == "backing" then
            self:play("truck_arrival", { cooldown = 1.0 })
        elseif after.truck == "cargo_opening" or after.truck == "cargo_closing" then
            self:play("loading_door", { cooldown = 0.25, volume = 0.72 })
        end
    end
    if before.pallet ~= after.pallet then
        if before.pallet == nil and after.pallet ~= nil then self:play("pallet_pickup")
        elseif before.pallet ~= nil and after.pallet == nil then self:play("pallet_place") end
    end
    if before.wrapper ~= after.wrapper and after.wrapper == "wrapping" then
        self:play("wrapper_cycle", { cooldown = 0.5 })
    end
    if before.cutterClamp ~= after.cutterClamp and after.cutterClamp then
        self:play("cutter_clamp", { cooldown = 0.15 })
    end
    if before.cutterStep ~= after.cutterStep and after.cutterStep == "cutting" then
        self:play("cutter_cut", { cooldown = 0.25 })
    end
    if before.pressMotor ~= after.pressMotor and after.pressMotor then
        self:play("press_start", { cooldown = 0.5 })
    end
    if before.completedJobs < after.completedJobs then
        self:play("job_complete", { cooldown = 0.5 })
    elseif after.money > before.money then
        self:play("cash_sale", { cooldown = 0.25 })
    end
    if before.message ~= after.message then
        if includes(after.message, "service complete") or includes(after.message, "lubrication complete")
            or includes(after.message, "blade removed")
        then
            self:play("maintenance_tool", { cooldown = 0.2 })
        elseif isErrorMessage(after.message) then
            self:play("ui_error", { cooldown = 0.18, volume = 0.75 })
        end
    end
end

function Sound:update(dt)
    if not self.initialized then return end
    self.clock = self.clock + math.max(0, tonumber(dt) or 0)
    for index = #self.active, 1, -1 do
        local source = self.active[index]
        if not source:isPlaying() then
            if source.release then pcall(source.release, source) end
            table.remove(self.active, index)
        end
    end
    local current = self:capture()
    if self.previous and not self.paused then self:handleTransitions(self.previous, current) end
    self:syncPersistentLoops(current)
    self.previous = current
end

function Sound:pointerPressed(button, screen)
    if button == 1 and screen ~= "world" then
        self:play("ui_click", { cooldown = 0.035 })
    end
end

function Sound:setPaused(paused)
    paused = paused == true
    if paused == self.paused then return end
    self.paused = paused
    if paused then
        for _, entry in pairs(self.loops) do entry.source:pause() end
    else
        for _, entry in pairs(self.loops) do entry.source:play() end
        self.previous = self:capture()
        self:syncPersistentLoops(self.previous)
    end
end

function Sound:setMuted(muted)
    self.muted = muted == true
    for owner, entry in pairs(self.loops) do
        entry.source:setVolume(self:volumeFor(entry.name))
        if self.muted and entry.source:isPlaying() then entry.source:pause()
        elseif not self.muted and not self.paused then entry.source:play() end
    end
end

function Sound:setLevels(master, sfx, ambient)
    self.masterVolume = math.max(0, math.min(1, tonumber(master) or self.masterVolume))
    self.sfxVolume = math.max(0, math.min(1, tonumber(sfx) or self.sfxVolume))
    self.ambientVolume = math.max(0, math.min(1, tonumber(ambient) or self.ambientVolume))
    for _, entry in pairs(self.loops) do
        entry.source:setVolume(self:volumeFor(entry.name))
    end
end

function Sound:status()
    return {
        initialized = self.initialized,
        available = audioAvailable(),
        loaded = self:loadedCount(),
        expected = self:catalogCount(),
        errors = self.errors,
        lastError = self.lastError,
    }
end

function Sound:shutdown()
    for owner in pairs(self.loops) do self:stopLoop(owner) end
    for _, source in ipairs(self.active) do
        source:stop()
        if source.release then pcall(source.release, source) end
    end
    for _, source in pairs(self.prototypes) do
        source:stop()
        if source.release then pcall(source.release, source) end
    end
    self.active, self.prototypes, self.previous = {}, {}, nil
    self.initialized = false
end

return Sound
