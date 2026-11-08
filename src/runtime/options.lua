-- Options access and settings application.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    local function applySettings(nextSettings)
        Runtime.App.settings = Runtime.App.settings or {}
        local current = Runtime.App.settings
        for key in pairs(current) do current[key] = nil end
        for key, value in pairs(nextSettings) do current[key] = value end
        return current
    end

    function Runtime.closeOptions()
        local returnScreen = Runtime.state.optionsReturnScreen or "title"
        Runtime.state.optionsReturnScreen = nil
        Runtime.state.screen = returnScreen
        if Runtime.syncMobileKeyboard then Runtime.syncMobileKeyboard() end
        return true
    end

    Runtime.openOptions = function()
        require('src.commute.runtime').cancelCameraDrag(Runtime)
        if Runtime.state.screen == "asset_error" or Runtime.spriteLabActive then return false end
        if Runtime.state.screen == "options" then return Runtime.OptionsScreen.leave() end
        -- A submenu may consume touch releases. Clear gameplay touches now so
        -- returning from the controls editor cannot resume a held movement axis.
        if Runtime.mobileControls then Runtime.mobileControls:cancelAll() end
        local returnScreen = Runtime.state.screen
        local liveShop = Runtime.state.activeSlot ~= nil
            and (returnScreen ~= "title" and returnScreen ~= "lan" and returnScreen ~= "direct"
                or Runtime.multiplayer:isHost())
        local inGame=returnScreen~='title' and returnScreen~='lan' and returnScreen~='direct'
            and (Runtime.state.activeSlot~=nil or Runtime.multiplayer:isClient())
        Runtime.state.optionsReturnScreen = returnScreen
        Runtime.OptionsScreen.enter({
            settings = Runtime.App.settings or Runtime.Settings.normalize(),
            sound = Runtime.App.sound,
            save = Runtime.Save,
            state = Runtime.state,
            saveCurrent = Runtime.saveCurrent,
            isNetworkClient = function() return Runtime.multiplayer:isClient() end,
            useActiveState = liveShop,
            canReturnToMenu = inGame or Runtime.multiplayer:isHost() or Runtime.multiplayer:isClient(),
            onReturnToMenu = Runtime.returnToTitle,
            preferredSlot = returnScreen == "title" and (Runtime.TitleScreen.selected or 1)
                or Runtime.state.activeSlot or Runtime.TitleScreen.selected or 1,
            getControlLayout = function(view)
                return Runtime.Settings.controlLayoutFor(Runtime.App.settings, view)
            end,
            setControlLayout = function(layout, view, key)
                applySettings(Runtime.Settings.setControlLayout(
                    Runtime.App.settings, view, layout, key))
                if Runtime.mobileControls then
                    local activeView = view == "shared" and "shared" or view
                    Runtime.mobileControls:setLayout(
                        Runtime.Settings.controlLayoutFor(Runtime.App.settings, activeView))
                end
            end,
            commitControlLayout = function()
                Runtime.Settings.save(Runtime.App.settings)
            end,
            resetControlLayout = function(view)
                applySettings(Runtime.Settings.resetControlLayout(Runtime.App.settings, view))
                if Runtime.mobileControls then
                    Runtime.mobileControls:setLayout(Runtime.Settings.controlLayoutFor(
                        Runtime.App.settings, view or "shared"))
                end
                Runtime.Settings.save(Runtime.App.settings)
            end,
            getDebugInfo = function()
                local state=Runtime.state
                local player=Runtime.World and Runtime.World.player or {}
                local gameHours
                if Runtime.BusinessCalendar and Runtime.BusinessCalendar.absoluteHours then
                    local okay,value=pcall(Runtime.BusinessCalendar.absoluteHours,state)
                    if okay then gameHours=tonumber(value) end
                end
                local multiplayer={}
                if Runtime.multiplayer and Runtime.multiplayer.debugInfo then
                    local okay,value=pcall(Runtime.multiplayer.debugInfo,Runtime.multiplayer)
                    if okay and type(value)=='table' then multiplayer=value end
                end
                local assetPack
                if Runtime.Assets and Runtime.Assets.activePackName then
                    local okay,value=pcall(Runtime.Assets.activePackName)
                    if okay then assetPack=value end
                end
                return {
                    screen=state.optionsReturnScreen or state.screen,
                    scene=player.sceneId,
                    activeSlot=state.activeSlot,
                    player={x=player.x,y=player.y},
                    gameHours=gameHours,
                    assetPack=assetPack,
                    multiplayer=multiplayer,
                    sessionSeconds=multiplayer.connectedForSeconds,
                }
            end,
            applyPlayerColorways = Runtime.App.syncPlayerColorways,
            onClose = Runtime.closeOptions,
        })
        Runtime.state.screen = "options"
        if Runtime.syncMobileKeyboard then Runtime.syncMobileKeyboard() end
        return true
    end
end

return Component
