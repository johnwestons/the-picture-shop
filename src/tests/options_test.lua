local Test = {}
local MobileControls = require("src.mobile_controls")
local OptionsScreen = require("src.screens.options_screen")

function Test.run(context, check)
    local normalized = context.Settings.normalize({
        fullscreen = true,
        vsync = false,
        muted = true,
        masterVolume = 130,
        sfxVolume = -4,
        ambientVolume = 49.6,
    })
    check("options_settings_normalize_and_bound_values",
        normalized.fullscreen and not normalized.vsync and normalized.muted
        and normalized.masterVolume == 100 and normalized.sfxVolume == 0
        and normalized.ambientVolume == 50)

    local positioned = MobileControls.new({
        enabled = false,
        layout = { joystick = { x = 0.3, y = 0.4 }, primary = { x = 0.7, y = 0.8 } },
        toGame = function(x, y) return x, y end,
        pressKey = function() end,
        releaseKey = function() end,
        pressPointer = function() end,
        movePointer = function() end,
        releasePointer = function() end,
        gameplayActive = function() return false end,
    })
    positioned:setBounds({ left = 0, top = 0, right = 1000, bottom = 700,
        width = 1000, height = 700 })
    check("options_touch_layout_positions_real_controls",
        positioned.joystick.x == 300 and positioned.joystick.y == 280
        and positioned.primary.x == 700 and positioned.primary.y == 560)
    local clamped = positioned:setLayout({
        joystick = { x = -1, y = 2 }, primary = { x = 2, y = -1 },
    })
    check("options_touch_layout_stays_inside_safe_screen_bounds",
        clamped.joystick.x == 0.05 and clamped.joystick.y == 0.92
        and positioned.joystick.x >= positioned.joystick.radius
        and positioned.joystick.y <= 700 - positioned.joystick.radius)

    local previewLayout = MobileControls.defaultLayout()
    local layoutCommits = 0
    OptionsScreen.enter({
        settings = normalized,
        save = { SLOT_COUNT = 3, load = function() return nil, "empty" end },
        state = {},
        getControlLayout = function() return previewLayout end,
        setControlLayout = function(layout) previewLayout = layout end,
        commitControlLayout = function() layoutCommits = layoutCommits + 1 end,
    })
    OptionsScreen.mousepressed(576, 114, 1)
    OptionsScreen.mousepressed(263, 472, 1)
    OptionsScreen.mousemoved(410, 350)
    OptionsScreen.mousereleased(410, 350, 1)
    check("options_controls_preview_drags_and_commits_layout",
        OptionsScreen.isControlsTab() and layoutCommits == 1
        and math.abs(previewLayout.joystick.x - ((410 - 205) / 550)) < 0.001
        and math.abs(previewLayout.joystick.y - ((350 - 176) / 350)) < 0.001)

    local state = context.State.new()
    state.activeSlot = 1
    local saveCalls = 0
    local editorContext = {
        save = context.save,
        state = state,
        useActiveState = true,
        saveCurrent = function() saveCalls = saveCalls + 1; return true end,
        isNetworkClient = function() return false end,
    }
    local edited, value = context.SaveEditor.editSlot(editorContext, 1, "money", 123456)
    check("options_cheats_edit_live_cash_and_save_immediately",
        edited and value == 123456 and state.money == 123456 and saveCalls == 1)

    editorContext.saveCurrent = function() return false end
    local rolledBack = not context.SaveEditor.editSlot(editorContext, 1, "paper", 999)
    check("options_cheats_roll_back_failed_live_save",
        rolledBack and state.inventory.paper == 40)

    editorContext.isNetworkClient = function() return true end
    local guestBlocked, guestMessage = context.SaveEditor.editSlot(
        editorContext, 1, "money", 999999)
    check("options_cheats_are_host_only_in_multiplayer",
        not guestBlocked and guestMessage:find("Only the host", 1, true) ~= nil
        and state.money == 123456)

    local fakeState = context.State.new()
    local writtenState, writtenPlayer
    local fakeSave = {
        SLOT_COUNT = 3,
        load = function(slot)
            if slot ~= 2 then return nil, "empty" end
            return { state = fakeState, player = { x = 12, y = 34 } }, "ok"
        end,
        save = function(slot, savedState, player)
            writtenState, writtenPlayer = savedState, player
            return slot == 2
        end,
    }
    local offlineEdited, offlineValue = context.SaveEditor.editSlot({
        save = fakeSave,
        state = state,
        useActiveState = false,
        isNetworkClient = function() return false end,
    }, 2, "shipping_cartons", 275)
    check("options_cheats_edit_offline_slot_and_preserve_player_snapshot",
        offlineEdited and offlineValue == 275
        and writtenState.inventory.stock.shipping_cartons == 275
        and writtenPlayer.x == 12 and writtenPlayer.y == 34)

    local bounded, boundedValue = context.SaveEditor.setValue(fakeState, "money", -500)
    check("options_cheat_values_are_nonnegative_and_schema_safe",
        bounded and boundedValue == 0 and fakeState.money == 0)
end

return Test
