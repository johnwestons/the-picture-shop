local GaitMotion = require("src.gait_motion")

local PlayerController = {}

local EPSILON = 0.0001

local function approach(value, target, amount)
    if value < target then return math.min(target, value + amount) end
    if value > target then return math.max(target, value - amount) end
    return target
end

local function movementConfig(player, definition)
    return definition or player.definition or {}
end

function PlayerController.gaitMotion(animationDistance, definition)
    return GaitMotion.sample(animationDistance, definition)
end

function PlayerController.reset(player, position, definition)
    definition = movementConfig(player, definition)
    player.x = position and tonumber(position.x) or definition.spawnX or player.x or 0
    player.y = position and tonumber(position.y) or definition.spawnY or player.y or 0
    player.speed = tonumber(definition.speed) or tonumber(player.speed) or 0
    player.velocityX, player.velocityY = 0, 0
    player.intentX, player.intentY = player.facing or 1, 0
    player.moving, player.blocked = false, false
    player.animationDistance, player.idleClock = 0, 0
    player.gaitSpeedMultiplier, player.gaitAccelerationMultiplier = 1, 1
    player.interactionClock = 0
end

function PlayerController.stop(player)
    player.velocityX, player.velocityY = 0, 0
    player.gaitSpeedMultiplier, player.gaitAccelerationMultiplier = 1, 1
end

local function tryStep(player, stepX, stepY, canMove)
    if math.abs(stepX) <= EPSILON and math.abs(stepY) <= EPSILON then return 0, 0 end
    local startX, startY = player.x, player.y
    local nextX, nextY = startX + stepX, startY + stepY
    if canMove(startX, startY, nextX, nextY) then
        player.x, player.y = nextX, nextY
        return stepX, stepY
    end

    local movedX, movedY = 0, 0
    local function moveX()
        if math.abs(stepX) > EPSILON
            and canMove(player.x, player.y, player.x + stepX, player.y)
        then
            player.x = player.x + stepX
            movedX = stepX
        end
    end
    local function moveY()
        if math.abs(stepY) > EPSILON
            and canMove(player.x, player.y, player.x, player.y + stepY)
        then
            player.y = player.y + stepY
            movedY = stepY
        end
    end
    if math.abs(stepX) >= math.abs(stepY) then moveX(); moveY() else moveY(); moveX() end
    return movedX, movedY
end

function PlayerController.update(player, inputX, inputY, dt, canMove, definition)
    definition = movementConfig(player, definition)
    dt = math.max(0, math.min(tonumber(dt) or 0, definition.maxFrameTime or 0.10))
    inputX, inputY = tonumber(inputX) or 0, tonumber(inputY) or 0
    local inputLength = math.sqrt(inputX * inputX + inputY * inputY)
    local strength = math.min(1, inputLength)
    local directionX, directionY = 0, 0
    if inputLength > EPSILON then
        directionX, directionY = inputX / inputLength, inputY / inputLength
        player.intentX, player.intentY = directionX, directionY
        if math.abs(directionX) > 0.08 then player.facing = directionX < 0 and -1 or 1 end
    end

    local gaitSpeed, gaitAcceleration = PlayerController.gaitMotion(
        player.animationDistance, definition)
    if inputLength <= EPSILON then
        gaitSpeed, gaitAcceleration = 1, 1
    end
    player.gaitSpeedMultiplier = gaitSpeed
    player.gaitAccelerationMultiplier = gaitAcceleration

    local speed = (tonumber(definition.speed) or tonumber(player.speed) or 0) * gaitSpeed
    local targetX, targetY = directionX * speed * strength, directionY * speed * strength
    local changingSpeed = inputLength > EPSILON
        and (targetX * (player.velocityX or 0) + targetY * (player.velocityY or 0) >= 0)
    local response = changingSpeed and (definition.acceleration or 1050) * gaitAcceleration
        or (definition.deceleration or 1350)
    player.velocityX = approach(player.velocityX or 0, targetX, response * dt)
    player.velocityY = approach(player.velocityY or 0, targetY, response * dt)

    local travelX, travelY = player.velocityX * dt, player.velocityY * dt
    local maximumTravel = math.max(math.abs(travelX), math.abs(travelY))
    local stepLimit = math.max(1, tonumber(definition.maxStepDistance) or 5)
    local steps = math.max(1, math.ceil(maximumTravel / stepLimit))
    local stepX, stepY = travelX / steps, travelY / steps
    local movedX, movedY = 0, 0
    for _ = 1, steps do
        local actualX, actualY = tryStep(player, stepX, stepY, canMove)
        movedX, movedY = movedX + actualX, movedY + actualY
        if math.abs(actualX) <= EPSILON and math.abs(stepX) > EPSILON then player.velocityX = 0 end
        if math.abs(actualY) <= EPSILON and math.abs(stepY) > EPSILON then player.velocityY = 0 end
    end

    local distance = math.sqrt(movedX * movedX + movedY * movedY)
    player.moving = distance > EPSILON
    player.blocked = inputLength > EPSILON and distance + 0.05 < math.sqrt(travelX * travelX + travelY * travelY)
    if player.moving then
        player.animationDistance = (player.animationDistance or 0) + distance
        player.idleClock = 0
    else
        player.idleClock = (player.idleClock or 0) + dt
    end
    player.interactionClock = (player.interactionClock or 0) + dt
    return distance
end

function PlayerController.observeExternalMove(player, startX, startY, moving, dt)
    PlayerController.stop(player)
    local dx, dy = player.x - startX, player.y - startY
    local distance = math.sqrt(dx * dx + dy * dy)
    player.moving = moving == true and distance > EPSILON
    if player.moving then
        player.intentX, player.intentY = dx / distance, dy / distance
        if math.abs(player.intentX) > 0.08 then player.facing = player.intentX < 0 and -1 or 1 end
        player.animationDistance = (player.animationDistance or 0) + distance
        player.idleClock = 0
    else
        player.idleClock = (player.idleClock or 0) + math.max(0, tonumber(dt) or 0)
    end
    player.interactionClock = (player.interactionClock or 0) + math.max(0, tonumber(dt) or 0)
end

return PlayerController
