local Config = require("src.config")

local Assets = {
    images = {},
    data = {},
    quads = {},
    failures = {},
}

local function recordFailure(path, reason)
    Assets.failures[#Assets.failures + 1] = path .. ": " .. tostring(reason)
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
    if keepData then Assets.data[name] = imageData end
    return image
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
    Assets.images = {}
    Assets.data = {}
    Assets.quads = {}
    Assets.failures = {}
    Assets.rabbit = nil

    local warehouse = loadImage("warehouse", Config.paths.warehouse, false)
    local walkmask = loadImage("walkmask", Config.paths.walkmask, true)
    local polar = loadImage("polar", Config.paths.polar, false)
    local polarDirections = loadImage("polarDirections", Config.paths.polarDirections, false)
    loadImage("picturePress", Config.paths.picturePress, false)
    local skidWrapperDirections = loadImage("skidWrapperDirections", Config.paths.skidWrapperDirections, false)
    local wrappedPalletStages = loadImage("wrappedPalletStages", Config.paths.wrappedPalletStages, false)
    local rabbit = loadImage("rabbit", Config.paths.rabbit, false)
    local loadingBayDoor = loadImage("loadingBayDoor", Config.paths.loadingBayDoor, false)
    local deliveryTruck = loadImage("deliveryTruck", Config.paths.deliveryTruck, false)
    local truckCargoDoor = loadImage("truckCargoDoor", Config.paths.truckCargoDoor, false)
    local polarOperatorConsole = loadImage("polarOperatorConsole", Config.paths.polarOperatorConsole, false)
    local cutterControlButtons = loadImage("cutterControlButtons", Config.paths.cutterControlButtons, false)
    local cutterClamp = loadImage("cutterClamp", Config.paths.cutterClamp, false)
    local cutterBlade = loadImage("cutterBlade", Config.paths.cutterBlade, false)
    local loadedPaperPallet = loadImage("loadedPaperPallet", Config.paths.loadedPaperPallet, false)
    local loadedPaperPalletDirections = loadImage("loadedPaperPalletDirections", Config.paths.loadedPaperPalletDirections, false)
    local palletJack = loadImage("palletJack", Config.paths.palletJack, false)
    local palletJackLoaded = loadImage("palletJackLoaded", Config.paths.palletJackLoaded, false)
    local vendorProductPallets = loadImage("vendorProductPallets", Config.paths.vendorProductPallets, false)
    local boxedPaperPalletStages = loadImage("boxedPaperPalletStages", Config.paths.boxedPaperPalletStages, false)
    local polarBackButton = loadImage("polarBackButton", Config.paths.polarBackButton, false)
    loadImage("emptyPallet", Config.paths.emptyPallet, false)
    loadImage("paperStack", Config.paths.paperStack, false)
    loadImage("toolboxSmall", Config.paths.toolboxSmall, false)
    loadImage("toolboxLarge", Config.paths.toolboxLarge, false)
    local paperBoxes = loadImage("paperBoxes", Config.paths.paperBoxes, false)

    if warehouse and walkmask then
        local warehouseWidth, warehouseHeight = warehouse:getDimensions()
        local maskWidth, maskHeight = walkmask:getDimensions()
        if warehouseWidth ~= maskWidth or warehouseHeight ~= maskHeight then
            recordFailure(Config.paths.walkmask, "must match the warehouse image dimensions")
        end
    end

    if polar then
        local width, height = polar:getDimensions()
        makeQuad("polarIso", polar, width * 0.03, height * 0.02, width * 0.46, height * 0.59)
        makeQuad("polarFront", polar, width * 0.51, height * 0.03, width * 0.46, height * 0.57)
        makeQuad("polarPaper", polar, width * 0.14, height * 0.71, width * 0.23, height * 0.15)
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
    if wrappedPalletStages then
        local width, height = wrappedPalletStages:getDimensions()
        if width ~= 1536 or height ~= 512 then
            recordFailure(Config.paths.wrappedPalletStages, "wrapped pallet stages must be a 3x1 grid of 512px cells")
        else
            for frame = 1, 3 do
                makeQuad("wrappedPalletStage" .. frame, wrappedPalletStages, (frame - 1) * 512, 0, 512, 512)
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
    if polarOperatorConsole then
        local width, height = polarOperatorConsole:getDimensions()
        if width ~= 1536 or height ~= 1024 then
            recordFailure(Config.paths.polarOperatorConsole, "operator console must be 1536x1024")
        end
    end
    if cutterControlButtons then
        local size = Config.cutterGui.buttonFrameSize
        local width, height = cutterControlButtons:getDimensions()
        if width ~= size * Config.cutterGui.buttonFrameCount or height ~= size then
            recordFailure(Config.paths.cutterControlButtons, "control button strip dimensions are invalid")
        else
            for frame = 1, Config.cutterGui.buttonFrameCount do
                makeQuad("cutterControlButton" .. frame, cutterControlButtons,
                    (frame - 1) * size, 0, size, size)
            end
        end
    end
    local function registerMotionStrip(name, image, path)
        if not image then return end
        local frameWidth = Config.cutterGui.motionFrameWidth
        local frameHeight = Config.cutterGui.motionFrameHeight
        local width, height = image:getDimensions()
        if width ~= frameWidth * Config.cutterGui.motionFrameCount or height ~= frameHeight then
            recordFailure(path, "cutter motion strip dimensions are invalid")
            return
        end
        for frame = 1, Config.cutterGui.motionFrameCount do
            makeQuad(name .. frame, image, (frame - 1) * frameWidth, 0, frameWidth, frameHeight)
        end
    end
    registerMotionStrip("cutterClamp", cutterClamp, Config.paths.cutterClamp)
    registerMotionStrip("cutterBlade", cutterBlade, Config.paths.cutterBlade)
    if loadedPaperPallet then
        local width, height = loadedPaperPallet:getDimensions()
        if width ~= 256 or height ~= 256 then
            recordFailure(Config.paths.loadedPaperPallet, "loaded paper pallet must be 256x256")
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
        local width, height = vendorProductPallets:getDimensions()
        if width ~= height or width < 1024 then
            recordFailure(Config.paths.vendorProductPallets, "vendor pallet atlas must be a square 4x4 atlas")
        else
            local cell = math.floor(width / 4)
            for row = 1, 4 do
                for frame = 1, 4 do
                    makeQuad("vendorProductPallet" .. row .. "_" .. frame, vendorProductPallets,
                        (frame - 1) * cell, (row - 1) * cell, cell, cell)
                end
            end
        end
    end
    if boxedPaperPalletStages then
        local width, height = boxedPaperPalletStages:getDimensions()
        local cellWidth, cellHeight = math.floor(width / 5), math.floor(height / 4)
        if cellWidth < 200 or cellHeight < 200 or math.abs(cellWidth - cellHeight) > 2 then
            recordFailure(Config.paths.boxedPaperPalletStages, "boxed-pallet stage atlas must be a 5x4 square-cell atlas")
        else
            for stage = 1, 5 do
                for frame = 1, 4 do
                    makeQuad("boxedPaperPalletStage" .. stage .. "_" .. frame,
                        boxedPaperPalletStages, (stage - 1) * cellWidth, (frame - 1) * cellHeight,
                        cellWidth, cellHeight)
                end
            end
        end
    end
    if polarBackButton then
        local width, height = polarBackButton:getDimensions()
        local cell = math.floor(width / 3)
        if math.abs(cell - height) > 2 then
            recordFailure(Config.paths.polarBackButton, "Polar back button must be a three-state horizontal strip")
        else
            for frame = 1, 3 do
                makeQuad("polarBackButton" .. frame, polarBackButton, (frame - 1) * cell, 0, cell, height)
            end
        end
    end
    if paperBoxes then
        local width, height = paperBoxes:getDimensions()
        local variantWidth = math.floor(width / 3)
        makeQuad("paperBoxClosed", paperBoxes, 0, 0, variantWidth, height)
        makeQuad("paperBoxOpen", paperBoxes, variantWidth, 0, variantWidth, height)
        makeQuad("paperBoxFilled", paperBoxes, variantWidth * 2, 0, width - variantWidth * 2, height)
    end
    registerRabbitAtlas(rabbit)
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
