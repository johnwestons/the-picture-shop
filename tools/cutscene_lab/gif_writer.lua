-- Streaming, silent animated-GIF capture for the stand-alone Cutscene Studio.
-- Frames are quantized to a stable 3:3:2 palette and encoded one at a time.
local Gif = {}
local function le16(value)
    value = math.max(0, math.floor(value))
    return string.char(value % 256, math.floor(value / 256) % 256)
end
local function palette()
    local out = {}
    for red = 0, 7 do
        for green = 0, 7 do
            for blue = 0, 3 do
                out[#out + 1] = string.char(math.floor(red * 255 / 7 + .5),
                    math.floor(green * 255 / 7 + .5), math.floor(blue * 255 / 3 + .5))
            end
        end
    end
    return table.concat(out)
end
local function quantize(image)
    local width, height = image:getDimensions()
    local ffi = require('ffi')
    local pixels = ffi.cast('const uint8_t*', image:getPointer())
    local redChannel = 0
    local rr, rg, rb = image:getPixel(0, 0)
    local first = math.floor(rr * 255 + .5)
    if pixels[0] ~= first then
        if pixels[2] == first then redChannel = 2
        else error('Screenshot pixel format is unsupported.') end
    end
    local greenChannel = redChannel == 0 and 1 or 1
    local blueChannel = redChannel == 0 and 2 or 0
    local indices = {}
    local cursor = 1
    for y = 0, height - 1 do
        local offset = y * width * 4
        for x = 0, width - 1 do
            local at = offset + x * 4
            local red = pixels[at + redChannel]
            local green = pixels[at + greenChannel]
            local blue = pixels[at + blueChannel]
            local r = math.floor(red * 7 / 255 + .5)
            local g = math.floor(green * 7 / 255 + .5)
            local b = math.floor(blue * 3 / 255 + .5)
            indices[cursor] = r * 32 + g * 4 + b
            cursor = cursor + 1
        end
    end
    return width, height, indices
end
local function lzw(indices)
    local output, bytes = {}, {}
    local byteCount, bitBuffer, bitCount = 0, 0, 0
    local function pushByte(byte)
        byteCount = byteCount + 1
        bytes[byteCount] = string.char(byte % 256)
        if byteCount >= 4096 then output[#output + 1] = table.concat(bytes); bytes = {}; byteCount = 0 end
    end
    local clear, ending = 256, 257
    local nextCode, codeSize = 258, 9
    local dictionary = {}
    local function emit(code)
        bitBuffer = bitBuffer + code * 2 ^ bitCount
        bitCount = bitCount + codeSize
        while bitCount >= 8 do
            pushByte(bitBuffer % 256)
            bitBuffer = math.floor(bitBuffer / 256)
            bitCount = bitCount - 8
        end
    end
    emit(clear)
    local prefix = indices[1]
    for index = 2, #indices do
        local value = indices[index]
        local key = prefix * 256 + value
        local existing = dictionary[key]
        if existing then
            prefix = existing
        else
            emit(prefix)
            if nextCode < 4096 then
                dictionary[key] = nextCode
                nextCode = nextCode + 1
                if nextCode == 2 ^ codeSize and codeSize < 12 then codeSize = codeSize + 1 end
            else
                emit(clear)
                dictionary = {}
                nextCode, codeSize = 258, 9
            end
            prefix = value
        end
    end
    emit(prefix)
    emit(ending)
    if bitCount > 0 then pushByte(bitBuffer) end
    if byteCount > 0 then output[#output + 1] = table.concat(bytes) end
    return table.concat(output)
end
local function writeBlocks(file, bytes)
    local at = 1
    while at <= #bytes do
        local size = math.min(255, #bytes - at + 1)
        file:write(string.char(size), bytes:sub(at, at + size - 1))
        at = at + size
    end
    file:write('\0')
end

function Gif.new(path, width, height, delayCs)
    if width < 1 or height < 1 or width > 65535 or height > 65535 then
        return nil, 'Capture dimensions are outside GIF limits.'
    end
    local file, reason = io.open(path, 'wb')
    if not file then return nil, tostring(reason) end
    file:write('GIF89a', le16(width), le16(height), string.char(0xF7, 0, 0), palette())
    file:write(string.char(0x21, 0xFF, 0x0B), 'NETSCAPE2.0', string.char(0x03, 0x01, 0, 0, 0))
    return setmetatable({ file = file, width = width, height = height,
        delayCs = delayCs or 4, frames = 0 }, { __index = Gif })
end

function Gif:add(image)
    if not self.file then return false, 'Recording file is closed.' end
    local ok, width, height, indices = pcall(quantize, image)
    if not ok then return false, width end
    if width ~= self.width or height ~= self.height then return false, 'Screenshot size changed during capture.' end
    local compressed = lzw(indices)
    self.file:write(string.char(0x21, 0xF9, 0x04, 0), le16(self.delayCs), string.char(0, 0))
    self.file:write(string.char(0x2C), le16(0), le16(0), le16(width), le16(height), string.char(0))
    self.file:write(string.char(8))
    writeBlocks(self.file, compressed)
    self.frames = self.frames + 1
    return true
end

function Gif:finish()
    if not self.file then return false, 'Recording file is already closed.' end
    local file = self.file
    self.file = nil
    local okay, reason = file:write(string.char(0x3B))
    local closed, closeReason = file:close()
    if not okay then return false, tostring(reason) end
    if not closed then return false, tostring(closeReason) end
    return true, self.frames
end

return Gif
