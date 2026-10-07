-- Options access and settings application.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.closeOptions()
        local returnScreen = Runtime.state.optionsReturnScreen or "title"
        Runtime.state.optionsReturnScreen = nil
        Runtime.state.screen = returnScreen
        if Runtime.syncMobileKeyboard then Runtime.syncMobileKeyboard() end
        return true
    end

    Runtime.openOptions = function()
        if Runtime.state.screen == "asset_error" or Runtime.spriteLabActive then return false end
        if Runtime.state.screen == "options" then return Runtime.OptionsScreen.leave() end
        local returnScreen = Runtime.state.screen
        local liveShop = Runtime.state.activeSlot ~= nil
            and (returnScreen ~= "title" and returnScreen ~= "lan" and returnScreen ~= "direct"
                or Runtime.multiplayer:isHost())
        Runtime.state.optionsReturnScreen = returnScreen
        Runtime.OptionsScreen.enter({
            settings = Runtime.App.settings or Runtime.Settings.normalize(),
            sound = Runtime.App.sound,
            save = Runtime.Save,
            state = Runtime.state,
            saveCurrent = Runtime.saveCurrent,
            isNetworkClient = function() return Runtime.multiplayer:isClient() end,
            useActiveState = liveShop,
            preferredSlot = returnScreen == "title" and (Runtime.TitleScreen.selected or 1)
                or Runtime.state.activeSlot or Runtime.TitleScreen.selected or 1,
            getControlLayout = function()
                return Runtime.mobileControls and Runtime.mobileControls:layout()
                    or Runtime.App.settings.controlLayout
            end,
            setControlLayout = function(layout)
                Runtime.App.settings.controlLayout = Runtime.mobileControls and Runtime.mobileControls:setLayout(layout)
                    or Runtime.Settings.normalizeControlLayout(layout)
            end,
            commitControlLayout = function()
                Runtime.Settings.save(Runtime.App.settings)
            end,
            resetControlLayout = function()
                local layout = Runtime.MobileControls.defaultLayout()
                Runtime.App.settings.controlLayout = Runtime.mobileControls and Runtime.mobileControls:setLayout(layout)
                    or layout
                Runtime.Settings.save(Runtime.App.settings)
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
