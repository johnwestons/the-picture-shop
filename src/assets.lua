local Config = require("src.config")
local ImageContract = require("src.image_contract")

local Assets = {
    images = {},
    data = {},
    quads = {},
    failures = {},
    activePack = nil,
}

local function recordFailure(path, reason)
    Assets.failures[#Assets.failures + 1] = path .. ": " .. tostring(reason)
end

function Assets.dimensionDiagnostic(path, actualWidth, actualHeight, expectedWidth, expectedHeight)
    if actualWidth == expectedWidth and actualHeight == expectedHeight then return true end
    return false, string.format("%s: expected %dx%d, got %dx%d",
        tostring(path), expectedWidth, expectedHeight, actualWidth, actualHeight)
end

local function hasExactDimensions(image, path, expectedWidth, expectedHeight)
    local width, height = image:getDimensions()
    local valid, diagnostic = Assets.dimensionDiagnostic(
        path, width, height, expectedWidth, expectedHeight)
    if not valid then Assets.failures[#Assets.failures + 1] = diagnostic end
    return valid
end

local function loadImage(name, path, keepData)
    if not love.filesystem.getInfo(path) then
        recordFailure(path, "missing required asset")
        return nil
    end

    local ok, imageData = pcall(love.image.newImageData, path)
    if not ok or not imageData then
        recordFailure(path, imageData or "image data could not be loaded")
        return nil
    end

    local image = love.graphics.newImage(imageData)
    image:setFilter("nearest", "nearest")
    Assets.images[name] = image
    if keepData then
        Assets.data[name] = imageData
    elseif imageData.release then
        pcall(imageData.release, imageData)
    end
    return image
end

local function loadData(name, path)
    if not love.filesystem.getInfo(path) then
        recordFailure(path, "missing required asset")
        return nil
    end
    local ok, imageData = pcall(love.image.newImageData, path)
    if not ok or not imageData then
        recordFailure(path, imageData or "image data could not be loaded")
        return nil
    end
    Assets.data[name] = imageData
    return imageData
end

local function validateExactPath(path, expectedWidth, expectedHeight)
    local width, height, errorMessage = ImageContract.dimensions(path)
    if not width then
        recordFailure(path, errorMessage)
        return false
    end
    local valid, diagnostic = Assets.dimensionDiagnostic(
        path, width, height, expectedWidth, expectedHeight)
    if not valid then Assets.failures[#Assets.failures + 1] = diagnostic end
    return valid
end

local function makeQuad(name, image, x, y, width, height)
    if not image then return end
    local imageWidth, imageHeight = image:getDimensions()
    x = math.floor(math.max(0, math.min(x, imageWidth - 1)))
    y = math.floor(math.max(0, math.min(y, imageHeight - 1)))
    width = math.floor(math.max(1, math.min(width, imageWidth - x)))
    height = math.floor(math.max(1, math.min(height, imageHeight - y)))
    Assets.quads[name] = {
        quad = love.graphics.newQuad(x, y, width, height, imageWidth, imageHeight),
        width = width,
        height = height,
    }
end

local function registerRabbitAtlas(image)
    if not image then return end
    local width, height = image:getDimensions()
    if width % 6 ~= 0 or height % 4 ~= 0 then
        recordFailure(Config.paths.rabbit, "atlas must be divisible into a 6x4 grid")
        return
    end

    local cellWidth, cellHeight = width / 6, height / 4
    Assets.rabbit = {
        cellWidth = cellWidth,
        cellHeight = cellHeight,
        idle = {},
        walk = {},
    }
    for column = 1, 2 do
        Assets.rabbit.idle[column] = love.graphics.newQuad(
            (column - 1) * cellWidth,
            0,
            cellWidth,
            cellHeight,
            width,
            height
        )
    end
    for column = 1, 6 do
        Assets.rabbit.walk[column] = love.graphics.newQuad(
            (column - 1) * cellWidth,
            cellHeight,
            cellWidth,
            cellHeight,
            width,
            height
        )
    end
end

function Assets.load()
    Assets.activatePack(nil)
    Assets.images = {}
    Assets.data = {}
    Assets.quads = {}
    Assets.failures = {}
    Assets.rabbit = nil
    Assets.activePack = nil

    local warehouse = loadImage("warehouse", Config.paths.warehouse, false)
    local walkmask = loadData("walkmask", Config.paths.walkmask)
    local polarDirections = loadImage("polarDirections", Config.paths.polarDirections, false)
    local skidWrapperDirections = loadImage("skidWrapperDirections", Config.paths.skidWrapperDirections, false)
    local rabbit = loadImage("rabbit", Config.paths.rabbit, false)
    local loadingBayDoor = loadImage("loadingBayDoor", Config.paths.loadingBayDoor, false)
    local deliveryTruck = loadImage("deliveryTruck", Config.paths.deliveryTruck, false)
    local truckCargoDoor = loadImage("truckCargoDoor", Config.paths.truckCargoDoor, false)
    local loadedPaperPalletDirections = loadImage("loadedPaperPalletDirections", Config.paths.loadedPaperPalletDirections, false)
    local palletJack = loadImage("palletJack", Config.paths.palletJack, false)
    local palletJackLoaded = loadImage("palletJackLoaded", Config.paths.palletJackLoaded, false)
    local vendorProductPallets = loadImage("vendorProductPallets", Config.paths.vendorProductPallets, false)
    local boxedPaperPalletStages = loadImage("boxedPaperPalletStages", Config.paths.boxedPaperPalletStages, false)
    local polarBackButton = loadImage("polarBackButton", Config.paths.polarBackButton, false)

    if warehouse and walkmask then
        local warehouseWidth, warehouseHeight = warehouse:getDimensions()
        local maskWidth, maskHeight = walkmask:getDimensions()
        if warehouseWidth ~= maskWidth or warehouseHeight ~= maskHeight then
            recordFailure(Config.paths.walkmask, "must match the warehouse image dimensions")
        end
    end

    if polarDirections then
        local size = Config.cutterPlacement.frameSize
        local width, height = polarDirections:getDimensions()
        local expectedWidth = size * Config.cutterPlacement.frameCount
        if width ~= expectedWidth or height ~= size then
            recordFailure(Config.paths.polarDirections, string.format(
                "expected %dx%d cutter-direction strip, got %dx%d",
                expectedWidth, size, width, height))
        else
            for frame = 1, Config.cutterPlacement.frameCount do
                makeQuad("polarDirection" .. frame, polarDirections,
                    (frame - 1) * size, 0, size, size)
            end
        end
    end
    if skidWrapperDirections then
        local size = Config.wrapperPlacement.frameSize
        local width, height = skidWrapperDirections:getDimensions()
        if width ~= size * Config.wrapperPlacement.frameCount or height ~= size then
            recordFailure(Config.paths.skidWrapperDirections, "wrapper direction strip must be a 4x1 grid of 512px cells")
        else
            for frame = 1, Config.wrapperPlacement.frameCount do
                makeQuad("skidWrapperDirection" .. frame, skidWrapperDirections, (frame - 1) * size, 0, size, size)
            end
        end
    end
    if loadingBayDoor then
        local width, height = loadingBayDoor:getDimensions()
        local expectedWidth = Config.loadingBay.frameWidth * Config.loadingBay.frameCount
        if width ~= expectedWidth or height ~= Config.loadingBay.frameHeight then
            recordFailure(Config.paths.loadingBayDoor, string.format(
                "expected %dx%d loading-bay strip, got %dx%d",
                expectedWidth,
                Config.loadingBay.frameHeight,
                width,
                height
            ))
        else
            for frame = 1, Config.loadingBay.frameCount do
                makeQuad(
                    "loadingBayDoor" .. frame,
                    loadingBayDoor,
                    (frame - 1) * Config.loadingBay.frameWidth,
                    0,
                    Config.loadingBay.frameWidth,
                    Config.loadingBay.frameHeight
                )
            end
        end
    end
    if deliveryTruck then
        local width, height = deliveryTruck:getDimensions()
        if width ~= Config.truck.frameSize or height ~= Config.truck.frameSize then
            recordFailure(Config.paths.deliveryTruck, string.format(
                "expected %dx%d delivery-truck sprite, got %dx%d",
                Config.truck.frameSize,
                Config.truck.frameSize,
                width,
                height
            ))
        end
    end
    if truckCargoDoor then
        local width, height = truckCargoDoor:getDimensions()
        local expectedWidth = Config.truck.frameSize * Config.truck.cargoFrameCount
        if width ~= expectedWidth or height ~= Config.truck.frameSize then
            recordFailure(Config.paths.truckCargoDoor, string.format(
                "expected %dx%d truck cargo-door strip, got %dx%d",
                expectedWidth,
                Config.truck.frameSize,
                width,
                height
            ))
        else
            for frame = 1, Config.truck.cargoFrameCount do
                makeQuad(
                    "truckCargoDoor" .. frame,
                    truckCargoDoor,
                    (frame - 1) * Config.truck.frameSize,
                    0,
                    Config.truck.frameSize,
                    Config.truck.frameSize
                )
            end
        end
    end
    if loadedPaperPalletDirections then
        local size = Config.palletJack.frameSize
        local width, height = loadedPaperPalletDirections:getDimensions()
        if width ~= size * Config.palletJack.frameCount or height ~= size then
            recordFailure(Config.paths.loadedPaperPalletDirections, "loaded-pallet direction strip dimensions are invalid")
        else
            for frame = 1, Config.palletJack.frameCount do
                makeQuad("loadedPaperPallet" .. frame, loadedPaperPalletDirections,
                    (frame - 1) * size, 0, size, size)
            end
        end
    end
    local function registerJackStrip(name, image, path)
        if not image then return end
        local size = Config.palletJack.frameSize
        local width, height = image:getDimensions()
        if width ~= size * Config.palletJack.frameCount or height ~= size then
            recordFailure(path, "pallet-jack direction strip dimensions are invalid")
            return
        end
        for frame = 1, Config.palletJack.frameCount do
            makeQuad(name .. frame, image, (frame - 1) * size, 0, size, size)
        end
    end
    registerJackStrip("palletJack", palletJack, Config.paths.palletJack)
    registerJackStrip("palletJackLoaded", palletJackLoaded, Config.paths.palletJackLoaded)
    if vendorProductPallets then
        if hasExactDimensions(vendorProductPallets, Config.paths.vendorProductPallets, 1252, 1252) then
            local cell = 313
            for row = 1, 4 do
                for frame = 1, 4 do
                    makeQuad("vendorProductPallet" .. row .. "_" .. frame, vendorProductPallets,
                        (frame - 1) * cell, (row - 1) * cell, cell, cell)
                end
            end
        end
    end
    if boxedPaperPalletStages then
        if hasExactDimensions(boxedPaperPalletStages, Config.paths.boxedPaperPalletStages, 1400, 1120) then
            local cellWidth, cellHeight = 280, 280
            for stage = 1, 5 do
                for frame = 1, 4 do
                    makeQuad("boxedPaperPalletStage" .. stage .. "_" .. frame,
                        boxedPaperPalletStages, (stage - 1) * cellWidth, (frame - 1) * cellHeight,
                        cellWidth, cellHeight)
                end
            end
        end
    end
    validateExactPath(Config.paths.polarOperatorConsole, 768, 512)
    validateExactPath(Config.paths.cutterControlButtons, 512, 128)
    validateExactPath(Config.paths.cutterClamp,
        Config.cutterGui.motionFrameWidth * Config.cutterGui.motionFrameCount,
        Config.cutterGui.motionFrameHeight)
    validateExactPath(Config.paths.cutterBlade,
        Config.cutterGui.motionFrameWidth * Config.cutterGui.motionFrameCount,
        Config.cutterGui.motionFrameHeight)
    validateExactPath(Config.paths.polarBackButton, 384, 128)
    validateExactPath(Config.paths.wrappedPalletStages, 1536, 512)
    validateExactPath(Config.paths.loadedPaperPallet, 256, 256)
    if polarBackButton then
        for frame = 1, 3 do
            makeQuad("polarBackButton" .. frame, polarBackButton, (frame - 1) * 128, 0, 128, 128)
        end
    end
    registerRabbitAtlas(rabbit)
end

local PACK_IMAGES = {
    menu = { "polarOperatorConsole", "cutterControlButtons" },
    cutter = { "polarOperatorConsole", "cutterControlButtons", "cutterClamp", "cutterBlade" },
    wrapper = { "wrappedPalletStages", "loadedPaperPallet" },
}

local function releaseImage(name)
    local image = Assets.images[name]
    if image and image.release then pcall(image.release, image) end
    Assets.images[name] = nil
end

local function clearPackQuads(packName)
    if packName == "menu" or packName == "cutter" then
        for frame = 1, Config.cutterGui.buttonFrameCount do
            Assets.quads["cutterControlButton" .. frame] = nil
        end
    end
    if packName == "cutter" then
        for frame = 1, Config.cutterGui.motionFrameCount do
            Assets.quads["cutterClamp" .. frame] = nil
            Assets.quads["cutterBlade" .. frame] = nil
        end
    elseif packName == "wrapper" then
        for frame = 1, 3 do Assets.quads["wrappedPalletStage" .. frame] = nil end
    end
end

local function unloadPack(packName)
    for _, name in ipairs(PACK_IMAGES[packName] or {}) do releaseImage(name) end
    clearPackQuads(packName)
end

local function loadMenuPack()
    local console = loadImage("polarOperatorConsole", Config.paths.polarOperatorConsole, false)
    local buttons = loadImage("cutterControlButtons", Config.paths.cutterControlButtons, false)
    if not console or not buttons then return false end
    local buttonSize = Config.cutterGui.buttonFrameSize
    for frame = 1, Config.cutterGui.buttonFrameCount do
        makeQuad("cutterControlButton" .. frame, buttons, (frame - 1) * buttonSize, 0,
            buttonSize, buttonSize)
    end
    return true
end

local function loadCutterPack()
    if not loadMenuPack() then return false end
    local clamp = loadImage("cutterClamp", Config.paths.cutterClamp, false)
    local blade = loadImage("cutterBlade", Config.paths.cutterBlade, false)
    if not clamp or not blade then return false end
    for frame = 1, Config.cutterGui.motionFrameCount do
        local x = (frame - 1) * Config.cutterGui.motionFrameWidth
        makeQuad("cutterClamp" .. frame, clamp, x, 0,
            Config.cutterGui.motionFrameWidth, Config.cutterGui.motionFrameHeight)
        makeQuad("cutterBlade" .. frame, blade, x, 0,
            Config.cutterGui.motionFrameWidth, Config.cutterGui.motionFrameHeight)
    end
    return true
end

local function loadWrapperPack()
    local stages = loadImage("wrappedPalletStages", Config.paths.wrappedPalletStages, false)
    local loadedPallet = loadImage("loadedPaperPallet", Config.paths.loadedPaperPallet, false)
    if not stages or not loadedPallet then return false end
    for frame = 1, 3 do
        makeQuad("wrappedPalletStage" .. frame, stages, (frame - 1) * 512, 0, 512, 512)
    end
    return true
end

function Assets.activatePack(packName)
    if packName == Assets.activePack then return true end
    if packName ~= nil and not PACK_IMAGES[packName] then return false end
    if Assets.activePack then unloadPack(Assets.activePack) end
    Assets.activePack = nil
    if not packName then return true end
    local loaded
    if packName == "menu" then
        loaded = loadMenuPack()
    elseif packName == "cutter" then
        loaded = loadCutterPack()
    else
        loaded = loadWrapperPack()
    end
    if not loaded then
        unloadPack(packName)
        return false
    end
    Assets.activePack = packName
    return true
end

function Assets.activePackName() return Assets.activePack end

function Assets.textureBytes()
    local bytes = 0
    for _, image in pairs(Assets.images) do
        local width, height = image:getDimensions()
        bytes = bytes + width * height * 4
    end
    return bytes
end

function Assets.get(name)
    return Assets.images[name]
end

function Assets.getData(name)
    return Assets.data[name]
end

function Assets.getQuad(name)
    return Assets.quads[name]
end

function Assets.getRabbitFrame(action, frame)
    local frames = Assets.rabbit and Assets.rabbit[action]
    if not frames or #frames == 0 then return nil end
    return frames[((frame - 1) % #frames) + 1], Assets.rabbit.cellWidth, Assets.rabbit.cellHeight
end

function Assets.assertHealthy()
    return #Assets.failures == 0, table.concat(Assets.failures, "\n")
end

function Assets.failureCount()
    return #Assets.failures
end

return Assets
