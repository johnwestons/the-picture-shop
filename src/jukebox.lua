local Jukebox = {
    trackIndex = 1,
    source = nil,
    active = false,
    paused = true,
    muted = false,
    loadError = nil,
    radioDirty = false,
    networkSession = nil,
}

local TRACKS = {
    { file = "blood_red.wav", title = "Blood Red" },
    { file = "downpour.wav", title = "Downpour" },
    { file = "go_in_peace.wav", title = "Go in Peace" },
    { file = "goodbye_youre_waking_up.wav", title = "Goodbye, You’re Waking Up" },
    { file = "pixel_memory.wav", title = "Pixel Memory" },
    { file = "pull_back_the_veil.wav", title = "Pull Back the Veil" },
    { file = "simplicity.wav", title = "Simplicity" },
    { file = "this_is_not_your_song.wav", title = "This Is Not Your Song" },
    { file = "time_time.wav", title = "Time Time" },
}

local MUSIC_ROOT = "assets/audio/music/vibes/"
local RADIO_PANEL = { x = 82, y = 190, width = 792, height = 444 }
local CONTROL_BUTTONS = {
    previous = { x = 154, y = 402, width = 150, height = 42 },
    play = { x = 322, y = 402, width = 150, height = 42 },
    next = { x = 490, y = 402, width = 150, height = 42 },
    mute = { x = 658, y = 402, width = 150, height = 42 },
}
local PLAYBACK_START_GRACE_SECONDS = 1.5

local function currentTrack()
    return TRACKS[Jukebox.trackIndex] or TRACKS[1]
end

local function clock()
    if love and love.timer and type(love.timer.getTime) == "function" then
        local ok, value = pcall(love.timer.getTime)
        if ok and type(value) == "number" and value == value then return value end
    end
    return os.clock()
end

local function releaseSource(source)
    if not source then return end
    if type(source.stop) == "function" then pcall(source.stop, source) end
    if type(source.release) == "function" then pcall(source.release, source) end
end

local function setVolume()
    if Jukebox.source then
        pcall(Jukebox.source.setVolume, Jukebox.source, Jukebox.muted and 0 or 0.24)
    end
end

local function startCurrentTrack()
    if not love or not love.audio or type(love.audio.newSource) ~= "function" then
        releaseSource(Jukebox.source)
        Jukebox.source, Jukebox.playbackStartedAt = nil, nil
        Jukebox.loadError = "LÖVE audio is unavailable."
        Jukebox.active, Jukebox.paused = false, true
        Jukebox.radioDirty = true
        return false
    end
    if Jukebox.source then
        releaseSource(Jukebox.source)
        Jukebox.source = nil
    end
    Jukebox.playbackStartedAt = nil
    local ok, source = pcall(love.audio.newSource, MUSIC_ROOT .. currentTrack().file, "stream")
    if not ok or not source then
        Jukebox.loadError = tostring(source or "The selected track could not be loaded.")
        Jukebox.active, Jukebox.paused = false, true
        Jukebox.radioDirty = true
        return false
    end
    local started, startError = pcall(function()
        source:setLooping(false)
        source:setVolume(Jukebox.muted and 0 or 0.24)
        source:play()
    end)
    if not started then
        releaseSource(source)
        Jukebox.loadError = tostring(startError or "The selected track could not start.")
        Jukebox.active, Jukebox.paused = false, true
        Jukebox.radioDirty = true
        return false
    end
    Jukebox.source = source
    Jukebox.loadError = nil
    Jukebox.playbackStartedAt = clock()
    Jukebox.active, Jukebox.paused = true, false
    Jukebox.radioDirty = true
    return true
end

local function contains(rect, x, y)
    return x >= rect.x and x <= rect.x + rect.width
        and y >= rect.y and y <= rect.y + rect.height
end

local function trackRect(index)
    local column = (index - 1) % 3
    local row = math.floor((index - 1) / 3)
    return { x = 106 + column * 250, y = 486 + row * 46, width = 240, height = 38 }
end

local function trackPosition()
    if not Jukebox.source or type(Jukebox.source.tell) ~= "function" then return 0 end
    local ok, value = pcall(Jukebox.source.tell, Jukebox.source)
    return ok and type(value) == "number" and math.max(0, value) or 0
end

local function trackDuration()
    if not Jukebox.source or type(Jukebox.source.getDuration) ~= "function" then return 0 end
    local ok, value = pcall(Jukebox.source.getDuration, Jukebox.source)
    return ok and type(value) == "number" and math.max(0, value) or 0
end

local function formatTime(seconds)
    seconds = math.floor(math.max(0, seconds or 0))
    return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function playPause()
    if Jukebox.active and not Jukebox.paused and Jukebox.source then
        pcall(Jukebox.source.pause, Jukebox.source)
        Jukebox.paused = true
        Jukebox.radioDirty = true
    elseif Jukebox.source and Jukebox.paused then
        local ok = pcall(Jukebox.source.play, Jukebox.source)
        if ok then
            Jukebox.active, Jukebox.paused = true, false
            Jukebox.playbackStartedAt = clock()
            Jukebox.radioDirty = true
        end
    else
        startCurrentTrack()
    end
end

function Jukebox.drawComputerTab(pointerX, pointerY, readOnly, drawButton)
    love.graphics.setColor(0.025, 0.045, 0.055, 1)
    love.graphics.rectangle("fill", RADIO_PANEL.x, RADIO_PANEL.y,
        RADIO_PANEL.width, RADIO_PANEL.height, 5, 5)
    love.graphics.setColor(0.25, 0.48, 0.50, 1)
    love.graphics.rectangle("line", RADIO_PANEL.x, RADIO_PANEL.y,
        RADIO_PANEL.width, RADIO_PANEL.height, 5, 5)
    love.graphics.setColor(0.96, 0.84, 0.43, 1)
    love.graphics.print("CRITTERNET RADIO  /  VIBES FM", 104, 204)
    love.graphics.setColor(0.60, 0.76, 0.72, 1)
    love.graphics.printf(readOnly and "HOST CONTROLLED" or "LOCAL RADIO CONTROLS",
        620, 204, 230, "right")

    love.graphics.setColor(0.01, 0.12, 0.14, 1)
    love.graphics.rectangle("fill", 106, 235, 748, 150, 4, 4)
    love.graphics.setColor(0.24, 0.45, 0.45, 1)
    love.graphics.rectangle("line", 106, 235, 748, 150, 4, 4)
    love.graphics.setColor(0.40, 0.83, 0.65, 1)
    love.graphics.print(string.format("STATION 01  /  TRACK %02d OF %02d",
        Jukebox.trackIndex, #TRACKS), 128, 250)
    local status = not Jukebox.active and "READY"
        or Jukebox.paused and "PAUSED" or "NOW PLAYING"
    love.graphics.setColor(0.96, 0.93, 0.81, 1)
    love.graphics.printf(currentTrack().title, 128, 273, 704, "center")
    love.graphics.setColor(0.66, 0.79, 0.75, 1)
    love.graphics.printf(status .. "  •  " .. formatTime(trackPosition())
        .. " / " .. formatTime(trackDuration()), 128, 312, 704, "center")
    if Jukebox.loadError then
        love.graphics.setColor(1, 0.48, 0.40, 1)
        love.graphics.printf("Radio audio could not be loaded.", 128, 333, 704, "center")
    end
    love.graphics.setColor(0.08, 0.18, 0.18, 1)
    love.graphics.rectangle("fill", 128, 356, 704, 8, 2, 2)
    local duration = trackDuration()
    local progress = duration > 0 and math.min(1, trackPosition() / duration) or 0
    love.graphics.setColor(0.40, 0.83, 0.65, 1)
    love.graphics.rectangle("fill", 128, 356, 704 * progress, 8, 2, 2)

    local controls = {
        { id = "previous", label = "|<  PREVIOUS" },
        { id = "play", label = Jukebox.active and not Jukebox.paused and "PAUSE" or "PLAY" },
        { id = "next", label = "NEXT  >|" },
        { id = "mute", label = Jukebox.muted and "UNMUTE" or "MUTE" },
    }
    for _, control in ipairs(controls) do
        local rect = CONTROL_BUTTONS[control.id]
        local hovered = pointerX and contains(rect, pointerX, pointerY)
        local style = readOnly and "disabled" or control.id == "play"
            and Jukebox.active and not Jukebox.paused and "primary"
            or hovered and "hover" or "secondary"
        drawButton(rect, control.label, style)
    end

    love.graphics.setColor(0.72, 0.85, 0.79, 1)
    love.graphics.print("VIBES PLAYLIST", 106, 461)
    for index, track in ipairs(TRACKS) do
        local rect = trackRect(index)
        local hovered = pointerX and contains(rect, pointerX, pointerY)
        local style = readOnly and "disabled" or index == Jukebox.trackIndex
            and "primary" or hovered and "hover" or "secondary"
        drawButton(rect, string.format("%02d  %s", index, track.title), style)
    end
end

function Jukebox.mousepressed(state, x, y, button, readOnly)
    if button ~= 1 then return nil end
    local control
    for name, rect in pairs(CONTROL_BUTTONS) do
        if contains(rect, x, y) then control = name; break end
    end
    local selectedTrack
    for index = 1, #TRACKS do
        if contains(trackRect(index), x, y) then selectedTrack = index; break end
    end
    if not control and not selectedTrack then return nil end
    if readOnly then
        state.message = "The host controls the radio for everyone."
        return { action = "blocked" }
    end
    if selectedTrack then
        Jukebox.trackIndex = selectedTrack
        startCurrentTrack()
        return { action = "radio_track_changed", trackIndex = selectedTrack }
    elseif control == "previous" then
        local position = trackPosition()
        if Jukebox.source and position > 3 then
            pcall(Jukebox.source.seek, Jukebox.source, 0)
            Jukebox.radioDirty = true
        else
            Jukebox.trackIndex = (Jukebox.trackIndex - 2) % #TRACKS + 1
            startCurrentTrack()
        end
    elseif control == "play" then
        playPause()
    elseif control == "next" then
        Jukebox.trackIndex = Jukebox.trackIndex % #TRACKS + 1
        startCurrentTrack()
    elseif control == "mute" then
        Jukebox.muted = not Jukebox.muted
        setVolume()
        Jukebox.radioDirty = true
    end
    return { action = "radio_control", control = control }
end

function Jukebox.update(keepPlaying, readOnly)
    if not keepPlaying then
        local wasPlaying = Jukebox.active and not Jukebox.paused
        releaseSource(Jukebox.source)
        Jukebox.source = nil
        Jukebox.playbackStartedAt = nil
        Jukebox.active, Jukebox.paused = false, true
        if wasPlaying then Jukebox.radioDirty = true end
        return
    end
    local elapsed = Jukebox.playbackStartedAt and clock() - Jukebox.playbackStartedAt or math.huge
    local playing = true
    if Jukebox.source and type(Jukebox.source.isPlaying) == "function" then
        local ok, value = pcall(Jukebox.source.isPlaying, Jukebox.source)
        playing = ok and value == true
    end
    if Jukebox.source and Jukebox.active and not Jukebox.paused and not playing
        and elapsed >= PLAYBACK_START_GRACE_SECONDS and not readOnly then
        Jukebox.trackIndex = Jukebox.trackIndex % #TRACKS + 1
        startCurrentTrack()
    end
end

function Jukebox.networkState()
    local position = 0
    if Jukebox.source and type(Jukebox.source.tell) == "function" then
        local ok, seconds = pcall(Jukebox.source.tell, Jukebox.source)
        if ok and type(seconds) == "number" and seconds == seconds then
            position = math.floor(math.max(0, math.min(3600, seconds)) * 1000 + 0.5)
        end
    end
    return {
        trackIndex = Jukebox.trackIndex,
        active = Jukebox.active == true,
        paused = Jukebox.paused == true,
        muted = Jukebox.muted == true,
        positionMs = position,
    }
end

function Jukebox.applyNetworkState(state)
    if type(state) ~= "table" then return false end
    local trackIndex = math.floor(tonumber(state.trackIndex) or 0)
    if trackIndex < 1 or trackIndex > #TRACKS then return false end
    local active = state.active == true
    local paused = state.paused == true
    local muted = state.muted == true
    local position = math.max(0, math.min(3600, (tonumber(state.positionMs) or 0) / 1000))
    local trackChanged = Jukebox.trackIndex ~= trackIndex
    Jukebox.trackIndex, Jukebox.muted = trackIndex, muted

    if not active then
        releaseSource(Jukebox.source)
        Jukebox.source = nil
        Jukebox.playbackStartedAt = nil
        Jukebox.active, Jukebox.paused = false, paused
    elseif trackChanged or not Jukebox.source then
        releaseSource(Jukebox.source)
        Jukebox.source = nil
        Jukebox.active, Jukebox.paused = false, true
        if startCurrentTrack() and Jukebox.source then
            if paused then pcall(Jukebox.source.pause, Jukebox.source) end
            Jukebox.active, Jukebox.paused = true, paused
            if not paused then Jukebox.playbackStartedAt = clock() end
            pcall(Jukebox.source.seek, Jukebox.source, position)
        end
    elseif Jukebox.source then
        if paused and not Jukebox.paused then pcall(Jukebox.source.pause, Jukebox.source) end
        if not paused and Jukebox.paused then
            pcall(Jukebox.source.play, Jukebox.source)
            Jukebox.playbackStartedAt = clock()
        end
        Jukebox.active, Jukebox.paused = true, paused
        local ok, currentPosition = pcall(Jukebox.source.tell, Jukebox.source)
        if ok and type(currentPosition) == "number"
            and math.abs(currentPosition - position) > 2
        then
            pcall(Jukebox.source.seek, Jukebox.source, position)
        end
    end
    setVolume()
    Jukebox.radioDirty = false
    return true
end

function Jukebox.stopNetworkPlayback()
    releaseSource(Jukebox.source)
    Jukebox.source = nil
    Jukebox.playbackStartedAt = nil
    Jukebox.active, Jukebox.paused = false, true
    Jukebox.radioDirty = false
end

function Jukebox.syncMultiplayer(multiplayer)
    if not multiplayer or type(multiplayer.isHost) ~= "function" or not multiplayer:isHost() then
        Jukebox.networkSession = nil
        Jukebox.radioDirty = false
        return
    end
    if Jukebox.networkSession ~= multiplayer.sessionId then
        Jukebox.networkSession = multiplayer.sessionId
        Jukebox.radioDirty = true
    end
    if Jukebox.radioDirty then
        local sent = multiplayer:publishRadioState(Jukebox.networkState())
        if sent then Jukebox.radioDirty = false end
    end
end

return Jukebox
