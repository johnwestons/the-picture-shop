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
        TitleScreen = { wantsTextInput = function() return wantsTextInput end },
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

    controlsEnabled=true;Runtime.state.screen="title";wantsTextInput=true
    Runtime.syncMobileKeyboard()
    local titleFieldOpensKeyboard=#calls==3 and calls[3]==true
    wantsTextInput=false;Runtime.syncMobileKeyboard()
    local titleFieldClosesKeyboard=#calls==4 and calls[4]==false

    -- Exercise the actual native-key route, not a manual post-action sync.
    local Title=require("src.screens.title_screen")
    local oldMode,oldSetup,oldTown,oldPending=Title.mode,Title.setup,Title.townSetup,Title.pendingAction
    Title.mode,Title.setup,Title.pendingAction="town-setup",{},nil
    Title.townSetup={focus="seed",seedText="0",dirty=true}
    Runtime.TitleScreen=Title
    Runtime.Input=require("src.input")
    Runtime.inputContext={state=Runtime.state,title=Title}
    Runtime.warehouseControls={keypressed=function()return false end}
    Runtime.invalidateMobileKeyboardState();Runtime.syncMobileKeyboard()
    local beforeReturn=#calls
    Runtime.dispatchKeyPressed("return")
    local nativeReturnClosesKeyboard=Title.townSetup.focus==nil and #calls==beforeReturn+1 and calls[#calls]==false
    Title.townSetup.focus="name";Runtime.syncMobileKeyboard()
    local beforeBack=#calls
    Runtime.dispatchKeyPressed("back")
    local nativeBackClosesKeyboard=Title.townSetup.focus==nil and #calls==beforeBack+1 and calls[#calls]==false
    Title.mode,Title.setup,Title.townSetup,Title.pendingAction=oldMode,oldSetup,oldTown,oldPending

    if previousSetTextInput then
        love.keyboard.setTextInput = previousSetTextInput
    else
        love.keyboard.setTextInput = nil
    end

    check("mobile_keyboard_sync_only_changes_text_input_on_focus_transitions",
        stableInputKeepsKeyboardState and transitionHidesKeyboardOnce
        and desktopSyncDoesNotDisableTextEvents)
    check("mobile_keyboard_supports_town_seed_and_preset_fields",titleFieldOpensKeyboard and titleFieldClosesKeyboard)
    check("mobile_keyboard_native_return_closes_town_field",nativeReturnClosesKeyboard)
    check("mobile_keyboard_native_back_closes_town_field",nativeBackClosesKeyboard)
end

return Test
