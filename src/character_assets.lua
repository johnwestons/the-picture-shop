local Config = require("src.config")

local CharacterAssets = { images = {}, frames = {}, anchors = {}, failures = {} }

function CharacterAssets.load()
    CharacterAssets.images, CharacterAssets.frames, CharacterAssets.anchors, CharacterAssets.failures = {}, {}, {}, {}
    for character, actions in pairs(Config.characters) do
        CharacterAssets.images[character], CharacterAssets.frames[character] = {}, {}
        CharacterAssets.anchors[character] = {}
        for action, path in pairs(actions) do
            if not love.filesystem.getInfo(path) then
                CharacterAssets.failures[#CharacterAssets.failures + 1] = path .. ": missing required asset"
            else
                local ok, imageData = pcall(love.image.newImageData, path)
                local image = ok and imageData and love.graphics.newImage(imageData) or nil
                if not ok or not image then
                    CharacterAssets.failures[#CharacterAssets.failures + 1] = path .. ": image could not be loaded"
                else
                    image:setFilter("nearest", "nearest")
                    local width, height = image:getDimensions()
                    if height ~= 512 or width % 512 ~= 0 then
                        CharacterAssets.failures[#CharacterAssets.failures + 1] = path .. ": expected 512px-high frame strip"
                    else
                        CharacterAssets.images[character][action] = image
                        CharacterAssets.frames[character][action] = {}
                        CharacterAssets.anchors[character][action] = {}
                        for frame = 1, width / 512 do
                            CharacterAssets.frames[character][action][frame] = love.graphics.newQuad((frame - 1) * 512, 0, 512, 512, width, height)
                            local left, top, right, bottom
                            for y = 0, 511 do
                                for x = (frame - 1) * 512, frame * 512 - 1 do
                                    local _, _, _, alpha = imageData:getPixel(x, y)
                                    if alpha > 0 then
                                        left = left and math.min(left, x) or x
                                        top = top and math.min(top, y) or y
                                        right = right and math.max(right, x) or x
                                        bottom = bottom and math.max(bottom, y) or y
                                    end
                                end
                            end
                            CharacterAssets.anchors[character][action][frame] = {
                                x = ((left or ((frame - 1) * 512)) + (right or (frame * 512 - 1))) / 2 - (frame - 1) * 512,
                                y = bottom or 398,
                            }
                        end
                    end
                end
            end
        end
    end
end

function CharacterAssets.get(character, action, frame)
    local image = CharacterAssets.images[character] and CharacterAssets.images[character][action]
    local frames = CharacterAssets.frames[character] and CharacterAssets.frames[character][action]
    if not image or not frames or #frames == 0 then return nil end
    return image, frames[((frame or 1) - 1) % #frames + 1], #frames
end

function CharacterAssets.getAnchor(character, action, frame)
    local anchors = CharacterAssets.anchors[character] and CharacterAssets.anchors[character][action]
    if not anchors or #anchors == 0 then return 256, 398 end
    local anchor = anchors[((frame or 1) - 1) % #anchors + 1]
    return anchor.x, anchor.y
end

function CharacterAssets.assertHealthy()
    return #CharacterAssets.failures == 0, table.concat(CharacterAssets.failures, "\n")
end

function CharacterAssets.failureCount() return #CharacterAssets.failures end

return CharacterAssets
