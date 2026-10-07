local Config = require("src.config")

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

local RADIO_FACE = "assets/generated/jukebox-radio.png"
local RADIO_BUTTONS = "assets/generated/jukebox-buttons.png"
local MUSIC_ROOT = "assets/audio/music/vibes/"
local PLAYLIST_BUTTON = { x = 438, y = 468, width = 82, height = 54 }
local CLOSE_BUTTON = { x = 628, y = 468, width = 82, height = 54 }
local PREVIOUS_BUTTON = { x = 242, y = 560, width = 110, height = 46 }
local PLAY_BUTTON = { x = 364, y = 560, width = 110, height = 46 }
local NEXT_BUTTON = { x = 486, y = 560, width = 110, height = 46 }
local MUTE_BUTTON = { x = 608, y = 560, width = 110, height = 46 }
local PLAYBACK_START_GRACE_SECONDS = 1.5

local radioFace
local radioButtons
local radioQuads

local function loadRadioImages()
    if not love or not love.graphics then return nil, nil, nil end
    if not radioFace then
        local ok, image = pcall(love.graphics.newImage, RADIO_FACE)
        if ok then radioFace = image end
    end
    if not radioButtons then
        local ok, image = pcall(love.graphics.newImage, RADIO_BUTTONS)
        if ok then
            radioButtons = image
            radioQuads = {}
            local width, height = image:getDimensions()
            local frameWidth = math.floor(width / 3)
            for index = 1, 3 do
                radioQuads[index] = love.graphics.newQuad(
                    (index - 1) * frameWidth, 0, frameWidth, height, width, height)
            end
        end
    end
    return radioFace, radioButtons, radioQuads
end

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

local function drawRadioButton(rect, label, frame, active, hovered, disabled)
    local _, buttons, quads = loadRadioImages()
    if buttons and quads then
        love.graphics.setColor(1, 1, 1, 1)
        local _, _, frameWidth, frameHeight = quads[frame]:getViewport()
        love.graphics.draw(buttons, quads[frame], rect.x, rect.y, 0,
            rect.width / frameWidth, rect.height / frameHeight)
    else
        love.graphics.setColor(0.10, 0.15, 0.16, 1)
        love.graphics.rectangle("fill", rect.x, rect.y, rect.width, rect.height, 5, 5)
    end
    if disabled then
        love.graphics.setColor(0.46, 0.50, 0.48, 0.62)
        love.graphics.rectangle("fill", rect.x, rect.y, rect.width, rect.height, 5, 5)
    else
        love.graphics.setColor(1, 1, 1, 1)
    end
    if (active or hovered) and not disabled then
        love.graphics.setColor(active and { 0.96, 0.77, 0.30, 1 } or { 0.59, 0.78, 0.75, 1 })
        love.graphics.setLineWidth(active and 3 or 1)
        love.graphics.rectangle("line", rect.x, rect.y, rect.width, rect.height, 5, 5)
        love.graphics.setLineWidth(1)
    end
    love.graphics.setColor(disabled and { 0.68, 0.70, 0.66, 0.86 }
        or { 0.96, 0.92, 0.78, 1 })
    love.graphics.printf(label, rect.x + 2, rect.y + rect.height / 2 - 8,
        rect.width - 4, "center")
end

function Jukebox.drawProp()
    local face = loadRadioImages()
    local config = Config.interactables.jukebox
    if not face or not config then return end
    local scale = config.drawScale or 0.10
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(face, config.wallX - face:getWidth() * scale / 2,
        config.wallY - face:getHeight() * scale / 2, 0, scale, scale)
end

function Jukebox.drawScreen(pointerX, pointerY, readOnly)
    local face = loadRadioImages()
    love.graphics.setColor(0, 0, 0, 0.72)
    love.graphics.rectangle("fill", 0, 0, 960, 678)
    if face then
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(face, 130, 95, 0, 700 / face:getWidth(), 450 / face:getHeight())
    else
        love.graphics.setColor(0.055, 0.075, 0.08, 1)
        love.graphics.rectangle("fill", 130, 95, 700, 450, 9, 9)
    end

    love.graphics.setColor(0.96, 0.84, 0.43, 1)
    love.graphics.printf("VIBES RADIO", 245, 360, 470, "center")
    love.graphics.setColor(0.96, 0.93, 0.81, 1)
    local track = currentTrack()
    local playback = not Jukebox.active and "READY  •  "
        or Jukebox.paused and "PAUSED  •  " or "NOW PLAYING  •  "
    love.graphics.printf(playback
        .. track.title, 220, 389, 520, "center")
    love.graphics.setColor(0.70, 0.79, 0.77, 1)
    love.graphics.printf(string.format("VIBES PLAYLIST  •  TRACK %d OF %d",
        Jukebox.trackIndex, #TRACKS), 260, 421, 440, "center")
    if readOnly then
        love.graphics.setColor(0.73, 0.82, 0.76, 1)
        love.graphics.printf("THE HOST CONTROLS THE RADIO FOR EVERYONE", 220, 444, 520, "center")
    end
    if Jukebox.loadError then
        love.graphics.setColor(1, 0.48, 0.40, 1)
        love.graphics.printf("Radio audio could not be loaded.", 260, 469, 440, "center")
    end

    drawRadioButton(PLAYLIST_BUTTON, "VIBES", 1, true,
        pointerX and contains(PLAYLIST_BUTTON, pointerX, pointerY), readOnly)
    drawRadioButton(CLOSE_BUTTON, "CLOSE", 3, false,
        pointerX and contains(CLOSE_BUTTON, pointerX, pointerY))
    love.graphics.setColor(0.045, 0.065, 0.07, 0.96)
    love.graphics.rectangle("fill", 230, 552, 500, 62, 6, 6)
    love.graphics.setColor(0.47, 0.56, 0.54, 1)
    love.graphics.rectangle("line", 230, 552, 500, 62, 6, 6)
    drawRadioButton(PREVIOUS_BUTTON, "|<  PREV", 2, false,
        pointerX and contains(PREVIOUS_BUTTON, pointerX, pointerY), readOnly)
    drawRadioButton(PLAY_BUTTON, Jukebox.active and not Jukebox.paused and "PAUSE" or "PLAY",
        2, false, pointerX and contains(PLAY_BUTTON, pointerX, pointerY), readOnly)
    drawRadioButton(NEXT_BUTTON, "NEXT  >|", 2, false,
        pointerX and contains(NEXT_BUTTON, pointerX, pointerY), readOnly)
    drawRadioButton(MUTE_BUTTON, Jukebox.muted and "UNMUTE" or "MUTE", 2, false,
        pointerX and contains(MUTE_BUTTON, pointerX, pointerY), readOnly)
end

function Jukebox.mousepressed(state, x, y, button, readOnly)
    if button ~= 1 then return true end
    if contains(CLOSE_BUTTON, x, y) then
        state.screen = "world"
        state.message = "Radio controls closed."
    elseif readOnly then
        state.message = "The host controls the radio for everyone."
        return true
    elseif contains(PLAYLIST_BUTTON, x, y) then
        if not Jukebox.active or Jukebox.paused then
            if Jukebox.source and Jukebox.paused then
                Jukebox.source:play()
                Jukebox.active, Jukebox.paused = true, false
                Jukebox.radioDirty = true
            else
                startCurrentTrack()
            end
        end
    elseif contains(PREVIOUS_BUTTON, x, y) then
        if Jukebox.source and Jukebox.source:tell() > 3 then
            Jukebox.source:seek(0)
            Jukebox.radioDirty = true
        else
            Jukebox.trackIndex = (Jukebox.trackIndex - 2) % #TRACKS + 1
            startCurrentTrack()
        end
    elseif contains(PLAY_BUTTON, x, y) then
        if Jukebox.active and not Jukebox.paused and Jukebox.source then
            Jukebox.source:pause()
            Jukebox.paused = true
            Jukebox.radioDirty = true
        elseif Jukebox.source and Jukebox.paused then
            Jukebox.source:play()
            Jukebox.active, Jukebox.paused = true, false
            Jukebox.radioDirty = true
        else
            startCurrentTrack()
        end
    elseif contains(NEXT_BUTTON, x, y) then
        Jukebox.trackIndex = Jukebox.trackIndex % #TRACKS + 1
        startCurrentTrack()
    elseif contains(MUTE_BUTTON, x, y) then
        Jukebox.muted = not Jukebox.muted
        setVolume()
        Jukebox.radioDirty = true
    end
    return true
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
