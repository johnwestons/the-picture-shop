-- Shared frame and facing helpers for the 64-view movable machines.
local Rotation = {}

local specs = {
    cutter = {
        directions = { "northwest", "north", "northeast", "east", "southeast", "south", "southwest", "west" },
        signs = {
            { 1, 1 }, { 0, 1 }, { -1, 1 }, { -1, 0 },
            { -1, -1 }, { 0, -1 }, { 1, -1 }, { 1, 0 },
        },
        stepsPerDirection = 8,
    },
    wrapper = {
        directions = { "northwest", "north", "northeast", "east", "southeast", "south", "southwest", "west" },
        signs = {
            { 1, 1 }, { 0, 1 }, { -1, 1 }, { -1, 0 },
            { -1, -1 }, { 0, -1 }, { 1, -1 }, { 1, 0 },
        },
        stepsPerDirection = 8,
    },
    windmill = {
        directions = { "northwest", "northeast", "southeast", "southwest" },
        signs = { { 1, 1 }, { -1, 1 }, { -1, -1 }, { 1, -1 } },
        stepsPerDirection = 16,
    },
}

function Rotation.validFrame(frame)
    return type(frame) == "number" and frame == math.floor(frame) and frame >= 1 and frame <= 64
end

function Rotation.frameForDirection(kind, direction)
    local spec = specs[kind]
    if not spec then return nil end
    for index, candidate in ipairs(spec.directions) do
        if candidate == direction then return (index - 1) * spec.stepsPerDirection + 1 end
    end
end

function Rotation.directionForFrame(kind, frame)
    local spec = specs[kind]
    if not spec or not Rotation.validFrame(frame) then return nil end
    local directionIndex = math.floor((frame - 1 + spec.stepsPerDirection / 2)
        / spec.stepsPerDirection) % #spec.directions + 1
    return spec.directions[directionIndex]
end

function Rotation.frameFor(kind, pose)
    if type(pose) ~= "table" then return 1 end
    return Rotation.normalizedFrame(kind, pose, "northwest")
end

function Rotation.normalizedFrame(kind, pose, defaultDirection)
    local direction = type(pose.direction) == "string" and pose.direction or defaultDirection
    local frame = Rotation.validFrame(pose.rotationIndex) and pose.rotationIndex or nil
    if frame and Rotation.directionForFrame(kind, frame) == direction then return frame end
    return Rotation.frameForDirection(kind, direction) or Rotation.frameForDirection(kind, defaultDirection) or 1
end

function Rotation.operatorVector(kind, frame)
    local spec = specs[kind]
    if not spec then return 0, 1 end
    frame = Rotation.validFrame(frame) and frame or 1
    local step = frame - 1
    local current = math.floor(step / spec.stepsPerDirection) + 1
    local nextDirection = current % #spec.directions + 1
    local fraction = (step % spec.stepsPerDirection) / spec.stepsPerDirection
    local first, second = spec.signs[current], spec.signs[nextDirection]
    return first[1] + (second[1] - first[1]) * fraction,
        first[2] + (second[2] - first[2]) * fraction
end

return Rotation
