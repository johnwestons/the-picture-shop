local Motion = require("src.screens.title_motion")
local Test = {}

function Test.run(context, check)
    local title = context.title or require("src.screens.title_screen")
    local phrases = { "Hello Trevor, welcome back to work.", "Happy Printing", "Have a Great Day",
        "Be a Nice Critter", "Sponsored by The CritterNet" }
    title.enter(nil)
    for index, phrase in ipairs(phrases) do
        check("title_rotating_message_" .. index, title.displayText() == phrase)
        title.update(5)
    end
    check("title_message_cycle_wraps", title.displayText() == phrases[1])
    title.update(12)
    check("title_large_dt_advances_multiple_messages", title.displayText() == phrases[3])
    title.setDisplayMessage("CUSTOM NOTICE")
    title.update(10)
    check("title_programmed_override_pauses_cycle", title.displayText() == "CUSTOM NOTICE")
    title.setDisplayMessage(nil)
    check("title_cycle_resumes_after_override", title.displayText() == phrases[3])
    title.message = "Save feedback"
    title.update(1)
    check("title_save_feedback_has_priority", title.displayText() == "Save feedback")
    title.update(2)
    check("title_feedback_expires_back_to_cycle", title.message == "" and title.displayText() == phrases[3])
    check("title_feedback_pauses_cycle_clock", title.cycleTime == 12)
    title.message = "Another notice"
    title.update(4)
    check("title_expired_feedback_keeps_only_unused_time", title.message == "" and title.cycleTime == 13)
    title.mode, title.message = "delete-confirm", "Confirm deletion"
    title.update(10)
    check("title_confirmation_notice_stays_visible", title.displayText() == "Confirm deletion")

    title.enter(nil, function() end)
    title.setHover(0, 0)
    title.keypressed("tab")
    title.setHover(0, 0)
    check("title_stationary_pointer_preserves_keyboard_focus", title.keyboardFocus == "slot-2")
    local x, y = title.buttonCenter("new")
    title.setHover(x, y)
    check("title_pointer_motion_takes_focus", title.keyboardFocus == nil
        and Motion.state("new", "normal") == "focus1")
    title.update(0.46)
    check("title_focus_reaches_second_open_frame", Motion.state("new", "normal") == "focus2")
    title.update(0.45)
    check("title_focus_animation_loops", Motion.state("new", "normal") == "focus1")
    title.setHover(0, 0)
    check("title_focus_closes_on_pointer_exit", Motion.state("new", "normal") == "normal")

    local opened = 0
    title.enter(nil, function() opened = opened + 1 end)
    x, y = title.buttonCenter("localPlay")
    title.mousepressed(x, y, 1)
    title.mousereleased(x, y, 1)
    check("title_quick_tap_keeps_click_frame", opened == 0
        and Motion.state("localPlay", "normal") == "click1")
    title.mousepressed(x, y, 1)
    title.update(0.08)
    check("title_click_reaches_rebound_before_action", opened == 0
        and Motion.state("localPlay", "normal") == "click2")
    title.update(0.11)
    title.update(1)
    check("title_click_runs_action_once_after_animation", opened == 1 and title.pendingAction == nil)

    title.enter(nil, function() opened = opened + 1 end)
    title.keypressed("l")
    title.enter(nil)
    title.update(1)
    check("title_reentry_cancels_stale_action", opened == 1)
    check("title_disabled_button_does_not_animate", Motion.state("localPlay", "disabled", true) == "disabled")

    title.enter(nil, function() opened = opened + 1 end)
    title.setHover(0, 0)
    local controller = require("src.controller").new({
        pressKey = title.keypressed, releaseKey = function() end,
        pressPointer = title.mousepressed, releasePointer = title.mousereleased,
        screenInfo = function() return "title", nil, title.keyboardFocus ~= nil end,
        menuAction = function() end, pointerX = 0, pointerY = 0,
    })
    local pad = { isGamepad = function() return true end }
    controller:gamepadpressed(pad, "dpleft")
    controller:gamepadreleased(pad, "dpleft")
    title.setHover(0, 0)
    check("title_controller_dpad_focuses_toolbox", title.keyboardFocus == "localPlay"
        and Motion.state("localPlay", "normal") == "focus1")
    controller:gamepadpressed(pad, "a")
    controller:gamepadreleased(pad, "a")
    check("title_controller_a_animates_focused_toolbox", opened == 1
        and Motion.state("localPlay", "normal") == "click1")
    title.update(0.2)
    check("title_controller_a_runs_focused_action", opened == 2)

    title.enter(nil, function() opened = opened + 1 end)
    x, y = title.buttonCenter("localPlay")
    controller.pointerX, controller.pointerY = x, y
    title.setHover(x, y)
    controller:gamepadpressed(pad, "a")
    controller:gamepadreleased(pad, "a")
    title.update(0.2)
    check("title_controller_cursor_still_activates_button", opened == 3)

    context.assets.activatePack("menu")
    local names = { "titleMenuPalletAnimation", "titleMenuInkAnimation", "titleMenuToolboxAnimation",
        "titleMenuPalletFocus", "titleMenuInkFocus", "titleMenuToolboxFocus" }
    local loaded = true
    for _, name in ipairs(names) do loaded = loaded and context.assets.get(name) ~= nil end
    check("title_animation_textures_load_with_menu", loaded)
    context.assets.activatePack("cutter")
    local released = true
    for _, name in ipairs(names) do released = released and context.assets.get(name) == nil end
    check("title_animation_textures_release_after_menu", released)
    context.assets.activatePack("menu")
    title.enter(nil)
end

return Test
