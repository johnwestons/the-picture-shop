local Gear = require('src.commute.gear')
local GearActionArt = require('src.commute.gear_action_art')
local Colorways = require('src.rabbit_colorways')
local Config = require('src.config')
local Anchors = require('src.character_anchors')
local Metrics = require('src.character_metrics')

local Review = {}
local g, art, gear
local normalImage, normalQuad, gearedImage, gearedQuads
local appearance = {character='rabbit-worker', furColorway=4, overallsColorway=5}
local currentAction, currentFrame
local playing = true
local gridCapture = os.getenv('PICTURE_SHOP_GEAR_ACTION_REVIEW_GRID_CAPTURE') == '1'
local capture = gridCapture or os.getenv('PICTURE_SHOP_GEAR_ACTION_REVIEW_CAPTURE') == '1'
local captured = false
local DISPLAY_SCALE = .78
local BASELINE = 606
local GRID_LABEL = 68
local GRID_HEADER = 48
local GRID_PANEL = GRID_LABEL + 4 * 256
local GRID_RIGHT = GRID_PANEL
local GRID_WIDTH = GRID_PANEL * 2
local GRID_HEIGHT = GRID_HEADER + 4 * 256
local GRID_ACTIONS = {'suit_on', 'zip_up', 'boots_gloves', 'helmet_on'}
local gridImageData = {}

local function setColor(r, gValue, b, a)
    g.setColor(r, gValue, b, a or 1)
end

local function printAt(text, x, y, color)
    if color then setColor(color[1], color[2], color[3], color[4]) else setColor(.87, .9, .84) end
    g.print(text, x, y)
end

local function normalArt()
    local metrics = Metrics['rabbit-worker'].idle_southeast[1]
    local anchor = Anchors['rabbit-worker'].idle_southeast[1]
    local height = metrics[4] - metrics[2]
    local scale = DISPLAY_SCALE * Config.characterRendering.referenceHeight / height
    Colorways.draw(normalImage, normalQuad, 675, BASELINE, 0, scale, scale,
        anchor.x, anchor.y, 0, 0, appearance.furColorway, appearance.overallsColorway)
end

local function gearedArt(x, baseline, scale)
    setColor(1, 1, 1)
    g.draw(gearedImage, gearedQuads[1], x, baseline, 0, scale, scale, 128, 232)
end

local function drawFootGuides()
    g.push('all')
    g.setShader()
    setColor(.5, .66, .62, .85)
    g.setLineWidth(1)
    g.line(80, BASELINE, 1195, BASELINE)
    for _, x in ipairs({250, 675, 1060}) do
        g.line(x, BASELINE - 9, x, BASELINE + 10)
        g.circle('line', x, BASELINE, 3)
    end
    g.pop()
end

local function activePose()
    if currentAction then return currentAction, nil end
    local pose, progress = Gear.pose(gear)
    return pose, progress
end

local function drawAction()
    local pose, progress = activePose()
    local action, mappedFrame = GearActionArt.actionFrameForPose(pose, progress or 0, art.registration)
    if action then
        local frame = currentFrame or mappedFrame or 1
        local scale = DISPLAY_SCALE * GearActionArt.normalization(action, art.registration)
        local okay = art:draw(action, frame, 250, BASELINE, scale, appearance)
        if okay then
            printAt(('ACTION / %s / frame %d of 4'):format(pose, frame), 86, 637, {.97, .77, .41})
        else
            printAt('ACTION ART IDENTITY MISMATCH — no rabbit substitute shown', 86, 637, {1, .32, .28})
        end
        if pose == 'boots_gloves' then
            printAt('The staged strip depicts gloves only; boot fastening is absent.', 86, 660, {1, .56, .36})
        end
    elseif pose == 'geared_idle' or pose == 'riding' or pose == 'seated' then
        gearedArt(250, BASELINE, DISPLAY_SCALE)
        printAt('SHARED GEARED IDLE / RAW SCALE', 86, 637, {.74, .85, .81})
    elseif pose == 'normal_idle' then
        normalArt()
        printAt('SELECTED RABBIT IDLE', 86, 637, {.74, .85, .81})
    else
        g.push('all')
        g.setShader()
        setColor(.24, .08, .07, .94)
        g.rectangle('fill', 72, 388, 360, 185, 8, 8)
        printAt(('MISSING ACTION ART / %s'):format(tostring(pose)), 92, 414, {1, .45, .35})
        printAt('No authored strip or safe transition proxy is available.', 92, 450, {.94, .85, .78})
        printAt('The visible suit is held in the previous state.', 92, 474, {.94, .85, .78})
        g.pop()
        printAt(('REMOVAL GAP / %s'):format(tostring(pose)), 86, 637, {1, .32, .28})
    end
    local transition = gear.transition
    if transition then
        local width = 280
        g.push('all');g.setShader()
        setColor(.13, .18, .18, .92);g.rectangle('fill', 85, 692, width, 9, 4, 4)
        setColor(.9, .59, .2);g.rectangle('fill', 85, 692, width * (progress or 0), 9, 4, 4)
        g.pop()
        printAt(('Gear state: %s · %.2fs step'):format(transition.kind, transition.elapsed), 85, 709, {.71, .79, .74})
    else
        printAt(('Gear state: %s'):format(gear.outfit), 85, 709, {.71, .79, .74})
    end
end

local function drawColorwayInfo()
    local fur = Colorways.choice('fur', appearance.furColorway)
    local overall = Colorways.choice('overalls', appearance.overallsColorway)
    printAt(('COLOR MASKS / fur: %s · overalls: %s'):format(fur.name, overall.name), 525, 665, {.9, .91, .84})
    printAt('Green = scoped fur mask   Red = blue-overalls mask   Brown leather and helmet stay shared.',
        525, 688, {.71, .79, .74})
end

local function writeGridChecks(imageData)
    local outputDir = os.getenv('PICTURE_SHOP_GEAR_ACTION_REVIEW_OUTPUT')
    assert(outputDir and outputDir ~= '', 'grid review output path is required')
    outputDir = outputDir:gsub('\\', '/')
    local results = {}
    local function record(name, okay, detail)
        results[#results + 1] = (okay and 'PASS ' or 'FAIL ') .. name .. ' ' .. detail
    end
    local function pixelsEqual(leftX, rightX, y, x)
        local lr, lg, lb, la = imageData:getPixel(leftX + x, y)
        local rr, rg, rb, ra = imageData:getPixel(rightX + x, y)
        local delta = math.max(math.abs(lr - rr), math.abs(lg - rg), math.abs(lb - rb), math.abs(la - ra))
        return delta <= (1 / 255), delta
    end

    assert(imageData:getWidth() == GRID_WIDTH and imageData:getHeight() == GRID_HEIGHT,
        ('pixel grid size mismatch: %dx%d'):format(imageData:getWidth(), imageData:getHeight()))
    for actionRow, action in ipairs(GRID_ACTIONS) do
        local entry = art.actions[action]
        local source, mask = gridImageData[action].source, gridImageData[action].mask
        local sourceOffsetY = GRID_HEADER + (actionRow - 1) * 256
        for frame = 1, entry.frameCount do
            local leftX = GRID_LABEL + (frame - 1) * 256
            local rightX = GRID_RIGHT + GRID_LABEL + (frame - 1) * 256
            local atlasX = (frame - 1) * 256
            local invariantPixels, furPixels, furChanged, overallPixels, overallChanged = 0, 0, 0, 0, 0
            local maxInvariantDelta = 0
            for y = 0, 255 do
                for x = 0, 255 do
                    local _, _, _, alpha = source:getPixel(atlasX + x, y)
                    if alpha > .95 then
                        local mr, mg = mask:getPixel(atlasX + x, y)
                        local equal, delta = pixelsEqual(leftX, rightX, sourceOffsetY + y, x)
                        if mr < .001 and mg < .001 then
                            invariantPixels = invariantPixels + 1
                            if delta > maxInvariantDelta then maxInvariantDelta = delta end
                            if not equal then
                                error(('colorway leaked outside masks: %s frame %d at %d,%d delta %.5f')
                                    :format(action, frame, x, y, delta))
                            end
                        end
                        if mr > .1 then
                            furPixels = furPixels + 1
                            if not equal and delta > .02 then furChanged = furChanged + 1 end
                        end
                        if mg > .1 then
                            overallPixels = overallPixels + 1
                            if not equal and delta > .02 then overallChanged = overallChanged + 1 end
                        end
                    end
                end
            end
            assert(invariantPixels > 1000, action .. ' frame ' .. frame .. ' has too few invariant comparison pixels')
            if furPixels > 0 then
                assert(furChanged > 0, action .. ' frame ' .. frame .. ' fur mask did not respond to the palette')
            end
            if overallPixels > 0 then
                assert(overallChanged > 0, action .. ' frame ' .. frame .. ' overalls mask did not respond to the palette')
            end
            record(action .. ' frame ' .. frame .. ' palette masks', true,
                ('fur %d/%d changed; overalls %d/%d changed; %d unmasked invariant pixels; max delta %.5f')
                    :format(furChanged, furPixels, overallChanged, overallPixels,
                        invariantPixels, maxInvariantDelta))
        end
    end

    local closedHelmetDiffs = {}
    local row = 4
    local y0 = GRID_HEADER + (row - 1) * 256
    for frame = 3, 4 do
        local leftX = GRID_LABEL + (frame - 1) * 256
        local rightX = GRID_RIGHT + GRID_LABEL + (frame - 1) * 256
        local diffPixels = 0
        for y = 0, 255 do
            for x = 0, 255 do
                local equal = pixelsEqual(leftX, rightX, y0 + y, x)
                if not equal then diffPixels = diffPixels + 1 end
            end
        end
        assert(diffPixels == 0, ('closed helmet frame %d differs across colorways at %d pixels')
            :format(frame, diffPixels))
        closedHelmetDiffs[#closedHelmetDiffs + 1] = diffPixels
        record('closed helmet frame ' .. frame .. ' full image equality', true,
            ('0 differing pixels across %d RGBA pixels'):format(256 * 256))
    end

    local samples = {
        {action='suit_on', frame=1, x=160, y=210, label='brown leather sample'},
        {action='helmet_on', frame=2, x=130, y=50, label='olive helmet shell sample'},
    }
    for _, sample in ipairs(samples) do
        local actionRow
        for rowIndex, action in ipairs(GRID_ACTIONS) do
            if action == sample.action then actionRow = rowIndex end
        end
        local source, mask = gridImageData[sample.action].source, gridImageData[sample.action].mask
        local atlasX = (sample.frame - 1) * 256 + sample.x
        local _, _, _, alpha = source:getPixel(atlasX, sample.y)
        local mr, mg = mask:getPixel(atlasX, sample.y)
        assert(alpha > .95 and mr < .001 and mg < .001,
            sample.label .. ' sample must be opaque and outside both masks')
        local leftX = GRID_LABEL + (sample.frame - 1) * 256
        local rightX = GRID_RIGHT + GRID_LABEL + (sample.frame - 1) * 256
        local equal, delta = pixelsEqual(leftX, rightX,
            GRID_HEADER + (actionRow - 1) * 256 + sample.y, sample.x)
        assert(equal, sample.label .. ' changed across palettes')
        record(sample.label .. ' palette invariance', true,
            ('sample (%d,%d), delta %.5f'):format(sample.x, sample.y, delta))
    end

    local resultPath = outputDir .. '/native-colorway-grid-checks.txt'
    local file, err = io.open(resultPath, 'wb')
    assert(file, 'cannot write native colorway pixel checks: ' .. tostring(err))
    for _, line in ipairs(results) do
        file:write(line .. '\n')
        print(line)
    end
    file:close()
    print('PIXEL CHECKS ' .. resultPath)
    return results
end

local function captureScreenshot()
    if not capture or captured then return end
    captured = true
    g.captureScreenshot(function(data)
        local outputDir = os.getenv('PICTURE_SHOP_GEAR_ACTION_REVIEW_OUTPUT')
        if outputDir and outputDir ~= '' then
            outputDir = outputDir:gsub('\\', '/')
        else
            outputDir = love.filesystem.getSource():gsub('\\', '/') .. '/output/commute-gear-actions-review'
        end
        local filename = gridCapture and '/native-colorway-grid.png' or '/native-review.png'
        local path = outputDir .. filename
        local file, err = io.open(path, 'wb')
        assert(file, 'cannot write native review screenshot: ' .. tostring(err))
        file:write(data:encode('png'):getString())
        file:close()
        print('CAPTURE ' .. path)
        if gridCapture then writeGridChecks(data) end
        io.flush()
        love.event.quit(0)
    end)
end

function Review.install()
    function love.load()
        love.window.setMode(gridCapture and GRID_WIDTH or 1280,
            gridCapture and GRID_HEIGHT or 880, {resizable=false, vsync=0})
        love.window.setTitle('The Picture Shop - Motorcycle gear action art review')
        g = love.graphics
        art = GearActionArt.new({review=true,
            registration=require('assets.staging.commute-gear-actions-v1.registration')})
        normalImage = g.newImage(Config.characters['rabbit-worker'].idle_southeast)
        normalImage:setFilter('linear', 'linear')
        normalQuad = g.newQuad(0, 0, 512, 512, normalImage:getWidth(), normalImage:getHeight())
        gearedImage = g.newImage('assets/staging/commute-rider-v1/idle_southeast.png')
        gearedImage:setFilter('linear', 'linear')
        gearedQuads = {
            g.newQuad(0, 0, 256, 256, gearedImage:getWidth(), gearedImage:getHeight()),
            g.newQuad(256, 0, 256, 256, gearedImage:getWidth(), gearedImage:getHeight()),
        }
        gear = Gear.new()
        assert(Gear.begin(gear, 'equip', {nearBike=true}))
        require('src.commute.tests.gear_action_art_test').run(function(name, okay, reason)
            print((okay and 'PASS ' or 'FAIL ') .. name .. (reason and ' ' .. tostring(reason) or ''))
            if not okay then error(name .. ': ' .. tostring(reason)) end
        end)
        if gridCapture then
            for _, name in ipairs(GRID_ACTIONS) do
                local entry = art.actions[name]
                gridImageData[name] = {
                    source=love.image.newImageData(entry.path),
                    mask=love.image.newImageData(entry.maskPath),
                }
            end
        end
        print('GEAR ACTION ART REVIEW READY')
    end

    function love.update(dt)
        if not capture and playing and gear and gear.transition then Gear.update(gear, math.min(dt, .1)) end
    end

    function love.draw()
        if gridCapture then
            g.clear(.29, .37, .41, 1)
            g.push('all');g.setShader()
            setColor(.98, .79, .39)
            g.print('GINGER FUR / BLUE OVERALLS', GRID_LABEL, 12)
            g.print('SILVER FUR / GOLD OVERALLS', GRID_RIGHT + GRID_LABEL, 12)
            g.print('Rows: suit, zip, gloves, helmet; columns: frames 1-4', 12, 28)
            local shortNames = {'SUIT', 'ZIP', 'GLOVE', 'HELMET'}
            local variants = {
                {character='rabbit-worker', furColorway=1, overallsColorway=1},
                {character='rabbit-worker', furColorway=4, overallsColorway=5},
            }
            for row, action in ipairs(GRID_ACTIONS) do
                local cellY = GRID_HEADER + (row - 1) * 256
                setColor(.86, .9, .84)
                g.printf(shortNames[row], 0, cellY + 6, GRID_LABEL - 3, 'center')
                for _, panelX in ipairs({0, GRID_RIGHT}) do
                    local variant = panelX == 0 and variants[1] or variants[2]
                    for frame = 1, 4 do
                        local cellX = panelX + GRID_LABEL + (frame - 1) * 256
                        setColor(.48, .62, .65, .75)
                        g.line(cellX, cellY + 238, cellX + 256, cellY + 238)
                        g.line(cellX + 128, cellY + 230, cellX + 128, cellY + 246)
                        local okay, reason = art:draw(action, frame, cellX + 128,
                            cellY + 238, 1, variant)
                        assert(okay, action .. ' frame ' .. frame .. ': ' .. tostring(reason))
                    end
                end
            end
            g.pop()
            captureScreenshot()
            return
        end
        g.clear(.075, .095, .092, 1)
        g.push('all');g.setShader()
        setColor(.12, .16, .15, .97);g.rectangle('fill', 32, 28, 1216, 100, 10, 10)
        printAt('MOTORCYCLE GEAR / NATIVE ACTION REVIEW', 55, 45, {.98, .79, .39})
        printAt('Real Gear.pose timing · planted contact line · selected rabbit appearance', 55, 72, {.82, .86, .8})
        printAt('Enter: restart equip   R: begin removal   Space: pause   Left/Right: frame   1-4: action',
            55, 98, {.71, .79, .74})
        g.pop()

        drawFootGuides()
        drawAction()
        normalArt()
        gearedArt(1060, BASELINE, DISPLAY_SCALE)

        g.push('all');g.setShader()
        setColor(.12, .16, .15, .97);g.rectangle('fill', 470, 385, 410, 195, 8, 8)
        setColor(.12, .16, .15, .97);g.rectangle('fill', 895, 385, 323, 195, 8, 8)
        g.pop()
        normalArt()
        gearedArt(1060, BASELINE, DISPLAY_SCALE)
        drawColorwayInfo()

        printAt('ACTION / 214-219px visible height after normalization', 86, 735, {.9, .91, .84})
        local normalHeight = Metrics['rabbit-worker'].idle_southeast[1][4]
            - Metrics['rabbit-worker'].idle_southeast[1][2]
        printAt(('NORMAL / %.0fpx source -> %dpx reference'):format(normalHeight,
            Config.characterRendering.referenceHeight), 525, 735, {.9, .91, .84})
        printAt('GEARED / raw 198px = 77%', 895, 735, {.9, .91, .84})
        printAt('Compare shoulder, hip and boot fit; bare ears and a closed helmet change total height.',
            86, 763, {.71, .79, .74})

        g.push('all');g.setShader()
        setColor(.12, .16, .15, .97);g.rectangle('fill', 32, 800, 1216, 47, 8, 8)
        printAt('Southeast rabbit poses · removal reverses matching strips · other species keep their own appearance',
            55, 815, {.71, .79, .74})
        g.pop()
        captureScreenshot()
    end

    function love.keypressed(key)
        if key == 'escape' then love.event.quit()
        elseif key == 'space' then playing = not playing
        elseif key == 'f' then appearance.furColorway = appearance.furColorway % #Colorways.fur + 1
        elseif key == 'o' then appearance.overallsColorway = appearance.overallsColorway % #Colorways.overalls + 1
        elseif key == 'return' or key == 'kpenter' then
            currentAction, currentFrame = nil, nil
            if gear.outfit == 'normal' and not gear.transition then
                Gear.begin(gear, 'equip', {nearBike=true})
            elseif gear.outfit == 'geared' and not gear.mounted and not gear.transition then
                Gear.begin(gear, 'remove', {})
            end
        elseif key == 'r' then
            currentAction, currentFrame = nil, nil
            if gear.outfit == 'geared' and not gear.mounted and not gear.transition then Gear.begin(gear, 'remove', {}) end
        elseif key == '1' or key == '2' or key == '3' or key == '4' then
            currentAction = ({'suit_on', 'zip_up', 'boots_gloves', 'helmet_on'})[tonumber(key)]
            currentFrame = 1
        elseif key == 'left' or key == 'right' then
            local pose = currentAction or Gear.pose(gear)
            if art:has(pose) then
                currentAction = pose
                local count = art.actions[pose].frameCount
                currentFrame = ((currentFrame or GearActionArt.frameForProgress(pose, select(2, Gear.pose(gear)) or 0) or 1)
                    + (key == 'right' and 1 or -1) - 1) % count + 1
            end
        elseif key == 'up' or key == 'down' then
            local actions = {'suit_on', 'zip_up', 'boots_gloves', 'helmet_on'}
            local current = 1
            for i, name in ipairs(actions) do if name == currentAction then current = i end end
            current = (current - 1 + (key == 'down' and 1 or -1)) % #actions + 1
            currentAction, currentFrame = actions[current], 1
        elseif key == 'c' then
            currentAction, currentFrame = nil, nil
        end
    end

    function love.quit()
        if art then art:release() end
        if normalImage then normalImage:release() end
        if normalQuad then normalQuad:release() end
        if gearedImage then gearedImage:release() end
        for _, quad in ipairs(gearedQuads or {}) do quad:release() end
    end
end

return Review
