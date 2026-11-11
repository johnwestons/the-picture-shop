local Config = require("src.config")
local SaveEditor = require("src.save_editor")
local Settings = require("src.settings")
local RabbitColorways = require("src.rabbit_colorways")
local CharacterAssets = require("src.character_assets")
local Ui = require("src.screens.ui")
local SilhouetteStyle = require("src.commute.silhouette_style")
local PlayerProfile = require('src.player_profile')
local PROFILE_NAME={x=250,y=178,width=370,height=40}
local PROFILE_SAVE={x=634,y=178,width=162,height=40}

local OptionsScreen = {
    tab = "game",
    selectedRow = 1,
    selectedSlot = 1,
    cheatPage = "resources",
    message = "",
    hover = nil,
    editField = nil,
    editBuffer = "",
    draggingControl = nil,
    draggingSensitivity = nil,
    selectedControlView = "shared",
    controlViewDropdownOpen = false,
    debugOffset = 0,
    debugDragY = nil,
    debugDragRemainder = 0,
    debugPage = "watchdog",
    debugNotesOffset = 0,
    debugNotesDragY = nil,
    context = nil,
}

local ACCESS = { x = 828, y = 14, width = 116, height = 42 }
local ACCESS_HEADER = { x = 828, y = 0, width = 116, height = 42 }
local ACCESS_FOOTER = { x = 828, y = 630, width = 116, height = 42 }
local ACCESS_RACK = { x = 696, y = 28, width = 116, height = 42 }
local ACCESS_MACHINE = { x = 662, y = 28, width = 116, height = 42 }
local CLOSE = { x = 812, y = 20, width = 112, height = 42 }
local MAIN_MENU = { x = 550, y = 20, width = 250, height = 42 }
local MOTORCYCLE_MENU = { x = 710, y = 590, width = 180, height = 40 }
local TABS = {
    game = { x = 106, y = 90, width = 118, height = 48, label = "GAME" },
    audio = { x = 232, y = 90, width = 118, height = 48, label = "AUDIO" },
    controls = { x = 358, y = 90, width = 118, height = 48, label = "CONTROLS" },
    character = { x = 484, y = 90, width = 118, height = 48, label = "PLAYER" },
    cheats = { x = 610, y = 90, width = 118, height = 48, label = "CHEATS" },
    debug = { x = 736, y = 90, width = 118, height = 48, label = "DEBUG" },
}
local TAB_ORDER = { "game", "audio", "controls", "character", "cheats", "debug" }
-- Keep a full-size hit target for every tab inside the existing panel.
TABS.video={label='VIDEO'}
TAB_ORDER={'game','video','audio','controls','character','cheats','debug'}
for i,id in ipairs(TAB_ORDER)do TABS[id].x=106+(i-1)*108;TABS[id].y=90;TABS[id].width=104;TABS[id].height=48 end
function OptionsScreen.tabRect(id)
    local r=TABS[id];if r then return {x=r.x,y=r.y,width=r.width,height=r.height}end
end
local SLOT_RECTS = {
    { x = 286, y = 166, width = 116, height = 42 },
    { x = 422, y = 166, width = 116, height = 42 },
    { x = 558, y = 166, width = 116, height = 42 },
}
local CHEAT_PAGES = {
    {id="resources",label="RESOURCES"}, {id="supplies",label="SUPPLIES"},
    {id="rooms",label="ROOMS"}, {id="machines",label="MACHINES"},
    {id="games",label="BREAK ROOM"},
}
local function cheatPageRect(index)
    return {x=164+(index-1)*128,y=210,width=120,height=28}
end
local function actionRect(index)
    return {x=654,y=267+(index-1)*40,width=108,height=30}
end

local GAME_ROWS = {
    { id = "fullscreen", label = "Fullscreen", kind = "toggle" },
    { id = "vsync", label = "Vertical sync", kind = "toggle" },
    { id = "followPlayerCamera", label = "Follow player camera", kind = "toggle" },
    { id = "twelveHourTime", label = "Time format", kind = "choice" },
    { id = "occlusionHighlightColor", label = "Hidden-player color", kind = "cycle" },
    { id = "occlusionHighlightStyle", label = "Hidden-player display", kind = "choice" },
}
local AUDIO_ROWS = {
    { id = "masterVolume", label = "Master volume", kind = "level" },
    { id = "sfxVolume", label = "Effects volume", kind = "level" },
    { id = "ambientVolume", label = "Ambience volume", kind = "level" },
    { id = "dialogueVolume", label = "Dialogue volume", kind = "level" },
    { id = "dialogueVoicesEnabled", label = "Character voices", kind = "toggle" },
    { id = "muted", label = "Mute all audio", kind = "toggle" },
}
local VIDEO_ROWS={
    {id='dynamicShadows',label='Object shadows',kind='toggle'},
    {id='vegetationShadows',label='Tree shadows',kind='toggle'},
    {id='shadowDistance',label='Shadow distance',kind='cycle'},
    {id='renderDistance',label='World render distance',kind='cycle'},
}
local CONTROL_PREVIEW = { x = 205, y = 176, width = 550, height = 238 }
local CONTROL_VIEW_SELECT = { x = 164, y = 143, width = 632, height = 30 }
local RESET_CONTROLS = { x = 164, y = 548, width = 210, height = 42 }
local MOBILE_STEERING_MODE = { x = 382, y = 548, width = 210, height = 42 }
local MOTORCYCLE_CONTROLS = { x = 604, y = 548, width = 210, height = 42 }
local SENSITIVITY_MIN, SENSITIVITY_MAX = 50, 150
local SENSITIVITY_TRACK = { x = 420, width = 308 }
local SENSITIVITY_ROWS = {
    { id = "mobileWalkSensitivity", label = "WALKING STICK", y = 420 },
    { id = "mobileDriveSensitivity", label = "DRIVING STICK", y = 462 },
}
local COLORWAY_GROUPS = {
    { id = "furColorway", group = "fur", label = "FUR", y = 258 },
    { id = "overallsColorway", group = "overalls", label = "OVERALLS", y = 398 },
}
local CONTROL_SPECS = {
    joystick = { label = "MOVE", radius = 43 },
    primary = { label = "USE", radius = 36 },
    extra1 = { label = "ACTION 1", radius = 27 },
    extra2 = { label = "ACTION 2", radius = 27 },
}
local CONTROL_VIEW_OPTIONS = Settings.controlLayoutViews()

local function selectedControlView()
    for _, view in ipairs(CONTROL_VIEW_OPTIONS) do
        if view.id == OptionsScreen.selectedControlView then return view end
    end
    return CONTROL_VIEW_OPTIONS[1]
end

local function selectedControlSpecs()
    local view = selectedControlView()
    if view.kind ~= "commute" then return CONTROL_SPECS end
    local result = { stick = { label = view.id == "overworld" and "MOVE" or "STEER", radius = 35 } }
    local profile = Settings.normalize(OptionsScreen.context.settings).motorcycleControls
    local bindings = require("src.commute.bindings")
    local allowed = view.id == "overworld"
        and { interact = "USE", worldAction = "ACTION", boost = "SPRINT" }
        or view.id == "truck"
        and { accelerate = "GO", brake = "BRAKE", interact = "EXIT" }
        or { accelerate = "GO", brake = "BRAKE", boost = "BOOST", interact = "GET OFF" }
    for index = 1, 6 do
        local key = "touch" .. index
        local action = bindings.action(profile, "touch", key)
        if allowed[action] then result[key] = { label = allowed[action], radius = 25 } end
    end
    return result
end

local function selectControlView(viewId)
    for _, view in ipairs(CONTROL_VIEW_OPTIONS) do
        if view.id == viewId then
            OptionsScreen.selectedControlView = viewId
            OptionsScreen.controlViewDropdownOpen = false
            OptionsScreen.draggingControl = nil
            OptionsScreen.message = viewId == "shared"
                and "Editing common controls inherited by each view."
                or ("Editing the " .. view.label .. " layout.")
            return true
        end
    end
    return false
end

local function rowRect(index, cheats)
    return { x = 164, y = (cheats and 264 or 202) + (index - 1) * (cheats and 40 or 52),
        width = 632, height = cheats and 36 or 42 }
end

local function controlRects(index, cheats)
    local row = rowRect(index, cheats)
    return {
        value = { x = 447, y = row.y + (cheats and 2 or 3), width = 142,
            height = cheats and 32 or 36 },
        minus = { x = 607, y = row.y + (cheats and 2 or 3), width = 70,
            height = cheats and 32 or 36 },
        plus = { x = 690, y = row.y + (cheats and 2 or 3), width = 70,
            height = cheats and 32 or 36 },
    }
end

local function persistSettings()
    local context = OptionsScreen.context
    if not context then return false end
    Settings.applyAudio(context.settings, context.sound)
    Settings.applyDisplay(context.settings)
    local saved = Settings.save(context.settings)
    OptionsScreen.message = saved and "Settings saved." or "Settings changed for this session, but could not be saved."
    return saved
end

local function setColorway(id, value)
    local context = OptionsScreen.context
    if not context then return false end
    local choices = id == "furColorway" and RabbitColorways.fur or RabbitColorways.overalls
    local fur, overalls = RabbitColorways.normalize(
        context.settings.furColorway, context.settings.overallsColorway)
    local current = id == "furColorway" and fur or overalls
    value = math.max(1, math.min(#choices, value))
    if current == value then return true end
    context.settings[id] = value
    if context.applyPlayerColorways then
        context.applyPlayerColorways(context.settings.furColorway, context.settings.overallsColorway)
    end
    local saved = persistSettings()
    OptionsScreen.message = saved
        and "Rabbit colors saved. Other players can see them online."
        or "Rabbit colors are active for this session but could not be saved."
    return true
end

local function adjustColorway(rowIndex, delta)
    local row = COLORWAY_GROUPS[rowIndex]
    if not row then return false end
    local current = tonumber(OptionsScreen.context.settings[row.id]) or 1
    local count = RabbitColorways.count(row.group)
    return setColorway(row.id, (current - 1 + delta) % count + 1)
end

local function colorwayCellRect(rowIndex, choiceIndex)
    local row = COLORWAY_GROUPS[rowIndex]
    return { x = 292 + (choiceIndex - 1) * 80, y = row.y + 31, width = 72, height = 80 }
end

local function slotState()
    local context = OptionsScreen.context
    if not context then return nil, "empty" end
    return SaveEditor.inspectSlot({
        save = context.save,
        state = context.state,
        useActiveState = context.useActiveState,
    }, OptionsScreen.selectedSlot)
end

local function close()
    local context = OptionsScreen.context
    OptionsScreen.editField, OptionsScreen.editBuffer = nil, ""
    if context and context.onClose then context.onClose() end
    return true
end

function OptionsScreen.enter(context)
    OptionsScreen.motorcycleEditor=nil
    OptionsScreen.context = assert(context, "options context is required")
    OptionsScreen.selectedSlot = context.preferredSlot or 1
    OptionsScreen.selectedSlot = math.max(1,
        math.min(context.save.SLOT_COUNT or 3, OptionsScreen.selectedSlot))
    OptionsScreen.selectedRow = 1
    OptionsScreen.cheatPage = "resources"
    OptionsScreen.editField, OptionsScreen.editBuffer = nil, ""
    OptionsScreen.draggingControl = nil
    OptionsScreen.draggingSensitivity = nil
    OptionsScreen.selectedControlView = "shared"
    OptionsScreen.controlViewDropdownOpen = false
    OptionsScreen.debugOffset=0
    OptionsScreen.debugDragY=nil
    OptionsScreen.debugDragRemainder=0
    OptionsScreen.debugPage="watchdog"
    OptionsScreen.debugNotesOffset=0
    OptionsScreen.debugNotesDragY=nil
    OptionsScreen.message = context.isNetworkClient and context.isNetworkClient()
        and "Audio and game settings are local. Save cheats are host-only."
        or "Changes are saved immediately."
    if OptionsScreen.tab=='character' then OptionsScreen.message='Choose SAVE NAME after editing. Color choices save immediately.' end
end

function OptionsScreen.leave()
    return close()
end

function OptionsScreen.openDebugPanel()
    OptionsScreen.motorcycleEditor=nil
    OptionsScreen.tab="debug"
    OptionsScreen.selectedRow=1
    OptionsScreen.debugOffset=0
    OptionsScreen.debugDragY=nil
    OptionsScreen.debugPage="watchdog"
    OptionsScreen.debugNotesOffset=0
    OptionsScreen.debugNotesDragY=nil
    return true
end

function OptionsScreen.isDebugPanel()
    return OptionsScreen.tab=="debug" and OptionsScreen.motorcycleEditor==nil
end

function OptionsScreen.menuRect()
    local context=OptionsScreen.context
    if not context or not context.canReturnToMenu or type(context.onReturnToMenu)~='function'
        or OptionsScreen.motorcycleEditor and OptionsScreen.motorcycleEditor.capture then return nil end
    return OptionsScreen.motorcycleEditor and MOTORCYCLE_MENU or MAIN_MENU
end

function OptionsScreen.menuLabel()
    local context=OptionsScreen.context
    return context and context.isNetworkClient and context.isNetworkClient()
        and 'LEAVE SESSION' or 'SAVE & MAIN MENU'
end

function OptionsScreen.returnToMenu()
    if not OptionsScreen.menuRect() then return false end
    local okay,reason=OptionsScreen.context.onReturnToMenu()
    if okay then
        OptionsScreen.motorcycleEditor=nil
        OptionsScreen.editField,OptionsScreen.editBuffer,OptionsScreen.draggingControl=nil,'',nil
        OptionsScreen.draggingSensitivity=nil
    else
        OptionsScreen.message=reason or 'Could not return to the menu. Please try again.'
        if OptionsScreen.motorcycleEditor then OptionsScreen.motorcycleEditor.message=OptionsScreen.message end
    end
    return true
end

function OptionsScreen.wantsTextInput()
    return OptionsScreen.editField ~= nil
end

function OptionsScreen.accessRect(screen, bounds)
    -- Keep the global shortcut clear of each console's own Back/Exit controls.
    if screen == 'home_world' then
        local right = bounds and bounds.right or Config.baseWidth
        return {x=right-200,y=14,width=42,height=42}
    elseif screen == "world" then
        local right = bounds and bounds.right or Config.baseWidth
        return { x = right - 272, y = 14, width = ACCESS.width, height = ACCESS.height }
    elseif screen == "machine" then
        return ACCESS_MACHINE
    elseif screen == "machine_service" or screen == "workshop_remote"
        or screen == "shop_clock" or screen == "job_offer" then
        return ACCESS_FOOTER
    elseif screen == "computer" or screen == "work_phone" then
        return ACCESS_HEADER
    elseif screen == "pallet_rack" then
        return ACCESS_RACK
    end
    return ACCESS
end

function OptionsScreen.accessHit(x, y, screen, bounds)
    return Ui.contains(OptionsScreen.accessRect(screen, bounds), x, y)
end

local function selectTab(tab)
    if not TABS[tab] then return false end
    OptionsScreen.tab, OptionsScreen.selectedRow = tab, 1
    OptionsScreen.editField, OptionsScreen.editBuffer = nil, ""
    OptionsScreen.draggingControl = nil
    OptionsScreen.draggingSensitivity = nil
    OptionsScreen.controlViewDropdownOpen = false
    OptionsScreen.debugDragY=nil
    OptionsScreen.debugNotesDragY=nil
    if tab=='debug' then
        OptionsScreen.debugOffset=0
        OptionsScreen.debugPage="watchdog"
        OptionsScreen.debugNotesOffset=0
    end
    OptionsScreen.message = tab == "controls"
        and "Choose a view, then drag the touch controls into place."
        or tab == "cheats"
        and (OptionsScreen.context.isNetworkClient and OptionsScreen.context.isNetworkClient()
            and "Save cheats are host-only in multiplayer."
            or "Developer tools: save changes are immediate.")
        or tab == "debug" and "Live AI and multiplayer diagnostics for playtesting."
        or tab == "character" and 'Choose SAVE NAME after editing. Color choices save immediately.'
        or "Changes are saved immediately."
    return true
end

local function selectCheatPage(page)
    for _,entry in ipairs(CHEAT_PAGES) do
        if entry.id==page then
            OptionsScreen.cheatPage=page
            OptionsScreen.selectedRow=1
            OptionsScreen.editField,OptionsScreen.editBuffer=nil,""
            OptionsScreen.message=OptionsScreen.context.isNetworkClient
                and OptionsScreen.context.isNetworkClient()
                and "Save cheats are host-only in multiplayer."
                or "Selected "..entry.label.." cheats for slot "..OptionsScreen.selectedSlot.."."
            return true
        end
    end
    return false
end

local function toggleSetting(id)
    local context = OptionsScreen.context
    if not context then return false end
    context.settings[id] = not context.settings[id]
    persistSettings()
    return true
end

local setChoice

local function choiceOptions(id)
    if id=='shadowDistance' or id=='renderDistance' then
        return {{value='near',label='NEAR'},{value='medium',label='MEDIUM'},{value='far',label='FAR'}}
    elseif id=="twelveHourTime" then
        return {{value=true,label="12 HOUR"},{value=false,label="24 HOUR"}}
    elseif id=="occlusionHighlightStyle" then
        return {{value="filled",label="FILLED"},{value="outline",label="OUTLINE"}}
    elseif id=="occlusionHighlightColor" then
        local options={}
        for _,color in ipairs(SilhouetteStyle.COLOR_ORDER) do
            options[#options+1]={value=color,label=SilhouetteStyle.LABELS[color]}
        end
        return options
    end
    return {}
end

setChoice=function(id,value)
    local context = OptionsScreen.context
    if not context then return false end
    if id=="twelveHourTime" then context.settings.twelveHourTime=value==true
    else context.settings[id]=value end
    persistSettings()
    return true
end

local function currentChoiceIndex(id,options)
    local current=OptionsScreen.context.settings[id]
    for index,option in ipairs(options) do
        if option.value==current then return index end
    end
    return 1
end

local function stepChoice(id,delta)
    local options=choiceOptions(id)
    if #options==0 or not OptionsScreen.context then return false end
    local index=currentChoiceIndex(id,options)
    index=(index-1+delta)%#options+1
    return setChoice(id,options[index].value)
end

local function adjustSetting(id, delta)
    local context = OptionsScreen.context
    if not context then return false end
    context.settings[id] = math.max(0, math.min(100,
        (tonumber(context.settings[id]) or 0) + delta))
    persistSettings()
    return true
end

local function editContext()
    local context = OptionsScreen.context
    return {
        save = context.save,
        state = context.state,
        saveCurrent = context.saveCurrent,
        isNetworkClient = context.isNetworkClient,
        useActiveState = context.useActiveState,
    }
end

local function setCheatValue(field, value)
    local ok, applied, message = SaveEditor.editSlot(
        editContext(), OptionsScreen.selectedSlot, field.id, value)
    OptionsScreen.message = ok
        and (message .. " " .. field.label .. " is now " .. Ui.commaNumber(applied) .. ".")
        or tostring(applied)
    return ok
end

local function adjustCheat(index, direction)
    if OptionsScreen.cheatPage~="resources" and OptionsScreen.cheatPage~="supplies" then return false end
    local field = SaveEditor.fields(OptionsScreen.cheatPage)[index]
    local state = slotState()
    if not field or not state then
        OptionsScreen.message = "That slot has no editable shop save."
        return false
    end
    local current = tonumber(SaveEditor.value(state, field.id)) or 0
    return setCheatValue(field, current + field.step * direction)
end

local function beginEdit(index)
    if OptionsScreen.cheatPage~="resources" and OptionsScreen.cheatPage~="supplies" then return false end
    local field = SaveEditor.fields(OptionsScreen.cheatPage)[index]
    local state = slotState()
    if not field or not state then
        OptionsScreen.message = "That slot has no editable shop save."
        return false
    end
    OptionsScreen.selectedRow = index
    OptionsScreen.editField = field.id
    OptionsScreen.editBuffer = tostring(math.floor(tonumber(SaveEditor.value(state, field.id)) or 0))
    OptionsScreen.message = "Type a value, then press Enter."
    return true
end

local function grantCheat(index)
    local action=SaveEditor.actions(OptionsScreen.cheatPage)[index]
    if not action then return false end
    local ok,message=SaveEditor.grantSlot(editContext(),OptionsScreen.selectedSlot,action.id)
    OptionsScreen.message=tostring(message)
    return ok
end

local function beginProfileName()
    OptionsScreen.editField='playerName'
    OptionsScreen.editBuffer=PlayerProfile.name(OptionsScreen.context.settings)
    OptionsScreen.replaceName=true
    OptionsScreen.message='Type your display name, then choose SAVE NAME or press Enter.'
    return true
end
local function commitEdit()
    if OptionsScreen.editField=='playerName' then
        local name=PlayerProfile.cleanName(OptionsScreen.editBuffer)
        if name=='' then OptionsScreen.message='Enter a display name before saving.';return false end
        OptionsScreen.context.settings.playerName=name
        local saved=Settings.save(OptionsScreen.context.settings)
        if OptionsScreen.context.applyPlayerProfile then OptionsScreen.context.applyPlayerProfile() end
        OptionsScreen.message=saved and 'Player profile saved for every shop and multiplayer session.'
            or 'Your name is active for this session, but could not be saved. Try again.'
        if saved then OptionsScreen.editField,OptionsScreen.editBuffer=nil,'' end
        return saved
    end
    local field = SaveEditor.field(OptionsScreen.editField)
    if not field then return false end
    local value = tonumber(OptionsScreen.editBuffer)
    if not value then
        OptionsScreen.message = "Enter a whole number before saving."
        return false
    end
    local ok = setCheatValue(field, value)
    if ok then OptionsScreen.editField, OptionsScreen.editBuffer = nil, "" end
    return ok
end

local function rowsForTab()
    if OptionsScreen.tab == 'video' then return VIDEO_ROWS end
    if OptionsScreen.tab == "game" then return GAME_ROWS end
    if OptionsScreen.tab == "audio" then return AUDIO_ROWS end
    if OptionsScreen.tab == "controls" then return {} end
    if OptionsScreen.tab == "character" then return {} end
    if OptionsScreen.tab == "debug" then return {} end
    return (OptionsScreen.cheatPage=="resources" or OptionsScreen.cheatPage=="supplies")
        and SaveEditor.fields(OptionsScreen.cheatPage)
        or SaveEditor.actions(OptionsScreen.cheatPage)
end

function OptionsScreen.isControlsTab()
    return OptionsScreen.tab == "controls"
end

local function controlLayout()
    local context = OptionsScreen.context
    return context and context.getControlLayout and context.getControlLayout(OptionsScreen.selectedControlView)
        or context and context.settings.controlLayout
        or Settings.DEFAULTS.controlLayout
end

local function controlCenter(key)
    local point = controlLayout()[key]
    return CONTROL_PREVIEW.x + point.x * CONTROL_PREVIEW.width,
        CONTROL_PREVIEW.y + point.y * CONTROL_PREVIEW.height
end

local function controlAt(x, y)
    local best, bestDistance
    for key, spec in pairs(selectedControlSpecs()) do
        local centerX, centerY = controlCenter(key)
        local dx, dy = x - centerX, y - centerY
        local distanceSquared = dx * dx + dy * dy
        if distanceSquared <= (spec.radius * 1.25) ^ 2
            and (not bestDistance or distanceSquared < bestDistance)
        then
            best, bestDistance = key, distanceSquared
        end
    end
    return best
end

local function moveDraggedControl(x, y)
    local key = OptionsScreen.draggingControl
    local context = OptionsScreen.context
    if not key or not context or not context.setControlLayout then return false end
    local spec = selectedControlSpecs()[key]
    if not spec then return false end
    local layout = controlLayout()
    local marginX, marginY = spec.radius / CONTROL_PREVIEW.width,
        spec.radius / CONTROL_PREVIEW.height
    layout[key] = {
        x = math.max(marginX, math.min(1 - marginX,
            (x - CONTROL_PREVIEW.x) / CONTROL_PREVIEW.width)),
        y = math.max(marginY, math.min(1 - marginY,
            (y - CONTROL_PREVIEW.y) / CONTROL_PREVIEW.height)),
    }
    context.setControlLayout(layout, OptionsScreen.selectedControlView, key)
    OptionsScreen.message = "Positioning " .. spec.label .. "..."
    return true
end

local function sensitivityRowRect(row)
    return { x = SENSITIVITY_TRACK.x - 12, y = row.y,
        width = SENSITIVITY_TRACK.width + 24, height = 34 }
end

local function sensitivityAt(x, y)
    for _, row in ipairs(SENSITIVITY_ROWS) do
        if Ui.contains(sensitivityRowRect(row), x, y) then return row.id end
    end
end

local function moveSensitivity(x)
    local id = OptionsScreen.draggingSensitivity
    local context = OptionsScreen.context
    if not id or not context then return false end
    local fraction = math.max(0, math.min(1,
        (x - SENSITIVITY_TRACK.x) / SENSITIVITY_TRACK.width))
    local steps = math.floor(fraction * ((SENSITIVITY_MAX - SENSITIVITY_MIN) / 5) + 0.5)
    context.settings[id] = SENSITIVITY_MIN + steps * 5
    return true
end

local function finishSensitivityDrag()
    local id = OptionsScreen.draggingSensitivity
    if not id then return false end
    OptionsScreen.draggingSensitivity = nil
    local value = OptionsScreen.context.settings[id]
    local saved = Settings.save(OptionsScreen.context.settings)
    local label = id == "mobileWalkSensitivity" and "Walking" or "Driving"
    OptionsScreen.message = saved
        and (label .. " stick sensitivity set to " .. value .. "%.")
        or (label .. " stick sensitivity changed for this session, but could not be saved.")
    return true
end

local function resetControls()
    local context = OptionsScreen.context
    if not context or not context.resetControlLayout then return false end
    context.resetControlLayout(OptionsScreen.selectedControlView)
    OptionsScreen.message = OptionsScreen.selectedControlView == "shared"
        and "Shared touch controls reset to their default positions."
        or (selectedControlView().label .. " controls restored their inherited positions.")
    return true
end

local function toggleMobileSteeringMode()
    local context=OptionsScreen.context
    if not context then return false end
    local current=context.settings.mobileVehicleSteering or 'radial'
    local nextMode={radial='bike-horizontal',['bike-horizontal']='all-horizontal',
        ['all-horizontal']='radial'}
    context.settings.mobileVehicleSteering=nextMode[current] or 'radial'
    context.settings.mobileBikeSteering=context.settings.mobileVehicleSteering=='radial'
        and 'radial' or 'horizontal'
    local saved=persistSettings()
    local labels={radial='radial', ['bike-horizontal']='horizontal for bikes',
        ['all-horizontal']='horizontal for all vehicles'}
    local mode=labels[context.settings.mobileVehicleSteering] or labels.radial
    OptionsScreen.message=saved and ('Mobile steering set to '..mode..'.')
        or ('Mobile steering set to '..mode..' for this session, but could not be saved.')
    return true
end

function OptionsScreen.keypressed(key)
    if key=='f9' and OptionsScreen.menuRect() then return OptionsScreen.returnToMenu() end
    if OptionsScreen.motorcycleEditor then return OptionsScreen.motorcycleEditor:keypressed(key) end
    if OptionsScreen.editField then
        if key == "return" or key == "kpenter" then return commitEdit() end
        if key == "escape" then
            OptionsScreen.editField, OptionsScreen.editBuffer = nil, ""
            OptionsScreen.message = "Value edit cancelled."
            return true
        end
        if key == "backspace" then
            OptionsScreen.editBuffer = OptionsScreen.editField=='playerName'
                and (OptionsScreen.replaceName and '' or PlayerProfile.backspace(OptionsScreen.editBuffer))
                or OptionsScreen.editBuffer:sub(1, -2)
            OptionsScreen.replaceName=false
            return true
        end
        return false
    end
    if key == "escape" or key == "o" then return close() end
    if key == "tab" then
        local index = 1
        for current, tab in ipairs(TAB_ORDER) do if tab == OptionsScreen.tab then index = current end end
        return selectTab(TAB_ORDER[index % #TAB_ORDER + 1])
    end
    if OptionsScreen.tab=="debug" then
        if OptionsScreen.debugPage=="notes" then
            local notes=require("src.screens.update_notes_panel")
            if key=="backspace" or key=="b" then
                OptionsScreen.debugPage="watchdog"
                OptionsScreen.message="Live diagnostics for playtesting."
                return true
            end
            local maximum=notes.maxOffset()
            if key=="up" or key=="w" or key=="pageup" then
                OptionsScreen.debugNotesOffset=math.max(0,OptionsScreen.debugNotesOffset
                    -(key=="pageup" and 240 or 40));return true
            elseif key=="down" or key=="s" or key=="pagedown" then
                OptionsScreen.debugNotesOffset=math.min(maximum,OptionsScreen.debugNotesOffset
                    +(key=="pagedown" and 240 or 40));return true
            elseif key=="home" then OptionsScreen.debugNotesOffset=0;return true
            elseif key=="end" then OptionsScreen.debugNotesOffset=maximum;return true end
            return false
        end
        local panel=require("src.screens.ai_watchdog_panel")
        local snapshot=require("src.ai_watchdog").snapshot(OptionsScreen.context.state)
        local maximum=panel.maxOffset(snapshot)
        if key=="up" or key=="w" or key=="pageup" then
            OptionsScreen.debugOffset=math.max(0,OptionsScreen.debugOffset-(key=="pageup" and 2 or 1));return true
        elseif key=="down" or key=="s" or key=="pagedown" then
            OptionsScreen.debugOffset=math.min(maximum,OptionsScreen.debugOffset+(key=="pagedown" and 2 or 1));return true
        elseif key=="home" then OptionsScreen.debugOffset=0;return true
        elseif key=="end" then OptionsScreen.debugOffset=maximum;return true end
        return false
    end
    if OptionsScreen.tab == "controls" then
        if key=='m' then return OptionsScreen.openMotorcycleControls() end
        if key == "r" then return resetControls() end
        if key == "h" then return toggleMobileSteeringMode() end
        if key == "left" or key == "a" or key == "right" or key == "d" then
            local index = 1
            for current, view in ipairs(CONTROL_VIEW_OPTIONS) do
                if view.id == OptionsScreen.selectedControlView then index = current end
            end
            local delta = (key == "left" or key == "a") and -1 or 1
            return selectControlView(CONTROL_VIEW_OPTIONS[(index - 1 + delta) % #CONTROL_VIEW_OPTIONS + 1].id)
        end
        return false
    end
    if OptionsScreen.tab == "character" then
        if key=='n' then return beginProfileName() end
        if key == "up" or key == "w" then
            OptionsScreen.selectedRow = 1
            return true
        elseif key == "down" or key == "s" then
            OptionsScreen.selectedRow = 2
            return true
        elseif key == "left" or key == "a" then
            return adjustColorway(OptionsScreen.selectedRow, -1)
        elseif key == "right" or key == "d" or key == "return" or key == "kpenter" then
            return adjustColorway(OptionsScreen.selectedRow, 1)
        end
        return false
    end
    if OptionsScreen.tab == "cheats" and (key == "1" or key == "2" or key == "3") then
        OptionsScreen.selectedSlot = tonumber(key)
        OptionsScreen.message = "Selected slot " .. key .. "."
        return true
    end
    if OptionsScreen.tab=="cheats" and (key=="q" or key=="e") then
        local index=1
        for current,page in ipairs(CHEAT_PAGES) do
            if page.id==OptionsScreen.cheatPage then index=current;break end
        end
        return selectCheatPage(CHEAT_PAGES[(index-1+(key=="e" and 1 or -1))%#CHEAT_PAGES+1].id)
    end
    local rows = rowsForTab()
    if key == "up" or key == "w" then
        OptionsScreen.selectedRow = ((OptionsScreen.selectedRow - 2) % #rows) + 1
        return true
    elseif key == "down" or key == "s" then
        OptionsScreen.selectedRow = (OptionsScreen.selectedRow % #rows) + 1
        return true
    end
    local row = rows[OptionsScreen.selectedRow]
    if OptionsScreen.tab == "cheats" then
        if OptionsScreen.cheatPage=="resources" or OptionsScreen.cheatPage=="supplies" then
            if key == "left" or key == "a" then return adjustCheat(OptionsScreen.selectedRow, -1) end
            if key == "right" or key == "d" then return adjustCheat(OptionsScreen.selectedRow, 1) end
            if key == "return" or key == "kpenter" then return beginEdit(OptionsScreen.selectedRow) end
        elseif key=="right" or key=="d" or key=="return" or key=="kpenter" then
            return grantCheat(OptionsScreen.selectedRow)
        end
    elseif row.kind == "choice" then
        local options=choiceOptions(row.id)
        if key == "left" or key == "a" then return setChoice(row.id,options[1].value) end
        if key == "right" or key == "d" then return setChoice(row.id,options[2].value) end
        if key == "return" or key == "kpenter" then return stepChoice(row.id,1) end
    elseif row.kind == "cycle" then
        if key == "left" or key == "a" then return stepChoice(row.id,-1) end
        if key == "right" or key == "d" or key == "return" or key == "kpenter" then
            return stepChoice(row.id,1)
        end
    elseif row.kind == "toggle" and (key == "left" or key == "right"
        or key == "return" or key == "kpenter")
    then
        return toggleSetting(row.id)
    elseif row.kind == "level" then
        if key == "left" or key == "a" then return adjustSetting(row.id, -5) end
        if key == "right" or key == "d" then return adjustSetting(row.id, 5) end
    end
    return false
end

function OptionsScreen.textinput(text)
    if not OptionsScreen.editField then return false end
    if OptionsScreen.editField=='playerName' then
        local prefix=OptionsScreen.replaceName and '' or OptionsScreen.editBuffer
        OptionsScreen.editBuffer=PlayerProfile.input(prefix..tostring(text or ''))
        OptionsScreen.replaceName=false
        return true
    end
    local digits = tostring(text or ""):gsub("[^0-9]", "")
    if digits == "" then return false end
    OptionsScreen.editBuffer = (OptionsScreen.editBuffer .. digits):sub(1, 9)
    return true
end

function OptionsScreen.mousepressed(x, y, button)
    local menu=OptionsScreen.menuRect()
    if button==1 and menu and Ui.contains(menu,x,y) then return OptionsScreen.returnToMenu() end
    if OptionsScreen.motorcycleEditor then return OptionsScreen.motorcycleEditor:mousepressed(x,y,button) end
    if button ~= 1 then return false end
    if Ui.contains(CLOSE, x, y) then return close() end
    for tab, rect in pairs(TABS) do
        if Ui.contains(rect, x, y) then return selectTab(tab) end
    end
    if OptionsScreen.tab=="debug" then
        local notes=require("src.screens.update_notes_panel")
        local navigation=notes.hitTest(x,y,OptionsScreen.debugPage)
        if navigation=="open" then
            OptionsScreen.debugPage="notes"
            OptionsScreen.debugNotesOffset=0
            OptionsScreen.message="Browse the dated release notes."
            return true
        elseif navigation=="back" then
            OptionsScreen.debugPage="watchdog"
            OptionsScreen.message="Live diagnostics for playtesting."
            return true
        end
        if OptionsScreen.debugPage=="notes" then
            if notes.inViewport(x,y) then
                OptionsScreen.debugNotesDragY=y
                return true
            end
            return false
        end
        local panel=require("src.screens.ai_watchdog_panel")
        local snapshot=require("src.ai_watchdog").snapshot(OptionsScreen.context.state)
        local maximum=panel.maxOffset(snapshot)
        local action=panel.hitTest(x,y)
        if action=="newer" then
            OptionsScreen.debugOffset=math.max(0,OptionsScreen.debugOffset-panel.PAGE_SIZE);return true
        elseif action=="older" then
            OptionsScreen.debugOffset=math.min(maximum,OptionsScreen.debugOffset+panel.PAGE_SIZE);return true
        elseif action=="latest" then OptionsScreen.debugOffset=0;return true end
        if x>=110 and x<=850 and y>=321 and y<=565 then
            OptionsScreen.debugDragY=y;OptionsScreen.debugDragRemainder=0;return true
        end
        return false
    end
    if OptionsScreen.tab == "cheats" then
        for slot, rect in ipairs(SLOT_RECTS) do
            if Ui.contains(rect, x, y) then
                OptionsScreen.selectedSlot = slot
                OptionsScreen.editField, OptionsScreen.editBuffer = nil, ""
                OptionsScreen.message = "Selected slot " .. slot .. "."
                return true
            end
        end
        for index,page in ipairs(CHEAT_PAGES) do
            if Ui.contains(cheatPageRect(index),x,y) then return selectCheatPage(page.id) end
        end
    elseif OptionsScreen.tab == "controls" then
        if OptionsScreen.controlViewDropdownOpen then
            for index, view in ipairs(CONTROL_VIEW_OPTIONS) do
                local column = (index - 1) % 2
                local row = math.floor((index - 1) / 2)
                local rect = { x = 164 + column * 320, y = 179 + row * 29,
                    width = 312, height = 26 }
                if Ui.contains(rect, x, y) then return selectControlView(view.id) end
            end
            if not Ui.contains(CONTROL_VIEW_SELECT, x, y) then
                OptionsScreen.controlViewDropdownOpen = false
                local menuBottom = 178 + math.ceil(#CONTROL_VIEW_OPTIONS / 2) * 29 + 6
                if x >= CONTROL_VIEW_SELECT.x and x <= CONTROL_VIEW_SELECT.x + CONTROL_VIEW_SELECT.width
                    and y >= 178 and y <= menuBottom then return true end
            else
                OptionsScreen.controlViewDropdownOpen = false
                return true
            end
        end
        if Ui.contains(CONTROL_VIEW_SELECT, x, y) then
            OptionsScreen.controlViewDropdownOpen = not OptionsScreen.controlViewDropdownOpen
            return true
        end
        if Ui.contains(MOTORCYCLE_CONTROLS,x,y) then return OptionsScreen.openMotorcycleControls() end
        if Ui.contains(MOBILE_STEERING_MODE,x,y) then return toggleMobileSteeringMode() end
        if Ui.contains(RESET_CONTROLS, x, y) then return resetControls() end
        local sensitivity = sensitivityAt(x, y)
        if sensitivity then
            OptionsScreen.draggingSensitivity = sensitivity
            return moveSensitivity(x)
        end
        local control = controlAt(x, y)
        if control then
            OptionsScreen.draggingControl = control
            return moveDraggedControl(x, y)
        end
        return false
    elseif OptionsScreen.tab == "character" then
        if Ui.contains(PROFILE_NAME,x,y) then return beginProfileName() end
        if Ui.contains(PROFILE_SAVE,x,y) then
            if OptionsScreen.editField=='playerName' then return commitEdit() end
            return beginProfileName()
        end
        for rowIndex, row in ipairs(COLORWAY_GROUPS) do
            for choiceIndex = 1, RabbitColorways.count(row.group) do
                if Ui.contains(colorwayCellRect(rowIndex, choiceIndex), x, y) then
                    OptionsScreen.selectedRow = rowIndex
                    return setColorway(row.id, choiceIndex)
                end
            end
        end
        return false
    end
    if OptionsScreen.tab=="cheats" and OptionsScreen.cheatPage~="resources"
        and OptionsScreen.cheatPage~="supplies" then
        for index in ipairs(SaveEditor.actions(OptionsScreen.cheatPage)) do
            if Ui.contains(rowRect(index,true),x,y) then OptionsScreen.selectedRow=index end
            if Ui.contains(actionRect(index),x,y) then return grantCheat(index) end
        end
        return false
    end
    local rows = rowsForTab()
    for index, row in ipairs(rows) do
        local rects = controlRects(index, OptionsScreen.tab == "cheats")
        if Ui.contains(rowRect(index, OptionsScreen.tab == "cheats"), x, y) then
            OptionsScreen.selectedRow = index
        end
        if Ui.contains(rects.value, x, y) then
            if OptionsScreen.tab == "cheats" then return beginEdit(index) end
            if row.kind == "toggle" then return toggleSetting(row.id) end
            if row.kind == "choice" or row.kind == "cycle" then return stepChoice(row.id,1) end
        elseif Ui.contains(rects.minus, x, y) then
            if OptionsScreen.tab == "cheats" then return adjustCheat(index, -1) end
            if row.kind == "level" then return adjustSetting(row.id, -5) end
            if row.kind == "choice" then
                local options=choiceOptions(row.id);return setChoice(row.id,options[1].value)
            end
            if row.kind == "cycle" then return stepChoice(row.id,-1) end
            return toggleSetting(row.id)
        elseif Ui.contains(rects.plus, x, y) then
            if OptionsScreen.tab == "cheats" then return adjustCheat(index, 1) end
            if row.kind == "level" then return adjustSetting(row.id, 5) end
            if row.kind == "choice" then
                local options=choiceOptions(row.id);return setChoice(row.id,options[2].value)
            end
            if row.kind == "cycle" then return stepChoice(row.id,1) end
            return toggleSetting(row.id)
        end
    end
    return false
end

function OptionsScreen.mousereleased(x, y, button)
    if OptionsScreen.motorcycleEditor then return OptionsScreen.motorcycleEditor:mousereleased(x,y,button) end
    if button==1 and OptionsScreen.debugNotesDragY then
        OptionsScreen.debugNotesDragY=nil
        return true
    end
    if button==1 and OptionsScreen.debugDragY then OptionsScreen.debugDragY=nil;return true end
    if button == 1 and OptionsScreen.draggingSensitivity then return finishSensitivityDrag() end
    if button == 1 and OptionsScreen.draggingControl then
        OptionsScreen.draggingControl = nil
        local context = OptionsScreen.context
        if context and context.commitControlLayout then context.commitControlLayout(OptionsScreen.selectedControlView) end
        OptionsScreen.message = selectedControlView().id == "shared"
            and "Shared control layout saved on this device."
            or (selectedControlView().label .. " layout saved on this device.")
        return true
    end
    return false
end

function OptionsScreen.mousemoved(x, y)
    if OptionsScreen.motorcycleEditor then return OptionsScreen.motorcycleEditor:mousemoved(x,y) end
    OptionsScreen.hover = { x = x, y = y }
    if OptionsScreen.debugNotesDragY then
        local delta=y-OptionsScreen.debugNotesDragY
        OptionsScreen.debugNotesDragY=y
        local notes=require("src.screens.update_notes_panel")
        OptionsScreen.debugNotesOffset=math.max(0,math.min(notes.maxOffset(),
            OptionsScreen.debugNotesOffset-delta))
        return true
    end
    if OptionsScreen.debugDragY then
        local delta=y-OptionsScreen.debugDragY
        OptionsScreen.debugDragY=y
        OptionsScreen.debugDragRemainder=OptionsScreen.debugDragRemainder+delta
        local panel=require("src.screens.ai_watchdog_panel")
        local maximum=panel.maxOffset(require("src.ai_watchdog").snapshot(OptionsScreen.context.state))
        while OptionsScreen.debugDragRemainder<=-40 do
            OptionsScreen.debugOffset=math.min(maximum,OptionsScreen.debugOffset+1)
            OptionsScreen.debugDragRemainder=OptionsScreen.debugDragRemainder+40
        end
        while OptionsScreen.debugDragRemainder>=40 do
            OptionsScreen.debugOffset=math.max(0,OptionsScreen.debugOffset-1)
            OptionsScreen.debugDragRemainder=OptionsScreen.debugDragRemainder-40
        end
        return true
    end
    if OptionsScreen.draggingSensitivity then return moveSensitivity(x) end
    if OptionsScreen.draggingControl then return moveDraggedControl(x, y) end
end

local function drawButton(rect, label, active, danger)
    local hovered = OptionsScreen.hover and Ui.contains(rect,
        OptionsScreen.hover.x, OptionsScreen.hover.y)
    Ui.panel(rect,
        active and { 0.31, 0.39, 0.34, 1 }
            or hovered and { 0.20, 0.27, 0.27, 1 }
            or danger and { 0.30, 0.12, 0.11, 1 }
            or { 0.12, 0.17, 0.18, 1 },
        active and { 0.96, 0.77, 0.24, 1 } or { 0.43, 0.53, 0.51, 1 }, 4, active and 3 or 1)
    love.graphics.setColor(0.94, 0.95, 0.89)
    love.graphics.printf(label, rect.x, rect.y + rect.height / 2 - 7, rect.width, "center")
end

function OptionsScreen.drawAccessButton(mouseX, mouseY, screen, bounds, assets)
    OptionsScreen.hover = mouseX and mouseY and { x = mouseX, y = mouseY } or nil
    if screen == 'home_world' then
        local g=love.graphics;local rect=OptionsScreen.accessRect(screen,bounds)
        local hovered=mouseX and mouseY and Ui.contains(rect,mouseX,mouseY)
        g.push('all');g.setShader()
        g.setColor(hovered and .18 or .055,hovered and .29 or .12,.12,.96)
        g.circle('fill',rect.x+21,rect.y+21,20)
        g.setColor(.76,.66,.40,1);g.setLineWidth(2)
        g.circle('line',rect.x+21,rect.y+21,18)
        for i=0,7 do
            local angle=i*math.pi/4
            g.line(rect.x+21+math.cos(angle)*10,rect.y+21+math.sin(angle)*10,
                rect.x+21+math.cos(angle)*15,rect.y+21+math.sin(angle)*15)
        end
        g.circle('line',rect.x+21,rect.y+21,9)
        g.circle('line',rect.x+21,rect.y+21,3)
        g.pop();return
    end
    if screen == "title" then
        local rect = OptionsScreen.accessRect(screen, bounds)
        local hovered = mouseX and mouseY and Ui.contains(rect, mouseX, mouseY)
        require("src.screens.title_skin").button(assets or require("src.assets"), rect,
            Ui.pressWithin(rect) and "pressed" or hovered and "hover" or "normal")
        local previousFont = love.graphics.getFont()
        local font = require("src.screens.title_fonts").get("metal", 16)
        love.graphics.setFont(font)
        love.graphics.setColor(0.94, 0.95, 0.89)
        love.graphics.printf("OPTIONS", rect.x + 11, rect.y + (rect.height - font:getHeight()) / 2,
            rect.width - 22, "center")
        love.graphics.setFont(previousFont)
        return
    end
    if screen == 'computer' then
        local rect = OptionsScreen.accessRect(screen, bounds)
        local hovered = mouseX and mouseY and Ui.contains(rect, mouseX, mouseY)
        Ui.panel(rect, {0.12, 0.17, 0.18, hovered and 0.85 or 0.56}, {0.43, 0.53, 0.51, 0.7}, 4, 1)
        love.graphics.setColor(0.94, 0.95, 0.89)
        love.graphics.printf('OPTIONS', rect.x, rect.y + rect.height / 2 - 7, rect.width, 'center')
        return
    end
    drawButton(OptionsScreen.accessRect(screen, bounds), "OPTIONS", false, false)
end

local function drawRows(rows, values, cheats)
    for index, row in ipairs(rows) do
        local rect = rowRect(index, cheats)
        local selected = OptionsScreen.selectedRow == index
        Ui.panel(rect, selected and { 0.14, 0.20, 0.20, 1 } or { 0.09, 0.12, 0.13, 1 },
            selected and { 0.67, 0.58, 0.27, 1 } or { 0.25, 0.31, 0.31, 1 }, 3, 1)
        love.graphics.setColor(0.86, 0.88, 0.82)
        love.graphics.print(row.label, rect.x + 18, rect.y + 13)
        local controls = controlRects(index, cheats)
        local value = values[index]
        local editing = cheats and OptionsScreen.editField == row.id
        drawButton(controls.value, editing and (OptionsScreen.editBuffer .. "|") or value,
            editing or row.kind=="choice" or row.kind=="cycle", false)
        if row.kind == "choice" then
            local options=choiceOptions(row.id)
            local current=OptionsScreen.context.settings[row.id]
            drawButton(controls.minus,options[1].label,current==options[1].value,false)
            drawButton(controls.plus,options[2].label,current==options[2].value,false)
        elseif row.kind == "cycle" then
            drawButton(controls.minus,"PREV",false,false)
            drawButton(controls.plus,"NEXT",false,false)
        elseif row.kind == "toggle" then
            drawButton(controls.minus, "TOGGLE", false, false)
            drawButton(controls.plus, "TOGGLE", false, false)
        else
            drawButton(controls.minus, cheats and ("-" .. Ui.commaNumber(row.step)) or "- 5", false, false)
            drawButton(controls.plus, cheats and ("+" .. Ui.commaNumber(row.step)) or "+ 5", false, false)
        end
    end
end

local function drawCheatActions(state)
    for index,action in ipairs(SaveEditor.actions(OptionsScreen.cheatPage)) do
        local rect=rowRect(index,true)
        local selected=OptionsScreen.selectedRow==index
        Ui.panel(rect,selected and {0.14,0.20,0.20,1} or {0.09,0.12,0.13,1},
            selected and {0.67,0.58,0.27,1} or {0.25,0.31,0.31,1},3,1)
        love.graphics.setColor(0.86,0.88,0.82)
        love.graphics.print(action.label,rect.x+18,rect.y+11)
        local status=SaveEditor.actionStatus(state,action.id)
        love.graphics.setColor(0.66,0.74,0.70)
        love.graphics.printf(status,487,rect.y+11,155,"right")
        local canGrant=status~="OWNED" and status~="OTHER ROOM"
        local caption=status=="FINISH" and "FINISH" or status=="OTHER ROOM" and "BLOCKED"
            or status=="OWNED" and "OWNED" or "GRANT"
        drawButton(actionRect(index),caption,false,not canGrant)
    end
end

local function slotLabel(slot, state, status)
    if state then return "SLOT " .. slot end
    if status == "corrupted" then return "SLOT " .. slot .. " !" end
    return "SLOT " .. slot .. " —"
end

local function drawControlPreview()
    Ui.panel(CONTROL_PREVIEW, { 0.075, 0.105, 0.12, 1 },
        { 0.36, 0.48, 0.49, 1 }, 8, 2)
    love.graphics.setColor(0.12, 0.17, 0.18, 1)
    for line = 1, 5 do
        local y = CONTROL_PREVIEW.y + line * CONTROL_PREVIEW.height / 6
        love.graphics.line(CONTROL_PREVIEW.x + 10, y,
            CONTROL_PREVIEW.x + CONTROL_PREVIEW.width - 10, y)
    end
    for key, spec in pairs(selectedControlSpecs()) do
        local x, y = controlCenter(key)
        local dragged = OptionsScreen.draggingControl == key
        love.graphics.setColor(0.025, 0.055, 0.07, 0.88)
        love.graphics.circle("fill", x, y, spec.radius)
        love.graphics.setColor(dragged and { 0.98, 0.82, 0.25, 1 }
            or { 0.42, 0.73, 0.78, 1 })
        love.graphics.setLineWidth(dragged and 4 or 3)
        love.graphics.circle("line", x, y, spec.radius)
        love.graphics.setColor(0.96, 0.98, 0.92, 1)
        local textScale = spec.radius < 30 and 0.60 or 0.74
        love.graphics.printf(spec.label, x - spec.radius, y - 6,
            spec.radius * 2, "center", 0, textScale, textScale)
    end
    love.graphics.setLineWidth(1)
end

local function drawControlViewSelector()
    local selected = selectedControlView()
    local hovered = OptionsScreen.hover and Ui.contains(CONTROL_VIEW_SELECT,
        OptionsScreen.hover.x, OptionsScreen.hover.y)
    Ui.panel(CONTROL_VIEW_SELECT, { 0.09, 0.13, 0.12, 1 },
        (hovered or OptionsScreen.controlViewDropdownOpen) and { 0.85, 0.70, 0.30, 1 }
            or { 0.34, 0.43, 0.41, 1 }, 4, 1)
    love.graphics.setColor(0.60, 0.69, 0.64)
    love.graphics.print("VIEW", CONTROL_VIEW_SELECT.x + 12, CONTROL_VIEW_SELECT.y + 8)
    love.graphics.setColor(0.96, 0.94, 0.83)
    love.graphics.print(selected.label, CONTROL_VIEW_SELECT.x + 86, CONTROL_VIEW_SELECT.y + 8)
    love.graphics.setColor(0.76, 0.83, 0.73)
    love.graphics.printf(OptionsScreen.controlViewDropdownOpen and "▲" or "▼",
        CONTROL_VIEW_SELECT.x + CONTROL_VIEW_SELECT.width - 34, CONTROL_VIEW_SELECT.y + 6, 22, "center")
    if not OptionsScreen.controlViewDropdownOpen then return end
    local rows = math.ceil(#CONTROL_VIEW_OPTIONS / 2)
    local menu = { x = CONTROL_VIEW_SELECT.x, y = 178, width = CONTROL_VIEW_SELECT.width,
        height = rows * 29 + 6 }
    Ui.panel(menu, { 0.045, 0.065, 0.06, 0.98 }, { 0.55, 0.64, 0.56, 1 }, 4, 2)
    for index, view in ipairs(CONTROL_VIEW_OPTIONS) do
        local column = (index - 1) % 2
        local row = math.floor((index - 1) / 2)
        local rect = { x = 164 + column * 320, y = 181 + row * 29,
            width = 312, height = 26 }
        local active = view.id == OptionsScreen.selectedControlView
        local hover = OptionsScreen.hover and Ui.contains(rect, OptionsScreen.hover.x, OptionsScreen.hover.y)
        love.graphics.setColor(active and { 0.34, 0.32, 0.19, 1 }
            or hover and { 0.15, 0.21, 0.18, 1 } or { 0.07, 0.10, 0.09, 1 })
        love.graphics.rectangle("fill", rect.x, rect.y, rect.width, rect.height, 3, 3)
        love.graphics.setColor(active and { 1, 0.86, 0.40, 1 } or { 0.89, 0.92, 0.83, 1 })
        love.graphics.print(view.label, rect.x + 10, rect.y + 6)
    end
end

local function drawSensitivitySliders()
    for _, row in ipairs(SENSITIVITY_ROWS) do
        local value = tonumber(OptionsScreen.context.settings[row.id]) or 100
        value = math.max(SENSITIVITY_MIN, math.min(SENSITIVITY_MAX, value))
        local fraction = (value - SENSITIVITY_MIN) / (SENSITIVITY_MAX - SENSITIVITY_MIN)
        local y = row.y + 17
        love.graphics.setColor(0.82, 0.86, 0.79, 1)
        love.graphics.print(row.label, 164, row.y + 8)
        love.graphics.setColor(0.12, 0.18, 0.18, 1)
        love.graphics.rectangle("fill", SENSITIVITY_TRACK.x, y - 3,
            SENSITIVITY_TRACK.width, 6, 3, 3)
        love.graphics.setColor(0.82, 0.67, 0.28, 1)
        love.graphics.rectangle("fill", SENSITIVITY_TRACK.x, y - 3,
            SENSITIVITY_TRACK.width * fraction, 6, 3, 3)
        local knobX = SENSITIVITY_TRACK.x + SENSITIVITY_TRACK.width * fraction
        love.graphics.setColor(0.025, 0.055, 0.06, 1)
        love.graphics.circle("fill", knobX, y, 9)
        love.graphics.setColor(0.96, 0.80, 0.34, 1)
        love.graphics.setLineWidth(2)
        love.graphics.circle("line", knobX, y, 8)
        love.graphics.setLineWidth(1)
        love.graphics.setColor(0.95, 0.94, 0.83, 1)
        love.graphics.printf(value .. "%", 744, row.y + 8, 52, "center")
    end
end

local function drawColorways()
    love.graphics.setColor(0.78, 0.81, 0.76)
    love.graphics.print("PLAYER PROFILE", 164, 150)
    love.graphics.print('NAME',164,188)
    Ui.panel(PROFILE_NAME,{.10,.14,.14,1},OptionsScreen.editField=='playerName'
        and {.98,.80,.30,1} or {.38,.47,.45,1},4,1)
    local name=OptionsScreen.editField=='playerName' and OptionsScreen.editBuffer
        or PlayerProfile.name(OptionsScreen.context.settings)
    love.graphics.setColor(.95,.94,.83,1)
    local nameScale=math.min(1,(PROFILE_NAME.width-20)/math.max(1,love.graphics.getFont():getWidth(name)))
    love.graphics.print(name,PROFILE_NAME.x+10,PROFILE_NAME.y+10,0,nameScale,nameScale)
    drawButton(PROFILE_SAVE,'SAVE NAME',false,false)
    love.graphics.setColor(0.58, 0.64, 0.61)
    love.graphics.printf('Name and colors carry across all saves on this device and are shared online. [N: edit name]',
        164, 230, 632, 'left')
    for rowIndex, row in ipairs(COLORWAY_GROUPS) do
        Ui.panel({ x = 164, y = row.y, width = 632, height = 124 },
            OptionsScreen.selectedRow == rowIndex and { 0.11, 0.15, 0.15, 1 }
                or { 0.075, 0.105, 0.11, 1 },
            OptionsScreen.selectedRow == rowIndex and { 0.67, 0.58, 0.27, 1 }
                or { 0.25, 0.31, 0.31, 1 }, 4, 1)
        love.graphics.setColor(0.86, 0.88, 0.82)
        love.graphics.printf(row.label, 176, row.y + 51, 104, "center")
        local selected = tonumber(OptionsScreen.context.settings[row.id]) or 1
        for choiceIndex = 1, RabbitColorways.count(row.group) do
            local choice = RabbitColorways.choice(row.group, choiceIndex)
            local rect = colorwayCellRect(rowIndex, choiceIndex)
            local hovered = OptionsScreen.hover and Ui.contains(rect,
                OptionsScreen.hover.x, OptionsScreen.hover.y)
            love.graphics.setColor(hovered and { 0.19, 0.25, 0.24, 1 }
                or { 0.10, 0.14, 0.14, 1 })
            love.graphics.rectangle("fill", rect.x, rect.y, rect.width, rect.height, 3, 3)
            love.graphics.setColor(choice.color[1], choice.color[2], choice.color[3], 1)
            love.graphics.rectangle("fill", rect.x + 18, rect.y + 7, 36, 36, 4, 4)
            love.graphics.setColor(choiceIndex == selected and { 0.98, 0.80, 0.30, 1 }
                or { 0.38, 0.47, 0.45, 1 })
            love.graphics.setLineWidth(choiceIndex == selected and 3 or 1)
            love.graphics.rectangle("line", rect.x + 17, rect.y + 6, 38, 38, 4, 4)
            love.graphics.setLineWidth(1)
            love.graphics.setColor(choiceIndex == selected and { 0.98, 0.84, 0.38, 1 }
                or { 0.78, 0.82, 0.77, 1 })
            love.graphics.printf(choice.name, rect.x + 1, rect.y + 51, rect.width - 2, "center")
        end
    end
    local image, quad = CharacterAssets.get("rabbit-worker", "idle", 1)
    if image and quad then
        local anchorX, anchorY = CharacterAssets.getAnchor("rabbit-worker", "idle", 1)
        local scale = 0.18 * CharacterAssets.getNormalization("rabbit-worker", "idle")
        love.graphics.setColor(1, 1, 1, 1)
        RabbitColorways.draw(image, quad, 462, 596, 0, scale, scale, anchorX, anchorY,
            0, 0, OptionsScreen.context.settings.furColorway,
            OptionsScreen.context.settings.overallsColorway)
    end
    love.graphics.setColor(0.86, 0.88, 0.82)
    love.graphics.print("LIVE PLAYER PREVIEW", 514, 551)
    love.graphics.setColor(0.58, 0.64, 0.61)
    love.graphics.printf(PlayerProfile.name(OptionsScreen.context.settings), 514, 575, 250, "left")
end

function OptionsScreen.draw(mouseX, mouseY)
    if OptionsScreen.motorcycleEditor then
        OptionsScreen.motorcycleEditor:draw()
        local menu=OptionsScreen.menuRect()
        if menu then drawButton(menu,OptionsScreen.menuLabel(),false,false) end
        return
    end
    if mouseX and mouseY then OptionsScreen.mousemoved(mouseX, mouseY) end
    love.graphics.clear(0.045, 0.055, 0.058)
    Ui.panel({ x = 92, y = 66, width = 776, height = 576 },
        { 0.065, 0.085, 0.087, 1 }, { 0.48, 0.55, 0.49, 1 }, 6, 2)
    love.graphics.setColor(0.95, 0.82, 0.26)
    love.graphics.print("SHOP CONTROL", 116, 28, 0, 1.15, 1.15)
    love.graphics.setColor(0.66, 0.72, 0.69)
    love.graphics.print("OPTIONS // O KEY OR CONTROLLER START", 116, 49)
    drawButton(CLOSE, OptionsScreen.menuRect() and "RESUME" or "BACK", false, false)
    local menu=OptionsScreen.menuRect()
    if menu then drawButton(menu,OptionsScreen.menuLabel(),false,false) end
    for _, tab in ipairs(TAB_ORDER) do
        local rect = TABS[tab]
        drawButton(rect, rect.label, OptionsScreen.tab == tab, false)
    end

    if OptionsScreen.tab == "game" then
        love.graphics.setColor(0.78, 0.81, 0.76)
        love.graphics.print("DISPLAY, CAMERA & VISIBILITY", 164, 166)
        local android = love.system and love.system.getOS and love.system.getOS() == "Android"
        local values = {
            android and "SYSTEM" or (OptionsScreen.context.settings.fullscreen and "ON" or "OFF"),
            OptionsScreen.context.settings.vsync and "ON" or "OFF",
            OptionsScreen.context.settings.followPlayerCamera and "ON" or "OFF",
            OptionsScreen.context.settings.twelveHourTime and "12 HOUR" or "24 HOUR",
            SilhouetteStyle.LABELS[OptionsScreen.context.settings.occlusionHighlightColor] or "YELLOW",
            SilhouetteStyle.STYLE_LABELS[OptionsScreen.context.settings.occlusionHighlightStyle] or "FILLED",
        }
        drawRows(GAME_ROWS, values, false)
        love.graphics.setColor(0.58, 0.64, 0.61)
        love.graphics.printf(android and "Fullscreen is managed by Android."
            or "Display, time format, and hidden-player highlight changes apply immediately.", 164, 522, 632, "center")
        love.graphics.printf("Hidden-player highlights can be filled or outlined. Use left/right to change color.",
            164, 548, 632, "center")
        love.graphics.printf("Follow keeps you centered; turn it off to pan. Pinch or mouse wheel zooms.",
            164, 574, 632, "center")
    elseif OptionsScreen.tab == 'video' then
        local settings=OptionsScreen.context.settings
        love.graphics.setColor(.78,.81,.76);love.graphics.print('VIDEO / PERFORMANCE',164,166)
        drawRows(VIDEO_ROWS,{
            settings.dynamicShadows~=false and 'ON' or 'OFF',settings.vegetationShadows==true and 'ON' or 'OFF',
            (settings.shadowDistance or 'medium'):upper(),(settings.renderDistance or 'medium'):upper()},false)
        love.graphics.setColor(.58,.64,.61)
        love.graphics.printf('Object shadows affect the warehouse and outdoors. Tree shadows are optional; grass never casts shadows.',164,438,632,'center')
        love.graphics.printf('Shorter distances reduce outdoor detail and shadow work. Tree shadows require object shadows to be ON.',164,490,632,'center')
        love.graphics.printf('Changes apply immediately and save on this device. New shadow areas fill in gradually to keep camera movement smooth.',164,548,632,'center')
    elseif OptionsScreen.tab == "audio" then
        love.graphics.setColor(0.78, 0.81, 0.76)
        love.graphics.print("AUDIO MIX", 164, 166)
        local settings = OptionsScreen.context.settings
        drawRows(AUDIO_ROWS, {
            settings.masterVolume .. "%", settings.sfxVolume .. "%",
            settings.ambientVolume .. "%", settings.dialogueVolume .. "%",
            settings.dialogueVoicesEnabled and "ON" or "OFF",
            settings.muted and "ON" or "OFF",
        }, false)
        love.graphics.setColor(0.58, 0.64, 0.61)
        love.graphics.printf("Dialogue volume is separate from effects. Turning character voices off keeps dialogue text and bubbles.",
            164, 532, 632, "center")
    elseif OptionsScreen.tab == "controls" then
        drawControlPreview()
        drawControlViewSelector()
        drawSensitivitySliders()
        love.graphics.setColor(0.58, 0.64, 0.61)
        love.graphics.printf("Shared MOVE / USE positions carry across screens; move any other button per view. Layouts save on this device.",
            164, 528, 632, "center")
        drawButton(RESET_CONTROLS, OptionsScreen.selectedControlView == "shared"
            and "RESET SHARED" or "RESET THIS VIEW", false, false)
        local steering=OptionsScreen.context.settings.mobileVehicleSteering or 'radial'
        local steeringLabel=steering=='bike-horizontal' and 'BIKE: HORIZONTAL'
            or steering=='all-horizontal' and 'ALL: HORIZONTAL' or 'STICK: RADIAL'
        drawButton(MOBILE_STEERING_MODE,steeringLabel,steering~='radial',false)
        drawButton(MOTORCYCLE_CONTROLS,'MOTORCYCLE CONTROLS',false,false)
    elseif OptionsScreen.tab == "character" then
        drawColorways()
    elseif OptionsScreen.tab == "debug" then
        if OptionsScreen.debugPage=="notes" then
            OptionsScreen.debugNotesOffset=require("src.screens.update_notes_panel").drawOptions(
                OptionsScreen.debugNotesOffset)
        else
            local environment=OptionsScreen.context.getDebugInfo
                and OptionsScreen.context.getDebugInfo() or {}
            require("src.screens.ai_watchdog_panel").drawOptions(
                OptionsScreen.context.state,environment,OptionsScreen.debugOffset)
            require("src.screens.update_notes_panel").drawOpenButton()
        end
    else
        for slot, rect in ipairs(SLOT_RECTS) do
            local context = OptionsScreen.context
            local stateForSlot, status = SaveEditor.inspectSlot({
                save = context.save, state = context.state,
                useActiveState = context.useActiveState,
            }, slot)
            drawButton(rect, slotLabel(slot, stateForSlot, status),
                OptionsScreen.selectedSlot == slot, status == "corrupted")
        end
        for index,page in ipairs(CHEAT_PAGES) do
            drawButton(cheatPageRect(index),page.label,
                OptionsScreen.cheatPage==page.id,false)
        end
        local stateForSlot, status = slotState()
        love.graphics.setColor(0.68, 0.72, 0.68)
        if stateForSlot then
            local jobs = stateForSlot.jobs or {}
            love.graphics.printf(string.format("%s SAVE  |  %d active jobs  |  %d completed jobs",
                status == "live" and "LIVE" or "OFFLINE",
                #(jobs.active or {}), #(jobs.completed or {})), 164, 242, 632, "center")
            if OptionsScreen.cheatPage=="resources" or OptionsScreen.cheatPage=="supplies" then
                local values = {}
                local fields=SaveEditor.fields(OptionsScreen.cheatPage)
                for index, field in ipairs(fields) do
                    local value = SaveEditor.value(stateForSlot, field.id) or 0
                    values[index] = field.money and Ui.money(value) or Ui.commaNumber(value)
                end
                drawRows(fields, values, true)
            else
                drawCheatActions(stateForSlot)
            end
        else
            love.graphics.setColor(status == "corrupted" and { 0.95, 0.35, 0.30 }
                or { 0.70, 0.74, 0.69 })
            love.graphics.printf(status == "corrupted"
                and "This save is damaged and has no valid recovery copy."
                or "This slot is empty. Create a shop from the title screen first.",
                164, 312, 632, "center")
        end
    end

    love.graphics.setColor(0.72, 0.76, 0.70)
    love.graphics.printf(OptionsScreen.message, 116, 604, 728, "center")
    love.graphics.setColor(0.47, 0.53, 0.50)
    love.graphics.printf(OptionsScreen.tab=="controls"
        and "Drag sliders for stick sensitivity  |  H: steering mode  |  M: motorcycle controls"
        or OptionsScreen.tab=="cheats"
        and "Tab: section  |  Q/E: cheat category  |  1-3: slot  |  Enter: edit/grant"
        or OptionsScreen.tab=="debug" and OptionsScreen.debugPage=="notes"
        and "Scroll, swipe, or use arrows to browse  |  Home: newest  |  Backspace: diagnostics"
        or OptionsScreen.tab=="debug"
        and "Swipe/wheel or arrows to browse reports  |  Home: newest  |  F10 opens diagnostics on desktop"
        or (OptionsScreen.menuRect() and "Esc: resume  |  F9 / controller Y: main menu  |  Tab: section"
            or "Tab changes section  |  Arrows adjust  |  Enter edits  |  Esc closes"),
        116, 654, 728, "center")
end

function OptionsScreen.openMotorcycleControls()
    OptionsScreen.draggingControl=nil
    OptionsScreen.draggingSensitivity=nil
    OptionsScreen.motorcycleEditor=require('src.commute.controls_screen').new(OptionsScreen.context.settings,
        function() return Settings.save(OptionsScreen.context.settings) end,
        function() OptionsScreen.motorcycleEditor=nil end)
    return true
end
function OptionsScreen.gamepadpressed(joystick,button)
    if button=='y' and OptionsScreen.menuRect() then return OptionsScreen.returnToMenu() end
    if OptionsScreen.motorcycleEditor then return OptionsScreen.motorcycleEditor:gamepadpressed(joystick,button) end
    return false
end
function OptionsScreen.gamepadaxis(joystick,axis,value)
    if OptionsScreen.motorcycleEditor then return OptionsScreen.motorcycleEditor:gamepadaxis(joystick,axis,value) end
    return false
end
function OptionsScreen.wheelmoved(x,y)
    if OptionsScreen.motorcycleEditor then return OptionsScreen.motorcycleEditor:wheelmoved(x,y) end
    if OptionsScreen.tab=="debug" and y~=0 then
        if OptionsScreen.debugPage=="notes" then
            local notes=require("src.screens.update_notes_panel")
            OptionsScreen.debugNotesOffset=math.max(0,math.min(notes.maxOffset(),
                OptionsScreen.debugNotesOffset+(y<0 and 60 or -60)))
            return true
        end
        local panel=require("src.screens.ai_watchdog_panel")
        local maximum=panel.maxOffset(require("src.ai_watchdog").snapshot(OptionsScreen.context.state))
        OptionsScreen.debugOffset=math.max(0,math.min(maximum,
            OptionsScreen.debugOffset+(y<0 and 1 or -1)))
        return true
    end
    return false
end
return OptionsScreen
