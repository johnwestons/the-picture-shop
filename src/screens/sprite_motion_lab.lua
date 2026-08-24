local Lab = {
    clock = 0,
    selected = 1,
    paused = false,
}

local function animatedFrame(clock, action, count)
    if count <= 1 then return 1 end
    local raw = math.floor(clock * (action == "walk" and 5 or 2.5))
    if action == "walk" and count > 2 then
        local cycle = count * 2 - 2
        local frame = raw % cycle + 1
        return frame <= count and frame or count * 2 - frame
    end
    return raw % count + 1
end

function Lab.enter(characterAssets)
    Lab.clock, Lab.selected, Lab.paused = 0, 1, false
    local names = characterAssets.characterNames()
    if names[1] then characterAssets.retainCharacters({ [names[1]] = true }) end
end

function Lab.update(dt, characterAssets)
    if not Lab.paused then Lab.clock = Lab.clock + math.max(0, dt or 0) end
    local names = characterAssets.characterNames()
    local character = names[Lab.selected]
    if character then characterAssets.retainCharacters({ [character] = true }) end
end

local function drawPose(characterAssets, character, action, frame, x, baseline, scale, normalized)
    local image, quad = characterAssets.get(character, action, frame)
    if not image or not quad then return end
    local anchorX, anchorY = characterAssets.getAnchor(character, action, frame)
    local factor = normalized and characterAssets.getNormalization(character, action) or 1
    local finalScale = scale * factor
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(image, quad, x, baseline, 0, finalScale, finalScale, anchorX, anchorY)

    local left, top, right, bottom = characterAssets.getVisibleBounds(character, action, frame)
    if left then
        love.graphics.setColor(normalized and 0.30 or 0.95, normalized and 0.90 or 0.56, 0.42, 0.9)
        love.graphics.rectangle("line",
            x + (left - anchorX) * finalScale,
            baseline + (top - anchorY) * finalScale,
            (right - left) * finalScale,
            (bottom - top) * finalScale)
    end
end

function Lab.draw(characterAssets)
    local names = characterAssets.characterNames()
    local character = names[Lab.selected]
    if not character then return end
    local actions = characterAssets.actions(character)
    love.graphics.clear(0.025, 0.035, 0.05)
    love.graphics.setColor(0.96, 0.82, 0.26)
    love.graphics.print("SPRITE MOTION / SCALE LAB", 28, 20)
    love.graphics.setColor(0.86, 0.92, 0.93)
    love.graphics.print(string.format("%s  (%d of %d)", character, Lab.selected, #names), 28, 44)
    love.graphics.setColor(0.62, 0.74, 0.77)
    love.graphics.print("Left/Right: character    Space: pause    Esc: close", 28, 64)
    love.graphics.print("Orange boxes show source size. Green boxes show game-normalized size.", 28, 84)

    local columnWidth = 900 / math.max(1, #actions)
    for index, action in ipairs(actions) do
        local _, _, count = characterAssets.get(character, action, 1)
        local frame = animatedFrame(Lab.clock, action, count or 1)
        local x = 30 + (index - 0.5) * columnWidth
        love.graphics.setColor(0.95, 0.96, 0.90)
        love.graphics.printf(action:upper(), x - columnWidth / 2, 108, columnWidth, "center")
        love.graphics.setColor(0.48, 0.58, 0.62)
        love.graphics.line(x - columnWidth * 0.38, 290, x + columnWidth * 0.38, 290)
        love.graphics.line(x - columnWidth * 0.38, 580, x + columnWidth * 0.38, 580)
        drawPose(characterAssets, character, action, frame, x, 290, 0.40, false)
        drawPose(characterAssets, character, action, frame, x, 580, 0.40, true)
        local metrics = characterAssets.normalizedFrameMetrics(character, action, frame)
        love.graphics.setColor(0.55, 0.69, 0.72)
        love.graphics.printf(string.format("frame %d/%d  scale x%.2f",
            frame, count or 1, metrics and metrics.scale or 1),
            x - columnWidth / 2, 594, columnWidth, "center")
    end
    love.graphics.setColor(0.95, 0.56, 0.42)
    love.graphics.print("RAW SOURCE FRAMES", 28, 130)
    love.graphics.setColor(0.30, 0.90, 0.42)
    love.graphics.print("NORMALIZED IN-GAME FRAMES", 28, 410)
    if Lab.paused then
        love.graphics.setColor(1, 0.75, 0.25)
        love.graphics.print("PAUSED", 850, 24)
    end
end

function Lab.keypressed(key, characterAssets)
    local names = characterAssets.characterNames()
    if key == "escape" then love.event.quit(0); return true end
    if key == "space" then Lab.paused = not Lab.paused; return true end
    if key == "left" or key == "up" then
        Lab.selected = (Lab.selected - 2) % #names + 1
    elseif key == "right" or key == "down" then
        Lab.selected = Lab.selected % #names + 1
    else
        return false
    end
    characterAssets.retainCharacters({ [names[Lab.selected]] = true })
    return true
end

return Lab
