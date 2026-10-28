local Feedback = require("src.player_feedback")

local Test = {}

local function makeState(money)
    return {
        screen = "world",
        money = money or 0,
        clientEmails = { inbox = {} },
        workPhone = { incoming = nil },
    }
end

local function makeFeedback(state, world, sounds)
    return Feedback.new({
        state = state,
        world = world,
        playSound = function(name, options)
            sounds[#sounds + 1] = { name = name, options = options }
        end,
    })
end

local function hasNotice(feedback, kind, title)
    for _, notice in ipairs(feedback.notices) do
        if notice.kind == kind and (title == nil or notice.title == title) then
            return true
        end
    end
    return false
end

function Test.run(_, check)
    local world = {
        customer = { state = "waiting" },
        vendor = { state = "waiting" },
    }
    local state, sounds = makeState(500), {}
    local feedback = makeFeedback(state, world, sounds)
    feedback:update(0.016)
    local initialDelta, initialTimer = feedback:cashEffect()
    check("player_feedback_seeds_loaded_balance_without_popup",
        initialDelta == 0 and initialTimer == 0 and #feedback.notices == 0)

    state.money = 750
    feedback:update(0.016)
    local earned, earnedTimer, cashDuration = feedback:cashEffect()
    check("player_feedback_shows_money_received",
        earned == 250 and earnedTimer > 0 and cashDuration >= earnedTimer
            and cashDuration > 1.0)
    state.money = 600
    feedback:update(0.016)
    local spent = feedback:cashEffect()
    check("player_feedback_shows_money_spent", spent == -150)

    local email = {
        id = 17, receivedAtHours = 8, subject = "New estimate",
        unread = true, estimateRequest = true,
    }
    state.clientEmails.inbox[1] = email
    feedback:update(0.016)
    check("player_feedback_announces_new_job_email",
        hasNotice(feedback, "email", "NEW JOB REQUEST"))
    local noticeCount = #feedback.notices
    feedback:update(0.016)
    check("player_feedback_does_not_repeat_same_email",
        #feedback.notices == noticeCount)

    local phoneSounds = #sounds
    state.workPhone.incoming = { id = "call-18", caller = "Mira", direction = "incoming" }
    feedback:update(0.016)
    local cue = sounds[phoneSounds + 1]
    check("player_feedback_announces_incoming_phone_call",
        hasNotice(feedback, "phone", "INCOMING CALL") and cue ~= nil
            and cue.name == "ui_confirm" and cue.options.volume == 0.38
            and cue.options.cooldown == 0.5)
    feedback:update(0.016)
    check("player_feedback_rings_once_per_call", #sounds == phoneSounds + 1)

    local arrivalWorld = {
        customer = { state = "waiting" },
        vendor = { state = "waiting" },
    }
    local arrivalState, arrivalSounds = makeState(40), {}
    local arrivalFeedback = makeFeedback(arrivalState, arrivalWorld, arrivalSounds)
    arrivalFeedback:update(0.016)
    arrivalWorld.customer.state = "entering"
    arrivalFeedback:update(0.016)
    check("player_feedback_announces_customer_arrival",
        hasNotice(arrivalFeedback, "customer", "CUSTOMER ARRIVING"))
    local arrivals = #arrivalFeedback.notices
    arrivalFeedback:update(0.016)
    check("player_feedback_does_not_repeat_ongoing_arrival",
        #arrivalFeedback.notices == arrivals)

    local remoteState, remoteSounds = makeState(500), {}
    local remoteWorld = {
        customer = { state = "waiting" },
        vendor = { state = "waiting" },
    }
    local remoteFeedback = makeFeedback(remoteState, remoteWorld, remoteSounds)
    remoteFeedback:update(0.016)
    -- Each player's feedback tracker consumes their own replica of shared shop state.
    remoteState.money = 750
    remoteState.clientEmails.inbox[1] = email
    remoteState.workPhone.incoming = {
        id = "call-18", caller = "Mira", direction = "incoming",
    }
    remoteWorld.customer.state = "entering"
    remoteFeedback:update(0.016)
    local remoteDelta = remoteFeedback:cashEffect()
    check("player_feedback_responds_to_replicated_shop_updates",
        remoteDelta == 250 and #remoteFeedback.notices == 3
            and remoteSounds[1] and remoteSounds[1].name == "ui_confirm")

    local menuState = makeState(100)
    menuState.screen = "title"
    local menuSounds = {}
    local menuFeedback = makeFeedback(menuState, arrivalWorld, menuSounds)
    menuFeedback:update(0.016)
    menuState.screen, menuState.money = "world", 300
    menuState.clientEmails.inbox[1] = email
    menuState.workPhone.incoming = {
        id = "old-call", caller = "Saved caller", direction = "incoming",
    }
    menuFeedback:update(0.016)
    local menuDelta, menuTimer = menuFeedback:cashEffect()
    check("player_feedback_seeds_when_entering_a_loaded_shop",
        menuDelta == 0 and menuTimer == 0 and #menuFeedback.notices == 0
            and #menuSounds == 0)
end

return Test
