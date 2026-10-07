local KeyboardMobile = require("src.runtime.keyboard_mobile")

local Test = {}

function Test.run(_, check)
    local previousSetTextInput = love.keyboard.setTextInput
    local calls = {}
    local wantsTextInput = true
    local controlsEnabled = true
    love.keyboard.setTextInput = function(enabled)
        calls[#calls + 1] = enabled
    end

    local Runtime = {
        state = { screen = "lan" },
        mobileControls = { isEnabled = function() return controlsEnabled end },
        LanScreen = { wantsTextInput = function() return wantsTextInput end },
        DirectScreen = { wantsTextInput = function() return false end },
        OptionsScreen = { wantsTextInput = function() return false end },
    }
    KeyboardMobile.install(Runtime)
    Runtime.syncMobileKeyboard()
    Runtime.syncMobileKeyboard()
    Runtime.syncMobileKeyboard()
    local stableInputKeepsKeyboardState = #calls == 1 and calls[1] == true

    wantsTextInput = false
    Runtime.syncMobileKeyboard()
    Runtime.syncMobileKeyboard()
    local transitionHidesKeyboardOnce = #calls == 2 and calls[2] == false

    controlsEnabled = false
    Runtime.invalidateMobileKeyboardState()
    Runtime.syncMobileKeyboard()
    local desktopSyncDoesNotDisableTextEvents = #calls == 2

    if previousSetTextInput then
        love.keyboard.setTextInput = previousSetTextInput
    else
        love.keyboard.setTextInput = nil
    end

    check("mobile_keyboard_sync_only_changes_text_input_on_focus_transitions",
        stableInputKeepsKeyboardState and transitionHidesKeyboardOnce
        and desktopSyncDoesNotDisableTextEvents)
end

return Test
