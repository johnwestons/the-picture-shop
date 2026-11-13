-- In-engine cutscene editor. It uses the real town, road, rider and renderer
-- modules, but never loads a shop save or advances gameplay state.
local Scene = require('src.cutscene')
local Town = require('src.commute.town')
local Arrival = require('src.story_arrival')
local Routes = require('src.commute.routes')
local Rider = require('src.commute.rider')
local Bike = require('src.commute.motorcycle')
local Camera = require('src.commute.camera')
local Renderer = require('src.commute.renderer')
local Animation = require('src.commute.riding_animation')
local CharacterAssets = require('src.character_assets')
local Audio = require('src.commute.audio')
local Gif = require('tools.cutscene_lab.gif_writer')

local Studio = {}
-- The lab is launched with its project directory as the working directory.
-- getSourceBaseDirectory points to the parent when LOVE is passed `.` on Windows.
local root = love.filesystem.getWorkingDirectory()
local sourceDirectory = 'assets/source/cutscene-studio'
local sourceFolder = root .. '/assets/source/cutscene-studio/'
local gameFolder = root .. '/assets/generated/cutscenes/'
local recordingFolder = root .. '/output/cutscene-studio/recordings/'
local FPS, FRAME_STEP = 25, 1 / 25
local viewportWidth, viewportHeight = 1050, 730
local windowWidth, windowHeight = 1440, 900
local projects, projectIndex = {}, 1
local project, routePlan, world, rider, actor, camera, renderer, audio
local elapsed, cursor, playing, looping = 0, 0, false, false
local buttons, status = {}, 'Ready to edit. This preview uses a generated town and never opens a shop save.'
local panelScroll, panelContentHeight, sidebarOffset = 0, 760, 0
local selection, textEntry
local actionChoice, cameraChoice, dialogueSpeaker = 1, 1, 'Player'
local recording, recorder, recordingPath, captureDue, captureWaiting = false, nil, nil, false, false
local captureAccumulator, captureCount, captureTarget = 0, 0, 0
local speedDistance, speedDistanceTotal = {}, 0
local soundsMuted = false
local fonts = {}
local actorAssist, actorAssistElapsed, actorAssistAccumulator, actorAssistTicks = false, 0, 0, 0
local cameraPass, cameraReview, cameraDraft, cameraPassOriginal = false, false, nil, nil
local cameraPassNextSample, cameraDrag = 0, nil
local takeFrames = {}
local TAKE_FPS, TAKE_STEP, PHYSICS_STEP = 30, 1 / 30, 1 / 60
local CAMERA_CAPTURE_STEP = .2
local updateViewport, startRecording, sampleProject
local actions = { 'boost', 'shift', 'brake', 'jump', 'turn', 'tuck' }
local presets = {
    { label = 'Low rear chase', yaw = 0, tilt = 31, zoom = 1.05 },
    { label = 'Bridge side glide', yaw = 82, tilt = 47, zoom = .82 },
    { label = 'Front wheel rush', yaw = 164, tilt = 34, zoom = 1.24 },
    { label = 'Overhead hairpin', yaw = 42, tilt = 81, zoom = .7 },
    { label = 'Low lean chase', yaw = -21, tilt = 28, zoom = 1.12 },
    { label = 'Wide farm reveal', yaw = 18, tilt = 59, zoom = .68 },
}

local function clamp(value, low, high) return math.max(low, math.min(high, value)) end
local function ease(value) value = clamp(value, 0, 1); return value * value * (3 - 2 * value) end
local function cleanText(value, limit)
    return (tostring(value or ''):gsub('[%c]+', ' '):gsub('%s+', ' '):match('^%s*(.-)%s*$') or ''):sub(1, limit)
end
local function sortCues(cues)
    table.sort(cues, function(a, b) return a.time == b.time and tostring(a.label or a.action or a.text) < tostring(b.label or b.action or b.text) or a.time < b.time end)
end
local function luaString(value) return string.format('%q', value) end
local function serialize(value, depth)
    depth = depth or 0
    if depth > 16 then error('Cutscene data is nested too deeply.') end
    local kind = type(value)
    if kind == 'nil' then return 'nil' end
    if kind == 'boolean' then return tostring(value) end
    if kind == 'number' then
        assert(value == value and value ~= math.huge and value ~= -math.huge, 'Cutscene numbers must be finite.')
        local text = string.format('%.6f', value):gsub('0+$', ''):gsub('%.$', '')
        if text == '-0' or text == '' then return '0' end
        return text
    end
    if kind == 'string' then return luaString(value) end
    if kind ~= 'table' then error('Cutscene files can contain only plain data.') end
    local count, maximum, isArray = 0, 0, true
    for key in pairs(value) do
        count = count + 1
        if type(key) ~= 'number' or key % 1 ~= 0 or key < 1 then isArray = false
        else maximum = math.max(maximum, key) end
    end
    isArray = isArray and maximum == count
    local pieces = { '{' }
    if isArray then
        for index = 1, count do pieces[#pieces + 1] = serialize(value[index], depth + 1) .. ',' end
    else
        local keys = {}
        for key in pairs(value) do assert(type(key) == 'string', 'Cutscene map keys must be strings.'); keys[#keys + 1] = key end
        table.sort(keys)
        for _, key in ipairs(keys) do
            pieces[#pieces + 1] = '[' .. luaString(key) .. ']=' .. serialize(value[key], depth + 1) .. ','
        end
    end
    pieces[#pieces + 1] = '}'
    return table.concat(pieces)
end
local function encodeProject(value)
    return '-- Authored in The Picture Shop Cutscene Studio.\nreturn ' .. serialize(value) .. '\n'
end
local function writeFile(path, value)
    local file, reason = io.open(path, 'wb')
    if not file then return false, tostring(reason) end
    local okay, issue = file:write(value)
    local closed, closeIssue = file:close()
    if not okay then return false, tostring(issue) end
    if not closed then return false, tostring(closeIssue) end
    return true
end
local function validateAndSort(value)
    for _, key in ipairs({ 'camera', 'actions', 'dialogue', 'speed' }) do sortCues(value[key]) end
    return Scene.validate(value)
end
local function loadProject(file)
    local filename = sourceDirectory .. '/' .. file
    local chunk, reason = love.filesystem.load(filename)
    if not chunk then return nil, tostring(reason) end
    local okay, value = pcall(chunk)
    if not okay then return nil, tostring(value) end
    local valid, issue = validateAndSort(value)
    if not valid then return nil, issue end
    return value
end
local function findProjects()
    projects = {}
    for _, file in ipairs(love.filesystem.getDirectoryItems(sourceDirectory)) do
        if file:match('^[%w_%-]+%.lua$') then
            local value = loadProject(file)
            if value then projects[#projects + 1] = file:gsub('%.lua$', '') end
        end
    end
    table.sort(projects)
    if #projects == 0 then projects[1] = 'high-octane-return' end
end
local function saveProject(publish)
    if actorAssist or cameraPass or cameraReview then
        status = 'Finish the take or keep/discard the camera pass before saving.'
        return false
    end
    local valid, reason = validateAndSort(project)
    if not valid then status = reason; return false end
    local folder = publish and gameFolder or sourceFolder
    local okay, issue = writeFile(folder .. project.id .. '.lua', encodeProject(project))
    if not okay then status = 'Could not save cutscene: ' .. issue; return false end
    if not publish then
        local found = false
        for _, id in ipairs(projects) do if id == project.id then found = true end end
        if not found then
            projects[#projects + 1] = project.id
            table.sort(projects)
        end
        for index, id in ipairs(projects) do if id == project.id then projectIndex = index; break end end
        status = 'Composition saved to assets/source/cutscene-studio/' .. project.id .. '.lua.'
    else
        local imported, loadIssue = Scene.load(project.id)
        if not imported then
            status = 'Saved, but the game loader rejected the import: ' .. tostring(loadIssue)
            return false
        end
        project = imported
        status = 'Imported into the game at assets/generated/cutscenes/' .. project.id .. '.lua.'
    end
    return true
end
local function buildMotionTable()
    speedDistance = {}
    local total, previous = 0, Scene.speedAt(project, 0) / 2.236936
    speedDistance[1] = { time = 0, distance = 0 }
    local time = FRAME_STEP
    while time <= project.duration + 1e-6 do
        local speed = Scene.speedAt(project, time) / 2.236936
        total = total + (previous + speed) * .5 * FRAME_STEP
        speedDistance[#speedDistance + 1] = { time = time, distance = total }
        previous = speed
        time = time + FRAME_STEP
    end
    speedDistanceTotal = math.max(.001, total)
end
local function motionDistance(time)
    local items = speedDistance
    if #items == 0 then return 0 end
    if time <= 0 then return 0 end
    local index = math.min(#items, math.floor(time / FRAME_STEP) + 1)
    local a = items[index]
    local b = items[math.min(#items, index + 1)]
    local fraction = b.time > a.time and clamp((time - a.time) / (b.time - a.time), 0, 1) or 0
    return (a.distance + (b.distance - a.distance) * fraction) / speedDistanceTotal * routePlan.length
end
local function routeExtras()
    local farm = world and world.sites and world.sites.byId.farm
    if not farm then return {} end
    for _, path in ipairs(world.roads.paths or {}) do
        if path.id == 'farm-drive' and path.points[#path.points] then
            return { story_farm = path.points[#path.points] }
        end
    end
    return {}
end
local function findRoute()
    if project.route.from == 'mainland_exit' and project.route.to == 'story_farm' then
        local plan, reason = Arrival.plan(world)
        if not plan then return false, reason end
        routePlan = plan
        buildMotionTable()
        return true
    end
    local extras = routeExtras()
    if (project.route.from == 'story_farm' or project.route.to == 'story_farm') and not extras.story_farm then
        return false, 'The Miller Farm driveway is unavailable.'
    end
    local route, reason = Routes.new(world.roads, { destinations = extras }):find(project.route.from, project.route.to)
    if not route or #route.points < 2 then return false, reason or 'Choose two connected town destinations.' end
    local cumulative = { [1] = 0 }
    for index = 2, #route.points do
        local a, b = route.points[index - 1], route.points[index]
        cumulative[index] = cumulative[index - 1] + math.sqrt((b.x - a.x)^2 + (b.z - a.z)^2)
    end
    local length = cumulative[#cumulative]
    if length < 4 then return false, 'The selected route is too short for a cutscene.' end
    routePlan = { points = route.points, cumulative = cumulative, length = length,
        route = route, terrainPath = route.points, crossesBridge = route.crossesBridge }
    buildMotionTable()
    return true
end
local function assistStartPose()
    local lastSafeDistance = math.max(0, routePlan.length - 2)
    local firstTry = math.min(20, lastSafeDistance)
    local startDistance, startPose
    for distance = firstTry, lastSafeDistance, 2 do
        local pose = Scene.samplePath(routePlan, distance)
        local roadDistance, segment = world.roads:nearest(pose.x, pose.z)
        if segment and roadDistance < 1 and Rider.clear(world, pose.x, pose.z, Bike.RADIUS) then
            startDistance, startPose = distance, pose
            break
        end
    end
    startDistance = startDistance or firstTry
    startPose = startPose or Scene.samplePath(routePlan, startDistance)
    local before = Scene.samplePath(routePlan, math.max(0, startDistance - 1.5))
    local after = Scene.samplePath(routePlan, math.min(routePlan.length, startDistance + 1.5))
    local heading = math.atan2(after.z - before.z, after.x - before.x)
    return startPose, heading, startDistance
end
local function resetAssistRider()
    local startPose, heading = assistStartPose()
    local motorcycle = project.actor.kind == 'motorcycle-rider'
    rider = Rider.new(startPose.x, startPose.z, heading, { version = 1,
        outfit = motorcycle and 'geared' or project.actor.outfit,
        mounted = motorcycle, engine = motorcycle, revision = 0 })
    if motorcycle then rider.bike.upgradeLevel = 3
    else rider.ped.x, rider.ped.z = startPose.x, startPose.z end
    actor = Rider.actor(rider)
    Rider.update(rider, {}, 0, world)
    camera = Camera.new(actor, world)
    camera.outsideMode = 'fixed'
    local shot = Scene.cameraAt(project, cursor)
    camera.yaw = (-math.deg(actor.heading) - 90 + shot.yaw) % 360
    camera.fixedYaw = camera.yaw
    camera.tilt, camera.targetZoom, camera.zoom = shot.tilt, shot.zoom, shot.zoom
    updateViewport()
end
local function takeMatchesCurrentScene(take)
    if not take or take.actorKind ~= project.actor.kind then return false end
    local route = take.route
    return not route or route.seed == project.world.seed
        and route.from == project.route.from and route.to == project.route.to
end
local function captureActorFrame(time)
    if project.actor.kind == 'player-character' then
        local ped = rider.ped
        return { time = time, x = ped.x, z = ped.z, h = ped.h or 0, heading = ped.heading,
            speed = ped.speed or 0, lean = 0, steering = 0, throttle = 0, brake = 0,
            boostPulse = 0, shiftTime = 0, pitch = 0, vy = 0, distance = ped.distance or 0,
            gear = 1, rpm = Bike.IDLE_RPM, vx = ped.vx or 0, vz = ped.vz or 0,
            boosting = false, grounded = true, reverse = false }
    end
    local bike = rider.bike
    return { time = time, x = bike.x, z = bike.z, h = bike.h or 0, heading = bike.heading,
        speed = bike.speed, lean = bike.lean or 0, steering = bike.steering or 0,
        throttle = bike.throttle or 0, brake = bike.brake or 0, boostPulse = bike.boostPulse or 0,
        shiftTime = bike.shiftTime or 0, pitch = bike.pitch or 0, vy = bike.vy or 0,
        distance = bike.distance or 0, gear = bike.gear or 1, rpm = bike.rpm or Bike.IDLE_RPM,
        vx = bike.vx or 0, vz = bike.vz or 0, boosting = bike.boosting == true,
        grounded = bike.grounded ~= false, reverse = bike.reverse == true }
end
local function beginActorTake()
    playing, cursor, actorAssistElapsed, actorAssistAccumulator, actorAssistTicks = false, 0, 0, 0, 0
    resetAssistRider()
    takeFrames = { captureActorFrame(0) }
    actorAssist = true
    status = project.actor.kind == 'motorcycle-rider'
        and 'Recording at 30 fps with game motorcycle physics. W gas, S brake, A/D steer; Shift boosts.'
        or 'Recording at 30 fps with game walking physics. WASD moves; hold Shift to run.'
end
local function finishActorTake()
    if not actorAssist then return end
    actorAssist = false
    if #takeFrames >= 2 and takeFrames[#takeFrames].time >= .05 then
        local duration = takeFrames[#takeFrames].time
        project.take = { fps = TAKE_FPS, actorKind = project.actor.kind,
            route = { seed = project.world.seed, from = project.route.from, to = project.route.to },
            duration = duration, frames = takeFrames }
        project.trimIn = math.min(project.trimIn, math.max(0, duration - .25))
        project.trimOut = math.max(.25, math.min(project.trimOut, duration))
        cursor = project.trimIn
        status = ('Kept %d actor frames (%0.1f seconds). Save the composition to keep this take.'):format(#takeFrames, duration)
    else
        status = 'Take was too short to keep; the previous take is unchanged.'
    end
    takeFrames = {}
end
local function actorInput()
    local forward = love.keyboard.isDown('w', 'up')
    local back = love.keyboard.isDown('s', 'down')
    local left = love.keyboard.isDown('a', 'left')
    local right = love.keyboard.isDown('d', 'right')
    if project.actor.kind == 'player-character' then
        local walkX, walkZ = right and 1 or left and -1 or 0,
            back and 1 or forward and -1 or 0
        walkX, walkZ = camera:screenVectorToWorld(walkX, walkZ)
        return { walkX = walkX, walkZ = walkZ,
            sprint = love.keyboard.isDown('lshift', 'rshift') }
    end
    return { throttle = forward and 1 or 0, brake = back and 1 or 0,
        steer = right and 1 or left and -1 or 0, boost = love.keyboard.isDown('lshift', 'rshift') }
end
local function presentActor(time, dt)
    local bike = rider.bike
    actor = Rider.actor(rider)
    camera.outsideMode = 'fixed'
    if not actorAssist and not cameraPass then
        local shot = Scene.cameraAt(project, time)
        camera.yaw = (-math.deg(actor.heading) - 90 + shot.yaw) % 360
        camera.fixedYaw = camera.yaw
        camera.tilt, camera.targetZoom = shot.tilt, shot.zoom
    end
    camera:updateRide(rider, dt, actor)
    renderer:prepare(camera, dt)
    if rider.gear.mounted then renderer:updateTireTracks('cutscene-studio', bike, world, dt) end
    if audio then audio:setMuted(soundsMuted); audio:update(dt, bike, rider.gear.engine, { outdoors = true }) end
end
local function updateActorAssist(dt)
    actorAssistAccumulator = actorAssistAccumulator + math.min(dt, .1)
    while actorAssistAccumulator >= PHYSICS_STEP and actorAssist do
        actorAssistAccumulator = actorAssistAccumulator - PHYSICS_STEP
        Rider.update(rider, actorInput(), PHYSICS_STEP, world)
        actorAssistElapsed = actorAssistElapsed + PHYSICS_STEP
        actorAssistTicks = actorAssistTicks + 1
        cursor = math.min(project.duration, actorAssistElapsed)
        if actorAssistTicks % 2 == 0 then
            takeFrames[#takeFrames + 1] = captureActorFrame(actorAssistElapsed)
        end
        if actorAssistElapsed >= project.duration then finishActorTake() end
    end
    presentActor(cursor, math.min(dt, .1))
end
local function applyTakePose(time)
    local pose = Scene.sampleTake(project, time)
    if not pose or not takeMatchesCurrentScene(project.take) then return false end
    if project.actor.kind == 'player-character' then
        rider.gear.outfit, rider.gear.mounted, rider.gear.engine, rider.gear.transition =
            project.actor.outfit, false, false, nil
        rider.ped.x, rider.ped.z, rider.ped.h = pose.x, pose.z, pose.h
        rider.ped.heading, rider.ped.speed = pose.heading, pose.speed
        rider.ped.distance, rider.ped.vx, rider.ped.vz = pose.distance, pose.vx, pose.vz
        return true
    end
    local bike = rider.bike
    bike.x, bike.z, bike.h, bike.heading = pose.x, pose.z, pose.h, pose.heading
    bike.speed, bike.lean, bike.steering = pose.speed, pose.lean, pose.steering
    bike.throttle, bike.brake, bike.boostPulse = pose.throttle, pose.brake, pose.boostPulse
    bike.shiftTime, bike.pitch, bike.vy = pose.shiftTime, pose.pitch, pose.vy
    bike.distance, bike.gear, bike.rpm = pose.distance, pose.gear, pose.rpm
    bike.vx, bike.vz = pose.vx, pose.vz
    bike.boosting, bike.grounded, bike.reverse = pose.boosting, pose.grounded, pose.reverse
    bike.frontGrounded, bike.rearGrounded = pose.grounded, pose.grounded
    bike._velocitySpeed = pose.speed
    rider.ped.x, rider.ped.z, rider.ped.heading = pose.x, pose.z, pose.heading
    return true
end
local function drawLoading(label, progress)
    local g = love.graphics
    g.clear(.035, .055, .047, 1)
    g.setColor(.94, .91, .78)
    g.setFont(fonts.heading or love.graphics.newFont(27))
    g.printf('CUTSCENE STUDIO', 0, 350, windowWidth, 'center')
    g.setFont(fonts.body or love.graphics.newFont(16))
    g.printf(label .. '  ' .. tostring(math.floor((progress or 0) * 100)) .. '%', 80, 408, windowWidth - 160, 'center')
    g.setColor(.18, .26, .20); g.rectangle('fill', windowWidth * .2, 448, windowWidth * .6, 12, 5)
    g.setColor(.79, .67, .42); g.rectangle('fill', windowWidth * .2, 448, windowWidth * .6 * clamp(progress or 0, 0, 1), 12, 5)
    love.graphics.present()
end
local function buildWorld(seed)
    drawLoading('Generating the authored town', 0)
    local definition, reason = Town.generate(seed, { progress = function(value, label) drawLoading(label or 'Preparing roads', value or 0) end })
    if not definition then error(reason or 'Town generation failed.') end
    drawLoading('Building production terrain and scenery', 1)
    world = Town.world(definition)
    local okay, issue = findRoute()
    if not okay then error(issue or 'The cutscene route is unavailable.') end
end
updateViewport = function()
    local width, height = love.graphics.getDimensions()
    windowWidth, windowHeight = width, height
    local right = math.max(344, math.floor(width * .27))
    local bottom = 170
    viewportWidth = recording and width or width - right
    viewportHeight = recording and height or height - bottom
    if camera then camera:setViewport(viewportWidth, viewportHeight) end
    if renderer then renderer:resizeViewport(viewportWidth, viewportHeight) end
end
local function setSelection(track, index)
    selection = { track = track, index = index }
end
local function selectedCue()
    local track = selection and project[selection.track]
    return track and track[selection.index] or nil
end
local function loadScene(index)
    if #projects == 0 then return end
    projectIndex = (index - 1) % #projects + 1
    local value, reason = loadProject(projects[projectIndex] .. '.lua')
    if not value then status = 'Could not open composition: ' .. tostring(reason); return end
    project = value
    cursor = project.trimIn
    selection = nil
    buildMotionTable()
    status = 'Loaded ' .. project.title .. ' from the editable project library.'
    if project.world.seed ~= world.town.seed then
        local okay, issue = pcall(buildWorld, project.world.seed)
        if not okay then status = 'Could not load this town: ' .. tostring(issue) end
        renderer = Renderer.new(world)
        renderer.characterAssets = CharacterAssets
        renderer.calendar = { year = 2026, month = 6, day = 21, totalDays = 0, elapsed = 600, secondsPerDay = 1200 }
        world.calendar = renderer.calendar
        renderer:prewarmViews()
    end
    local okay, issue = findRoute()
    if not okay then status = 'Could not load this route: ' .. tostring(issue); return end
    resetAssistRider()
end
local function newProject()
    local copy = {}
    local function clone(value)
        if type(value) ~= 'table' then return value end
        local out = {}; for key, item in pairs(value) do out[key] = clone(item) end; return out
    end
    copy = clone(project)
    local serial = 1
    local id
    repeat id = 'cutscene-' .. serial; serial = serial + 1 until not love.filesystem.getInfo(sourceDirectory .. '/' .. id .. '.lua')
    copy.id, copy.title, copy.duration, copy.trimIn, copy.trimOut = id, 'New Cutscene', 12, 0, 12
    copy.world.seed = world.town.seed
    copy.camera = { { time = 0, label = 'Rear chase', yaw = 0, tilt = 55, zoom = 1.05 } }
    copy.speed = { { time = 0, mph = 0 }, { time = 12, mph = 0 } }
    copy.actions, copy.dialogue, copy.take = {}, {}, nil
    project = copy
    projects[#projects + 1] = id
    table.sort(projects)
    for index, candidate in ipairs(projects) do if candidate == id then projectIndex = index end end
    cursor, selection = 0, nil
    buildMotionTable()
    resetAssistRider()
    textEntry = { kind = 'title', value = project.title }
    love.keyboard.setTextInput(true)
    status = 'Name the new composition, then press Enter.'
end
local function toggleActorKind()
    if project.actor.kind == 'motorcycle-rider' then
        project.actor.kind, project.actor.outfit, project.actor.mounted = 'player-character', 'normal', false
    else
        project.actor.kind, project.actor.outfit, project.actor.mounted = 'motorcycle-rider', 'geared', true
    end
    resetAssistRider()
    status = project.take and not takeMatchesCurrentScene(project.take)
        and 'Recorded take kept; route preview is active for this actor.'
        or 'Actor type changed. Drive & Record Take to perform this scene.'
end
local function routeOptions()
    local ids = {}
    for id in pairs(world.roads.destinations or {}) do ids[#ids + 1] = id end
    if routeExtras().story_farm then ids[#ids + 1] = 'story_farm' end
    table.sort(ids)
    return ids
end
local function routeLabel(id)
    if id == 'story_farm' then return 'Miller Farm' end
    local destination = world.roads.destinations[id]
    return destination and (destination.label or id) or id
end
local function connectedRouteCandidates(excludeCurrent)
    local options = routeOptions()
    local planner = Routes.new(world.roads, { destinations = routeExtras() })
    local candidates = {}
    for _, from in ipairs(options) do
        for _, to in ipairs(options) do
            local different = from ~= project.route.from or to ~= project.route.to
            if from ~= to and (not excludeCurrent or different) then
                local route
                if from == 'mainland_exit' and to == 'story_farm' then
                    route = Arrival.plan(world)
                else
                    route = planner:find(from, to)
                end
                if route and route.length >= 80 and #route.points >= 3 then
                    candidates[#candidates + 1] = { from = from, to = to, length = route.length }
                end
            end
        end
    end
    return candidates
end
local function cycleRoute(field, step)
    local options = routeOptions()
    if #options < 2 then status = 'This town has fewer than two route destinations.'; return end
    local current = 1
    for index, id in ipairs(options) do if id == project.route[field] then current = index; break end end
    local old = project.route[field]
    for offset = 1, #options do
        local candidate = options[(current - 1 + step * offset) % #options + 1]
        if candidate ~= project.route[field == 'from' and 'to' or 'from'] then
            project.route[field] = candidate
            local okay, reason = findRoute()
            if okay then
                resetAssistRider()
                status = project.take and not takeMatchesCurrentScene(project.take)
                    and 'Recorded take kept. Route preview is active; record a fresh take for this route.'
                    or ('Route set: %s to %s.'):format(routeLabel(project.route.from), routeLabel(project.route.to))
            else
                project.route[field] = old
                findRoute()
                status = 'Route not available: ' .. tostring(reason)
            end
            return
        end
    end
end
local function randomRoute()
    local candidates = connectedRouteCandidates(true)
    if #candidates == 0 then
        status = 'No different connected road route is available in this town.'
        return
    end
    local choice = candidates[love.math.random(#candidates)]
    local previous = project.route
    project.route = { from = choice.from, to = choice.to }
    local okay, reason = findRoute()
    if not okay then
        project.route = previous
        findRoute()
        status = 'Random route unavailable: ' .. tostring(reason)
        return
    end
    resetAssistRider()
    status = ('Random route: %s to %s.'):format(routeLabel(choice.from), routeLabel(choice.to))
    if project.take and not takeMatchesCurrentScene(project.take) then
        status = status .. ' Previous take kept; route preview is active.'
    end
end
local function cloneData(value)
    if type(value) ~= 'table' then return value end
    local copy = {}
    for key, item in pairs(value) do copy[key] = cloneData(item) end
    return copy
end
local function captureCameraCue(time)
    local heading = actor and actor.heading or 0
    local baseYaw = -math.deg(heading) - 90
    local yaw = ((camera.yaw - baseYaw + 180) % 360) - 180
    return { time = clamp(time, project.trimIn, project.trimOut), label = 'Camera pass',
        yaw = yaw, tilt = clamp(camera.tilt, 6, 89), zoom = clamp(camera.targetZoom, .55, 4) }
end
local function recordCameraCue(time)
    if not cameraPass or not cameraDraft then return end
    local cue = captureCameraCue(time)
    local previous = cameraDraft[#cameraDraft]
    if previous and math.abs(previous.time - cue.time) < .001 then
        cameraDraft[#cameraDraft] = cue
    else
        cameraDraft[#cameraDraft + 1] = cue
    end
end
local function finishCameraPass()
    if not cameraPass then return false end
    recordCameraCue(cursor)
    cameraPass = false
    playing = false
    cameraReview = true
    cameraDrag = nil
    status = ('Camera pass ready with %d angle keys. Keep it to preview, or discard it.'):format(#cameraDraft)
    return true
end
local function beginCameraPass()
    if actorAssist or cameraPass or cameraReview or recording then return false end
    cameraPassOriginal = cloneData(project.camera)
    cameraDraft = {}
    cursor = project.trimIn
    sampleProject(cursor, 0)
    cameraPass = true
    cameraReview = false
    cameraPassNextSample = cursor + CAMERA_CAPTURE_STEP
    recordCameraCue(cursor)
    playing = true
    looping = false
    status = 'Replay started. Drag in the preview to orbit; scroll to zoom. The camera will be captured as you go.'
    return true
end
local function keepCameraPass()
    if not cameraReview or not cameraDraft or #cameraDraft < 2 then
        status = 'The camera pass needs at least two angle keys.'
        return false
    end
    local merged = {}
    for _, cue in ipairs(cameraPassOriginal or project.camera) do
        if cue.time < project.trimIn - .0001 or cue.time > project.trimOut + .0001 then
            merged[#merged + 1] = cue
        end
    end
    for _, cue in ipairs(cameraDraft) do merged[#merged + 1] = cue end
    project.camera = merged
    sortCues(project.camera)
    cameraPass, cameraReview, cameraDraft, cameraPassOriginal = false, false, nil, nil
    cameraDrag, selection = nil, nil
    cursor, playing, looping = project.trimIn, true, false
    sampleProject(cursor, 0)
    status = 'Camera pass kept. Previewing its camera track; save the composition to keep it.'
    return true
end
local function discardCameraPass()
    if not cameraReview then return false end
    cameraPass, cameraReview, cameraDraft, cameraPassOriginal = false, false, nil, nil
    cameraDrag = nil
    cursor, playing = project.trimIn, false
    sampleProject(cursor, 0)
    status = 'Camera pass discarded. The previous camera track is restored.'
    return true
end
local function generatedSceneId()
    local base = 'high-octane-' .. os.date('%Y%m%d-%H%M%S') .. '-' .. love.math.random(1000, 9999)
    local id, suffix = base, 1
    while love.filesystem.getInfo(sourceDirectory .. '/' .. id .. '.lua') do
        id, suffix = base .. '-' .. suffix, suffix + 1
    end
    return id
end
local function generateHighOctaneScene()
    local candidates = connectedRouteCandidates(true)
    if #candidates == 0 then candidates = connectedRouteCandidates(false) end
    if #candidates == 0 then
        status = 'No connected road route is long enough for a high-octane scene.'
        return
    end
    local choice = candidates[love.math.random(#candidates)]
    local scene = cloneData(project)
    local durations = { 20, 24, 28 }
    local duration = durations[love.math.random(#durations)]
    scene.id = generatedSceneId()
    scene.title = ('High-Octane Ride · %s to %s'):format(routeLabel(choice.from), routeLabel(choice.to))
    scene.actor.kind, scene.actor.outfit, scene.actor.mounted = 'motorcycle-rider', 'geared', true
    scene.route = { from = choice.from, to = choice.to }
    scene.duration, scene.trimIn, scene.trimOut = duration, 0, duration
    scene.take = nil
    scene.camera, scene.speed, scene.actions, scene.dialogue = {}, {}, {}, {}

    local shotCount = love.math.random(5, 7)
    local previousPreset
    for index = 1, shotCount do
        local presetIndex = love.math.random(#presets)
        if presetIndex == previousPreset then presetIndex = presetIndex % #presets + 1 end
        previousPreset = presetIndex
        local preset = presets[presetIndex]
        local spread = duration - 3
        local time = index == 1 and 0 or 1.5 + (index - 1) * spread / (shotCount - 1)
        scene.camera[#scene.camera + 1] = {
            time = time, label = preset.label, yaw = preset.yaw, tilt = preset.tilt, zoom = preset.zoom,
        }
    end

    local speedTimes = { 0, .14, .31, .49, .66, .83, 1 }
    local speedRanges = { { 26, 42 }, { 54, 72 }, { 82, 104 }, { 56, 76 }, { 88, 110 }, { 58, 78 } }
    for index, fraction in ipairs(speedTimes) do
        local mph
        if index == #speedTimes then mph = 0
        else
            local range = speedRanges[index]
            mph = love.math.random(range[1], range[2])
        end
        scene.speed[#scene.speed + 1] = { time = duration * fraction, mph = mph }
    end

    local actionPool = { 'boost', 'jump', 'shift', 'brake', 'turn', 'tuck' }
    for index = #actionPool, 2, -1 do
        local swap = love.math.random(index)
        actionPool[index], actionPool[swap] = actionPool[swap], actionPool[index]
    end
    local actionCount = love.math.random(4, #actionPool)
    for index = 1, actionCount do
        local action = actionPool[index]
        local fraction = .12 + (index - 1) * .72 / math.max(1, actionCount - 1)
            + love.math.random(-5, 5) / 100
        local cue = { time = duration * clamp(fraction, .08, .9), action = action,
            duration = action == 'jump' and .86 or action == 'turn' and 1.2 or .78 }
        if action == 'jump' then cue.height = 1.8 end
        scene.actions[#scene.actions + 1] = cue
    end
    sortCues(scene.camera); sortCues(scene.speed); sortCues(scene.actions)

    project = scene
    cursor, selection, playing = 0, nil, false
    local okay, reason = findRoute()
    if not okay then
        status = 'Could not build the generated route: ' .. tostring(reason)
        return
    end
    buildMotionTable()
    resetAssistRider()
    status = ('Generated %d s high-octane scene: %s to %s. Add dialogue or record a take, then save when ready.')
        :format(duration, routeLabel(choice.from), routeLabel(choice.to))
end
sampleProject = function(time, dt)
    if actorAssist then
        presentActor(time, dt)
        return
    end
    if applyTakePose(time) then
        presentActor(time, dt)
        return
    end
    local distance = motionDistance(time)
    local pose = Scene.samplePath(routePlan, distance)
    local before = Scene.samplePath(routePlan, math.max(0, distance - 2.5))
    local after = Scene.samplePath(routePlan, math.min(routePlan.length, distance + 2.5))
    local dx, dz = after.x - before.x, after.z - before.z
    local heading = math.atan2(dz, dx)
    if project.actor.kind == 'player-character' then
        local ped = rider.ped
        local walkSpeed = math.min(3.45, Scene.speedAt(project, time) / 2.236936)
        ped.x, ped.z, ped.h, ped.heading = pose.x, pose.z, world:supportHeight(pose.x, pose.z), heading
        ped.speed, ped.distance = walkSpeed, distance
        ped.vx, ped.vz = math.cos(heading) * walkSpeed, math.sin(heading) * walkSpeed
        presentActor(time, dt)
        return
    end
    local function tangentAt(at)
        local a = Scene.samplePath(routePlan, math.max(0, at - 2.5))
        local b = Scene.samplePath(routePlan, math.min(routePlan.length, at + 2.5))
        return math.atan2(b.z - a.z, b.x - a.x)
    end
    -- Estimate cornering over a broad section of the road so small route-point
    -- changes do not flip the lean from side to side.
    local priorHeading = tangentAt(distance - 10)
    local nextHeading = tangentAt(distance + 10)
    local turn = math.atan2(math.sin(nextHeading - priorHeading), math.cos(nextHeading - priorHeading))
    local bike = rider.bike
    local baseHeight = world:supportHeight(pose.x, pose.z)
    local mph = Scene.speedAt(project, time)
    local speed = math.min(Bike.BOOST_MAX_SPEED, mph / 2.236936)
    local jump, boost, brake, shifting, extraTurn
    for _, cue in ipairs(Scene.actionsAt(project, time)) do
        if cue.action == 'jump' then jump = cue end
        if cue.action == 'boost' then boost = cue end
        if cue.action == 'brake' then brake = cue end
        if cue.action == 'shift' then shifting = cue end
        if cue.action == 'turn' then extraTurn = cue end
    end
    local vertical, verticalSpeed, grounded, pitch = 0, 0, true, math.atan2(after.h - before.h, math.max(.01, 2.4))
    if jump then
        local p = clamp((time - jump.time) / jump.duration, 0, 1)
        vertical = math.sin(p * math.pi) * jump.height
        verticalSpeed = math.cos(p * math.pi) * jump.height * math.pi / jump.duration
        grounded, pitch = p <= 0 or p >= 1, .30 * math.cos(p * math.pi)
    end
    if extraTurn then turn = turn + math.sin((time - extraTurn.time) / extraTurn.duration * math.pi) * .05 end
    local priorSpeed = math.min(Bike.BOOST_MAX_SPEED,
        Scene.speedAt(project, math.max(0, time - .08)) / 2.236936)
    bike.x, bike.z, bike.heading = pose.x, pose.z, heading
    bike.h = baseHeight + vertical
    bike.speed, bike.vx, bike.vz = speed, math.cos(heading) * speed, math.sin(heading) * speed
    bike.distance = distance
    bike.throttle = speed > priorSpeed + .18 and 1 or speed > 2 and .45 or 0
    bike.brake = brake and .86 or speed < priorSpeed - .35 and .58 or 0
    bike.acceleration = (speed - priorSpeed) / .08
    bike.steering = clamp(turn * 1.2, -1, 1)
    bike.lean = clamp(-turn * .36, -.52, .52)
    bike.gear = clamp(math.ceil(speed / (Bike.MAX_SPEED * .26)), 1, 4)
    bike.rpm = Bike.rpmForSpeed(bike, speed)
    bike.grounded, bike.frontGrounded, bike.rearGrounded = grounded, grounded, grounded
    bike.vy, bike.pitch = verticalSpeed, pitch
    bike.boosting, bike.boostPulse = boost ~= nil, boost and (time - boost.time) or 0
    bike.shiftTime = shifting and math.max(0, shifting.duration - (time - shifting.time)) or 0
    bike.surface = 'road'
    if shifting and bike.ridingAnimation.kind ~= 'shift' then
        bike.ridingAnimation.kind, bike.ridingAnimation.remaining = 'shift', .32
    end
    if bike.ridingAnimation.kind == 'shift' then
        bike.ridingAnimation.remaining = math.max(0, bike.ridingAnimation.remaining - dt)
        if bike.ridingAnimation.remaining <= 0 then bike.ridingAnimation.kind = 'idle' end
    end
    rider.ped.x, rider.ped.z, rider.ped.heading = pose.x, pose.z, heading
    presentActor(time, dt)
end
local function dialogueCue(time) return Scene.dialogueAt(project, time) end
local function drawPreview()
    sampleProject(cursor, 0)
    renderer:draw(camera, actor, { { actor = actor, gear = rider.gear,
        presentation = { h = actor.h, speed = actor.speed, grounded = actor.grounded,
            lean = actor.lean, pitch = actor.pitch, throttle = actor.throttle,
            brake = actor.brake, boostPulse = actor.boostPulse,
            shiftTime = actor.shiftTime, acceleration = actor.acceleration }, localPlayer = true } })
    if actorAssist then
        local g = love.graphics
        g.setColor(.02, .03, .025, .86); g.rectangle('fill', 18, 18, 520, 91, 7, 7)
        g.setColor(.95, .82, .57); g.setFont(fonts.small)
        g.print(('ACTOR ASSIST  ·  TAKE %0.1f s  ·  %02.0f mph')
            :format(actorAssistElapsed, (actor.speed or 0) * 2.236936), 30, 28)
        g.setColor(.94, .94, .87)
        local controls = project.actor.kind == 'motorcycle-rider'
            and 'W gas  ·  S brake  ·  A/D steer  ·  Shift boost'
            or 'WASD move  ·  hold Shift to run'
        g.print(controls, 30, 52)
        if project.actor.kind == 'motorcycle-rider' then
            g.print('T auto/manual  ·  Z/X shift  ·  R restart  ·  Esc keep', 30, 69)
        else
            g.print('Esc keeps the take', 30, 69)
        end
        g.print('Drag preview to orbit  ·  scroll to zoom', 30, 85)
    elseif cameraPass then
        local g = love.graphics
        g.setColor(.02, .03, .025, .86); g.rectangle('fill', 18, 18, 520, 54, 7, 7)
        g.setColor(.95, .82, .57); g.setFont(fonts.small)
        g.print('CAMERA PASS  ·  DRAG TO ORBIT  ·  SCROLL TO ZOOM  ·  SPACE PAUSES  ·  ESC ENDS', 30, 28)
        g.setColor(.94, .94, .87)
        g.print(('PLAYBACK %0.1f / %0.1f s'):format(cursor, project.trimOut), 30, 49)
    elseif cameraReview then
        local g = love.graphics
        g.setColor(.02, .03, .025, .86); g.rectangle('fill', 18, 18, 520, 54, 7, 7)
        g.setColor(.95, .82, .57); g.setFont(fonts.small)
        g.print('CAMERA PASS READY  ·  KEEP TO PREVIEW  ·  DISCARD TO RESTORE', 30, 28)
        g.setColor(.94, .94, .87)
        g.print(('%d angle keys captured'):format(#(cameraDraft or {})), 30, 49)
    end
    local cue = dialogueCue(cursor)
    if cue then
        local g = love.graphics
        local y = viewportHeight - 94
        g.setColor(.025, .035, .03, .82); g.rectangle('fill', viewportWidth * .16, y, viewportWidth * .68, 66, 8, 8)
        g.setColor(.84, .70, .43); g.setFont(fonts.small); g.printf(cue.speaker, viewportWidth * .18, y + 9, viewportWidth * .64, 'center')
        g.setColor(.96, .94, .85); g.setFont(fonts.body); g.printf(cue.text, viewportWidth * .19, y + 29, viewportWidth * .62, 'center')
    end
end
local function button(label, x, y, width, callback, tone)
    local drawY = y + sidebarOffset
    local rect = { label = label, x = x, y = drawY, w = width, h = 32, fn = callback }
    if sidebarOffset == 0 or drawY >= 0 and drawY + rect.h <= windowHeight - 170 then
        buttons[#buttons + 1] = rect
    end
    local g = love.graphics
    local active = tone == 'active'
    g.setColor(active and .35 or tone == 'primary' and .35 or .13,
        active and .42 or tone == 'primary' and .38 or .20,
        active and .29 or tone == 'primary' and .26 or .17, .98)
    g.rectangle('fill', x, drawY, width, rect.h, 5, 5)
    g.setColor(active and .97 or tone == 'primary' and .96 or .79,
        active and .89 or tone == 'primary' and .86 or .83, active and .67 or .73, 1)
    g.setFont(fonts.small); g.printf(label, x + 4, drawY + 9, width - 8, 'center')
end
local function label(text, x, y, color)
    y = y + sidebarOffset
    love.graphics.setColor(color or {.74, .80, .73})
    love.graphics.setFont(fonts.small); love.graphics.print(text, x, y)
end
local function box(x, y, width, height)
    love.graphics.setColor(.035, .052, .045, .97)
    love.graphics.rectangle('fill', x, y, width, height)
end
local function rightPanel()
    local x, width = viewportWidth, windowWidth - viewportWidth
    box(x, 0, width, windowHeight - 170)
    local g = love.graphics
    g.push('all')
    g.setScissor(x, 0, width, windowHeight - 170)
    sidebarOffset = -panelScroll
    local left, content = x + 16, width - 32
    love.graphics.setFont(fonts.heading); love.graphics.setColor(.91, .83, .62)
    love.graphics.print('CUTSCENE STUDIO', left, 16)
    label('IN-ENGINE EDITOR  ·  SCROLL FOR MORE', left, 48)
    local row = 72
    button('‹', left, row, 36, function() loadScene(projectIndex - 1) end)
    button('›', left + 42, row, 36, function() loadScene(projectIndex + 1) end)
    button('+ NEW', left + 84, row, math.min(92, content - 88), newProject, 'primary')
    button('RENAME', left + 182, row, content - 182, function()
        textEntry = { kind = 'title', value = project.title }; love.keyboard.setTextInput(true)
    end)
    label(project.title, left, row + 39, {.93, .92, .82})
    local actorLabel = project.actor.kind == 'motorcycle-rider' and 'GEARED RIDER' or 'PLAYER ON FOOT'
    label(('TOWN SEED %d  ·  %s'):format(project.world.seed, actorLabel), left, row + 57)
    row = row + 83
    label('FROM  ·  ' .. routeLabel(project.route.from), left, row)
    button('‹ START', left, row + 14, (content - 8) / 2,
        function() cycleRoute('from', -1) end)
    button('NEXT START ›', left + (content - 8) / 2 + 8, row + 14, (content - 8) / 2,
        function() cycleRoute('from', 1) end)
    row = row + 52
    label('TO  ·  ' .. routeLabel(project.route.to), left, row)
    button('‹ DESTINATION', left, row + 14, (content - 8) / 2,
        function() cycleRoute('to', -1) end)
    button('NEXT DESTINATION ›', left + (content - 8) / 2 + 8, row + 14, (content - 8) / 2,
        function() cycleRoute('to', 1) end)
    row = row + 52
    button('RANDOM ROUTE  ·  CONNECTED ROADS', left, row, content, randomRoute, 'primary')
    row = row + 38
    button('GENERATE HIGH-OCTANE SCENE', left, row, content, generateHighOctaneScene, 'primary')
    row = row + 38
    button(playing and 'PAUSE' or 'PLAY', left, row, (content - 8) / 2, function()
        playing = not playing
        if playing and cursor >= project.trimOut then cursor = project.trimIn end
        status = playing and 'Playing the selected trim range.' or 'Playback paused.'
    end, playing and 'active' or 'primary')
    button(looping and 'LOOP ON' or 'LOOP OFF', left + (content - 8) / 2 + 8, row, (content - 8) / 2,
        function() looping = not looping end, looping and 'active' or nil)
    row = row + 40
    button(project.actor.kind == 'motorcycle-rider' and 'ACTOR: MOTORCYCLE' or 'ACTOR: ON FOOT',
        left, row, content, toggleActorKind)
    row = row + 38
    label(project.actor.kind == 'motorcycle-rider' and 'ACTOR ASSIST  ·  LIVE MOTORCYCLE PHYSICS'
        or 'ACTOR ASSIST  ·  LIVE WALKING PHYSICS', left, row)
    local takeButton = actorAssist and 'STOP & KEEP TAKE'
        or project.actor.kind == 'motorcycle-rider' and 'DRIVE & RECORD TAKE'
        or 'WALK & RECORD TAKE'
    button(takeButton, left, row + 17, content,
        function() if actorAssist then finishActorTake() else beginActorTake() end end,
        actorAssist and 'active' or 'primary')
    row = row + 54
    label(project.actor.kind == 'motorcycle-rider'
        and 'W GAS  ·  S BRAKE  ·  A/D STEER  ·  SHIFT BOOST'
        or 'WASD MOVE  ·  SHIFT RUN  ·  ESC FINISH', left, row)
    row = row + 22
    label(project.take and ('TAKE %0.1f s  ·  %s'):format(project.take.duration,
        takeMatchesCurrentScene(project.take) and 'ACTIVE' or 'KEPT')
        or 'NO RECORDED TAKE  ·  USE THE ROUTE PREVIEW', left, row)
    row = row + 22
    if cameraReview then
        label(('CAMERA PASS READY  ·  %d ANGLE KEYS'):format(#(cameraDraft or {})), left, row,
            {.93, .89, .72})
        button('KEEP CAMERA PASS & PREVIEW', left, row + 17, content,
            keepCameraPass, 'primary')
        row = row + 55
        button('DISCARD CAMERA PASS', left, row, content, discardCameraPass)
        row = row + 38
    else
        button(cameraPass and 'STOP CAMERA PASS' or 'RECORD CAMERA PASS', left, row, content,
            function() if cameraPass then finishCameraPass() else beginCameraPass() end end,
            cameraPass and 'active' or 'primary')
        row = row + 38
    end
    button('SAVE COMPOSITION', left, row, content, function() saveProject(false) end)
    row = row + 38
    button('IMPORT TO GAME', left, row, content, function() if saveProject(false) then saveProject(true) end end, 'primary')
    row = row + 40
    button(recording and ('RECORDING  ' .. captureCount) or 'RECORD PLAYBACK', left, row, content, function()
        if recording then
            recording = false; playing = false; captureDue = false
            local okay, count = recorder:finish()
            recorder = nil
            updateViewport()
            status = okay and ('Saved %d frames to %s'):format(count, recordingPath) or ('Recording failed: ' .. tostring(count))
        else
            startRecording()
        end
    end, recording and 'active' or nil)
    row = row + 42
    label('CAMERA TRACK', left, row)
    local preset = presets[cameraChoice]
    button('ADD SHOT  ·  ' .. preset.label, left, row + 17, content, function()
        local cue = { time = cursor, label = preset.label,
            yaw = preset.yaw, tilt = preset.tilt, zoom = preset.zoom }
        project.camera[#project.camera + 1] = cue
        sortCues(project.camera)
        for index, current in ipairs(project.camera) do if current == cue then setSelection('camera', index) end end
    end)
    row = row + 56
    button('‹ ANGLE', left, row, (content - 8) / 2, function() cameraChoice = (cameraChoice - 2) % #presets + 1 end)
    button('NEXT ANGLE ›', left + (content - 8) / 2 + 8, row, (content - 8) / 2,
        function() cameraChoice = cameraChoice % #presets + 1 end)
    row = row + 39
    local shot = selection and selection.track == 'camera' and selectedCue()
    label(shot and ('SELECTED: ' .. shot.label) or 'Select a camera marker to adjust its shot', left, row)
    row = row + 17
    button('YAW −', left, row, (content - 8) / 2, function() if shot then shot.yaw = shot.yaw - 15 end end)
    button('YAW +', left + (content - 8) / 2 + 8, row, (content - 8) / 2, function() if shot then shot.yaw = shot.yaw + 15 end end)
    row = row + 37
    button('TILT −', left, row, (content - 8) / 2, function() if shot then shot.tilt = clamp(shot.tilt - 5, 6, 89) end end)
    button('TILT +', left + (content - 8) / 2 + 8, row, (content - 8) / 2, function() if shot then shot.tilt = clamp(shot.tilt + 5, 6, 89) end end)
    row = row + 37
    button('ZOOM −', left, row, (content - 8) / 2, function() if shot then shot.zoom = clamp(shot.zoom - .1, .45, 4) end end)
    button('ZOOM +', left + (content - 8) / 2 + 8, row, (content - 8) / 2, function() if shot then shot.zoom = clamp(shot.zoom + .1, .45, 4) end end)
    row = row + 40
    label('RIDER, DIALOGUE & SPEED', left, row)
    button('ADD ACTION  ·  ' .. actions[actionChoice], left, row + 17, content, function()
        local action = actions[actionChoice]
        local cue = { time = cursor, action = action, duration = action == 'jump' and .86 or action == 'turn' and 1.2 or .78 }
        if action == 'jump' then cue.height = 1.8 end
        project.actions[#project.actions + 1] = cue; sortCues(project.actions)
        for index, value in ipairs(project.actions) do if value == cue then setSelection('actions', index) end end
    end)
    row = row + 55
    button('‹ ACTION', left, row, (content - 8) / 2, function() actionChoice = (actionChoice - 2) % #actions + 1 end)
    button('NEXT ACTION ›', left + (content - 8) / 2 + 8, row, (content - 8) / 2,
        function() actionChoice = actionChoice % #actions + 1 end)
    row = row + 39
    button('ADD DIALOGUE', left, row, content, function()
        textEntry = { kind = 'dialogue', value = '', time = cursor }; love.keyboard.setTextInput(true)
    end)
    row = row + 38
    button('SPEAKER: ' .. dialogueSpeaker, left, row, content, function()
        dialogueSpeaker = dialogueSpeaker == 'Player' and 'Grandpa' or 'Player'
    end)
    row = row + 38
    button('ADD SPEED KEY', left, row, content, function()
        local cue = { time = cursor, mph = Scene.speedAt(project, cursor) }
        project.speed[#project.speed + 1] = cue; sortCues(project.speed)
        for index, value in ipairs(project.speed) do if value == cue then setSelection('speed', index) end end
        buildMotionTable()
    end)
    row = row + 38
    local speedCue = selection and selection.track == 'speed' and selectedCue()
    button('− 5 MPH', left, row, (content - 8) / 2, function()
        if speedCue then speedCue.mph = clamp(speedCue.mph - 5, 0, 120); buildMotionTable() end
    end)
    button('+ 5 MPH', left + (content - 8) / 2 + 8, row, (content - 8) / 2, function()
        if speedCue then speedCue.mph = clamp(speedCue.mph + 5, 0, 120); buildMotionTable() end
    end)
    row = row + 41
    local takePose = project.take and Scene.sampleTake(project, cursor)
    local displayedSpeed = takePose and takePose.speed * 2.236936 or Scene.speedAt(project, cursor)
    label(('TIME %05.2f s  ·  %s %02.0f mph'):format(cursor, takePose and 'TAKE' or 'SPEED', displayedSpeed), left, row, {.93, .89, .72})
    row = row + 22
    button('MARK IN', left, row, (content - 8) / 2, function()
        project.trimIn = math.min(cursor, project.trimOut - .25); status = 'Playback trim-in moved to the playhead.'
    end)
    button('MARK OUT', left + (content - 8) / 2 + 8, row, (content - 8) / 2, function()
        project.trimOut = math.max(cursor, project.trimIn + .25); status = 'Playback trim-out moved to the playhead.'
    end)
    row = row + 38
    button('RESET TRIM', left, row, content, function() project.trimIn, project.trimOut = 0, project.duration end)
    row = row + 40
    label(soundsMuted and 'Game motorcycle audio is muted' or 'Game motorcycle audio is live', left, row)
    button(soundsMuted and 'UNMUTE PREVIEW' or 'MUTE PREVIEW', left, row + 17, content, function()
        soundsMuted = not soundsMuted; if audio then audio:setMuted(soundsMuted) end
    end)
    panelContentHeight = row + 56
    panelScroll = clamp(panelScroll, 0, math.max(0, panelContentHeight - (windowHeight - 170)))
    local visibleHeight = windowHeight - 170
    if panelContentHeight > visibleHeight then
        local trackHeight = visibleHeight - 8
        local thumbHeight = math.max(28, trackHeight * visibleHeight / panelContentHeight)
        local travel = trackHeight - thumbHeight
        local ratio = panelScroll / math.max(1, panelContentHeight - visibleHeight)
        g.setColor(.31, .39, .32, .72)
        g.rectangle('fill', windowWidth - 5, 4 + travel * ratio + panelScroll, 3, thumbHeight, 2, 2)
    end
    sidebarOffset = 0
    g.pop()
end

local function timeline()
    local y0 = windowHeight - 170
    box(0, y0, windowWidth, 170)
    label('TIMELINE   ·   DRAG OR CLICK TO SCRUB   ·   SPACE PLAY   ·   I/O TRIM   ·   C CAMERA   ·   A ACTION   ·   D DIALOGUE',
        24, y0 + 10, {.91, .86, .70})
    local names = { { 'camera', 'CAMERA', {.86, .67, .39} },
        { 'actions', 'RIDER ACTION', {.57, .78, .56} },
        { 'dialogue', 'DIALOGUE', {.62, .71, .88} },
        { 'speed', 'SPEED', {.82, .65, .71} } }
    local left, right = 142, windowWidth - 24
    local width = right - left
    local rowHeight = 27
    local function marker(time, track, index, color, markerY)
        local x = left + width * time / project.duration
        local selected = selection and selection.track == track and selection.index == index
        love.graphics.setColor(color[1], color[2], color[3], selected and 1 or .78)
        love.graphics.rectangle('fill', x - (selected and 5 or 3), markerY - (selected and 5 or 3),
            selected and 10 or 6, selected and 22 or 16, 2, 2)
    end
    local g = love.graphics
    for row, info in ipairs(names) do
        local y = y0 + 31 + (row - 1) * rowHeight
        label(info[2], 24, y + 3)
        g.setColor(.16, .20, .17); g.rectangle('fill', left, y + 9, width, 2)
        local cues = project[info[1]]
        local stride = info[1] == 'camera' and math.max(1, math.ceil(#cues / 96)) or 1
        for index, cue in ipairs(cues) do
            local selected = selection and selection.track == info[1] and selection.index == index
            if index % stride == 1 or selected then marker(cue.time, info[1], index, info[3], y + 13) end
        end
        if info[1] == 'speed' then
            local previous
            for _, cue in ipairs(cues) do
                local x = left + width * cue.time / project.duration
                if previous then
                    g.setColor(.65, .43, .52, .8); g.setLineWidth(2); g.line(previous, y + 10, x, y + 10)
                end
                previous = x
            end
        end
    end
    local playX = left + width * cursor / project.duration
    g.setColor(.96, .93, .84, .85); g.setLineWidth(1); g.line(playX, y0 + 29, playX, y0 + 136)
    g.setColor(.97, .76, .43); g.polygon('fill', playX - 5, y0 + 25, playX + 5, y0 + 25, playX, y0 + 33)
    local trimLeft = left + width * project.trimIn / project.duration
    local trimRight = left + width * project.trimOut / project.duration
    g.setColor(.35, .55, .39, .25); g.rectangle('fill', trimLeft, y0 + 137, trimRight - trimLeft, 5)
    g.setColor(.89, .88, .78); g.printf('0.0 s', left, y0 + 147, 72, 'left')
    g.printf(('%0.1f s'):format(project.duration), right - 72, y0 + 147, 72, 'right')
    label(status, 220, y0 + 147, {.73, .81, .73})
end

startRecording = function()
    local okay = saveProject(false)
    if not okay then return end
    project.trimIn = clamp(project.trimIn, 0, project.duration - .25)
    project.trimOut = clamp(project.trimOut, project.trimIn + .25, project.duration)
    recordingPath = recordingFolder .. project.id .. '-' .. os.date('%Y%m%d-%H%M%S') .. '.gif'
    local width, height = love.graphics.getDimensions()
    local created, reason = Gif.new(recordingPath, width, height, 4)
    if not created then status = 'Could not start recording: ' .. tostring(reason); return end
    recorder, recording = created, true
    playing, cursor, captureAccumulator, captureCount = false, project.trimIn, 0, 0
    captureTarget = math.max(1, math.ceil((project.trimOut - project.trimIn) * FPS - 1e-6))
    captureDue, captureWaiting = true, false
    updateViewport()
    status = 'Recording the game renderer at 25 fps. The editor chrome is hidden from the playback.'
end
local function finishRecording()
    if not recorder then return end
    local okay, count = recorder:finish()
    recorder = nil
    recording, captureDue, captureWaiting = false, false, false
    updateViewport()
    status = okay and ('Saved %d-frame silent animated GIF: %s'):format(count, recordingPath)
        or ('Recording failed: ' .. tostring(count))
end
local function captureFrame()
    if not recording or captureWaiting or not captureDue then return end
    captureDue, captureWaiting = false, true
    local okay, reason = pcall(love.graphics.captureScreenshot, function(image)
        if not recording or not recorder then captureWaiting = false; return end
        local saved, issue = recorder:add(image)
        image:release()
        captureWaiting = false
        if not saved then
            recorder:finish(); recorder = nil; recording = false; updateViewport()
            status = 'Recording stopped: ' .. tostring(issue)
            return
        end
        captureCount = captureCount + 1
        if captureCount >= captureTarget then finishRecording() end
    end)
    if not okay then
        recording, captureWaiting, captureDue = false, false, false
        if recorder then recorder:finish(); recorder = nil end
        updateViewport(); status = 'Could not capture a frame: ' .. tostring(reason)
    end
end
local function timelineY(track)
    local base = windowHeight - 170 + 31
    local offset = ({ camera = 4, actions = 31, dialogue = 58, speed = 85 })[track]
    return base + offset
end
local function editDialogue()
    local cue = selection and selection.track == 'dialogue' and selectedCue()
    textEntry = { kind = 'dialogue', value = cue and cue.text or '', time = cursor, cue = cue }
    love.keyboard.setTextInput(true)
end
local function addCamera()
    local preset = presets[cameraChoice]
    local cue = { time = cursor, label = preset.label, yaw = preset.yaw, tilt = preset.tilt, zoom = preset.zoom }
    project.camera[#project.camera + 1] = cue; sortCues(project.camera)
    for index, value in ipairs(project.camera) do if value == cue then setSelection('camera', index) end end
end
local function addAction()
    local action = actions[actionChoice]
    local cue = { time = cursor, action = action, duration = action == 'jump' and .86 or action == 'turn' and 1.2 or .78 }
    if action == 'jump' then cue.height = 1.8 end
    project.actions[#project.actions + 1] = cue; sortCues(project.actions)
    for index, value in ipairs(project.actions) do if value == cue then setSelection('actions', index) end end
end

-- Keep LÖVE callbacks at module scope. Defining them inside Studio.load makes
-- that closure capture every editor local used by the callbacks, exceeding the
-- 60-upvalue limit in LuaJIT.
local function studioUpdate(dt)
    if recording then
        if captureCount == 0 and not captureWaiting then captureDue = true end
        if not captureDue and not captureWaiting then
            captureAccumulator = captureAccumulator + math.min(dt, .1)
            if captureAccumulator >= FRAME_STEP then
                captureAccumulator = captureAccumulator - FRAME_STEP
                cursor = math.min(project.trimOut, project.trimIn + captureCount * FRAME_STEP)
                captureDue = true
            end
        end
        sampleProject(cursor, FRAME_STEP)
        renderer:prepare(camera, FRAME_STEP)
        return
    end
    if actorAssist then
        updateActorAssist(dt)
        return
    end
    dt = math.min(dt, .1)
    if cameraPass then
        if playing then cursor = math.min(project.trimOut, cursor + dt) end
        sampleProject(cursor, dt)
        if playing and cursor >= cameraPassNextSample then
            recordCameraCue(cursor)
            cameraPassNextSample = cursor + CAMERA_CAPTURE_STEP
        end
        if playing and cursor >= project.trimOut then finishCameraPass() end
        return
    end
    if playing then
        cursor = cursor + dt
        if cursor >= project.trimOut then
            if looping then cursor = project.trimIn + (cursor - project.trimOut)
            else cursor = project.trimOut; playing = false end
        end
    end
    sampleProject(cursor, dt)
end

local function studioDraw()
    love.graphics.clear(.015, .025, .021, 1)
    drawPreview()
    if not recording then
        buttons = {}
        rightPanel()
        timeline()
        if textEntry then
            local g = love.graphics
            g.setColor(.02, .03, .025, .94); g.rectangle('fill', viewportWidth * .12, viewportHeight * .38,
                viewportWidth * .76, 118, 9, 9)
            g.setColor(.92, .84, .62); g.setFont(fonts.body)
            local prompt = textEntry.kind == 'title' and 'Composition title' or 'Dialogue line'
            g.printf(prompt .. '  ·  Enter saves  ·  Esc cancels', viewportWidth * .15,
                viewportHeight * .38 + 14, viewportWidth * .70, 'center')
            g.setColor(.96, .95, .88); g.printf(textEntry.value .. '▏', viewportWidth * .16,
                viewportHeight * .38 + 52, viewportWidth * .68, 'center')
        end
        captureFrame()
    else
        captureFrame()
    end
end

local function studioResize() updateViewport() end

local function studioKeypressed(key)
    if recording and key ~= 'escape' then return end
    if textEntry then
        if key == 'escape' then textEntry = nil; love.keyboard.setTextInput(false)
        elseif key == 'return' or key == 'kpenter' then
            local entry = textEntry; textEntry = nil; love.keyboard.setTextInput(false)
            local value = cleanText(entry.value, entry.kind == 'title' and 96 or 240)
            if entry.kind == 'title' then
                project.title = value ~= '' and value or 'Untitled Cutscene'
                status = 'Composition title updated.'
            elseif value ~= '' then
                if entry.cue then entry.cue.text = value
                else
                    local cue = { time = entry.time, speaker = dialogueSpeaker, text = value, duration = 2.8 }
                    project.dialogue[#project.dialogue + 1] = cue; sortCues(project.dialogue)
                    for index, current in ipairs(project.dialogue) do if current == cue then setSelection('dialogue', index) end end
                end
                status = 'Dialogue cue updated.'
            end
        elseif key == 'backspace' then textEntry.value = textEntry.value:sub(1, -2) end
        return
    end
    if key == 'escape' then
        if recording then
            recording, captureDue = false, false
            if recorder then recorder:finish(); recorder = nil end
            updateViewport(); status = 'Recording cancelled.'
        elseif cameraPass then finishCameraPass()
        elseif cameraReview then discardCameraPass()
        elseif actorAssist then finishActorTake()
        else love.event.quit() end
    elseif actorAssist then
        if key == 'r' then beginActorTake()
        elseif key == 't' and project.actor.kind == 'motorcycle-rider' then
            local command = rider.bike.transmission == 'manual' and 'automatic' or 'manual'
            local okay, message = Rider.command(rider, command, world); status = message
        elseif key == 'z' and project.actor.kind == 'motorcycle-rider' and rider.bike.transmission == 'manual' then
            local _, message = Rider.command(rider, 'shiftdown', world); status = message or 'Shifted down.'
        elseif key == 'x' and project.actor.kind == 'motorcycle-rider' and rider.bike.transmission == 'manual' then
            local _, message = Rider.command(rider, 'shiftup', world); status = message or 'Shifted up.'
        end
        return
    elseif cameraPass then
        if key == 'space' then
            playing = not playing
            status = playing and 'Camera pass resumed.' or 'Camera pass paused. Drag or scroll to set the shot.'
        end
        return
    elseif cameraReview then
        return
    elseif key == 'space' then playing = not playing
    elseif key == 'left' then cursor = clamp(cursor - .25, 0, project.duration)
    elseif key == 'right' then cursor = clamp(cursor + .25, 0, project.duration)
    elseif key == 'i' then project.trimIn = math.min(cursor, project.trimOut - .25)
    elseif key == 'o' then project.trimOut = math.max(cursor, project.trimIn + .25)
    elseif key == 'c' then addCamera()
    elseif key == 'a' then addAction()
    elseif key == 'd' then editDialogue()
    elseif key == 'delete' or key == 'backspace' then
        if selection then table.remove(project[selection.track], selection.index); selection = nil end
    elseif key == 's' and love.keyboard.isDown('lctrl', 'rctrl') then saveProject(false)
    elseif key == 'r' and love.keyboard.isDown('lctrl', 'rctrl') then if saveProject(false) then saveProject(true) end
    elseif key == 'return' then playing = not playing
    elseif key == 'm' then soundsMuted = not soundsMuted; if audio then audio:setMuted(soundsMuted) end
    elseif key == '1' or key == '2' or key == '3' or key == '4' or key == '5' or key == '6' then
        cameraChoice = tonumber(key)
    end
end

local function studioTextinput(value)
    if textEntry then textEntry.value = (textEntry.value .. value):sub(1, 300) end
end

local function studioMousepressed(x, y, buttonNumber)
    if recording then return end
    for index = #buttons, 1, -1 do
        local item = buttons[index]
        if x >= item.x and x <= item.x + item.w and y >= item.y and y <= item.y + item.h then
            if actorAssist and item.label ~= 'STOP & KEEP TAKE' then return end
            if cameraPass and item.label ~= 'STOP CAMERA PASS' then return end
            if cameraReview and item.label ~= 'KEEP CAMERA PASS & PREVIEW'
                and item.label ~= 'DISCARD CAMERA PASS' then return end
            item.fn(); return
        end
    end
    if actorAssist or cameraPass or cameraReview then
        if (actorAssist or cameraPass) and buttonNumber == 1
            and x >= 0 and x < viewportWidth and y >= 0 and y < viewportHeight then
            cameraDrag = { x = x, y = y }
        end
        return
    end
    local base = windowHeight - 170
    if y >= base + 27 then
        local left, right = 142, windowWidth - 24
        local t = clamp((x - left) / (right - left), 0, 1) * project.duration
        cursor = t
        local trackNames = { 'camera', 'actions', 'dialogue', 'speed' }
        local selectedTrack
        for _, track in ipairs(trackNames) do
            if math.abs(y - timelineY(track)) < 15 then selectedTrack = track end
        end
        if selectedTrack then
            local cues = project[selectedTrack]
            local chosen, nearest
            for index, cue in ipairs(cues) do
                local distance = math.abs(cue.time - t)
                if not nearest or distance < nearest then chosen, nearest = index, distance end
            end
            if chosen and nearest < math.max(.24, project.duration * 7 / (right - left)) then setSelection(selectedTrack, chosen)
            else selection = nil end
        end
    end
end

local function studioMousemoved(x, y, dx, dy)
    if not cameraDrag then return end
    cameraDrag.x, cameraDrag.y = x, y
    camera:orbit((dx or 0) * .32, -(dy or 0) * .32)
    if cameraPass then camera.targetZoom = clamp(camera.targetZoom, .55, 4) end
end

local function studioMousereleased()
    if not cameraDrag then return end
    cameraDrag = nil
    if cameraPass then recordCameraCue(cursor) end
end

local function studioWheelmoved(_, y)
    if y == 0 or recording then return end
    local mouseX, mouseY = love.mouse.getPosition()
    if cameraReview then
        if mouseX >= viewportWidth and mouseY < windowHeight - 170 then
            panelScroll = clamp(panelScroll - y * 72, 0,
                math.max(0, panelContentHeight - (windowHeight - 170)))
        end
        return
    end
    if (actorAssist or cameraPass) and mouseX < viewportWidth and mouseY < viewportHeight then
        camera:zoomBy(y * .8)
        if cameraPass then
            camera.targetZoom = clamp(camera.targetZoom, .55, 4)
            recordCameraCue(cursor)
        end
        return
    end
    if mouseX >= viewportWidth and mouseY < windowHeight - 170 then
        panelScroll = clamp(panelScroll - y * 72, 0, math.max(0, panelContentHeight - (windowHeight - 170)))
    else
        cursor = clamp(cursor + (y > 0 and -.5 or .5), 0, project.duration)
    end
end

local function studioQuit()
    if audio then audio:release() end
    if renderer then renderer:release() end
    return false
end

function Studio.load()
    fonts = { heading = love.graphics.newFont(24), body = love.graphics.newFont(15), small = love.graphics.newFont(12) }
    love.window.setMode(1440, 900, { resizable = true, vsync = 1 })
    love.window.setTitle('The Picture Shop - Cutscene Studio')
    love.graphics.setDefaultFilter('nearest', 'nearest')
    findProjects()
    local defaultIndex = 1
    for index, id in ipairs(projects) do if id == 'high-octane-return' then defaultIndex = index end end
    projectIndex = defaultIndex
    local loaded, reason = loadProject(projects[projectIndex] .. '.lua')
    if not loaded then error(reason) end
    project = loaded
    buildMotionTable()
    buildWorld(project.world.seed)
    renderer = Renderer.new(world)
    renderer.characterAssets = CharacterAssets
    renderer.calendar = { year = 2026, month = 6, day = 21, totalDays = 0, elapsed = 600, secondsPerDay = 1200 }
    world.calendar = renderer.calendar
    renderer:prewarmViews()
    CharacterAssets.load()
    resetAssistRider()
    audio = Audio.new(); audio:setLevels(.72, .85, .42)
    updateViewport()
    sampleProject(cursor, 0)
    love.update = studioUpdate
    love.draw = studioDraw
    love.resize = studioResize
    love.keypressed = studioKeypressed
    love.textinput = studioTextinput
    love.mousepressed = studioMousepressed
    love.mousemoved = studioMousemoved
    love.mousereleased = studioMousereleased
    love.wheelmoved = studioWheelmoved
    love.quit = studioQuit
end
function Studio.install()
    love.load = function() Studio.load() end
end

Studio.install()

return Studio
