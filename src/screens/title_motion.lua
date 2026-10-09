-- All time comes from title-screen dt, so focus and quick-tap animations also
-- work with touch/controller input and can be reviewed at deterministic times.
local Motion = { CLICK_DURATION = 0.18 }
local focused, focusTime, clicks = nil, 0, {}

function Motion.reset()
    focused, focusTime, clicks = nil, 0, {}
end

function Motion.focus(id)
    if focused ~= id then focused, focusTime = id, 0 end
end

function Motion.press(id)
    clicks[id] = 0
end

function Motion.update(dt)
    dt = math.max(0, tonumber(dt) or 0)
    focusTime = (focusTime + dt) % 0.9
    for id, age in pairs(clicks) do
        clicks[id] = age + dt < Motion.CLICK_DURATION and age + dt or nil
    end
end

function Motion.state(id, resting, held)
    if resting == "disabled" then return resting end
    local age = clicks[id]
    if age then return age < 0.08 and "click1" or "click2" end
    if held then return "pressed" end
    if id == focused then return focusTime < 0.45 and "focus1" or "focus2" end
    return resting
end

return Motion
