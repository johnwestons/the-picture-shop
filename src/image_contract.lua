local ImageContract = {}

local PNG_SIGNATURE = "\137PNG\r\n\26\n"

local function uint32be(data, offset)
    local a, b, c, d = data:byte(offset, offset + 3)
    if not d then return nil end
    return ((a * 256 + b) * 256 + c) * 256 + d
end

function ImageContract.dimensions(path)
    if not love.filesystem.getInfo(path) then return nil, nil, "missing required asset" end
    local ok, data = pcall(love.filesystem.read, path, 24)
    if not ok or type(data) ~= "string" or #data < 24 then
        return nil, nil, "image header could not be read"
    end
    if data:sub(1, 8) ~= PNG_SIGNATURE or data:sub(13, 16) ~= "IHDR" then
        return nil, nil, "expected a PNG image"
    end
    local width, height = uint32be(data, 17), uint32be(data, 21)
    if not width or not height or width < 1 or height < 1 then
        return nil, nil, "PNG dimensions are invalid"
    end
    return width, height
end

return ImageContract
